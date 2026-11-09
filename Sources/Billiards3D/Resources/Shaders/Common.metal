// Shared by all the shaders: the uniforms as the renderer fills them, noise, display transforms and shapes. The
// shader files are compiled together, in the order ShaderLibrary lists them, this one first.

#include <metal_stdlib>
using namespace metal;

constant float PI = 3.14159265359;

// Uniforms -------------------------------------------------------------------------------------------
// Laid out as the structs of Uniforms.swift: only 4x4 matrices, four-component vectors and arrays of them, so that
// both sides agree without padding.

struct FrameUniforms {
    float4x4 viewProjection;
    float4x4 inverseViewProjection;
    float4x4 lightViewProjection;
    float4 cameraPosition;  // xyz; w: time in seconds
    float4 lightDirection;  // toward the light; w: world size of a shadow map texel
    float4 lightColor;      // radiance; w: tangent of the light's angular radius, for soft shadows
    float4 shadowParams;    // x: depth range of the shadow map, y: depth bias, z: where the fog begins
    float4 viewport;        // width, height, 1 / width, 1 / height
    float4 environment;     // x: diffuse light, y: reflected light, z: highest mip of the prefiltered map, w: background
    float4 accent;          // highlights
    float4 fog;             // rgb; w: density
};

// Per pass: where the shading looks from.
struct PassUniforms {
    float4 eye;  // xyz; w: 1 to leave out the shadows
};

// A ball, drawn with the others in one call: each instance its place, its turn and its number.
struct BallInstance {
    float4x4 model;  // the radius, the ball's turn and its place
    float4 params;   // x: number, y: 1 for the Russian set, z: opacity, w: highlight
    float4 extra;    // x: height of the cloth under it
};

struct BallUniforms {
    float4 surface;  // roughness, clear coat roughness, ivory tint strength
    float4 draw;     // x: the first instance of the draw
};

// The looks of the table, the floor and the cue, and the marks on the cloth: the same for every mesh of a pass.
struct TableUniforms {
    float4 cloth;        // rgb
    float4 clothStyle;   // roughness, nap strength, sheen, wear
    float4 railColor;    // rgb
    float4 railStyle;    // roughness, clear coat, pattern (0 wood, 1 lacquer), wood seed
    float4 frameColor;   // rgb
    float4 frameStyle;   // roughness, clear coat, pattern, seed
    float4 pocketColor;  // rgb
    float4 pocketStyle;  // roughness, 1 for nets
    float4 floorColor;   // rgb
    float4 floorStyle;   // roughness, pattern (0 boards, 1 carpet, 2 stone)
    float4 sightColor;   // rgb
    float4 sightStyle;   // metallic, roughness, shape (0 diamonds, 1 dots), glow
    float4 table;        // length, width, ball radius, the x of the head string
    float4 marks;        // x: 1 to show the head string, y: 1 for the Russian table
    float4 guideColor;   // rgb, strength
    float4 pocketMark;   // a ring round the pocket called: xz, radius, strength
    float4 counts;       // x: sights, y: guides, z: balls on the cloth
    float4 holes[6];     // the pockets' holes in the cloth: xz, radius
    float4 cups[6];      // the openings in the rails: xz, radius
    float4 sights[24];   // xz, size
    float4 guides[16];   // segments of the aim: from xz, to xz
    float4 balls[16];    // the balls on the cloth: xz, radius, opacity
};

// One mesh of the table: where it is placed and what it is.
struct MeshUniforms {
    float4x4 model;
    float4 kind;  // x: 0 cloth, 1 cushions, 2 rails, 3 frame and legs, 4 pockets, 5 floor, 6 cue
};

struct ShadowUniforms {
    float4x4 model;
    float4 draw;  // x: 1 for the balls, drawn together; y: the first instance
};

struct BloomUniforms {
    float4 source;  // xy: the size of a texel of the source; z: 1 for the first step down
};

struct CompositeUniforms {
    float4 settings;  // x: exposure, y: bloom strength, z: vignette, w: number of frosted panels
    float4 viewport;  // width, height, 1 / width, 1 / height
};

struct FrostedPanelUniforms {
    float4 bounds;  // center x, center y, half width, half height, in pixels from the top left
    float4 style;   // x: corner radius, y: opacity
};

struct EnvironmentUniforms {
    float4 ceiling;
    float4 horizon;
    float4 floor;
    int4 counts;  // x: number of lights
};

struct StudioPanelUniforms {
    float4 direction;  // xyz toward the panel, w: roll
    float4 shape;      // half width, half height (as tangents), corner, softness
    float4 color;      // rgb radiance, w: falloff from the center
};

// A triangle that covers the screen ---------------------------------------------------------------

struct FullscreenVaryings {
    float4 position [[position]];
    float2 uv;   // texture coordinates, from the top left
    float2 ndc;  // normalized device coordinates, y up
};

vertex FullscreenVaryings fullscreenVertex(uint vertexId [[vertex_id]])
{
    float2 p = float2(float((vertexId << 1) & 2), float(vertexId & 2));
    FullscreenVaryings out;
    out.ndc = p * 2.0 - 1.0;
    out.uv = float2(p.x, 1.0 - p.y);
    // At the far plane, for the background drawn behind the scene.
    out.position = float4(out.ndc, 1.0, 1.0);
    return out;
}

// Helpers -----------------------------------------------------------------------------------------

float Luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// GLSL's mod: the remainder takes the sign of the divisor.
float Mod(float x, float y) { return x - y * floor(x / y); }

float RoundedBox(float2 p, float2 halfSize, float radius)
{
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

// Display -----------------------------------------------------------------------------------------

float3 RrtAndOdtFit(float3 v)
{
    float3 a = v * (v + 0.0245786) - 0.000090537;
    float3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
}

// The ACES filmic curve, after Stephen Hill's fit.
float3 Aces(float3 color)
{
    const float3x3 inputMatrix = float3x3(float3(0.59719, 0.07600, 0.02840), float3(0.35458, 0.90834, 0.13383), float3(0.04823, 0.01566, 0.83777));
    const float3x3 outputMatrix = float3x3(float3(1.60475, -0.10208, -0.00327), float3(-0.53108, 1.10813, -0.07276), float3(-0.07367, -0.00605, 1.07602));
    return saturate(outputMatrix * RrtAndOdtFit(inputMatrix * color));
}

float3 EncodeSrgb(float3 c)
{
    return mix(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, 12.92 * c, step(c, float3(0.0031308)));
}

// Noise -------------------------------------------------------------------------------------------

float Hash12(float2 p)
{
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float Hash13(float3 p3)
{
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

float Noise(float2 p)
{
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(Hash12(i), Hash12(i + float2(1.0, 0.0)), u.x), mix(Hash12(i + float2(0.0, 1.0)), Hash12(i + float2(1.0, 1.0)), u.x), u.y);
}

float Noise(float3 p)
{
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float a = mix(mix(Hash13(i), Hash13(i + float3(1.0, 0.0, 0.0)), u.x), mix(Hash13(i + float3(0.0, 1.0, 0.0)), Hash13(i + float3(1.0, 1.0, 0.0)), u.x), u.y);
    float b = mix(mix(Hash13(i + float3(0.0, 0.0, 1.0)), Hash13(i + float3(1.0, 0.0, 1.0)), u.x), mix(Hash13(i + float3(0.0, 1.0, 1.0)), Hash13(i + float3(1.0, 1.0, 1.0)), u.x), u.y);
    return mix(a, b, u.z);
}

float Fbm(float2 p)
{
    const float2x2 turn = float2x2(float2(1.6, 1.2), float2(-1.2, 1.6));
    float sum = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; ++i) {
        sum += amplitude * Noise(p);
        p = turn * p + 7.13;
        amplitude *= 0.5;
    }
    return sum;
}

float Fbm(float3 p)
{
    float sum = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; ++i) {
        sum += amplitude * Noise(p);
        p = p * 2.03 + float3(5.1, 1.7, 9.2);
        amplitude *= 0.5;
    }
    return sum;
}

// Anti-aliasing ----------------------------------------------------------------------------------

// The share of a pixel that a line covers: the pixel is `pixel` wide with its middle `d` from the line's middle,
// and the line reaches `halfWidth` to either side. Thin lines fade instead of breaking up.
float LineCoverage(float d, float halfWidth, float pixel)
{
    return saturate((min(d + 0.5 * pixel, halfWidth) - max(d - 0.5 * pixel, -halfWidth)) / pixel);
}

// Per-pixel noise for dithering and for rotating sample patterns.
float InterleavedGradientNoise(float2 pixel)
{
    return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
}
