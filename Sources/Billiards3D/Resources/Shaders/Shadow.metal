// The depth of the table, the balls and the cue as the key light sees them. The balls are drawn together, each
// instance placed by its own matrix. Compiled after Common.metal.

#include <metal_stdlib>
using namespace metal;

struct ShadowVertexIn {
    float3 position [[attribute(0)]];
};

struct ShadowVaryings {
    float4 position [[position]];
};

vertex ShadowVaryings shadowVertex(ShadowVertexIn in [[stage_in]],
                                   uint instance [[instance_id]],
                                   constant FrameUniforms& frame [[buffer(1)]],
                                   constant ShadowUniforms& caster [[buffer(3)]],
                                   constant BallInstance* balls [[buffer(5)]])
{
    float4x4 model = caster.draw.x > 0.5 ? balls[uint(caster.draw.y + 0.5) + instance].model : caster.model;
    ShadowVaryings out;
    out.position = frame.lightViewProjection * model * float4(in.position, 1.0);
    return out;
}

// Depth only.
fragment void shadowFragment()
{
}
