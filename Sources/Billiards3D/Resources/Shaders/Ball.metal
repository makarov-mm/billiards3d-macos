// A ball: pool balls in their colors with stripes and numbered circles, the cue ball with red dots, or the ivory
// balls of the Russian game with their numbers and an amber cue ball. Polished, with a clear coat. The balls are
// drawn together: each instance its place, its turn and its number. Compiled after Common.metal and Lighting.metal.

#include <metal_stdlib>
using namespace metal;

struct BallVertexIn {
    float3 position [[attribute(0)]];  // on the unit sphere
    float3 normal [[attribute(1)]];
};

struct BallVaryings {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 local;
    float4 params [[flat]];
    float4 extra [[flat]];
    float3 center [[flat]];
};

vertex BallVaryings ballVertex(BallVertexIn in [[stage_in]],
                               uint instance [[instance_id]],
                               constant FrameUniforms& frame [[buffer(1)]],
                               constant BallUniforms& draw [[buffer(3)]],
                               constant BallInstance* balls [[buffer(5)]])
{
    BallInstance ball = balls[uint(draw.draw.x + 0.5) + instance];
    float4 world = ball.model * float4(in.position, 1.0);
    BallVaryings out;
    out.world = world.xyz;
    out.normal = (ball.model * float4(in.normal, 0.0)).xyz;
    out.local = in.position;
    out.params = ball.params;
    out.extra = ball.extra;
    out.center = ball.model[3].xyz;
    out.position = frame.viewProjection * world;
    return out;
}

// The numbered circle, as an angle from its middle.
constant float CircleAngle = 0.36;

float3 PoolColor(int number)
{
    int k = (number - 1) % 8;
    if (k == 0) return float3(0.93, 0.52, 0.0);
    if (k == 1) return float3(0.0, 0.055, 0.38);
    if (k == 2) return float3(0.68, 0.006, 0.006);
    if (k == 3) return float3(0.085, 0.012, 0.2);
    if (k == 4) return float3(0.95, 0.15, 0.0);
    if (k == 5) return float3(0.0, 0.17, 0.042);
    if (k == 6) return float3(0.2, 0.012, 0.01);
    return float3(0.01);
}

// The number as ink, 0 to 1, on the two sides of the ball facing +x and -x; and the circle round it. The atlas is
// read everywhere, where all the pixels of a quad run together, and counts only inside the circle.
float NumberInk(float3 n, int number, thread float& circle, texture2d<float> numbers)
{
    constexpr sampler numberSampler(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(8));
    float side = n.x >= 0.0 ? 1.0 : -1.0;
    float c = abs(n.x);
    float edge = cos(CircleAngle);
    float width = max(fwidth(c), 1e-4);
    circle = smoothstep(edge - width, edge + width, c);
    float2 local = float2(-side * n.z, n.y) / sin(CircleAngle);  // -1 to 1 across the circle, upright
    float2 cell = float2(float((number - 1) % 4), float((number - 1) / 4));
    float2 uv = (cell + 0.5 + float2(0.5, -0.5) * local * 0.86) / 4.0;
    return numbers.sample(numberSampler, uv).r * circle;
}

fragment float4 ballFragment(BallVaryings in [[stage_in]],
                             constant FrameUniforms& frame [[buffer(1)]],
                             constant PassUniforms& pass [[buffer(2)]],
                             constant BallUniforms& draw [[buffer(3)]],
                             depth2d<float> shadowMap [[texture(0)]],
                             texturecube<float> irradiance [[texture(1)]],
                             texturecube<float> prefiltered [[texture(2)]],
                             texture2d<float> brdf [[texture(3)]],
                             texture2d<float> numbers [[texture(4)]])
{
    float3 N = normalize(in.normal);
    float spread = NormalSpread(N);
    float3 n = normalize(in.local);
    int number = int(in.params.x + 0.5);
    bool russian = in.params.y > 0.5;
    float3 white = float3(0.86, 0.85, 0.81);
    float3 albedo = white;
    float circle = 0.0;

    if (russian) {
        // Ivory, a little warm and uneven; the cue ball amber.
        float cloud = Fbm(n * 3.0 + in.params.x * 1.7);
        albedo = number == 0 ? float3(0.8, 0.42, 0.05) * (0.94 + 0.12 * cloud) : float3(0.8, 0.74, 0.58) * (0.95 + 0.1 * cloud * draw.surface.z);
        if (number > 0) {
            float ink = NumberInk(n, number, circle, numbers);
            albedo = mix(albedo, float3(0.18, 0.015, 0.012), ink);
        }
    }
    else if (number == 0) {
        // Red dots on the six axes, to show the spin.
        float d = max(max(abs(n.x), abs(n.y)), abs(n.z));
        float edge = cos(0.1);
        float w = max(fwidth(d), 1e-4);
        albedo = mix(white, float3(0.55, 0.01, 0.015), smoothstep(edge - w, edge + w, d));
    }
    else {
        float3 color = PoolColor(number);
        if (number >= 9) {
            float w = max(fwidth(n.y), 1e-4);
            albedo = mix(color, white, smoothstep(0.58 - w, 0.58 + w, abs(n.y)));
        }
        else {
            albedo = color;
        }
        float ink = NumberInk(n, number, circle, numbers);
        albedo = mix(albedo, white, circle);
        albedo = mix(albedo, float3(0.01), ink);
    }

    float3 V = normalize(pass.eye.xyz - in.world);
    Material m = DefaultMaterial(albedo, WidenRoughness(draw.surface.x, spread));
    m.clearcoat = 1.0;
    m.clearcoatRoughness = WidenRoughness(draw.surface.y, spread);
    m.subsurface = russian ? 0.2 : 0.05;
    // The cloth darkens the underside, most near the point it stands on.
    float above = in.world.y - in.extra.x;
    m.occlusion = mix(0.25, 1.0, smoothstep(0.0, 1.4 * length(in.world - in.center), above + 0.0001));
    float shadow = pass.eye.w > 0.5 ? 1.0 : Shadow(in.world, N, in.position.xy, frame, shadowMap);
    float3 color = Shade(m, in.world, N, V, shadow, frame, irradiance, prefiltered, brdf);

    // A highlighted ball glows at its rim.
    float rim = pow(1.0 - saturate(dot(N, V)), 2.5);
    color += frame.accent.rgb * in.params.w * (0.15 + 1.4 * rim);
    return float4(ApplyFog(color, in.world, frame), in.params.z);
}
