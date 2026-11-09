import AppKit
import Metal
import simd

/// The game: it runs the matches, the computer players and the interface, and has the renderer draw them into the
/// view. The interface is drawn immediately: each frame lays out the widgets and hears the pointer at once.
@MainActor
final class GameController {
    enum Mode: Int, CaseIterable {
        case vsComputer, twoPlayers, practice, demo
    }

    enum AimLines: Int, CaseIterable {
        case full, short, off
    }

    /// Between strokes the game is ready for one; a computer thinks, then shows its aim; the cue strikes; the balls
    /// roll; or the game is over.
    enum Stage {
        case ready, thinking, presenting, stroke, rolling, over
    }

    enum Gesture {
        case none, strike, placeBall, turnCamera
    }

    /// The widgets that take the pointer while it is held; a selector has two, for its arrows.
    enum Widget {
        static let help = 1
        static let newGame = 2
        static let undo = 3
        static let camera = 4
        static let powerBar = 5
        static let spinBall = 6
        static let game = 7
        static let mode = 9
        static let level = 11
        static let aim = 13
        static let theme = 15
        static let sound = 17
        static let language = 18
        /// Past it, the widgets of the help, which work while it is open.
        static let modal = 100
        static let helpClose = 101
    }

    struct Toast {
        var text: String
        var age: Float = 0
    }

    /// The game before a stroke, to go back to.
    struct Snapshot {
        var match: Match
        var sim: Simulation
        var history: Int
        var shots: Int
    }

    struct HistoryLine {
        var text: String
        /// 0 a stroke, 1 a foul, 2 the end of the game.
        var kind: Int
    }

    static let panelWidth: Float = 352
    static let panelMargin: Float = 16
    /// Pixels the pointer travels to draw the cue back all the way.
    static let fullPull: Float = 230
    /// How far from the middle the cue may strike, as a share of the radius.
    static let maxSpin: Float = 0.6
    /// Seconds the computer takes over a stroke, at least.
    static let minThink: Float = 0.6
    /// The cue stays in sight after striking.
    static let followTime: Float = 0.4
    static let textColor = RGBA(236, 239, 245)
    static let mutedColor = RGBA(150, 158, 176)
    static let foulColor = RGBA(255, 146, 124)

    // Collaborators.
    weak var view: GameView?
    let renderer: Renderer
    let painter: Painter
    let sound: SoundBank
    /// Told when the language changes, for the menus and the window's title.
    var languageChanged: (@MainActor (Language) -> Void)?

    // The window.
    var width = 0 // of the picture, in pixels
    var height = 0
    var scale: Float = 1 // of the interface: pixels for a point
    var fontScale: Float = 0 // that the fonts were made for
    var dirty = true // something to draw since the last frame
    var cursorHand = false
    let clock = ContinuousClock()
    var lastFrame: ContinuousClock.Instant
    var time: Float = 0

    // The game.
    var settings: Settings
    var language: Language
    var table: TableSpec
    /// The renderer and the view have the table.
    var tableReady = false
    var match = Match()
    /// The balls at rest between strokes.
    var sim: Simulation
    /// The stroke being played.
    var live: Simulation
    var events: [Event] = []
    /// Events already sounded.
    var heard = 0
    /// The stroke being played or about to be.
    var shot = Shot()
    var stage = Stage.ready
    var mode = Mode.vsComputer
    var level = 3
    var themeIndex = 0
    var game = GameType.eightBall
    var aimLines = AimLines.full
    /// Who breaks the next game.
    var breaker = 0
    var random = RandomSource()
    var undoStack: [Snapshot] = []
    var history: [HistoryLine] = []
    var shots = 0
    var rollClock: Float = 0
    var overClock: Float = 0
    var tableView = TableView()

    // The aim.
    var struck = 0
    var aim = V2(1, 0)
    /// 0 to 1.
    var power: Float = 0.4
    var side: Float = 0
    var vertical: Float = 0
    var called = -1
    var calledFixed = false
    var prediction = Prediction()
    var predictionDirty = true
    /// The cue drawn back from the ball, metres.
    var pull: Float = 0
    /// The power while the pointer draws the cue back.
    var charge: Float = 0

    // The stroke.
    var strokeClock: Float = 0
    var strokeFrom: Float = 0
    var strokeTo: Float = 0
    var strokeBack: Float = 0
    var strokeHold: Float = 0
    var strokeForward: Float = 0.08
    /// Seconds since the cue met the ball.
    var follow: Float = 10
    /// Where the struck ball was.
    var strikeSpot = V2.zero

    // The computer.
    let computer = ComputerWorker()
    var thinkClock: Float = 0
    var computerShot: Shot?
    var presentClock: Float = 0
    var presentSpot = V2.zero
    var presentAim = V2(1, 0)
    var presentPower: Float = 0
    var presentSide: Float = 0
    var presentVertical: Float = 0

    // The view and the pointer.
    var camera = TableCamera()
    var pointer = Pointer()
    var gesture = Gesture.none
    var pressX: Float = 0
    var pressY: Float = 0
    var dragX: Float = 0
    var dragY: Float = 0
    /// The pointer when it last aimed.
    var aimX: Float = -1
    var aimY: Float = -1
    /// The pointer when the turn began.
    var turnX: Float = -1
    var turnY: Float = -1
    /// It has moved since, and the aim follows it.
    var pointerAims = false
    var grabOffset = V2.zero
    var hoverBall = -1
    var hoverPocket = -1

    // The interface.
    var activeWidget = 0
    var panelVisible = true
    var panelSlide: Float = 1
    var helpVisible = false
    var historyScroll: Float = 0
    var followHistory = true
    var bannerFade: Float = 0
    /// Left to show; below zero it stays.
    var bannerTime: Float = 0
    var bannerTitle = ""
    var bannerDetail = ""
    var toasts: [Toast] = []

    init(view: GameView) throws {
        guard let device = view.device else { throw RendererError.noDevice }
        let settings = Settings.load(themeCount: Themes.all.count)
        let renderer = try Renderer(device: device, drawableFormat: view.colorPixelFormat)
        try renderer.setTheme(Themes.all[settings.theme])
        self.renderer = renderer
        painter = Painter(device: device, framesInFlight: Renderer.framesInFlight)
        sound = SoundBank()
        self.view = view
        self.settings = settings
        language = settings.language
        themeIndex = settings.theme
        level = settings.level
        mode = Mode(rawValue: settings.mode) ?? .vsComputer
        game = GameType(rawValue: settings.game) ?? .eightBall
        aimLines = AimLines(rawValue: settings.aim) ?? .full
        breaker = settings.breaker
        panelVisible = settings.panel
        panelSlide = settings.panel ? 1 : 0
        table = TableSpec(game.table)
        sim = Simulation(table: table)
        live = Simulation(table: table)
        lastFrame = clock.now

        sound.isEnabled = settings.sound
        camera.setMode(CameraMode(rawValue: settings.camera) ?? .overview)
        if loadMatch(settings.match) {
            // The history of the game, as far as it was kept.
            for line in settings.history.split(separator: "|") {
                if line.count > 1, let kind = line.first?.wholeNumberValue, (0...2).contains(kind) {
                    history.append(HistoryLine(text: String(line.dropFirst()), kind: kind))
                }
            }
            tableView.reset(sim, rack: false)
            startTurn()
            followAim(instant: true)
        } else {
            newGame()
        }
    }

    var theme: Theme { Themes.all[themeIndex] }

    var isFullScreen: Bool { view?.window?.styleMask.contains(.fullScreen) ?? false }

    func text(_ id: Str) -> String { id.text(language) }

    func text(_ id: Str, _ values: CustomStringConvertible...) -> String {
        var result = ""
        var rest = Substring(id.text(language))
        var next = values.makeIterator()
        while let place = rest.range(of: "{}") {
            result += rest[..<place.lowerBound]
            result += next.next()?.description ?? ""
            rest = rest[place.upperBound...]
        }
        return result + rest
    }

    /// Stops the computer and keeps the game, when the program ends.
    func shutDown() {
        computer.cancel()
        save()
    }

    // MARK: - Frames

    /// Something changed: a frame is drawn soon, and the animation clock does not count the time the view rested.
    func requestFrame() {
        dirty = true
        guard let view, view.isPaused else { return }
        lastFrame = clock.now
        view.isPaused = false
    }

    /// Updates the game, lays out the interface and draws a frame; the view rests afterwards while nothing moves.
    func frame() {
        guard let view else { return }
        // Nothing moves while the window cannot be seen: the game goes on from there when it shows again.
        if let window = view.window, !window.occlusionState.contains(.visible) {
            rest(true)
            return
        }
        let now = clock.now
        let elapsed = lastFrame.duration(to: now).components
        // The balls roll on in real time even when frames are slow; other animations are kept from jumping.
        let seconds = min(Float(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18), 0.25)
        lastFrame = now
        time += seconds
        dirty = false

        updateSize()
        guard width > 0, height > 0 else {
            rest(true) // until the view has a size again
            return
        }
        if scale != fontScale {
            buildFonts()
        }
        if stage == .rolling {
            updateRolling(seconds)
        }
        update(min(seconds, 0.1))

        let scene = buildScene()
        cursorHand = false
        painter.begin(width: width, height: height)
        drawInterface()
        handleTablePointer()
        if let drawable = view.currentDrawable {
            renderer.render(scene, to: drawable) { encoder, frameIndex in
                painter.encode(encoder, frameIndex: frameIndex)
            }
        }

        // The widgets are drawn as they were before they heard the click: what it changed shows in the next frame.
        if pointer.leftPressed || pointer.leftReleased || pointer.rightPressed || pointer.rightReleased {
            dirty = true
        }
        pointer.leftPressed = false
        pointer.leftReleased = false
        pointer.rightPressed = false
        pointer.rightReleased = false
        pointer.zoom = 0
        pointer.scroll = 0
        pointer.consumed = false
        view.setCursor(hand: cursorHand)
        rest(!(dirty || needsAnimation))
    }

    /// Stops the frames, or lets them run, touching the view only when that changes.
    private func rest(_ resting: Bool) {
        if let view, view.isPaused != resting {
            view.isPaused = resting
        }
    }

    private func updateSize() {
        guard let view else { return }
        width = Int(view.drawableSize.width)
        height = Int(view.drawableSize.height)
        let points = Float(view.bounds.width)
        scale = min(max(points > 0 ? Float(width) / points : 1, 0.5), 4)
    }

    private func buildFonts() {
        do {
            let fonts = try FontId.allCases.map { id in
                try FontAtlas(device: renderer.device, queue: renderer.queue, pixelHeight: id.size * scale, semibold: id.isSemibold)
            }
            painter.setFonts(fonts)
            fontScale = scale
        } catch {
            FileHandle.standardError.write(Data("3D Billiards: \(error)\n".utf8))
        }
    }

    private func update(_ seconds: Float) {
        let slideTarget: Float = panelVisible ? 1 : 0
        panelSlide += (slideTarget - panelSlide) * (1 - exp(-seconds * 12))
        if abs(slideTarget - panelSlide) < 0.001 {
            panelSlide = slideTarget
        }
        camera.setSpace(freeArea.width / max(1, Float(width)))

        switch stage {
        case .thinking, .presenting:
            updateComputer(seconds)
        case .stroke:
            updateStroke(seconds)
        case .over:
            overClock += seconds
            if mode == .demo && overClock > 6 {
                newGame()
            }
        default:
            break
        }
        // The cue settles back to the ball when no stroke draws it.
        if stage == .ready && gesture != .strike {
            pull *= exp(-seconds * 14)
            if pull < 1e-4 {
                pull = 0
            }
        }
        follow += seconds
        tableView.update(shown, seconds: seconds)
        updatePrediction()
        camera.update(seconds)

        for index in toasts.indices {
            toasts[index].age += seconds
        }
        toasts.removeAll { $0.age > 2.8 }
        var bannerTarget: Float = 0
        if bannerTime < 0 {
            bannerTarget = 1
        } else if bannerTime > 0 {
            bannerTarget = 1
            bannerTime = max(0, bannerTime - seconds)
        }
        bannerFade += (bannerTarget - bannerFade) * (1 - exp(-seconds * 7))
        if abs(bannerTarget - bannerFade) < 0.002 {
            bannerFade = bannerTarget
        }
    }

    var needsAnimation: Bool {
        stage == .thinking || stage == .presenting || stage == .stroke || stage == .rolling || (stage == .over && mode == .demo) || camera.isMoving
            || tableView.isAnimating || !toasts.isEmpty || bannerTime > 0 || (bannerFade > 0.001 && bannerFade < 0.999)
            || abs(panelSlide - (panelVisible ? 1 : 0)) > 0.001 || follow < Self.followTime || (pull > 0 && gesture != .strike)
    }

    // MARK: - The scene

    /// The balls as they are shown: rolling, or at rest between strokes.
    var shown: Simulation { stage == .rolling ? live : sim }

    private func buildScene() -> RenderScene {
        var scene = RenderScene()
        let aspect = Float(width) / max(1, Float(height))
        scene.view = camera.view
        scene.projection = camera.projection(aspect: aspect)
        scene.eye = camera.eye
        scene.time = time
        let sim = shown
        let R = Float(table.ballRadius)
        let aiming = !match.isOver && (isAiming || stage == .presenting || stage == .stroke)
        let placing = stage == .presenting && shot.place && presentClock < 0.7

        // The glow at the rims: the ball in hand, the ball chosen to strike, the ball the aim meets.
        var highlight = [Float](repeating: 0, count: Simulation.maxBalls)
        if aiming {
            if match.inHand != .none && stage != .stroke {
                highlight[0] = gesture == .placeBall || hoverBall == 0 ? 1 : 0.55
            }
            if game == .americanka && !match.breakShot {
                highlight[struck] = 0.7
                if hoverBall >= 0 && hoverBall != struck {
                    highlight[hoverBall] = max(highlight[hoverBall], 0.4)
                }
            }
            if aimLines != .off && prediction.hit >= 0 && !placing {
                highlight[prediction.hit] = max(highlight[prediction.hit], 0.35)
            }
        }
        scene.balls = tableView.balls(sim, highlight: highlight)

        // The lines of the aim and the ghost ball where the struck ball meets another.
        if aiming && !placing && aimLines != .off && sim.balls[struck].onTable {
            let full = aimLines == .full
            func add(_ points: [V2], segments: Int, reach: Double) {
                var length = 0.0
                var segments = segments
                var i = 1
                while i < points.count && segments > 0 && scene.guides.count < 16 {
                    let a = points[i - 1]
                    var b = points[i]
                    let segment = (b - a).length
                    if segment >= 1e-6 {
                        let last = length + segment >= reach
                        if last {
                            b = a + (b - a) * ((reach - length) / segment)
                        }
                        scene.guides.append(SIMD4(Float(a.x), Float(a.z), Float(b.x), Float(b.z)))
                        length += segment
                        if last {
                            break
                        }
                    }
                    i += 1
                    segments -= 1
                }
            }
            let scale = table.length / 2.54
            add(prediction.path, segments: full ? 8 : 3, reach: (full ? 3.0 : 1.0) * scale)
            if prediction.hit >= 0 {
                // Into a rack the lines after the contact would say little.
                if !match.breakShot {
                    add(prediction.object, segments: full ? 4 : 1, reach: full ? 1.6 * scale : 0.14 * scale)
                }
                if full && !match.breakShot {
                    add(prediction.after, segments: 4, reach: 0.6 * scale)
                }
                var ghost = BallDraw()
                ghost.model = TableView.ballMatrix(SIMD3(Float(prediction.contact.x), R, Float(prediction.contact.z)), Quat(), radius: R)
                ghost.number = struck
                ghost.russian = table.kind == .pyramid
                ghost.opacity = 0.3
                scene.balls.append(ghost)
            }
            scene.guideStrength = stage == .stroke ? 0.6 : stage == .presenting ? 0.75 : 1
        }

        // The cue.
        if aiming && !placing && sim.balls[struck].onTable {
            let pull = gesture == .strike ? CuePose.pull(for: charge) : self.pull
            scene.cue = CuePose.matrix(table: table, center: tableView.position(sim, struck), aim: aim, side: side, vertical: vertical, pull: pull)
        } else if stage == .rolling && follow < Self.followTime {
            let through = -min(follow * 0.5, 0.045) * (0.4 + powerFor(shot.speed))
            let at = SIMD3<Float>(Float(strikeSpot.x), R, Float(strikeSpot.z))
            scene.cue = CuePose.matrix(table: table, center: at, aim: shot.direction, side: Float(shot.side), vertical: Float(shot.vertical),
                                       pull: through)
        }

        scene.showKitchen = aiming && match.inHand == .kitchen
        // The pocket called for the eight, or the one under the pointer.
        if aiming && isOnEight {
            let pocket = hoverPocket >= 0 ? hoverPocket : called
            if pocket >= 0 {
                let p = table.pockets[pocket]
                scene.pocketMark = SIMD4(Float(p.hole.x), Float(p.hole.z), Float(p.cupRadius) + 0.006,
                                         hoverPocket >= 0 && hoverPocket != called ? 0.55 : 1)
            }
        }
        scene.panels = frostedPanels
        return scene
    }
}
