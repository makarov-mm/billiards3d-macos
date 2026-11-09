// The table, the floor, the pockets and the cue: cloth, rubber under cloth, polished wood, leather or net, and the
// marks drawn on the cloth: the spots, the head string, and the lines of the aim. Meshes placed by a matrix.
// Compiled after Common.metal and Lighting.metal.

#include <metal_stdlib>
using namespace metal;

struct TableVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
};

struct TableVaryings {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 uv;
    float3 local;
};

vertex TableVaryings tableVertex(TableVertexIn in [[stage_in]],
                                 constant FrameUniforms& frame [[buffer(1)]],
                                 constant MeshUniforms& mesh [[buffer(4)]])
{
    float4 world = mesh.model * float4(in.position, 1.0);
    TableVaryings out;
    out.world = world.xyz;
    out.normal = (mesh.model * float4(in.normal, 0.0)).xyz;
    out.uv = in.uv;
    out.local = in.position;
    out.position = frame.viewProjection * world;
    return out;
}

// Wood with its grain along x: growth lines of uneven spacing and strength, fine fibres and a soft figure. Detail
// finer than the footprint, the size of a pixel in p, fades to its average instead of flickering.
float3 Wood(float2 p, float3 color, float seed, float footprint)
{
    p += float2(seed * 31.7, seed * 17.3);
    // The growth lines: their spacing drifts across the grain, and they wander a little along it.
    float t = p.y * 7.0 + 2.5 * Fbm(float2(p.y * 0.8, seed * 5.0)) + 0.8 * Fbm(float2(p.x * 0.3, p.y * 1.2)) + 0.2 * sin(p.x * 1.1 + seed * 6.0);
    float ring = floor(t);
    float phase = t - ring;
    float width = 0.2 + 0.3 * Hash12(float2(ring, seed));
    float late = smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(width, width + 0.25, phase));
    late *= 0.35 + 0.9 * Hash12(float2(ring, seed + 7.0));
    late = mix(late, 0.3, smoothstep(0.04, 0.12, footprint));
    float fibers = 0.5 * Noise(float2(p.x * 3.0, p.y * 260.0)) + 0.5 * Noise(float2(p.x * 7.0, p.y * 600.0));
    fibers = mix(fibers, 0.5, smoothstep(0.001, 0.004, footprint));
    float figure = Noise(p * float2(0.8, 2.2) + seed * 9.0);
    return color * (1.0 - 0.2 * late) * (0.9 + 0.16 * fibers) * (0.9 + 0.2 * figure);
}

// Polished stone: a cloudy ground with faint veins wandering through it.
float3 Marble(float2 p, float3 color, float3 veinColor, float seed)
{
    p += seed * 10.0;
    float warp = Fbm(p * 1.1) * 3.0;
    float wave = abs(sin((p.x * 1.2 + p.y * 0.7 + warp) * 2.2));
    float vein = pow(1.0 - wave, 26.0) + 0.3 * pow(1.0 - abs(sin((p.x * 2.6 - p.y * 1.9 + warp * 1.4) * 2.4)), 40.0);
    float3 c = color * (0.85 + 0.3 * Fbm(p * 2.2 + 5.0));
    return mix(c, veinColor, saturate(vein) * 0.35);
}

// Felt: fine fibres along the nap and a soft mottle, fading to their average where they are finer than a pixel.
float3 Cloth(float2 p, float footprint, constant TableUniforms& look)
{
    float fibres = 0.5 * Noise(float2(p.x * 900.0, p.y * 280.0)) + 0.5 * Noise(float2(p.x * 260.0, p.y * 900.0));
    fibres = mix(fibres, 0.5, smoothstep(0.0006, 0.002, footprint));
    float mottle = Fbm(p * 3.0) - 0.5;
    float nap = mix(Noise(float2(p.x * 40.0, p.y * 6.0)), 0.5, smoothstep(0.004, 0.012, footprint));
    return look.cloth.rgb * (0.92 + 0.14 * fibres + 0.12 * mottle * look.clothStyle.w + 0.06 * (nap - 0.5) * look.clothStyle.y);
}

// Coverage of the inside of a circle, over the pixel.
float Inside(float2 p, float2 center, float radius, float pixel)
{
    return 1.0 - smoothstep(radius - pixel, radius + pixel, length(p - center));
}

float SegmentDistance(float2 p, float2 a, float2 b)
{
    float2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-9), 0.0, 1.0);
    return length(p - a - ab * t);
}

// How much of the light from around a point of the cloth the balls near it keep off: dark under each ball, fading
// within a couple of radii.
float BallOcclusion(float2 p, constant TableUniforms& look)
{
    float open = 1.0;
    int count = int(look.counts.z + 0.5);
    for (int i = 0; i < count; ++i) {
        float2 d = (p - look.balls[i].xy) / look.balls[i].z;
        float q = 1.0 / (1.0 + dot(d, d));
        open *= 1.0 - 0.8 * q * sqrt(q);
    }
    return open;
}

// The ring round the pocket called, the same seen on the cloth, the cushions and the rails.
float PocketRing(float2 p, float pixel, constant TableUniforms& look)
{
    if (look.pocketMark.w <= 0.0)
        return 0.0;
    return LineCoverage(abs(length(p - look.pocketMark.xy) - look.pocketMark.z), 0.0022, pixel * 1.5) * look.pocketMark.w;
}

fragment float4 tableFragment(TableVaryings in [[stage_in]],
                              bool frontFacing [[front_facing]],
                              constant FrameUniforms& frame [[buffer(1)]],
                              constant PassUniforms& pass [[buffer(2)]],
                              constant TableUniforms& look [[buffer(3)]],
                              constant MeshUniforms& mesh [[buffer(4)]],
                              depth2d<float> shadowMap [[texture(0)]],
                              texturecube<float> irradiance [[texture(1)]],
                              texturecube<float> prefiltered [[texture(2)]],
                              texture2d<float> brdf [[texture(3)]])
{
    int kind = int(mesh.kind.x + 0.5);
    float3 N = normalize(in.normal);
    if (!frontFacing)
        N = -N;
    // Measured here, where all the pixels of a quad still run together.
    float spread = NormalSpread(N);
    float3 V = normalize(pass.eye.xyz - in.world);
    float2 p = in.world.xz;
    float footprint = length(fwidth(p));
    float pixel = max(footprint * 0.7, 1e-5);
    Material m = DefaultMaterial(float3(0.5), 0.5);
    float3 glow = float3(0.0);
    float coverage = 1.0;
    float contact = 1.0;  // the shade of the balls close by, on the key light too

    if (kind == 0 || kind == 1) {
        m.albedo = Cloth(p, footprint, look);
        m.roughness = look.clothStyle.x;
        m.subsurface = 0.1;
        if (kind == 1) {
            m.albedo *= 0.92;
        }
        else {
            // The holes of the pockets.
            for (int i = 0; i < 6; ++i)
                coverage *= 1.0 - Inside(p, look.holes[i].xy, look.holes[i].z, pixel);
            // The spots, and the head string when a ball is placed behind it.
            float R = look.table.z;
            float spotRadius = look.marks.y > 0.5 ? R * 0.18 : R * 0.3;
            float spot = 0.0;
            spot = max(spot, Inside(p, float2(look.table.x * 0.25, 0.0), spotRadius, pixel));
            spot = max(spot, Inside(p, float2(-look.table.x * 0.25, 0.0), spotRadius, pixel));
            spot = max(spot, Inside(p, float2(0.0), spotRadius * 0.8, pixel));
            m.albedo = mix(m.albedo, float3(0.75), spot * 0.85);
            if (look.marks.x > 0.5) {
                float line = LineCoverage(abs(p.x - look.table.w), 0.0012, max(fwidth(p.x), 1e-5)) * step(abs(p.y), look.table.y * 0.5);
                m.albedo = mix(m.albedo, float3(0.8), line * 0.7);
            }
            // The lines of the aim, glowing on the cloth.
            int guides = int(look.counts.y + 0.5);
            for (int i = 0; i < guides; ++i) {
                float d = SegmentDistance(p, look.guides[i].xy, look.guides[i].zw);
                float line = LineCoverage(d, 0.0012, pixel * 1.4);
                glow += look.guideColor.rgb * look.guideColor.a * line;
                m.albedo = mix(m.albedo, look.guideColor.rgb * 0.6, line * 0.5);
            }
        }
        float balls = BallOcclusion(p, look);
        m.occlusion = balls;
        contact = mix(1.0, balls, 0.6);
        // The sheen of cloth at grazing angles.
        m.emissive += look.cloth.rgb * look.clothStyle.z * pow(1.0 - saturate(dot(N, V)), 4.0) * 0.4;
    }
    else if (kind == 2 || kind == 3) {
        float4 style = kind == 2 ? look.railStyle : look.frameStyle;
        float3 color = kind == 2 ? look.railColor.rgb : look.frameColor.rgb;
        // The grain runs along the rail.
        bool alongX = abs(N.x) < 0.7 && (kind == 3 || abs(p.y) > look.table.y * 0.5 + 0.02);
        float2 grain = alongX ? float2(p.x, p.y + in.world.y * 0.6) : float2(p.y, p.x + in.world.y * 0.6);
        if (kind == 3 && abs(N.y) < 0.5 && length(in.local.xz) < 0.2 && in.world.y < -0.15)
            grain = float2(in.world.y * 0.3, atan2(in.local.z, in.local.x) * 0.1);  // a turned leg
        m.albedo = style.z > 0.5 ? color * (0.95 + 0.1 * Noise(p * 30.0)) : Wood(grain * float2(0.6, 1.6), color, style.w, footprint);
        m.roughness = style.x;
        m.clearcoat = style.y;
        m.clearcoatRoughness = 0.09;
        if (kind == 2) {
            // The openings of the pockets.
            for (int i = 0; i < 6; ++i)
                coverage *= 1.0 - Inside(p, look.cups[i].xy, look.cups[i].z, pixel);
            // The sights inlaid in the top.
            if (N.y > 0.9) {
                float inlay = 0.0;
                int sights = int(look.counts.x + 0.5);
                for (int i = 0; i < sights; ++i) {
                    float2 d = abs(p - look.sights[i].xy);
                    float size = look.sights[i].z;
                    float shape = look.sightStyle.z > 0.5 ? length(d) : (d.x + d.y) * 0.75;
                    inlay = max(inlay, 1.0 - smoothstep(size - pixel, size + pixel, shape));
                }
                float pearl = 0.85 + 0.15 * sin(dot(p, float2(900.0, 700.0)));
                m.albedo = mix(m.albedo, look.sightColor.rgb * pearl, inlay);
                m.metallic = mix(m.metallic, look.sightStyle.x, inlay);
                m.roughness = mix(m.roughness, look.sightStyle.y, inlay);
                glow += look.sightColor.rgb * look.sightStyle.w * inlay;
            }
        }
        // Darker toward the floor.
        m.occlusion = mix(0.55, 1.0, smoothstep(-0.35, 0.02, in.world.y));
    }
    else if (kind == 4) {
        // Leather, or below the cloth a net of cord.
        m.albedo = look.pocketColor.rgb * (0.85 + 0.3 * Noise(in.uv * float2(60.0, 300.0)));
        m.roughness = look.pocketStyle.x;
        m.occlusion = mix(0.25, 1.0, smoothstep(-0.1, 0.03, in.world.y));
        float2 net = float2(in.uv.x * 40.0, in.uv.y * 70.0);
        float2 width = fwidth(net) * 0.8 + 0.12;
        if (look.pocketStyle.y > 0.5 && in.world.y < -0.012) {
            float2 cell = abs(fract(net + float2(0.5 * floor(net.y), 0.0)) - 0.5);
            float cord = max(1.0 - smoothstep(width.x * 0.5, width.x, cell.x), 1.0 - smoothstep(width.y * 0.5, width.y, cell.y));
            coverage = cord;
            m.albedo = look.pocketColor.rgb * 1.6;
        }
    }
    else if (kind == 5) {
        int pattern = int(look.floorStyle.y + 0.5);
        if (pattern == 0) {
            // Boards, each its own shade.
            float board = floor(p.y / 0.18);
            float2 q = float2(p.x + board * 1.37, p.y);
            m.albedo = Wood(q * float2(0.5, 2.0), look.floorColor.rgb * (0.85 + 0.3 * Hash12(float2(board, 3.0))), 0.2 + board * 0.13, footprint);
            float seam = 1.0 - smoothstep(0.0, 0.004 + footprint, abs(fract(p.y / 0.18) - 0.0) * 0.18);
            m.albedo *= 1.0 - 0.5 * seam;
        }
        else if (pattern == 1) {
            m.albedo = look.floorColor.rgb * (0.85 + 0.3 * mix(Noise(p * 120.0), 0.5, smoothstep(0.004, 0.012, footprint)));
        }
        else {
            // Square slabs of stone, each cut from another part of the block, with thin joints between.
            float2 tile = floor(p / 0.9);
            float2 inTile = fract(p / 0.9);
            float shade = 0.85 + 0.3 * Hash12(tile + 7.0);
            m.albedo = Marble(p * 0.7 + tile * 3.7, look.floorColor.rgb * shade, look.floorColor.rgb * 1.8, 3.0);
            float2 edge = min(inTile, 1.0 - inTile) * 0.9;
            float joint = 1.0 - smoothstep(0.0015, 0.0015 + footprint, min(edge.x, edge.y));
            m.albedo *= 1.0 - 0.6 * joint;
        }
        m.roughness = look.floorStyle.x;
        // The table's shadow and the darkness away from the lamp.
        float r = length(max(abs(p) - look.table.xy * 0.5, float2(0.0)));
        m.occlusion = mix(0.35, 1.0, smoothstep(0.0, 0.8, r));
        m.albedo *= mix(1.0, 0.1, smoothstep(0.0, 2.2, r));
    }
    else {
        // The cue, by the distance from its tip.
        float z = in.local.z;
        float2 grain = float2(z * 3.0, atan2(in.local.y, in.local.x) * 0.02);
        if (z < 0.009) {
            m.albedo = float3(0.06, 0.18, 0.55) * (0.8 + 0.4 * Noise(in.local.xy * 3000.0));
            m.roughness = 0.9;
        }
        else if (z < 0.03) {
            m.albedo = float3(0.85, 0.83, 0.76);
            m.roughness = 0.3;
        }
        else if (z < 0.74) {
            m.albedo = Wood(grain * float2(1.0, 30.0), float3(0.72, 0.56, 0.36), 0.4, footprint);
            m.roughness = 0.35;
            m.clearcoat = 0.5;
        }
        else if (z < 0.77) {
            m.albedo = float3(0.75, 0.74, 0.72);
            m.metallic = 1.0;
            m.roughness = 0.2;
        }
        else if (z < 1.04) {
            // The forearm: dark wood with long points of maple.
            float angle = atan2(in.local.y, in.local.x);
            float point = step(abs(fract(angle / 6.2831853 * 4.0) - 0.5) * 2.0, saturate((1.04 - z) / 0.22) * 0.7);
            m.albedo = mix(Wood(grain * float2(1.0, 30.0), float3(0.07, 0.025, 0.015), 0.8, footprint), float3(0.7, 0.55, 0.35), point);
            m.roughness = 0.25;
            m.clearcoat = 0.8;
        }
        else if (z < 1.33) {
            // The wrap.
            float weave = 0.5 + 0.5 * sin(z * 900.0) * sin(atan2(in.local.y, in.local.x) * 40.0);
            m.albedo = float3(0.025, 0.025, 0.03) * (0.8 + 0.4 * mix(weave, 0.5, smoothstep(0.002, 0.006, footprint)));
            m.roughness = 0.75;
        }
        else {
            m.albedo = Wood(grain * float2(1.0, 30.0), float3(0.06, 0.02, 0.012), 0.3, footprint);
            m.roughness = 0.25;
            m.clearcoat = 0.8;
        }
    }

    if (kind <= 2) {
        float ring = PocketRing(p, pixel, look);
        glow += look.guideColor.rgb * ring * 1.8;
        m.albedo = mix(m.albedo, look.guideColor.rgb * 0.5, ring * 0.6);
    }
    if (coverage <= 0.002)
        discard_fragment();
    m.roughness = WidenRoughness(m.roughness, spread);
    m.clearcoatRoughness = WidenRoughness(m.clearcoatRoughness, spread);
    // The cue is too thin to shade itself cleanly; it still casts its shadow on the table.
    float shadow = (pass.eye.w > 0.5 || kind == 6 ? 1.0 : Shadow(in.world, N, in.position.xy, frame, shadowMap)) * contact;
    float3 color = Shade(m, in.world, N, V, shadow, frame, irradiance, prefiltered, brdf) + glow;
    return float4(ApplyFog(color, in.world, frame), coverage);
}
