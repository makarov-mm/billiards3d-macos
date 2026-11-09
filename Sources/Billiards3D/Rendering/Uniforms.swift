import simd

/// The uniforms of Common.metal, laid out the same way: only 4x4 matrices, four-component vectors and arrays of them,
/// which both languages align to 16 bytes, so neither side needs padding.
enum Uniforms {
    struct Frame {
        var viewProjection: float4x4
        var inverseViewProjection: float4x4
        var lightViewProjection: float4x4
        var cameraPosition: SIMD4<Float> // xyz; w: time in seconds
        var lightDirection: SIMD4<Float> // toward the light; w: world size of a shadow map texel
        var lightColor: SIMD4<Float> // radiance; w: tangent of the light's angular radius
        var shadowParams: SIMD4<Float> // x: depth range of the shadow map, y: depth bias, z: where the fog begins
        var viewport: SIMD4<Float> // width, height, 1 / width, 1 / height
        var environment: SIMD4<Float> // diffuse light, reflected light, highest mip of the prefiltered map, background
        var accent: SIMD4<Float>
        var fog: SIMD4<Float> // rgb; w: density
    }

    struct Pass {
        var eye: SIMD4<Float> // xyz; w: 1 to leave out the shadows
    }

    struct BallInstance {
        var model: float4x4
        var params: SIMD4<Float> // number, 1 for the Russian set, opacity, highlight
        var extra: SIMD4<Float> // x: height of the cloth under it
    }

    struct Balls {
        var surface: SIMD4<Float> // roughness, clear coat roughness, ivory tint strength
        var draw: SIMD4<Float> // x: the first instance of the draw
    }

    struct Mesh {
        var model: float4x4
        var kind: SIMD4<Float> // x: 0 cloth, 1 cushions, 2 rails, 3 frame and legs, 4 pockets, 5 floor, 6 cue
    }

    struct Shadow {
        var model: float4x4
        var draw: SIMD4<Float> // x: 1 for the balls, drawn together; y: the first instance
    }

    struct Bloom {
        var source: SIMD4<Float> // xy: a texel of the source; z: 1 for the first step down
    }

    struct Composite {
        var settings: SIMD4<Float> // exposure, bloom strength, vignette, number of frosted panels
        var viewport: SIMD4<Float> // width, height, 1 / width, 1 / height
    }

    struct FrostedPanel {
        var bounds: SIMD4<Float> // center x, center y, half width, half height
        var style: SIMD4<Float> // x: corner radius, y: opacity
    }

    struct Environment {
        var ceiling: SIMD4<Float>
        var horizon: SIMD4<Float>
        var floor: SIMD4<Float>
        var counts: SIMD4<Int32> // x: number of lights
    }

    struct StudioPanel {
        var direction: SIMD4<Float> // xyz toward the light, w: roll
        var shape: SIMD4<Float> // half width, half height (as tangents), corner, softness
        var color: SIMD4<Float> // rgb radiance, w: falloff from the center
    }
}
