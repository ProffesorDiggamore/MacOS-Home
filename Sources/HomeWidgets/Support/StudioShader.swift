/// Metal source for the wallpaper renderer, compiled at runtime.
///
/// Two kinds of scene share one studio light rig:
/// - surfaces seen from straight above (liquid chrome, veins, satin, clay terraces),
///   shaded from a height field's normal, and
/// - real 3D objects (glass ribbon, liquid metal, dark glass, glass pills, glass wave,
///   twin ribbons, glass knot, glass rings, frosted ribbon), ray marched against signed
///   distance fields with mirror bounces and refraction. Glass splits red, green and
///   blue across samples for natural dispersion.
enum StudioShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct Light { float4 dir; float4 t1; float4 t2; float4 color; float4 size; };

struct Params {
    uint width; uint height; uint originY; uint scene;
    uint samples; uint pad0; uint pad1; uint pad2;
    float4 seed; float4 seed2;
    float4 skyTop; float4 skyMid; float4 skyBottom;
    float4 metal;   // rgb tint, w iridescence
    float4 base;    // rgb surface colour, w gloss blur
    float4 glass;   // rgb absorption, w index of refraction
    float4 misc;    // x exposure, y vignette, z camera distance, w grain
    float4 rot0; float4 rot1; float4 rot2; float4 offset;
    float4 sun;     // xyz key direction for clay
};

struct Scene { constant Params* P; constant Light* L; constant float4* B; };

// MARK: noise

float2 hash22(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float hash11(float n) { return fract(sin(n * 12.9898 + 4.1414) * 43758.5453); }

float gnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = dot(hash22(i), f);
    float b = dot(hash22(i + float2(1, 0)), f - float2(1, 0));
    float c = dot(hash22(i + float2(0, 1)), f - float2(0, 1));
    float d = dot(hash22(i + float2(1, 1)), f - float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(float2 p, int octaves) {
    float sum = 0.0;
    float amp = 0.5;
    float2x2 m = float2x2(float2(1.6, 1.2), float2(-1.2, 1.6));
    for (int i = 0; i < octaves; i++) {
        sum += amp * gnoise(p);
        p = m * p;
        amp *= 0.5;
    }
    return sum;
}

// MARK: studio lighting

float3 env(float3 d, float blur, thread const Scene& S) {
    float3 c = mix(S.P->skyBottom.rgb, S.P->skyMid.rgb, smoothstep(-0.75, 0.1, d.y));
    c = mix(c, S.P->skyTop.rgb, smoothstep(-0.1, 0.95, d.y));
    for (int i = 0; i < 5; i++) {
        Light l = S.L[i];
        float k = dot(d, l.dir.xyz);
        if (k <= 0.02) continue;
        float2 q = float2(dot(d, l.t1.xyz), dot(d, l.t2.xyz)) / k;
        float2 e = abs(q) - l.size.xy;
        float soft = l.size.z + blur;
        float m = (1.0 - smoothstep(-soft, soft, e.x)) * (1.0 - smoothstep(-soft, soft, e.y));
        // Softboxes fall off along their length, like real studio lights.
        m *= mix(0.3, 1.0, smoothstep(-l.size.y, l.size.y, q.y));
        c += l.color.rgb * m;
    }
    return max(c, float3(0.0));
}

float3 film(float cosTheta, thread const Scene& S) {
    float amount = S.P->metal.w;
    if (amount <= 0.0) return float3(1.0);
    float x = 1.0 - cosTheta;
    float3 tint = 0.6 + 0.4 * cos(6.2831 * (x * 1.7 + S.P->seed.w + float3(0.0, 0.33, 0.67)));
    return mix(float3(1.0), tint * 1.25, amount * (0.25 + 0.75 * x));
}

float3 chromeColor(float3 rd, float3 n, thread const Scene& S) {
    float c = clamp(-dot(rd, n), 0.0, 1.0);
    float3 f0 = S.P->metal.rgb;
    float3 fresnel = f0 + (1.0 - f0) * pow(1.0 - c, 5.0);
    return fresnel * film(c, S);
}

// MARK: height fields (seen from above)

float hLiquid(float2 p, thread const Scene& S) {
    float2 o = S.P->seed.xy * 40.0;
    float2 q = float2(fbm(p + o, 3), fbm(p + o + float2(5.2, 1.3), 3));
    float2 r = float2(fbm(p + 1.6 * q + float2(1.7, 9.2), 3), fbm(p + 1.6 * q + float2(8.3, 2.8), 3));
    return fbm(p + 1.5 * r, 2);
}

float hSatin(float2 p, thread const Scene& S) {
    float2 o = S.P->seed.yz * 40.0;
    float2 w = float2(fbm(p * 0.35 + o, 3), fbm(p * 0.35 + o + float2(3.1, 7.7), 3));
    float2 q = p + 1.7 * w;
    float a = S.P->seed.x * 6.2831;
    float x = dot(q, float2(cos(a), sin(a))) * 1.7;
    return 0.5 * sin(x) + 0.25 * sin(x * 2.1 + 1.3 + 2.5 * fbm(q * 0.45 + o.yx, 2));
}

float hClay(float2 p, thread const Scene& S) {
    float2 o = S.P->seed.zw * 40.0;
    float2 q = float2(fbm(p * 0.8 + o, 3), fbm(p * 0.8 + o + float2(4.4, 2.2), 3));
    float h = fbm(p * 0.7 + 1.3 * q + o.yx, 3) * 1.7 + 0.5;
    float steps = 5.0;
    float f = h * steps;
    float level = floor(f);
    float t = smoothstep(0.6, 1.0, fract(f));
    return (level + t) / steps;
}

float veinField(float2 p, thread const Scene& S) {
    float2 o = S.P->seed.xw * 40.0;
    float2 q = float2(fbm(p * 0.9 + o, 3), fbm(p * 0.9 + o + float2(2.7, 6.1), 3));
    return fbm(p * 0.8 + 1.3 * q, 3);
}

float3 shadeVeins(float2 p, thread const Scene& S) {
    float e = 0.002;
    float f = veinField(p, S);
    float2 g = float2(veinField(p + float2(e, 0), S) - f, veinField(p + float2(0, e), S) - f) / e;
    float gl = max(length(g), 1e-4);
    float k = 2.0;
    float fc = (fract(f * k + 0.5) - 0.5) / k;
    float d = fc / gl;
    float r = mix(0.015, 0.06, smoothstep(-0.3, 0.4, gnoise(p * 0.9 + S.P->seed.yx * 30.0)));
    float3 rd = float3(0, 0, -1);
    if (abs(d) < r) {
        float h = sqrt(r * r - d * d);
        float3 n = normalize(float3(g / gl * d, h));
        return env(reflect(rd, n), 0.0, S) * chromeColor(rd, n, S);
    }
    // Glossy dark ground between the veins, with a soft groove where they meet it.
    float3 n = normalize(float3(-g * 0.02, 1.0));
    float c = clamp(n.z, 0.0, 1.0);
    float fr = 0.04 + 0.96 * pow(1.0 - c, 5.0);
    float groove = smoothstep(r, r * 3.0, abs(d));
    return (S.P->base.rgb * 0.25 + env(reflect(rd, n), 0.25, S) * fr) * mix(0.35, 1.0, groove);
}

float3 shadeHeight(float2 p, thread const Scene& S) {
    float3 rd = float3(0, 0, -1);
    float e = 0.0025;
    uint scene = S.P->scene;
    if (scene == 1) return shadeVeins(p, S);
    float h0, hx, hy, amp;
    if (scene == 0) {
        h0 = hLiquid(p, S); hx = hLiquid(p + float2(e, 0), S); hy = hLiquid(p + float2(0, e), S); amp = 0.8;
    } else if (scene == 2) {
        h0 = hSatin(p, S); hx = hSatin(p + float2(e, 0), S); hy = hSatin(p + float2(0, e), S); amp = 1.3;
    } else {
        h0 = hClay(p, S); hx = hClay(p + float2(e, 0), S); hy = hClay(p + float2(0, e), S); amp = 0.22;
    }
    float3 n = normalize(float3(-(hx - h0) / e * amp, -(hy - h0) / e * amp, 1.0));
    if (scene == 0) {
        return env(reflect(rd, n), 0.0, S) * chromeColor(rd, n, S);
    }
    if (scene == 2) {
        float c = clamp(n.z, 0.0, 1.0);
        float fr = 0.04 + 0.96 * pow(1.0 - c, 5.0);
        float3 diffuse = S.P->skyMid.rgb * 0.25 * (0.4 + 0.6 * c);
        for (int i = 0; i < 4; i++) {
            float area = S.L[i].size.x * S.L[i].size.y;
            diffuse += max(S.L[i].color.rgb, 0.0) * area * 1.4 * pow(max(dot(n, S.L[i].dir.xyz), 0.0), 2.0);
        }
        float3 sheen = env(reflect(rd, n), 0.2 + S.P->base.w, S);
        return S.P->base.rgb * diffuse + sheen * (fr * 0.8 + 0.1) * film(c, S);
    }
    // Clay terraces: soft key light, soft shadows and contact darkening.
    float3 sun = S.P->sun.xyz;
    float lambert = max(dot(n, sun), 0.0);
    float z0 = h0 * amp;
    float shadow = 1.0;
    float2 sd = normalize(sun.xy);
    float rise = sun.z / length(sun.xy);
    float s = 0.01;
    for (int i = 0; i < 18; i++) {
        float z = z0 + s * rise;
        float hz = hClay(p + sd * s, S) * amp;
        shadow = min(shadow, clamp(14.0 * (z - hz) / s + 0.5, 0.0, 1.0));
        s += 0.012 + s * 0.18;
        if (shadow <= 0.0) break;
    }
    float occ = 0.0;
    for (int i = 0; i < 4; i++) {
        float a = 1.5708 * float(i) + 0.4;
        occ += max(hClay(p + 0.08 * float2(cos(a), sin(a)), S) - h0, 0.0);
    }
    float ao = clamp(1.0 - occ * 2.2, 0.35, 1.0);
    float3 light = S.P->skyMid.rgb * 0.35 * ao + float3(0.85) * lambert * shadow;
    float3 col = S.P->base.rgb * (0.25 + light) * mix(0.82, 1.05, h0);
    float c = clamp(n.z, 0.0, 1.0);
    col += env(reflect(rd, n), 0.6, S) * (0.03 + 0.2 * pow(1.0 - c, 4.0));
    return col;
}

// MARK: 3D distance fields

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float3 toObject(float3 p, thread const Scene& S) {
    p -= S.P->offset.xyz;
    return float3(dot(S.P->rot0.xyz, p), dot(S.P->rot1.xyz, p), dot(S.P->rot2.xyz, p));
}

float sdRibbon(float3 p, thread const Scene& S) {
    float a = atan2(p.z, p.x);
    float radius = 1.5 + 0.35 * sin(2.0 * a + S.P->seed.x * 6.2831);
    float lift = 0.45 * sin(3.0 * a + S.P->seed.y * 6.2831);
    float2 q = float2(length(p.xz) - radius, p.y - lift);
    float tw = a * S.P->seed2.x + S.P->seed.z * 6.2831;
    float c = cos(tw);
    float s = sin(tw);
    q = float2(c * q.x - s * q.y, s * q.x + c * q.y);
    float2 d = abs(q) - float2(0.5, 0.08);
    return (length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 0.04) * 0.55;
}

// A wide, thin sheet of glass rolling across the frame, turning over as it goes.
float sdWave(float3 p, thread const Scene& S) {
    float y = 0.5 * sin(0.8 * p.x + S.P->seed.x * 6.2831) + 0.2 * sin(1.9 * p.x + S.P->seed.y * 6.2831);
    float z = 0.5 * sin(0.6 * p.x + S.P->seed.z * 6.2831);
    float2 q = float2(p.y - y, p.z - z);
    float tw = (0.5 + 0.5 * S.P->seed2.x) * p.x + S.P->seed.w * 6.2831;
    float c = cos(tw);
    float s = sin(tw);
    q = float2(c * q.x - s * q.y, s * q.x + c * q.y);
    float2 d = abs(q) - float2(0.05, 0.55);
    return (length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 0.035) * 0.45;
}

// Two narrow bands braided around one looping path, always on opposite sides so they never touch.
float sdTwin(float3 p, thread const Scene& S) {
    float a = atan2(p.z, p.x);
    float radius = 1.5 + 0.3 * sin(2.0 * a + S.P->seed.x * 6.2831);
    float2 q = float2(length(p.xz) - radius, p.y - 0.3 * sin(3.0 * a + S.P->seed.y * 6.2831));
    float d = 1e9;
    for (int i = 0; i < 2; i++) {
        // A whole number of turns per loop keeps the braid seamless where atan2 wraps.
        float w = 3.0 * a + S.P->seed.z * 6.2831 + 3.1416 * float(i);
        float c = cos(w);
        float s = sin(w);
        float2 r = q - 0.42 * float2(c, s);
        r = float2(c * r.x + s * r.y, -s * r.x + c * r.y);
        float2 e = abs(r) - float2(0.05, 0.3);
        d = min(d, length(max(e, 0.0)) + min(max(e.x, e.y), 0.0) - 0.03);
    }
    return d * 0.4;
}

// A glass tube tied as a torus knot: a trefoil, or a five-lobed knot.
float sdKnot(float3 p, thread const Scene& S) {
    float a = atan2(p.z, p.x);
    float2 q = float2(length(p.xz) - 1.25, p.y);
    float n = S.P->seed2.x < 1.2 ? 1.5 : 2.5;
    float d = 1e9;
    for (int i = 0; i < 2; i++) {
        float w = n * (a + 6.2831 * float(i)) + S.P->seed.x * 6.2831;
        d = min(d, length(q - 0.5 * float2(cos(w), sin(w))) - 0.26);
    }
    return d * 0.5;
}

float sdTorus(float3 q, float tube) { return length(float2(length(q.xz) - 0.95, q.y)) - tube; }

// Three linked rings: the middle one stands upright through the two tilted end rings.
float sdRings(float3 p, thread const Scene& S) {
    float tube = 0.17 + 0.1 * S.P->seed.y;
    float d = sdTorus(p.xzy, tube);
    for (int i = 0; i < 2; i++) {
        float3 q = p - float3(i == 0 ? -1.05 : 1.05, 0.0, 0.0);
        float t = ((i == 0 ? S.P->seed.z : S.P->seed.w) - 0.5) * 1.0;
        float c = cos(t);
        float s = sin(t);
        q.yz = float2(c * q.y - s * q.z, s * q.y + c * q.z);
        d = min(d, sdTorus(q, tube));
    }
    return d;
}

float sdBlobs(float3 p, thread const Scene& S) {
    p += 0.28 * sin(p.yzx * 1.3 + S.P->seed.xyz * 6.2831);
    float d = 1e9;
    for (int i = 0; i < 8; i++) {
        float4 b = S.B[i];
        d = smin(d, length(p - b.xyz) - b.w, 0.5);
    }
    return d * 0.7;
}

float sdPills(float3 p, thread const Scene& S) {
    float spacing = 0.62;
    float d = 1e9;
    for (int layer = 0; layer < 2; layer++) {
        float3 q = p - float3(float(layer) * spacing * 0.5, 0.0, -float(layer) * 0.75);
        float id = round(q.x / spacing);
        for (int k = -1; k <= 1; k++) {
            float cell = id + float(k);
            float x = q.x - cell * spacing;
            float salt = cell * 7.31 + float(layer) * 31.7 + S.P->seed.x * 97.0;
            float halfLength = 0.5 + 1.7 * hash11(salt);
            float lift = (hash11(salt + 3.3) - 0.5) * 2.2;
            float3 r = float3(x, q.y - lift, q.z);
            r.y -= clamp(r.y, -halfLength, halfLength);
            d = min(d, length(r) - 0.24);
        }
    }
    return d;
}

float map(float3 p, thread const Scene& S) {
    float3 q = toObject(p, S);
    uint scene = S.P->scene;
    if (scene == 4 || scene == 12) return sdRibbon(q, S);
    if (scene == 7) return sdPills(q, S);
    if (scene == 8) return sdWave(q, S);
    if (scene == 9) return sdTwin(q, S);
    if (scene == 10) return sdKnot(q, S);
    if (scene == 11) return sdRings(q, S);
    return sdBlobs(q, S);
}

float3 normalAt(float3 p, thread const Scene& S) {
    const float e = 0.0007;
    const float2 k = float2(1, -1);
    return normalize(k.xyy * map(p + k.xyy * e, S) + k.yyx * map(p + k.yyx * e, S) +
                     k.yxy * map(p + k.yxy * e, S) + k.xxx * map(p + k.xxx * e, S));
}

bool march(float3 ro, float3 rd, float side, thread float& t, thread const Scene& S) {
    t = 0.0;
    for (int i = 0; i < 240; i++) {
        float d = side * map(ro + rd * t, S);
        if (d < 0.00015) return true;
        t += max(d, 0.0004);
        if (t > 24.0) break;
    }
    return false;
}

float3 trace(float3 ro, float3 rd, float ior, thread const Scene& S) {
    uint scene = S.P->scene;
    bool glass = scene != 5;
    // Frosted glass scatters light: blurry reflections, a milky surface, a soft view through.
    float frost = scene == 12 ? 0.45 : 0.0;
    bool passed = false;
    float3 col = float3(0.0);
    float3 through = float3(1.0);
    bool inside = false;
    int bounces = 0;
    for (int event = 0; event < 7; event++) {
        float t;
        bool hit = march(ro, rd, inside ? -1.0 : 1.0, t, S);
        if (!hit) {
            col += through * env(rd, passed ? frost : 0.0, S);
            return col;
        }
        float3 p = ro + rd * t;
        float3 n = normalAt(p, S);
        p -= n * map(p, S);  // land exactly on the surface
        if (!glass) {
            through *= chromeColor(rd, n, S);
            rd = reflect(rd, n);
            ro = p + n * 0.004;
            continue;
        }
        if (!inside) {
            float c = clamp(-dot(rd, n), 0.0, 1.0);
            float fr = 0.04 + 0.96 * pow(1.0 - c, 5.0);
            col += through * fr * env(reflect(rd, n), 0.03 + frost * 0.5, S) * film(c, S);
            through *= (1.0 - fr);
            if (frost > 0.0) {
                col += through * frost * env(n, 0.9, S);
                through *= 1.0 - frost;
            }
            rd = refract(rd, n, 1.0 / ior);
            ro = p - n * 0.004;
            inside = true;
        } else {
            through *= exp(-S.P->glass.rgb * t);
            float3 exitDir = refract(rd, -n, ior);
            if (dot(exitDir, exitDir) < 1e-4 && bounces < 2) {
                bounces++;
                rd = reflect(rd, -n);
                ro = p - n * 0.004;
            } else if (dot(exitDir, exitDir) < 1e-4) {
                ro = p + n * 0.004;
                inside = false;
                passed = true;
            } else {
                rd = exitDir;
                ro = p + n * 0.004;
                inside = false;
                passed = true;
            }
        }
    }
    return col + through * env(rd, 0.0, S) * 0.5;
}

// MARK: kernel

float3 aces(float3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

kernel void studio(device uint* out [[buffer(0)]],
                   constant Params& P [[buffer(1)]],
                   constant Light* L [[buffer(2)]],
                   constant float4* B [[buffer(3)]],
                   uint2 gid [[thread_position_in_grid]]) {
    uint x = gid.x;
    uint y = gid.y + P.originY;
    if (x >= P.width || y >= P.height) return;
    Scene S = { &P, L, B };
    float w = float(P.width);
    float h = float(P.height);
    float aspect = w / h;
    bool isFlat = P.scene < 4;
    bool glass = P.scene >= 4 && P.scene != 5;
    uint samples = max(P.samples, 1u);
    float3 sum = float3(0.0);
    float3 weight = float3(0.0);
    for (uint s = 0; s < samples; s++) {
        float2 jitter = fract(float2(0.5) + float(s) * float2(0.7548776662, 0.5698402910));
        float2 uv = (float2(float(x), float(y)) + jitter) / float2(w, h);
        float2 screen = float2((uv.x - 0.5) * aspect, 0.5 - uv.y);
        if (isFlat) {
            float scale = P.scene == 0 ? 0.95 : (P.scene == 1 ? 2.0 : (P.scene == 2 ? 2.4 : 1.8));
            sum += shadeHeight(screen * scale + P.seed2.yz * 10.0, S);
            weight += float3(1.0);
        } else {
            float3 ro = float3(0.0, 0.0, P.misc.z);
            float3 rd = normalize(float3(screen * 0.75, -1.0));
            if (glass) {
                uint channel = s % 3;
                float ior = P.glass.w + (float(channel) - 1.0) * 0.022;
                float3 mask = channel == 0 ? float3(1, 0, 0) : (channel == 1 ? float3(0, 1, 0) : float3(0, 0, 1));
                sum += trace(ro, rd, ior, S) * mask;
                weight += mask;
            } else {
                sum += trace(ro, rd, 1.0, S);
                weight += float3(1.0);
            }
        }
    }
    float3 col = sum / max(weight, float3(1.0));
    float2 uv = (float2(float(x), float(y)) + 0.5) / float2(w, h);
    float2 v = (uv - 0.5) * float2(aspect / 1.6, 1.0);
    col *= 1.0 - P.misc.y * dot(v, v);
    col = aces(col * P.misc.x);
    col = pow(col, float3(1.0 / 2.2));
    float noise = fract(sin(dot(float2(float(x), float(y)), float2(12.9898, 78.233))) * 43758.5453)
                + fract(sin(dot(float2(float(y), float(x)), float2(39.346, 11.135))) * 24634.6345) - 1.0;
    col += noise * (P.misc.w + 0.5 / 255.0);
    uint3 c = uint3(clamp(col, 0.0, 1.0) * 255.0 + 0.5);
    out[y * P.width + x] = c.r | (c.g << 8) | (c.b << 16) | (255u << 24);
}
"""#
}
