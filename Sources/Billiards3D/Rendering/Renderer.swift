import Foundation
import Metal
import QuartzCore
import simd

/// Draws the scene into the window: shadows, the lit scene in high dynamic range with multisampling, then bloom and
/// tone mapping. The interface is drawn on top, in the last pass, by the caller.
@MainActor
final class Renderer {
    /// The meshes of the table being played on.
    private struct TableParts {
        let bed: GPUMesh
        let cushions: GPUMesh
        let rails: GPUMesh
        let frame: GPUMesh
        let floor: GPUMesh
        let cornerPocket: GPUMesh
        let middlePocket: GPUMesh
    }

    private static let shadowSize = 2048
    private static let numberCell = 128
    private static let maxBallInstances = Simulation.maxBalls * 2
    private static let maxFrostedPanels = 4
    static let framesInFlight = 3

    let device: MTLDevice
    let queue: MTLCommandQueue
    private let samples: Int

    private let shadowPipeline: MTLRenderPipelineState
    private let ballPipeline: MTLRenderPipelineState
    private let seeThroughBallPipeline: MTLRenderPipelineState
    private let tablePipeline: MTLRenderPipelineState
    /// The cloth, the rails and the pockets have holes cut in them, smoothed over the samples of each pixel.
    private let cutTablePipeline: MTLRenderPipelineState
    private let backgroundPipeline: MTLRenderPipelineState
    private let resolvePipeline: MTLRenderPipelineState
    private let bloomDownPipeline: MTLRenderPipelineState
    private let bloomUpPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let interfacePipeline: MTLRenderPipelineState
    private let depthWrite: MTLDepthStencilState
    private let depthTest: MTLDepthStencilState
    private let depthRead: MTLDepthStencilState

    private let ball: GPUMesh
    private let simpleBall: GPUMesh
    private let cue: GPUMesh
    private var parts: TableParts?

    private let shadowMap: MTLTexture
    private let numbers: MTLTexture
    private let probes: LightProbes
    private var targets: RenderTargets?

    private var theme = Themes.all[0]
    private var table = TableSpec(.pool)
    private var lightViewProjection = Matrix.identity
    private var shadowRadius: Float = 3
    private var shadowRange: Float = 10
    private let inFlight: DispatchSemaphore
    private var frameIndex = 0

    init(device: MTLDevice, drawableFormat: MTLPixelFormat) throws {
        self.device = device
        inFlight = DispatchSemaphore(value: Self.framesInFlight)
        guard let queue = device.makeCommandQueue() else { throw RendererError.creationFailed("command queue") }
        queue.label = "3D Billiards"
        self.queue = queue
        samples = device.supportsTextureSampleCount(4) ? 4 : 1

        let library = try ShaderLibrary(device: device)
        let hdr = RenderTargets.hdrFormat
        let depth = RenderTargets.depthFormat
        let stride = MemoryLayout<SurfaceVertex>.stride
        let surfaceLayout = Self.vertexLayout([(.float3, 0), (.float3, 12), (.float2, 24)], stride: stride)
        let positionLayout = Self.vertexLayout([(.float3, 0)], stride: stride)
        let interfaceLayout = Self.vertexLayout([(.float2, 0), (.float2, 8), (.uchar4Normalized, 16), (.float4, 20)],
                                                stride: MemoryLayout<InterfaceVertex>.stride)

        func pipeline(_ label: String, _ vertex: String, _ fragment: String, layout: MTLVertexDescriptor? = nil, color: MTLPixelFormat?,
                      depth: MTLPixelFormat = .invalid, samples: Int = 1, blend: Blend = .none, alphaToCoverage: Bool = false) throws
            -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = label
            descriptor.vertexFunction = try library.function(vertex)
            descriptor.fragmentFunction = try library.function(fragment)
            descriptor.vertexDescriptor = layout
            descriptor.rasterSampleCount = samples
            descriptor.depthAttachmentPixelFormat = depth
            descriptor.isAlphaToCoverageEnabled = alphaToCoverage
            if let color {
                let attachment: MTLRenderPipelineColorAttachmentDescriptor = descriptor.colorAttachments[0]
                attachment.pixelFormat = color
                blend.apply(to: attachment)
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        shadowPipeline = try pipeline("shadow", "shadowVertex", "shadowFragment", layout: positionLayout, color: nil, depth: depth)
        ballPipeline = try pipeline("balls", "ballVertex", "ballFragment", layout: surfaceLayout, color: hdr, depth: depth, samples: samples)
        seeThroughBallPipeline = try pipeline("balls seen through", "ballVertex", "ballFragment", layout: surfaceLayout, color: hdr, depth: depth,
                                              samples: samples, blend: .alpha)
        tablePipeline = try pipeline("table", "tableVertex", "tableFragment", layout: surfaceLayout, color: hdr, depth: depth, samples: samples)
        cutTablePipeline = try pipeline("table with holes", "tableVertex", "tableFragment", layout: surfaceLayout, color: hdr, depth: depth,
                                        samples: samples, alphaToCoverage: true)
        backgroundPipeline = try pipeline("background", "fullscreenVertex", "backgroundFragment", color: hdr, depth: depth, samples: samples)
        resolvePipeline = try pipeline("resolve", "fullscreenVertex", "resolveFragment", color: hdr)
        bloomDownPipeline = try pipeline("bloom down", "fullscreenVertex", "bloomDownFragment", color: RenderTargets.bloomFormat)
        bloomUpPipeline = try pipeline("bloom up", "fullscreenVertex", "bloomUpFragment", color: RenderTargets.bloomFormat, blend: .additive)
        compositePipeline = try pipeline("composite", "fullscreenVertex", "compositeFragment", color: drawableFormat)
        interfacePipeline = try pipeline("interface", "interfaceVertex", "interfaceFragment", layout: interfaceLayout, color: drawableFormat,
                                         blend: .alpha)
        depthWrite = try Self.depthState(device, .less, write: true)
        depthTest = try Self.depthState(device, .lessEqual, write: false)
        depthRead = try Self.depthState(device, .less, write: false)

        ball = try GPUMesh(device: device, mesh: TableModel.ball(rings: 32, segments: 64), label: "ball")
        simpleBall = try GPUMesh(device: device, mesh: TableModel.ball(rings: 10, segments: 20), label: "plain ball")
        cue = try GPUMesh(device: device, mesh: TableModel.cue(), label: "cue")

        // The shadow map, read both with comparison (for filtering) and without (to find the casters).
        let shadowDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depth, width: Self.shadowSize, height: Self.shadowSize,
                                                                        mipmapped: false)
        shadowDescriptor.usage = [.renderTarget, .shaderRead]
        shadowDescriptor.storageMode = .private
        guard let shadowMap = device.makeTexture(descriptor: shadowDescriptor) else { throw RendererError.creationFailed("shadow map") }
        shadowMap.label = "shadow map"
        self.shadowMap = shadowMap

        probes = try LightProbes(device: device, library: library, queue: queue)
        let cell = Self.numberCell
        numbers = try TextureUpload.coverage(device: device, queue: queue, pixels: NumberAtlas.render(cell: cell), width: cell * 4, height: cell * 4,
                                             mipmapped: true, label: "ball numbers")
    }

    func setTheme(_ theme: Theme) throws {
        self.theme = theme
        updateLightView()
        try probes.bake(theme, queue: queue)
    }

    /// The table to draw; to be set before the first frame.
    func setTable(_ table: TableSpec) throws {
        self.table = table
        let meshes = TableModel.table(table)
        let top = Float(table.railHeight)
        let corner = table.pockets[0]
        let middle = table.pockets[1]
        parts = TableParts(
            bed: try GPUMesh(device: device, mesh: meshes.bed, label: "cloth"),
            cushions: try GPUMesh(device: device, mesh: meshes.cushions, label: "cushions"),
            rails: try GPUMesh(device: device, mesh: meshes.rails, label: "rails"),
            frame: try GPUMesh(device: device, mesh: meshes.frame, label: "frame"),
            floor: try GPUMesh(device: device, mesh: TableModel.floor(size: 40, height: meshes.floorHeight), label: "floor"),
            cornerPocket: try GPUMesh(device: device, mesh: TableModel.pocket(radius: Float(corner.cupRadius), top: top, depth: Float(corner.depth)),
                                      label: "corner pocket"),
            middlePocket: try GPUMesh(device: device, mesh: TableModel.pocket(radius: Float(middle.cupRadius), top: top, depth: Float(middle.depth)),
                                      label: "middle pocket"))
        updateLightView()
    }

    /// Draws a frame into the drawable and presents it. `overlay` draws the interface over the finished image, in the
    /// last pass; it is given the index of the frame among those the GPU may still be drawing.
    func render(_ scene: RenderScene, to drawable: CAMetalDrawable, overlay: (MTLRenderCommandEncoder, Int) -> Void) {
        let width = drawable.texture.width
        let height = drawable.texture.height
        if targets?.width != width || targets?.height != height {
            targets = try? RenderTargets(device: device, width: width, height: height, samples: samples)
        }
        guard let targets else { return }

        inFlight.wait()
        frameIndex = (frameIndex + 1) % Self.framesInFlight
        guard let commandBuffer = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        commandBuffer.label = "frame"
        Self.signal(inFlight, when: commandBuffer)

        let uniforms = frameUniforms(scene, width: width, height: height)
        let balls = ballInstances(scene)
        drawShadowMap(scene, uniforms: uniforms, balls: balls, commandBuffer: commandBuffer)
        drawMainPass(scene, uniforms: uniforms, balls: balls, targets: targets, commandBuffer: commandBuffer)
        drawBloom(targets: targets, commandBuffer: commandBuffer)
        drawFinalImage(scene, targets: targets, drawable: drawable, commandBuffer: commandBuffer, overlay: overlay)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Passes

    private func frameUniforms(_ scene: RenderScene, width: Int, height: Int) -> Uniforms.Frame {
        let viewProjection = scene.projection * scene.view
        // The depth bias, in world units the same whatever the shadow's range; the fog begins well beyond the table.
        let fogStart = length(scene.eye) + Float(table.length) * 0.9
        return Uniforms.Frame(
            viewProjection: viewProjection,
            inverseViewProjection: viewProjection.inverse,
            lightViewProjection: lightViewProjection,
            cameraPosition: SIMD4(scene.eye, scene.time),
            lightDirection: SIMD4(normalize(theme.keyDirection), 2 * shadowRadius / Float(Self.shadowSize)),
            lightColor: SIMD4(theme.keyRadiance, theme.keySoftness),
            shadowParams: SIMD4(shadowRange, 0.004 / shadowRange, fogStart, 0),
            viewport: SIMD4(Float(width), Float(height), 1 / Float(width), 1 / Float(height)),
            environment: SIMD4(theme.diffuseLight, theme.reflectedLight, Float(LightProbes.prefilteredLevels - 1), theme.background),
            accent: SIMD4(theme.accent, 1),
            fog: SIMD4(theme.fog, 0.08))
    }

    /// The balls as instances: the solid ones first, then those seen through.
    private func ballInstances(_ scene: RenderScene) -> (instances: [Uniforms.BallInstance], solid: Int) {
        var instances: [Uniforms.BallInstance] = []
        for seeThrough in [false, true] {
            for ball in scene.balls where (ball.opacity < 1) == seeThrough && instances.count < Self.maxBallInstances {
                instances.append(Uniforms.BallInstance(model: ball.model,
                                                       params: SIMD4(Float(ball.number), ball.russian ? 1 : 0, ball.opacity, ball.highlight),
                                                       extra: SIMD4(ball.ground, 0, 0, 0)))
            }
        }
        let solid = min(scene.balls.filter { $0.opacity >= 1 }.count, instances.count)
        return (instances, solid)
    }

    private func drawShadowMap(_ scene: RenderScene, uniforms: Uniforms.Frame, balls: (instances: [Uniforms.BallInstance], solid: Int),
                               commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "shadow map"
        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setDepthStencilState(depthWrite)
        encoder.setCullMode(.none)
        encoder.setDepthBias(3, slopeScale: 1.5, clamp: 0)
        encoder.setVertexValue(uniforms, index: 1)
        setBallInstances(balls.instances, encoder)

        encoder.setVertexValue(Uniforms.Shadow(model: Matrix.identity, draw: .zero), index: 3)
        if let parts {
            parts.cushions.draw(encoder)
            parts.rails.draw(encoder)
            parts.frame.draw(encoder)
        }
        if let model = scene.cue {
            encoder.setVertexValue(Uniforms.Shadow(model: model, draw: .zero), index: 3)
            cue.draw(encoder)
        }
        encoder.setVertexValue(Uniforms.Shadow(model: Matrix.identity, draw: SIMD4(1, 0, 0, 0)), index: 3)
        simpleBall.draw(encoder, instances: balls.solid)
        encoder.endEncoding()
    }

    /// The floor, the table, the balls and the cue, lit by the key light and the baked room; the background is the
    /// room itself, and the balls seen through are blended over it all.
    private func drawMainPass(_ scene: RenderScene, uniforms: Uniforms.Frame, balls: (instances: [Uniforms.BallInstance], solid: Int),
                              targets: RenderTargets, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = targets.sceneColor
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(theme.fog.x), green: Double(theme.fog.y), blue: Double(theme.fog.z), alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = targets.sceneDepth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "scene"
        encoder.setDepthStencilState(depthWrite)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        encoder.setVertexValue(uniforms, index: 1)
        encoder.setFragmentValue(uniforms, index: 1)
        let view = Uniforms.Pass(eye: SIMD4(scene.eye, 0))
        encoder.setFragmentValue(view, index: 2)
        encoder.setFragmentTexture(shadowMap, index: 0)
        encoder.setFragmentTexture(probes.irradiance, index: 1)
        encoder.setFragmentTexture(probes.prefiltered, index: 2)
        encoder.setFragmentTexture(probes.brdf, index: 3)
        encoder.setFragmentTexture(numbers, index: 4)

        func draw(_ mesh: GPUMesh, kind: Int, model: float4x4 = Matrix.identity) {
            let uniforms = Uniforms.Mesh(model: model, kind: SIMD4(Float(kind), 0, 0, 0))
            encoder.setVertexValue(uniforms, index: 4)
            encoder.setFragmentValue(uniforms, index: 4)
            mesh.draw(encoder)
        }

        let look = tableLook(scene).packed
        func setLook() {
            look.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 3) }
        }
        if let parts {
            encoder.setRenderPipelineState(tablePipeline)
            setLook()
            draw(parts.floor, kind: 5)
            draw(parts.frame, kind: 3)
            draw(parts.cushions, kind: 1)
            encoder.setRenderPipelineState(cutTablePipeline)
            encoder.setCullMode(.none)
            for pocket in table.pockets {
                draw(pocket.corner ? parts.cornerPocket : parts.middlePocket, kind: 4,
                     model: Matrix.translation(SIMD3(Float(pocket.hole.x), 0, Float(pocket.hole.z))))
            }
            encoder.setCullMode(.back)
            draw(parts.rails, kind: 2)
            draw(parts.bed, kind: 0)
        }

        encoder.setRenderPipelineState(ballPipeline)
        setBallInstances(balls.instances, encoder)
        let surface = SIMD4<Float>(theme.ballRoughness, theme.ballCoatRoughness, 1, 0)
        let solidBalls = Uniforms.Balls(surface: surface, draw: .zero)
        encoder.setVertexValue(solidBalls, index: 3)
        encoder.setFragmentValue(solidBalls, index: 3)
        ball.draw(encoder, instances: balls.solid)

        if let model = scene.cue {
            encoder.setRenderPipelineState(tablePipeline)
            setLook()
            draw(cue, kind: 6, model: model)
        }

        // Behind everything drawn, at the far plane; clamped there rather than clipped.
        encoder.setDepthStencilState(depthTest)
        encoder.setDepthClipMode(.clamp)
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setDepthClipMode(.clip)

        // The balls seen through, over the rest.
        if balls.instances.count > balls.solid {
            encoder.setDepthStencilState(depthRead)
            encoder.setRenderPipelineState(seeThroughBallPipeline)
            let seeThrough = Uniforms.Balls(surface: surface, draw: SIMD4(Float(balls.solid), 0, 0, 0))
            encoder.setVertexValue(seeThrough, index: 3)
            encoder.setFragmentValue(seeThrough, index: 3)
            ball.draw(encoder, instances: balls.instances.count - balls.solid)
        }
        encoder.endEncoding()
    }

    /// The samples resolved, and the bright parts spread: halved six times, then added back up.
    private func drawBloom(targets: RenderTargets, commandBuffer: MTLCommandBuffer) {
        fullscreenPass(commandBuffer, into: targets.resolved, label: "resolve") { encoder in
            encoder.setRenderPipelineState(resolvePipeline)
            encoder.setFragmentTexture(targets.sceneColor, index: 0)
        }?.endEncoding()
        for level in 0..<RenderTargets.bloomLevels {
            let source = level == 0 ? targets.resolved : targets.bloom[level - 1]
            fullscreenPass(commandBuffer, into: targets.bloom[level], label: "bloom down") { encoder in
                encoder.setRenderPipelineState(bloomDownPipeline)
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentValue(Uniforms.Bloom(source: Self.texelSize(source, first: level == 0)), index: 0)
            }?.endEncoding()
        }
        for level in stride(from: RenderTargets.bloomLevels - 2, through: 0, by: -1) {
            let source = targets.bloom[level + 1]
            fullscreenPass(commandBuffer, into: targets.bloom[level], load: true, label: "bloom up") { encoder in
                encoder.setRenderPipelineState(bloomUpPipeline)
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentValue(Uniforms.Bloom(source: Self.texelSize(source, first: false)), index: 0)
            }?.endEncoding()
        }
    }

    /// Tone mapping, vignetting and the frosted glass behind the interface's panels, then the interface itself.
    private func drawFinalImage(_ scene: RenderScene, targets: RenderTargets, drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer,
                                overlay: (MTLRenderCommandEncoder, Int) -> Void) {
        let panels = scene.panels.prefix(Self.maxFrostedPanels).map { panel in
            Uniforms.FrostedPanel(bounds: SIMD4(panel.rect.x + panel.rect.width / 2, panel.rect.y + panel.rect.height / 2,
                                                panel.rect.width / 2, panel.rect.height / 2),
                                  style: SIMD4(panel.radius, panel.opacity, 0, 0))
        }
        let width = Float(targets.width)
        let height = Float(targets.height)
        let composite = Uniforms.Composite(settings: SIMD4(theme.exposure, theme.bloom, theme.vignette, Float(panels.count)),
                                           viewport: SIMD4(width, height, 1 / width, 1 / height))
        let encoder = fullscreenPass(commandBuffer, into: drawable.texture, label: "final image") { encoder in
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentValue(composite, index: 0)
            encoder.setFragmentArray(panels, placeholder: Uniforms.FrostedPanel(bounds: .zero, style: .zero), index: 1)
            encoder.setFragmentTexture(targets.resolved, index: 0)
            encoder.setFragmentTexture(targets.bloom[0], index: 1)
            encoder.setFragmentTexture(targets.bloom[2], index: 2)
        }
        guard let encoder else { return }
        encoder.setRenderPipelineState(interfacePipeline)
        overlay(encoder, frameIndex)
        encoder.endEncoding()
    }

    // MARK: - The looks

    /// The key light's view: a box round the table and the floor about it.
    private func updateLightView() {
        shadowRadius = Float(table.length / 2 + table.cushionWidth + table.railWidth) * 1.25 + 0.4
        shadowRange = 2 * shadowRadius + 6
        let toLight = normalize(theme.keyDirection)
        let up: SIMD3<Float> = abs(toLight.y) > 0.99 ? SIMD3(0, 0, 1) : SIMD3(0, 1, 0)
        let center = SIMD3<Float>(0, -0.2, 0)
        let view = Matrix.lookAt(eye: center + toLight * (shadowRadius + 3), target: center, up: up)
        let projection = Matrix.orthographic(left: -shadowRadius, right: shadowRadius, bottom: -shadowRadius, top: shadowRadius, near: 0.5,
                                             far: 0.5 + shadowRange)
        lightViewProjection = projection * view
    }

    private func tableLook(_ scene: RenderScene) -> TableLook {
        let t = theme
        let russian = table.kind == .pyramid
        var look = TableLook()
        look.cloth = SIMD4(t.cloth, 0)
        look.clothStyle = SIMD4(t.clothRoughness, t.clothNap, t.clothSheen, t.clothWear)
        look.railColor = SIMD4(t.rail, 0)
        look.railStyle = SIMD4(t.railRoughness, t.railClearcoat, t.railPattern, t.railSeed)
        look.frameColor = SIMD4(t.frame, 0)
        look.frameStyle = SIMD4(t.frameRoughness, t.frameClearcoat, t.framePattern, t.frameSeed)
        look.pocketColor = SIMD4(russian ? SIMD3<Float>(0.32, 0.26, 0.18) * (t.railPattern > 0.5 ? 0.3 : 1) : t.pocket, 0)
        look.pocketStyle = SIMD4(t.pocketRoughness, russian ? 1 : 0, 0, 0)
        look.floorColor = SIMD4(t.floor, 0)
        look.floorStyle = SIMD4(t.floorRoughness, t.floorPattern, 0, 0)
        look.sightColor = SIMD4(t.sight, 0)
        look.sightStyle = SIMD4(t.sightMetallic, t.sightRoughness, russian ? 1 : t.sightShape, t.sightGlow)
        let tableLength = Float(table.length)
        let tableWidth = Float(table.width)
        look.table = SIMD4(tableLength, tableWidth, Float(table.ballRadius), Float(table.headString))
        look.marks = SIMD4(scene.showKitchen ? 1 : 0, russian ? 1 : 0, 0, 0)
        look.holes = table.pockets.map { SIMD4(Float($0.hole.x), Float($0.hole.z), Float($0.holeRadius), 0) }
        look.cups = table.pockets.map { SIMD4(Float($0.hole.x), Float($0.hole.z), Float($0.cupRadius), 0) }
        // The sights: three between the pockets along each rail, in the middle of the rail.
        let middle = Float(table.cushionWidth + table.railWidth * 0.45)
        let size: Float = russian ? 0.0065 : 0.009
        for side: Float in [-1, 1] {
            for k in 1..<8 where k != 4 {
                look.sights.append(SIMD4(-tableLength / 2 + tableLength * Float(k) / 8, side * (tableWidth / 2 + middle), size, 0))
            }
            for k in 1..<4 {
                look.sights.append(SIMD4(side * (tableLength / 2 + middle), -tableWidth / 2 + tableWidth * Float(k) / 4, size, 0))
            }
        }
        look.guides = scene.guides
        look.guideColor = SIMD4(t.accent, scene.guideStrength)
        look.pocketMark = scene.pocketMark
        // The balls lying on the cloth, for the shade under them.
        for ball in scene.balls where look.balls.count < TableLook.ballRoom {
            let radius = length(SIMD3(ball.model.columns.0.x, ball.model.columns.0.y, ball.model.columns.0.z))
            if ball.opacity > 0.5 && ball.ground == 0 && abs(ball.model.columns.3.y - radius) < 0.25 * radius {
                look.balls.append(SIMD4(ball.model.columns.3.x, ball.model.columns.3.z, radius, ball.opacity))
            }
        }
        return look
    }

    // MARK: - Helpers

    /// The balls for the vertex functions that read them; an empty list is bound as one, which no draw reads.
    private func setBallInstances(_ instances: [Uniforms.BallInstance], _ encoder: MTLRenderCommandEncoder) {
        let bound = instances.isEmpty ? [Uniforms.BallInstance(model: Matrix.identity, params: .zero, extra: .zero)] : instances
        bound.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 5) }
    }

    /// A pass that covers its target with one triangle, after `setUp` has set the pipeline and its inputs. The
    /// encoder is returned open, for more to be drawn over the triangle; the caller ends it.
    private func fullscreenPass(_ commandBuffer: MTLCommandBuffer, into target: MTLTexture, load: Bool = false, label: String,
                                _ setUp: (MTLRenderCommandEncoder) -> Void) -> MTLRenderCommandEncoder? {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = load ? .load : .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = label
        setUp(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        return encoder
    }

    private static func texelSize(_ texture: MTLTexture, first: Bool) -> SIMD4<Float> {
        SIMD4(1 / Float(texture.width), 1 / Float(texture.height), first ? 1 : 0, 0)
    }

    private static func vertexLayout(_ attributes: [(MTLVertexFormat, Int)], stride: Int) -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        for (index, (format, offset)) in attributes.enumerated() {
            descriptor.attributes[index].format = format
            descriptor.attributes[index].offset = offset
            descriptor.attributes[index].bufferIndex = 0
        }
        descriptor.layouts[0].stride = stride
        return descriptor
    }

    private static func depthState(_ device: MTLDevice, _ compare: MTLCompareFunction, write: Bool) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = compare
        descriptor.isDepthWriteEnabled = write
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else { throw RendererError.creationFailed("depth state") }
        return state
    }

    /// Frees a frame's slot when the GPU has drawn it. Outside the main actor, so that the handler, which runs on a
    /// thread of Metal's, does not belong to it.
    private nonisolated static func signal(_ semaphore: DispatchSemaphore, when commandBuffer: MTLCommandBuffer) {
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
    }
}
