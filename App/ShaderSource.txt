#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 5×7 pixel font — A-Z (0-25), 0-9 (26-35), space (36)
// Each glyph: 7 rows, each row is 5-bit data in a uint8 (bit4=leftmost column)
constant uint8_t ditherFont[37 * 7] = {
  // A     B     C     D     E     F     G
  14,17,17,31,17,17,17, 30,17,17,30,17,17,30, 14,17,16,16,16,17,14,
  28,18,17,17,17,18,28, 31,16,16,30,16,16,31, 31,16,16,30,16,16,16,
  14,17,16,23,17,17,15,
  // H     I     J     K     L     M     N
  17,17,17,31,17,17,17, 31, 4, 4, 4, 4, 4,31, 31, 2, 2, 2, 2,18,12,
  17,18,20,24,20,18,17, 16,16,16,16,16,16,31, 17,27,21,17,17,17,17,
  17,25,21,19,17,17,17,
  // O     P     Q     R     S     T     U
  14,17,17,17,17,17,14, 30,17,17,30,16,16,16, 14,17,17,17,21,18,13,
  30,17,17,30,20,18,17, 15,16,16,14, 1, 1,30, 31, 4, 4, 4, 4, 4, 4,
  17,17,17,17,17,17,14,
  // V     W     X     Y     Z
  17,17,17,17,10,10, 4, 17,17,17,21,21,27,17, 17,10, 4, 4, 4,10,17,
  17,17,10, 4, 4, 4, 4, 31, 2, 4, 8, 8,16,31,
  // 0     1     2     3     4     5     6
  14,17,19,21,25,17,14,  4,12, 4, 4, 4, 4,14, 14,17, 1, 6, 8,16,31,
  31, 2, 4, 6, 1,17,14,  2, 6,10,18,31, 2, 2, 31,16,30, 1, 1,17,14,
   6, 8,16,30,17,17,14,
  // 7     8     9    space
  31, 1, 2, 4, 8, 8, 8, 14,17,17,14,17,17,14, 14,17,17,15, 1, 2,12,
   0, 0, 0, 0, 0, 0, 0,
};

// 8×8 Bayer ordered dithering matrix (values 0–63)
constant int bayerMatrix[64] = {
   0, 32,  8, 40,  2, 34, 10, 42,
  48, 16, 56, 24, 50, 18, 58, 26,
  12, 44,  4, 36, 14, 46,  6, 38,
  60, 28, 52, 20, 62, 30, 54, 22,
   3, 35, 11, 43,  1, 33,  9, 41,
  51, 19, 59, 27, 49, 17, 57, 25,
  15, 47,  7, 39, 13, 45,  5, 37,
  63, 31, 55, 23, 61, 29, 53, 21
};

// ── Utilities ──────────────────────────────────────────────────────────────

// Remap a value from one range to another (from paper-design/shaders best practice)
float mapRange(float value, float inMin, float inMax, float outMin, float outMax) {
  return outMin + (outMax - outMin) * ((value - inMin) / (inMax - inMin));
}
float mapRangeClamped(float value, float inMin, float inMax, float outMin, float outMax) {
  return clamp(mapRange(value, inMin, inMax, outMin, outMax), min(outMin, outMax), max(outMin, outMax));
}

// Gradient noise (smoother than value noise, fewer directional artifacts)
// Sine-free hash (Dave Hoskins' hash22). Every smoothNoise call makes four of these, and the
// noisy shaders make up to seven smoothNoise calls per pixel, so the two sin() this used to
// cost were the most repeated instruction in the file.
float2 hash2(float2 p) {
  float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

float smoothNoise(float2 p) {
  float2 i = floor(p);
  float2 f = fract(p);
  // Quintic interpolation (C2 continuous) instead of cubic — fewer banding artifacts
  float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(mix(dot(hash2(i),               f),
                 dot(hash2(i + float2(1,0)), f - float2(1,0)), u.x),
             mix(dot(hash2(i + float2(0,1)), f - float2(0,1)),
                 dot(hash2(i + float2(1,1)), f - float2(1,1)), u.x), u.y);
}

// Fractional Brownian Motion — layered noise octaves for organic detail
float fbm(float2 p, int octaves) {
  float value = 0.0, amplitude = 0.5, frequency = 1.0;
  for (int i = 0; i < octaves; i++) {
    value     += amplitude * smoothNoise(p * frequency);
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return value;
}

half3 hsv2rgb(float h, float s, float v) {
  float3 p = abs(fract(float3(h) + float3(0,2,1)/3.0) * 6.0 - 3.0);
  return half3(v * mix(float3(1), clamp(p - 1.0, 0.0, 1.0), s));
}

// ── Wave Gradient ───────────────────────────────────────────────────────────

[[stitchable]] half4 waveGradient(float2 pos, half4 inColor, float2 size, float time,
                                   half4 c0, half4 c1, half4 c2, half4 c3,
                                   float speed, float bands, float angle,
                                   float warp, float smoothness, float radial) {
  float2 uv = pos / size;
  float t   = time * (speed * speed) * 0.3;
  float a   = angle * M_PI_F / 180.0;

  // Linear: project UV onto the band axis (perpendicular to angle)
  float2 dir = float2(-sin(a), cos(a));
  float across = dot(uv - 0.5, dir);

  // Radial: angle around a focal point (bottom-center of screen)
  float2 focal = float2(0.5, 1.0);
  float2 toPixel = uv - focal;
  float radialAngle = atan2(toPixel.x, -toPixel.y) / (M_PI_F) + 0.5; // 0..1 sweep

  // Blend linear ↔ radial band coordinate
  float bandCoord = mix(across, radialAngle - 0.5, radial);

  // Low-frequency smooth warp using two smooth noise layers
  float2 p1 = float2(uv.x * 0.9 + t * 0.4, uv.y * 0.7 - t * 0.3);
  float2 p2 = float2(uv.x * 0.6 - t * 0.25, uv.y * 1.1 + t * 0.5);
  // Two octaves each. A third at 10% weight was invisible in a warp this soft and cost a
  // third of the shader's noise lookups.
  float w1 = smoothNoise(p1) * 0.72 + smoothNoise(p1 * 2.1) * 0.28;
  float w2 = smoothNoise(p2) * 0.72 + smoothNoise(p2 * 1.9) * 0.28;
  float warpVal = (w1 * 0.6 + w2 * 0.4 - 0.5) * warp * 0.55;

  // Band position — fewer bands = wider, silkier ribbons
  float phase = (bandCoord + warpVal) * bands + t * 0.65;
  float bandPos = fract(phase);

  // Continuously cycle through all four stops, including c3 back to c0.
  float palettePhase = fract(phase * 0.25) * 4.0;
  float segment = floor(palettePhase);
  float linearT = fract(palettePhase);
  float colorT = mix(linearT, smoothstep(0.0, 1.0, linearT), smoothness);
  float3 base0, base1;
  if (segment < 1.0) {
    base0 = float3(c0.r, c0.g, c0.b); base1 = float3(c1.r, c1.g, c1.b);
  } else if (segment < 2.0) {
    base0 = float3(c1.r, c1.g, c1.b); base1 = float3(c2.r, c2.g, c2.b);
  } else if (segment < 3.0) {
    base0 = float3(c2.r, c2.g, c2.b); base1 = float3(c3.r, c3.g, c3.b);
  } else {
    base0 = float3(c3.r, c3.g, c3.b); base1 = float3(c0.r, c0.g, c0.b);
  }
  float3 col = mix(base0, base1, colorT);

  // Soft specular sheen at the crest of each ribbon
  float crest = 1.0 - abs(bandPos * 2.0 - 1.0);
  float sheen = pow(crest, 8.0) * 0.45;
  col = clamp(col + sheen, 0.0, 1.0);

  return half4(half3(col), 1.0h);
}

// ── Color Effects ───────────────────────────────────────────────────────────

[[stitchable]] half4 meshGradient(float2 pos, half4 color, float2 size, float time, float speed, float scale, float hueShift) {
  float2 uv = pos / size;
  float t = time * speed;
  // fbm for richer mesh structure
  float n1 = fbm(uv * scale * 2.5 + float2(t * 0.3, t * 0.2), 4);
  float n2 = fbm(uv * scale * 1.8 + float2(-t * 0.2, t * 0.3), 3);
  float hue = hueShift + uv.x * 0.4 + uv.y * 0.2 + n1 * 0.2 + n2 * 0.12;
  float sat = mapRangeClamped(n1, -1.0, 1.0, 0.5, 1.0);
  float val = mapRangeClamped(n1 + n2 * 0.5, -1.5, 1.5, 0.15, 1.0);
  return half4(hsv2rgb(hue, sat, val), 1.0);
}

[[stitchable]] half4 heatmap(float2 pos, half4 color, float2 size, float time, float speed, float scale, float bands) {
  float2 uv = pos / size;
  float t = time * speed;
  float n = smoothNoise(uv * scale * 3.0 + float2(t * 0.4, 0));
  n += 0.5 * smoothNoise(uv * scale * 6.0 + float2(0, t * 0.3));
  n += 0.25 * smoothNoise(uv * scale * 12.0 + float2(-t * 0.2, t * 0.35));
  n = fract((n / 1.75 + 1.0) * 0.5 * bands);
  float3 col;
  if      (n < 0.25) col = mix(float3(0,0,0.2),   float3(0.5,0,0.8), n * 4.0);
  else if (n < 0.5)  col = mix(float3(0.5,0,0.8), float3(1,0.1,0.1), (n-0.25)*4.0);
  else if (n < 0.75) col = mix(float3(1,0.1,0.1), float3(1,0.6,0),   (n-0.5)*4.0);
  else               col = mix(float3(1,0.6,0),   float3(1,1,0.5),   (n-0.75)*4.0);
  return half4(half3(col), 1.0);
}

// Integer hash of a pixel and a frame, 0..1. The usual fract(sin(dot(...)) * 43758.5453) breaks
// down for pixel coordinates times a frame offset: under fast math, sin of arguments in the
// millions comes back as 0, which turned every pixel of Grain black.
static float grain_hash(uint x, uint y, uint z) {
  uint h = (x * 0x8da6b343u) ^ (y * 0xd8163841u) ^ (z * 0xcb1ab31fu);
  h ^= h >> 16; h *= 0x7feb352du;
  h ^= h >> 15; h *= 0x846ca68bu;
  h ^= h >> 16;
  return float(h) * (1.0 / 4294967296.0);
}

[[stitchable]] half4 grainGradient(float2 pos, half4 color, float2 size, float time, float speed, float scale, float colorShift) {
  float2 uv = pos / size;
  float t = time * speed;
  float n = smoothNoise(uv * scale * 4.0 + float2(t * 0.4, 0));
  n += 0.5 * smoothNoise(uv * scale * 8.0 + float2(0, t * 0.3));
  n = (n / 1.5 + 1.0) * 0.5;
  uint frame = uint(fmod(floor(time * 24.0), 1024.0));
  float grain = grain_hash(uint(pos.x), uint(pos.y), frame + 4096u) * 0.08 - 0.04;
  float hue = colorShift + uv.x * 0.3 + n * 0.2;
  half3 col = hsv2rgb(hue, 0.7 + n * 0.2, clamp(n + grain + 0.3, 0.0, 1.0));
  return half4(col, 1.0);
}

[[stitchable]] half4 dithering(float2 pos, half4 color, float2 size, float time,
                               float pixelSize, float zoom, float speed, float rotation,
                               float tintHue,
                               float lblEnabled, float lblPixelSize, float lblScale, float lblRotation,
                               float g0,  float g1,  float g2,  float g3,
                               float g4,  float g5,  float g6,  float g7,
                               float g8,  float g9,  float g10, float g11,
                               float g12, float g13, float g14, float g15,
                               float charCount,
                               float lblR, float lblG, float lblB) {
  float2 uv = pos / size;
  float t = time * speed;
  float a = rotation * M_PI_F / 180.0;
  float2 c = uv - 0.5;
  float2 ruv = float2(cos(a)*c.x - sin(a)*c.y, sin(a)*c.x + cos(a)*c.y) + 0.5;

  float2 fq = ruv * zoom * 3.0;
  float n  = smoothNoise(fq + float2(t * 0.3, 0));
  n += 0.5  * smoothNoise(fq * 2.0 + float2(0, t * 0.2));
  n += 0.25 * smoothNoise(fq * 4.0 + float2(-t * 0.15, t * 0.1));
  float brightness = clamp((n / 1.75 + 1.0) * 0.5, 0.0, 1.0);

  int px = max(1, int(pixelSize));
  int bx = ((int(pos.x) / px) % 8 + 8) % 8;
  int by = ((int(pos.y) / px) % 8 + 8) % 8;
  float threshold = float(bayerMatrix[bx + by * 8]) / 63.0;

  half3 tint = hsv2rgb(half(tintHue), 0.9h, 1.0h);

  // Label rendering — glyph indices passed as float params
  if (lblEnabled > 0.5 && charCount > 0.0) {
    float glyphs[16] = {g0,g1,g2,g3,g4,g5,g6,g7,g8,g9,g10,g11,g12,g13,g14,g15};
    int nChars = min(int(charCount), 16);

    float ps    = max(1.0, lblPixelSize * lblScale);
    float charW = ps * 5.0;
    float charH = ps * 7.0;
    float totalW = float(nChars) * (charW + ps) - ps;

    float2 p = pos - size * 0.5;
    float la = lblRotation * M_PI_F / 180.0;
    float ca = cos(la), sa = sin(la);
    float2 rp = float2(ca * p.x + sa * p.y, -sa * p.x + ca * p.y);
    float2 lp = rp + float2(totalW * 0.5, charH * 0.5);

    // Character pixel rendering — no background box
    if (lp.x >= 0.0 && lp.x < totalW && lp.y >= 0.0 && lp.y < charH) {
      int ci = int(lp.x / (charW + ps));
      float xInChar = lp.x - float(ci) * (charW + ps);
      if (xInChar < charW && ci < nChars) {
        int col = int(xInChar / ps);
        int row = int(lp.y / ps);
        if (col < 5 && row < 7) {
          int gi = clamp(int(glyphs[ci]), 0, 36);
          uint8_t bits = ditherFont[gi * 7 + row];
          if (bool((bits >> (4 - col)) & 1u)) {
            return half4(half(lblR), half(lblG), half(lblB), 1.0h);
          }
        }
      }
    }
  }

  float d = brightness > threshold ? 1.0 : 0.0;
  return half4(mix(half3(0.0h), tint, half(d)), 1.0h);
}

[[stitchable]] half4 grain(float2 pos, half4 color, float2 size, float time, float intensity, float speed, float colorize) {
  float2 uv = pos / size;
  // Wrapped, so the frame number stays small however long the app has been running
  uint frame = uint(fmod(floor(time * speed), 1024.0));
  float n = grain_hash(uint(pos.x), uint(pos.y), frame);
  half grainVal = half((n - 0.5) * 2.0 * intensity);
  if (colorize > 0.5) {
    float2 s2 = uv * size * 0.1;
    float hue = grain_hash(uint(s2.x), uint(s2.y), 7u);
    return half4(clamp(color.rgb + hsv2rgb(hue, 0.8, abs(grainVal)), 0.0h, 1.0h), color.a);
  }
  return half4(clamp(color.rgb + grainVal, 0.0h, 1.0h), color.a);
}

// ── Fractal ─────────────────────────────────────────────────────────────────
// A cyanotype of branching seaweed, after the cover of Michael Frame's Geometry of Grief:
// a pale plant printed on cobalt paper, as in Anna Atkins' photograms. Organic blends a
// perfect binary tree (0) into seaweed (1): a main stem with alternate limbs, each a stem of
// its own with twigs, curving, with tufts of buds at the tips.

// A branch waiting to be drawn. The tree is walked depth first, skipping every branch whose
// whole subtree is too far from the pixel to touch it.
struct FTBranch {
  float2 base;
  float  heading;  // radians clockwise from straight up
  float  bend;     // how far it turns along its length, its stem's curve aside
  float  len;
  float  stem;     // length left on the stem it belongs to, this branch included
  float  curve;    // how much each branch of its stem turns: up toward the light, or drooping
  float  side;     // side its next side shoot leaves on: 1 right, -1 left
  float  dist;     // how far along the plant it starts: the length of the path to it
  uint   id;       // branch n's children are 2n (the leader) and 2n + 1 (the side shoot), so
                   // its highest set bit is its level
  float2 p;        // the pixel, in this branch's frame: the plant's, unless it has broken off
  float  alpha;    // how much of it is left, as a broken-off piece fades
  bool   loose;    // broken off, or on a piece that has
  float  lean;     // how far the Loss ending's wind leans it: as it was when it broke off
  float  witherAt; // when the piece it's on began to wither in the Loss ending, or -1
  float  witherBase, witherSpan;  // where that piece starts along the plant, and how far it reaches
};

static uint ftHash(uint x) {
  x ^= x >> 16; x *= 0x7feb352du;
  x ^= x >> 15; x *= 0x846ca68bu;
  return x ^ (x >> 16);
}

// A random number in [0, 1); the salt says what it's for
static float ftRand(uint id, uint salt) {
  return float(ftHash(id ^ salt)) * (1.0f / 4294967296.0f);
}

// Four random numbers in [0, 1] from one hash, for a branch's random make-up
static float4 ftJitter(uint id, uint salt) {
  uint h = ftHash(id ^ salt);
  return float4(float(h & 0xffu), float((h >> 8) & 0xffu), float((h >> 16) & 0xffu),
                float(h >> 24)) * (1.0f / 255.0f);
}

// Value noise on an integer hash, which stays even at the fine scale of paper fibre
static float ftNoise(float2 p, uint salt) {
  float2 i = floor(p), f = p - i;
  float2 u = f * f * (3.0f - 2.0f * f);
  uint x0 = uint(int(i.x)) * 0x8da6b343u, x1 = x0 + 0x8da6b343u;
  uint y0 = uint(int(i.y)) * 0xd8163841u, y1 = y0 + 0xd8163841u;
  return mix(mix(ftRand(x0 ^ y0, salt), ftRand(x1 ^ y0, salt), u.x),
             mix(ftRand(x0 ^ y1, salt), ftRand(x1 ^ y1, salt), u.x), u.y);
}

// Layers of value noise, about ±0.5, for the paper's broad unevenness
static float ftFbm(float2 p, int octaves, uint salt) {
  float sum = 0.0f, amplitude = 0.55f;
  for (int i = 0; i < octaves; i++) {
    sum += amplitude * (ftNoise(p, salt + uint(i)) - 0.5f);
    p = p * 2.03f + 17.0f;
    amplitude *= 0.5f;
  }
  return sum;
}

// Signed distance to a stroke from a to b whose radius tapers from ra to rb
static float ftStroke(float2 p, float2 a, float2 b, float ra, float rb, thread float &radius) {
  float2 pa = p - a, ba = b - a;
  float t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-12f), 0.0f, 1.0f);
  radius = mix(ra, rb, t);
  return length(pa - ba * t) - radius;
}

// Adds a shape at signed distance d and radius r to the plant, filling in where it joins
static void ftUnion(thread float &dist, thread float &nearRadius, float d, float r, float k) {
  float w = clamp(0.5f + 0.5f * (d - dist) / k, 0.0f, 1.0f);
  dist = mix(d, dist, w) - k * w * (1.0f - w);
  nearRadius = mix(r, nearRadius, w);
}

// The pieces the Loss ending's gusts break off, apart from the plant still standing so one
// falling past a branch doesn't melt into it. They also carry how much of the nearest is left.
struct FTLoose {
  float dist = 1e9f;
  float radius = 0.0f;
  float alpha = 0.0f;
};

// Adds a stroke to the standing plant, or to the falling pieces when it's on one
static void ftAdd(thread float &dist, thread float &nearRadius, thread FTLoose &fallen, bool loose,
                  float alpha, float d, float r, float k) {
  if (!loose) {
    ftUnion(dist, nearRadius, d, r, k);
    return;
  }
  float w = clamp(0.5f + 0.5f * (d - fallen.dist) / k, 0.0f, 1.0f);
  fallen.alpha = mix(alpha, fallen.alpha, w);
  ftUnion(fallen.dist, fallen.radius, d, r, k);
}

// In the Loss ending only the limbs, off the main stem, fly off whole: the walk can reach the
// main stem from anywhere their pieces have got to, but not every branch. Everything smaller
// withers or crumbles where it is. No limb goes before this many seconds into the gusts.
constant float FT_FIRST_FLIGHT = 1.9f;

// The Loss ending's wind, `fall` seconds in: how far it leans the plant (x: to the right as it
// gusts, swinging back as each gust drops) and how hard it blows (y). It builds, comes in
// irregular gusts from a few waves that never line up, and dies away as the last pieces go.
static float2 ftWind(float fall) {
  float strength = smoothstep(0.0f, 1.4f, fall) * (1.0f - smoothstep(3.9f, 5.6f, fall));
  float gusts = sin(1.6f * fall - 1.0f) * (0.7f + 0.3f * sin(0.63f * fall + 0.5f));
  float lean = strength * (0.02f + 0.024f * gusts + 0.006f * sin(4.1f * fall + 0.8f));
  return float2(lean, strength);
}

// How long a piece of the given heft takes to wither away in the Loss ending
static float ftWitherSeconds(float heft) {
  return 1.3f + 1.2f * heft;
}

// What becomes of a piece the Loss ending's wind works loose: a leaf (a tuft) or a side shoot
// with everything on it. Each has its own fate, for variety, as in a real gale. Some leaves
// hold on; the rest go first, in flurries, fluttering down or blown away. Then the twigs and
// branches, the thinner the sooner, the limbs last: some snap and fall with their weight,
// tumbling about their middle (`reach` along `heading` from where they broke), the heavier
// faster, off the bottom of the paper; some are blown away downwind like seeds or ash,
// lifting a little and crumbling as they go; some wither where they are, drooping and
// crumbling back from their tips (see `witherAt`). `heft` is how heavy it is, 0 to 1. Only a
// piece that goes before the one it's on withers (`parentWither`) has a fate of its own. A
// piece that falls or blows away moves the pixel into its frame and keeps the lean the wind
// gave it as it broke.
static void ftFate(float fall, uint id, float heft, bool leaf, bool flies, uint salt, float2 base,
                   float heading, float reach, float height, float dist, float span, float parentWither,
                   thread float2 &p, thread float &alpha, thread bool &loose, thread float &lean,
                   thread float &witherAt, thread float &witherBase, thread float &witherSpan) {
  float4 j = ftJitter(id, salt ^ 0x2545f491u);
  // 0 holds on, 1 falls, 2 is blown away, 3 withers, 4 crumbles away where it is. Only pieces
  // off big branches fly (`flies`); the walk can't reach the rest away from the plant.
  int fate;
  if (leaf) fate = j.y < 0.35f ? 0 : 4;
  else if (!flies) fate = j.y < 0.55f ? 3 : 4;
  else fate = j.y < 0.15f ? 2 : j.y < 0.4f ? 3 : 1;
  if (fate == 0) return;
  float start = leaf ? 0.9f + 2.4f * j.x * j.x : 1.0f + 3.4f * heft + 1.2f * (j.x - 0.5f);
  start = max(start, 0.7f);
  if (fate == 3) start = min(start, 5.6f - ftWitherSeconds(heft));
  if (fall < start || (parentWither >= 0.0f && start >= parentWither)) return;
  if (fate == 3) {
    witherAt = start;
    witherBase = dist;
    witherSpan = span;
    return;
  }
  if (flies) start = max(start, FT_FIRST_FLIGHT);
  if (fall < start) return;
  float since = fall - start;
  if (fate == 4) {
    alpha *= 1.0f - smoothstep(0.0f, 0.9f + 0.8f * heft, since);
    loose = true;
    witherAt = -1.0f;
    return;
  }
  float4 k = ftJitter(id, salt ^ 0x68bc21ebu);
  lean = ftWind(start).x;
  float light = 1.0f - heft;
  float x, y, turn;
  if (fate == 1) {
    // It falls: drag holds the light ones to a flutter, the heavy ones drop and tumble
    float terminal = mix(0.9f, 0.13f, light) * (0.8f + 0.4f * k.y);
    float settle = terminal / 1.2f;
    y = terminal * (since - settle * (1.0f - exp(-since / settle)));
    x = (0.05f + 0.09f * light) * (0.6f + 0.8f * k.x) * 1.1f * (1.0f - exp(-since / 1.1f));
    float swing = sin((2.0f + 1.8f * k.z) * since + 6.2832f * j.z) * light * light * min(since * 1.2f, 1.0f);
    x += 0.03f * swing;
    turn = (j.w - 0.5f) * (0.5f + 1.8f * heft) * since + 0.55f * swing;
    alpha *= 1.0f - smoothstep(2.0f, 3.6f, since);
  } else {
    // It's blown away downwind, lifting a little before it sinks, and crumbles as it goes
    x = (0.35f + 0.25f * k.x) * 1.4f * (1.0f - exp(-since / 1.4f));
    y = 0.05f * since * since - 0.06f * sin(min(since, 1.5f) * 2.1f);
    turn = (j.w - 0.5f) * 2.0f * since;
    alpha *= 1.0f - smoothstep(0.3f, 1.8f + 0.6f * k.y, since);
  }
  float2 centre = base + reach * float2(sin(heading), cos(heading));
  float2 rel = p - centre - height * float2(x, -y);
  float c = cos(turn), s = sin(turn);
  p = centre + float2(c * rel.x - s * rel.y, s * rel.x + c * rel.y);
  loose = true;
  witherAt = -1.0f;
}

// How much of a print that is wearing away into the paper still shows at a pixel, as `left` of
// it remains: it goes grain by grain, not all at once
static float ftWearing(float left, float grain) {
  float level = left * 1.3f - 0.15f;
  return smoothstep(grain - 0.12f, grain + 0.12f, level) * (0.5f + 0.5f * left);
}

// A tuft at a tip, as the seaweed's twigs end: two short forks, each with a bud on the end and
// one partway, and a bud between them
static float ftTuft(float2 p, float2 tip, float2 dir, float budRadius, float stalkRadius, float r) {
  float2 across = float2(dir.y, -dir.x);
  float spread = 0.5f + 0.5f * r;
  float stalk = 3.0f * budRadius;
  float2 fork1 = tip + (dir + across * spread) * stalk;
  float2 fork2 = tip + (dir - across * (1.3f - spread)) * stalk * (0.75f + 0.4f * r);
  float unused;
  float d = length(p - tip - dir * (1.2f * budRadius)) - 0.9f * budRadius;
  d = min(d, length(p - fork1) - budRadius);
  d = min(d, length(p - fork2) - 0.85f * budRadius);
  d = min(d, length(p - mix(tip, fork1, 0.5f) - across * budRadius) - 0.6f * budRadius);
  d = min(d, length(p - mix(tip, fork2, 0.5f) + across * budRadius) - 0.6f * budRadius);
  d = min(d, ftStroke(p, tip, fork1, stalkRadius, stalkRadius, unused));
  return min(d, ftStroke(p, tip, fork2, stalkRadius, stalkRadius, unused));
}

// How long the stages of the Grow loop last, in seconds. FractalGrowth.swift moves the Seed on
// when a cycle ends, so it uses the same numbers.
constant float FT_GROW_SECONDS = 6.0f;
constant float FT_DEVELOP_SECONDS = 3.0f;
constant float FT_TITLE_SECONDS = 3.0f;
constant float FT_HOLD_SECONDS = 3.0f;
constant float FT_FALL_SECONDS = 6.0f;
constant float FT_FADE_SECONDS = 1.5f;

// A spring from 0 to 1 that overshoots a little before it settles, for buds popping open
static float ftSpring(float x) {
  return x >= 1.0f ? 1.0f : 1.0f - exp(-6.0f * x) * cos(9.0f * x);
}

[[stitchable]] half4 fractalTree(float2 pos, half4 color, float2 size, float time,
                                  float depth, float angle, float ratio, float organic,
                                  float seed, float speed, float sway, float paperTexture,
                                  float paperHue, float grow, float growSpeed, float organicGrowth,
                                  float fractalLevels, float develops, float title, float loss,
                                  float growStart, float growPaused) {
  float o = clamp(organic, 0.0f, 1.0f);
  // Seaweed is many short branches deep, so Organic deepens the tree: up to 2.4 times Depth.
  // The deepest level grows in gradually, so the plant changes smoothly with the slider.
  float levelsF = min(floor(depth + 0.5f) * (1.0f + 1.4f * o), 28.0f);
  int levels = max(int(ceil(levelsF)), 1);
  float lastGrowth = levelsF - floor(levelsF);
  float a = angle * M_PI_F / 180.0f;  // the slider is in degrees
  uint salt = ftHash(uint(max(seed, 0.0f) + 0.5f) + 0x632be5abu);
  uint salt2 = salt ^ 0x5bd1e995u;

  // How a branch's two children leave it. At Organic 0 both turn by the angle, one each way,
  // and are `ratio` as long: the classic tree. Toward 1 one child becomes a leader that carries
  // the stem on with a slight zigzag, the other a side shoot at a wider angle that starts a stem
  // of its own, as long as a share of what's left of its parent's: long low down, short near
  // the top, so the plant and each limb taper like the cover's.
  float turnLead = a * mix(1.0f, 0.3f, o);
  // Limbs leave the main stem almost level; twigs leave limbs more steeply
  float turnLimb = a * mix(1.0f, 2.5f, o);
  float turnSide = a * mix(1.0f, 1.8f, o);
  float rLead = mix(ratio, 0.926f + 0.25f * (ratio - 0.68f), o);
  float rSide = mix(ratio, 0.6f, o);
  float share = mix(1.0f, 0.7f, o);
  // ...and every step away from the main stem gets a smaller share
  float logSubShare = log2(mix(1.0f, 0.62f, o));
  // The main stem's length: everything its leaders add up to
  float stem0 = (1.0f - pow(rLead, levelsF)) / (1.0f - rLead);
  // The main stem keeps turning back toward the light; other stems curve their own way
  float rise = 0.16f * o;
  float tufts = smoothstep(0.15f, 0.7f, o);
  // The first side shoot can go either way
  float side0 = o > 0.0f && ftRand(0u, salt) < 0.5f ? -1.0f : 1.0f;

  // Frame the plant. Trace the main stem as it will grow (leaving out the sway) for its height,
  // and where the stems of its lowest limbs head, for how far it reaches to each side and
  // below. At Organic 0, where every fork is symmetric, the widest path is the one that keeps
  // turning outward.
  float2 q = float2(0.0f);
  float h = 0.0f, len = 1.0f, stem = stem0, side = side0;
  float top = 0.0f, low = 0.0f, left = 0.0f, right = 0.0f;
  uint id = 1u;
  // The main stem grows first, as a plant's leader does: everything off it grows this many
  // times slower, so the plant rises before it spreads. Along the way, find how far the growth
  // has to go for the slowest limb to finish: a limb never carries more than its own stem, so
  // no path through it is longer.
  float sidePace = 1.0f + o;
  float along = 0.0f, growEnd = stem0;
  for (int i = 0; i < levels; i++) {
    float bend = o * (ftJitter(id, salt).z - 0.5f) * 0.25f - rise * sin(h);
    q += len * float2(sin(h + 0.5f * bend), cos(h + 0.5f * bend));
    h += bend;
    top = max(top, q.y);
    float stemLeft = stem - len;
    uint idSide = 2u * id + 1u;
    float4 js = ftJitter(idSide, salt);
    along += len;
    if (i < 10 && o > 0.0f && js.w >= 0.15f * o) {
      // The limb's stem, unless it runs out of levels first
      float lenSide = len * rSide * (1.0f + o * 0.15f);
      float limbStem = share * stemLeft * (1.0f + o * 0.5f * (js.x - 0.5f));
      float limb = min(limbStem, lenSide * (1.0f - pow(rLead, float(levels - i - 1))) / (1.0f - rLead));
      growEnd = max(growEnd, along + limbStem * sidePace);
      float hs = h - side * turnLimb + o * 0.45f * (js.y - 0.5f);
      // It turns by its curve at every branch, so aim along the middle of the arc
      float curve = o * 0.2f * (ftJitter(idSide, salt2).y - 0.6f);
      hs += 0.4f * curve * min(limb / lenSide, 10.0f) * sin(hs);
      float2 tip = q + 0.9f * limb * float2(sin(hs), cos(hs));
      // Its twigs reach past its stem, the further the bushier the plant
      float twigs = (0.2f + 0.5f * (1.0f - o)) * limb;
      left = min(left, tip.x - twigs);
      right = max(right, tip.x + twigs);
      low = min(low, tip.y - twigs);
      top = max(top, tip.y + twigs);
    }
    float4 jl = ftJitter(2u * id, salt);
    float lenLead = len * rLead * (1.0f + o * 0.15f * (jl.x - 0.5f));
    if (i + 1 >= levels || stemLeft <= 0.35f * lenLead) break;
    h += side * turnLead + o * 0.3f * (jl.y - 0.5f);
    len = min(lenLead, stemLeft);
    stem = stemLeft;
    side = -side;
    id *= 2u;
  }
  float outward = 0.0f;
  if (o < 1.0f) {
    q = float2(0.0f, 1.0f);
    h = a;
    len = ratio;
    for (int i = 1; i < levels; i++) {
      q += len * float2(sin(h), cos(h));
      outward = max(outward, q.x);
      h += sin(h + a) > sin(h - a) ? a : -a;
      len *= ratio;
    }
  }
  // Below full Organic the two estimates are each only roughly right, so take the wider
  left = min(-outward, left) - 0.05f;
  right = max(outward, right) + 0.05f;
  low = min(low, -0.45f * o) - 0.05f;  // the holdfast hangs below the stem
  top += 0.05f;
  float height = top - low;
  // Fill 74% of the height, or 92% of the width on narrow screens, with the plant centred
  float zoom = max(height / 0.74f, (right - left) / (0.92f * size.x / size.y));
  float2 uv = (pos - 0.5f * size) / size.y;
  uv.y = -uv.y;  // the plant grows up; SwiftUI's y points down
  float2 p = uv * zoom + float2(0.5f * (left + right), 0.5f * (top + low));

  float pt = zoom / size.y;  // one point, in plant units
  float aa = 0.6f * pt;
  // Sizes are relative to the plant, so it comes out the same on every screen and at every
  // render quality; only the finest lines are held to a minimum on screen
  float minRadius = max(0.0016f * height, 0.35f * pt);
  float stemRadius = 0.006f * height;
  float cull = max(mix(0.8f * pt, 0.006f * height, o), 0.8f * pt);  // shorter branches aren't grown
  // How far past a branch's stem the pixel can be and still be touched by it: its width, the
  // tufts at its tips and the soft edge
  float reachPad = 6.0f * minRadius + 3.0f * pt + aa;

  // Sway: the whole plant leans with a slow current and each branch drifts on its own. Speed
  // sets how fast, Sway how far (1 as it always was, 0 still).
  float t = time * speed;
  float current = 0.008f * sin(0.45f * t) + 0.004f * sin(0.83f * t + 1.3f);

  // The Grow loop, by how far into the cycle it is (the seconds since Grow Start at its speed,
  // or where Pause held it): the plant grows (with Organic Growth or Fractal Levels on), the
  // print develops (Cyanotype Develops) while the title comes up (Title, drawn by
  // FractalTitleView), it holds, then it fades for the next plant; with Loss, gusts of wind
  // shake it apart first, until only the main stem is left to fade. Organic Growth grows every
  // stem at one pace from the root, side shoots sprouting as it passes; Fractal Levels draws
  // one level of branching after another; with both, each level grows out in turn.
  bool growing = grow > 0.5f && growStart >= 0.0f;
  bool byLength = organicGrowth > 0.5f, byLevel = fractalLevels > 0.5f;
  bool developing = growing && develops > 0.5f;
  bool titled = growing && title > 0.5f;
  float pace = exp2(round(growSpeed) - 1.0f);  // 0.5×, 1× or 2×
  float age = growPaused >= 0.0f ? growPaused : max(time - growStart, 0.0f) * pace;
  float growFor = growing && (byLength || byLevel) ? FT_GROW_SECONDS : 0.0f;
  float grown = growFor > 0.0f ? clamp(age / growFor, 0.0f, 1.0f) : 1.0f;
  grown = grown * grown * (3.0f - 2.0f * grown);
  float exposed = developing ? clamp((age - growFor) / FT_DEVELOP_SECONDS, 0.0f, 1.0f) : 1.0f;
  float settle = max(developing ? FT_DEVELOP_SECONDS : 0.0f, titled ? FT_TITLE_SECONDS : 0.0f);
  float holdUntil = growFor + settle + FT_HOLD_SECONDS;
  // Loss: gusts of wind (ftWind) lean the plant and let it swing back, bending it more toward
  // the tips, like the sway, set its twigs fluttering, and tear it apart (ftLetGo)
  bool losing = growing && loss > 0.5f;
  float fall = losing ? age - holdUntil : 0.0f;
  float2 wind = fall > 0.0f ? ftWind(fall) : float2(0.0f);
  // How far the pieces the wind tears loose can have got by now from where they grew, at most:
  // the walk has to reach the branches they hung from wherever they've gone, or they'd be cut
  // off at the edge of the plant's bounds. They fall, or blow downwind, lifting a little.
  float2 debrisLow = float2(0.0f), debrisHigh = float2(0.0f);
  if (fall > FT_FIRST_FLIGHT) {
    float since = fall - FT_FIRST_FLIGHT;
    float drop = min(1.08f * (since - 0.9f * (1.0f - exp(-since / 0.9f))), 1.4f);
    float carry = 0.84f * (1.0f - exp(-since / 1.4f));
    debrisLow = height * float2(-0.08f, -drop - 0.03f);
    debrisHigh = height * float2(carry + 0.1f, 0.08f);
  }
  float fadeFrom = holdUntil + (losing ? FT_FALL_SECONDS : 0.0f);
  float faded = growing ? clamp((age - fadeFrom) / FT_FADE_SECONDS, 0.0f, 1.0f) : 0.0f;
  // How far the growth has got: along the paths from the root, or through the levels
  float front = growFor > 0.0f ? grown * (growEnd + 0.2f) : 1e9f;
  float levelFront = growFor > 0.0f ? grown * (levelsF + 1.0f) : 1e9f;

  float dist = 1e9f, nearRadius = 0.0f;
  FTLoose fallen;
  // A small holdfast under the stem, as the seaweed was pressed with its root
  if (tufts > 0.0f && length(p) < 1.0f) {
    for (int j = 0; j < 2; j++) {
      float rj = ftRand(uint(j) + 7u, salt ^ 0x9e3779b9u);
      float hh = M_PI_F + (j == 0 ? -1.0f : 1.0f) * (0.35f + 0.45f * rj);
      float2 dir = float2(sin(hh), cos(hh));
      float sprouted = byLevel ? clamp(levelFront, 0.0f, 1.0f) : clamp(front / 0.3f, 0.0f, 1.0f);
      float2 tip = dir * (0.22f + 0.2f * rj) * tufts * sprouted;
      float unused;
      float dh = ftStroke(p, float2(0.0f), tip, 0.6f * stemRadius, minRadius, unused);
      dh = min(dh, ftTuft(p, tip, dir, 1.4f * minRadius * tufts, 0.8f * minRadius * tufts, rj));
      ftUnion(dist, nearRadius, dh, minRadius, 0.6f * minRadius + 0.3f * pt);
    }
  }

  FTBranch stack[28];
  int count = 0;
  FTBranch b = { float2(0.0f), 0.0f, o * (ftJitter(1u, salt).z - 0.5f) * 0.25f, 1.0f, stem0, -rise,
                 side0, 0.0f, 1u, p, 1.0f, false, wind.x, -1.0f, 0.0f, 0.0f };
  for (int step = 0; step < 1500; step++) {
    // The branch runs along two halves, turning by its bend (and its stem's curve, by how far
    // it leans from upright) as it goes, and sways: more the further out it is
    int level = 31 - int(clz(b.id));
    // The pixel in this branch's frame, and whether it's on a piece that has broken off
    float2 bp = b.p;
    float bAlpha = b.alpha;
    uint bid = b.id;
    bool bLoose = b.loose;
    bool onMainStem = (b.id & (b.id - 1u)) == 0u;
    // On a piece that's withering: how far along it is, and how much of this part is left, the
    // tips going first
    float withered = 0.0f, left = 1.0f;
    if (b.witherAt >= 0.0f) {
      float heftRoot = sqrt(sqrt(b.witherSpan / (stem0 * sidePace)));
      withered = clamp((fall - b.witherAt) / ftWitherSeconds(heftRoot), 0.0f, 1.0f);
      float outward = clamp((b.dist - b.witherBase) / max(b.witherSpan, 1e-4f), 0.0f, 1.0f);
      left = clamp(1.0f + 0.6f * (1.0f - outward) - 1.6f * withered, 0.0f, 1.0f);
    }
    // Drawn apart from the standing plant, as much as is left of it
    bool bOwn = bLoose || b.witherAt >= 0.0f;
    float bShow = bAlpha * left;
    float phase = float((b.id * 0x9e3779b9u) >> 8) * (1.0f / 16777216.0f);
    // The gusts lean the main stem, and the limbs ride on it, flexing less, their twigs
    // fluttering each to its own beat; a withering piece droops
    float drift = sway * (current * (0.3f + 0.03f * float(level))
                          + o * 0.015f * sin(t * (0.7f + 0.6f * phase) + 6.2832f * phase))
                + b.lean * (0.3f + 0.03f * float(level)) * (onMainStem ? 1.0f : 0.6f)
                + (onMainStem ? 0.0f : wind.y * 0.035f * sin(fall * (5.0f + 4.0f * phase) + 6.2832f * phase))
                + withered * 0.07f * sin(b.heading);
    float h0 = b.heading + drift;
    float2 dir = float2(sin(h0), cos(h0));
    float2 across = float2(dir.y, -dir.x);
    float bend = b.bend + b.curve * dir.x;
    // Small turns, so sin and cos of the angle are near enough to the angle and 1 - angle² / 2
    float turn1 = 0.25f * bend, turn2 = 0.75f * bend;
    float2 mid = b.base + 0.5f * b.len * (dir * (1.0f - 0.5f * turn1 * turn1) + across * turn1);
    float2 end = mid + 0.5f * b.len * (dir * (1.0f - 0.5f * turn2 * turn2) + across * turn2);
    float hEnd = h0 + bend;
    // How much of it has grown, and how long ago it started: young shoots are thinner. `dist`
    // is how far the growth has gone when it starts; off the main stem it grows slower.
    float stretch = onMainStem ? 1.0f : sidePace;
    float grownBy = b.dist + b.len * stretch;
    float shown = 1.0f, young = 1.0f;
    if (growFor > 0.0f) {
      float into = byLevel ? levelFront - float(level) : (front - b.dist) / (b.len * stretch);
      shown = byLevel && !byLength ? smoothstep(0.0f, 0.4f, into) : clamp(into, 0.0f, 1.0f);
      float since = byLevel ? (levelFront - float(level)) / levelsF : (front - b.dist) / stem0;
      young = 0.45f + 0.55f * smoothstep(0.0f, 0.3f, since);
    }
    // Thickness follows how much stem is left to carry
    float stemLeft = b.stem - b.len;
    float thin = young * (1.0f - 0.3f * withered);
    float r1 = max(stemRadius * sqrt(b.stem / stem0) * thin, minRadius);
    float rEnd = max(stemRadius * sqrt(max(stemLeft, 0.0f) / stem0) * thin, minRadius);
    float rMid = 0.5f * (r1 + rEnd);
    float half1 = min(2.0f * shown, 1.0f), half2 = clamp(2.0f * shown - 1.0f, 0.0f, 1.0f);
    float ra, rb;
    float d1 = ftStroke(bp, b.base, mix(b.base, mid, half1), r1, mix(r1, rMid, half1), ra);
    float d2 = half2 > 0.0f ? ftStroke(bp, mid, mix(mid, end, half2), rMid, mix(rMid, rEnd, half2), rb) : 1e9f;
    if (bShow > 0.004f) ftAdd(dist, nearRadius, fallen, bOwn, bShow, min(d1, d2), d1 < d2 ? ra : rb, 0.6f * r1 + 0.3f * pt);

    bool isTip = true;
    bool grew = false;
    if (level + 1 < levels) {
      uint idLead = b.id * 2u, idSide = idLead + 1u;
      float4 jl = ftJitter(idLead, salt), js = ftJitter(idSide, salt);
      // Branches on a partly grown last level are that much shorter
      float growth = level + 2 == levels && lastGrowth > 0.0f ? lastGrowth : 1.0f;
      // A stem ends once what's left of it is under a third of its next branch
      float lenLead = b.len * rLead * growth * (1.0f + o * 0.15f * (jl.x - 0.5f));
      bool hasLead = stemLeft > 0.35f * lenLead && lenLead > cull;
      lenLead = min(lenLead, stemLeft);
      // Side shoots off side shoots get a smaller share, so limbs stay feathered, not bushy
      float stemSide = share * exp2(logSubShare * float(popcount(b.id) - 1)) * stemLeft
                     * (1.0f + o * 0.5f * (js.x - 0.5f));
      float lenSide = min(b.len * rSide * growth * (1.0f + o * 0.3f * (js.z - 0.5f)), stemSide);
      // Now and then a side shoot never grew
      bool hasSide = stemSide > 0.35f * lenSide && lenSide > cull && js.w >= 0.15f * o;
      isTip = !hasLead;
      // Each child goes on in this branch's frame, unless the wind has worked it loose (see
      // ftFate). Only side shoots go, so stems go whole, and the main stem stands to the end. A
      // branch gone from the standing plant leaves a stub.
      float sideHeading = hEnd - b.side * (onMainStem ? turnLimb : turnSide) + o * 0.45f * (js.y - 0.5f);
      float2 pSide = bp;
      float alphaSide = bAlpha, leanSide = b.lean;
      float witherSide = b.witherAt, witherBaseSide = b.witherBase, witherSpanSide = b.witherSpan;
      bool looseSide = bLoose;
      bool flies = onMainStem;
      float2 reachSide = bp - end;
      if (flies) reachSide -= clamp(reachSide, debrisLow, debrisHigh);
      if (fall > 0.0f && hasSide && !bLoose
          && length(reachSide) < (flies ? 1.6f : 1.0f) * stemSide + r1 + reachPad) {
        ftFate(fall, idSide, sqrt(sqrt(stemSide / stem0)), false, flies, salt, end, sideHeading,
               0.3f * stemSide, height, grownBy, stemSide * sidePace, b.witherAt, pSide, alphaSide,
               looseSide, leanSide, witherSide, witherBaseSide, witherSpanSide);
        bool gone = looseSide || witherSide != b.witherAt;
        if (gone && b.witherAt < 0.0f && stemSide > 0.012f * stem0) {
          float rStub = max(stemRadius * sqrt(stemSide / stem0), minRadius);
          float2 stubEnd = end + min(0.3f * lenSide, 5.0f * rStub) * float2(sin(sideHeading), cos(sideHeading));
          float rs;
          float ds = ftStroke(bp, end, stubEnd, rStub, 0.75f * rStub, rs);
          ftAdd(dist, nearRadius, fallen, false, 1.0f, ds, rs, 0.6f * rStub + 0.3f * pt);
        }
      }
      float2 pLead = bp;
      float alphaLead = bAlpha;
      bool looseLead = bLoose;
      // Grow a child only if something in its subtree could come near the pixel. A side shoot
      // never gets more stem than its parent has left, so no path through a subtree is longer
      // than the subtree's own stem: everything in it lies within that distance of its base.
      // A piece that has broken off is tested where it has fallen to, and not once it's gone.
      bool reached = byLevel ? levelFront > float(level + 1) : front > grownBy;
      // and not past where a withering piece has crumbled back to. In the Loss ending, a child
      // still on the plant may have pieces that have fallen or blown away: it's reached from
      // wherever they can have got to, turning about their middles as they go.
      // Only the main stem carries limbs that fly (see FT_FIRST_FLIGHT).
      float2 toLead = pLead - end, toSide = pSide - end;
      bool sweepLead = fall > FT_FIRST_FLIGHT && onMainStem;
      if (sweepLead) toLead -= clamp(toLead, debrisLow, debrisHigh);
      bool growLead = hasLead && reached && alphaLead > 0.004f && (b.witherAt < 0.0f || left > 0.0f)
                      && length(toLead) < (sweepLead ? 1.6f : 1.0f) * stemLeft + r1 + reachPad;
      bool growSide = hasSide && reached && alphaSide > 0.004f
                      && (witherSide < 0.0f || left > 0.0f || witherSide != b.witherAt)
                      && length(toSide) < stemSide + r1 + reachPad;
      if (growSide) {
        float4 js2 = ftJitter(idSide, salt2);
        FTBranch shoot = { end, sideHeading, o * (js2.z - 0.5f) * 0.5f, lenSide, stemSide,
                           o * 0.2f * (js2.y - 0.6f), js2.x < 0.5f ? -1.0f : 1.0f, grownBy, idSide,
                           pSide, alphaSide, looseSide, leanSide, witherSide, witherBaseSide, witherSpanSide };
        if (growLead) stack[count++] = shoot;
        else b = shoot;
      }
      if (growLead) {
        b = { end, hEnd + b.side * turnLead + o * 0.3f * (jl.y - 0.5f),
              o * (jl.z - 0.5f) * (onMainStem ? 0.25f : 0.5f), lenLead, stemLeft, b.curve, -b.side,
              grownBy, idLead, pLead, alphaLead, looseLead, b.lean, b.witherAt, b.witherBase, b.witherSpan };
      }
      grew = growLead || growSide;
    }
    // A tuft at the end of every stem
    float opened = 1.0f;
    if (growFor > 0.0f) {
      float since = byLevel ? levelFront - float(level + 1) : (front - grownBy) / (0.04f * stem0);
      opened = ftSpring(clamp(since, 0.0f, 1.0f));
    }
    if (isTip && tufts > 0.0f && opened > 0.0f) {
      float rt = fract(phase * 7.0f);
      float budRadius = rEnd * (1.4f + 0.6f * rt) * tufts * opened;
      float2 dirEnd = dir * (1.0f - 0.5f * bend * bend) + across * bend;
      // Most leaves go first, on their own; the rest stay with their twig
      float2 pTuft = bp;
      float alphaTuft = bAlpha, leanTuft = 0.0f, witherTuft = b.witherAt, unusedBase, unusedSpan;
      bool looseTuft = bLoose;
      if (fall > 0.0f && !bLoose) {
        ftFate(fall, bid * 2u, 0.0f, true, false, salt, end, hEnd + bend, 2.0f * budRadius, height, 0.0f,
               0.0f, b.witherAt, pTuft, alphaTuft, looseTuft, leanTuft, witherTuft, unusedBase, unusedSpan);
      }
      if (!looseTuft || bLoose) {
        alphaTuft = bShow;
        looseTuft = bOwn;
      }
      if (alphaTuft > 0.004f) {
        ftAdd(dist, nearRadius, fallen, looseTuft, alphaTuft,
              ftTuft(pTuft, end, dirEnd, budRadius, 0.8f * rEnd * tufts, rt), budRadius,
              0.6f * budRadius + 0.3f * pt);
      }
    }
    if (!grew) {
      if (count == 0) break;
      b = stack[--count];
    }
  }

  // Print it. Cyanotype paper turns blue where light reaches it, so the plant comes out pale:
  // thick stems nearly white, thin twigs letting some light through, all with soft edges.
  float tex = clamp(paperTexture, 0.0f, 1.0f);
  float2 paperUV = pos / min(size.x, size.y);
  // Pressed tissue has a ragged edge
  float ragged = (ftNoise(paperUV * 500.0f, 0x6a09e667u) - 0.5f) * 0.6f * minRadius;
  dist += ragged;
  float cover = 1.0f - smoothstep(-aa - 0.3f * nearRadius, aa, dist);
  float opacity = mix(0.94f, 1.0f, smoothstep(0.5f * pt, 3.0f * pt, nearRadius));
  float glow = 0.07f * exp(-max(dist, 0.0f) / (1.2f * pt));

  // The paper: an uneven coat of sensitiser, cloudy patches, fibre and pale specks
  float mottle = ftFbm(paperUV * 2.3f, 3, 0x3c6ef372u);
  float clouds = ftFbm(paperUV * 8.5f, 2, 0xa54ff53au);
  float fibre = ftNoise(paperUV * 420.0f, 0x51ed270bu) - 0.5f;
  float2 grainCell = floor(paperUV * 640.0f);
  float grains = pow(ftRand(uint(int(grainCell.x)) * 0x8da6b343u ^ uint(int(grainCell.y)) * 0xd8163841u,
                            0x68e31da4u), 4.0f);
  // At most one pale speck per cell, somewhere inside it
  float2 speckCell = floor(paperUV * 60.0f), inCell = paperUV * 60.0f - speckCell;
  float4 speck = ftJitter(uint(int(speckCell.x)) * 0x8da6b343u ^ uint(int(speckCell.y)) * 0xd8163841u,
                          0x2c1b3c6du);
  float speckSize = 0.05f + 0.08f * speck.z;
  float specks = speck.w < 0.3f
               ? 1.0f - smoothstep(0.4f * speckSize, speckSize, length(inCell - 0.25f - 0.5f * speck.xy))
               : 0.0f;
  float tissue = ftNoise(paperUV * 380.0f, 0x7a3d9e1fu) - 0.5f;
  float density = 1.0f + tex * (0.2f * mottle + 0.08f * clouds + 0.16f * fibre - 0.14f * grains
                                - 0.3f * specks);
  float blocked = clamp(cover * opacity * (1.0f + tex * 0.5f * tissue) + glow * (1.0f - cover), 0.0f, 1.0f);
  // The pieces the wind tore loose, printed the same way, wearing away into the paper grain by
  // grain as they fall
  float wearGrain = losing ? ftNoise(paperUV * 260.0f, 0x1b873593u) : 0.0f;
  if (fallen.alpha > 0.0f) {
    float fallenDist = fallen.dist + ragged;
    float fallenCover = 1.0f - smoothstep(-aa - 0.3f * fallen.radius, aa, fallenDist);
    float fallenOpacity = mix(0.94f, 1.0f, smoothstep(0.5f * pt, 3.0f * pt, fallen.radius));
    float fallenGlow = 0.07f * exp(-max(fallenDist, 0.0f) / (1.2f * pt));
    float fallenBlocked = fallenCover * fallenOpacity * (1.0f + tex * 0.5f * tissue)
                        + fallenGlow * (1.0f - fallenCover);
    blocked = max(blocked, clamp(fallenBlocked, 0.0f, 1.0f) * ftWearing(fallen.alpha, wearGrain));
  }
  // At the end of a Grow cycle the plant fades into the paper (with Loss, its last stem wears
  // away into it), unless the print develops
  if (!developing) blocked *= losing ? ftWearing(1.0f - faded, wearGrain) : 1.0f - faded;

  // The print is the paper's own colour where no light reached it: a pale tint of the same hue
  float3 paperColor = float3(hsv2rgb(paperHue, 0.894f, 0.706f));
  float3 printColor = float3(hsv2rgb(paperHue, 0.278f, 1.0f));
  float3 exposedPaper = mix(printColor, paperColor, density);
  float3 printed = mix(printColor, exposedPaper, 1.0f - blocked);
  if (developing) {
    // Unexposed, the paper is a pale yellow-green and the seaweed lies on it, a soft olive. In
    // the light the paper turns blue, patchily; then the seaweed comes off, leaving the white
    // print. As the cycle ends, everything fades back to a fresh sheet.
    float grain = 1.0f + tex * (0.05f * mottle + 0.06f * fibre);
    float3 sensitiser = float3(0.85f, 0.87f, 0.63f) * grain;
    float3 seaweed = float3(0.6f, 0.65f, 0.45f) * grain;
    float lit = smoothstep(0.0f, 1.0f, clamp(1.35f * exposed - 0.35f * (mottle + 0.5f), 0.0f, 1.0f));
    float washed = smoothstep(0.55f, 1.0f, exposed);
    printed = mix(mix(seaweed, printColor, washed), mix(sensitiser, exposedPaper, lit), 1.0f - blocked);
    printed = mix(printed, sensitiser, faded);
  }
  return half4(half3(clamp(printed, 0.0f, 1.0f)), 1.0h);
}

[[stitchable]] half4 spiralShader(float2 pos, half4 color, float2 size, float time, float speed, float density, float colorShift) {
  float2 uv = (pos / size) - 0.5;
  float r = length(uv);
  float theta = atan2(uv.y, uv.x);
  float t = time * speed * 0.4;
  float spiral = fract((theta / (2.0 * M_PI_F) + r * density - t));
  half3 col = hsv2rgb(colorShift + spiral * 0.5, 0.85, clamp(1.0 - r * 1.2, 0.0, 1.0));
  return half4(col, 1.0h);
}

[[stitchable]] half4 vortexShader(float2 pos, half4 color, float2 size, float time,
                                   float speed, float twist, float scale) {
  float minDim = min(size.x, size.y);
  float2 uv = (pos - size * 0.5) / minDim;
  float r = length(uv);
  float theta = atan2(uv.y, uv.x);
  float t = time * speed;

  float spiral = theta / (2.0 * M_PI_F) + r * twist - t;
  float arms   = sin(spiral * M_PI_F * 8.0) * 0.5 + 0.5;
  // theta wraps from pi to -pi on the left, moving `spiral` by a whole turn: multiples of
  // 2 pi per turn keep every term continuous there (5 left a hard seam along the left radius)
  float arms2  = sin(spiral * M_PI_F * 6.0 + 1.3) * 0.5 + 0.5;

  float falloff    = exp(-r * scale * 2.5);
  float noiseVal   = mapRangeClamped(fbm(uv * scale * 1.5 + float2(t * 0.15, 0), 3), -1.0, 1.0, 0.0, 1.0);
  float brightness = clamp((arms * arms2 * 0.7 + noiseVal * 0.3) * falloff * 2.2, 0.0, 1.0);

  float hue = fract((r * twist - t) * 0.12 + 0.06 * sin(theta) + t * 0.025);
  float sat = clamp(1.0 - r * scale * 0.8, 0.2, 1.0);
  return half4(hsv2rgb(hue, sat, brightness), 1.0h);
}

[[stitchable]] half4 sphereShader(float2 pos, half4 color, float2 size, float time,
                                   float speed, float roughness, float iridescence, float hueBase) {
  float minDim = min(size.x, size.y);
  float2 uv = (pos - size * 0.5) / minDim;
  float r2  = dot(uv, uv);
  float R   = 0.46;

  // Outside sphere — transparent so background shows through
  if (r2 > R * R) return half4(color.rgb, 1.0h);

  float z = sqrt(max(0.0, R * R - r2));
  float3 N = normalize(float3(uv.x, -uv.y, z));
  float3 V = float3(0.0, 0.0, 1.0);
  float t  = time * speed;

  // Two animated lights: key + fill
  float3 L1 = normalize(float3(cos(t * 0.7) * 0.9, sin(t * 0.5) * 0.7 + 0.2, 1.4));
  float3 L2 = normalize(float3(-cos(t * 0.4) * 0.6, -0.5, 0.8));

  // Surface texture coordinates straight from the normal (a stereographic projection), turning
  // slowly about the view axis. These used atan2, whose wrap from +1/2 to -1/2 along the left
  // radius showed as a hard-edged block in the sphere.
  float spin = t * 0.025 * 2.0 * M_PI_F;
  float2 turned = float2(N.x * cos(spin) - N.y * sin(spin), N.x * sin(spin) + N.y * cos(spin));
  float2 sUV = turned / (1.0 + N.z);

  // Multi-octave fbm surface — organic blobs
  float surface = fbm(sUV * 1.8 + float2(t * 0.05, 0.0), 5);
  surface = mapRangeClamped(surface, -0.8, 0.8, 0.0, 1.0);

  // Fresnel — view-dependent edge brightness
  float NdotV  = clamp(dot(N, V), 0.0, 1.0);
  float fresnel = pow(1.0 - NdotV, 3.0);

  // Iridescence: thin-film interference shifts hue by angle + surface
  float hue = fract(hueBase + iridescence * (fresnel * 0.6 + surface * 0.25) + t * 0.008);
  float sat = 0.65 + surface * 0.3 - fresnel * 0.15;
  float3 baseColor = float3(hsv2rgb(hue, sat, 1.0));

  // GGX specular (Cook-Torrance)
  float alpha  = max(0.02, roughness * roughness);
  float alpha2 = alpha * alpha;
  auto ggx = [&](float3 L) -> float {
    float3 H    = normalize(L + V);
    float NdotH = max(0.0, dot(N, H));
    float NdotL = max(0.0, dot(N, L));
    float denom = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
    float D     = alpha2 / (M_PI_F * denom * denom + 1e-5);
    return D * NdotL;
  };

  float spec1 = ggx(L1) * 0.9;
  float spec2 = ggx(L2) * 0.4;

  // Diffuse
  float diff1 = max(0.0, dot(N, L1));
  float diff2 = max(0.0, dot(N, L2)) * 0.35;
  float ambient = 0.12;

  // Subsurface scattering approximation: light bleeds through back
  float sss = max(0.0, dot(-N, L1)) * 0.18 * (1.0 - roughness);

  // Rim glow
  float rim = pow(fresnel, 2.5) * 0.55;

  // Combine
  float3 diffuse = baseColor * (ambient + diff1 + diff2 + sss);
  float3 specular = float3(spec1 + spec2) * mix(float3(1.0), baseColor, 0.4);
  float3 rimColor = mix(baseColor, float3(1.0), 0.5) * rim;
  float3 lit = diffuse + specular + rimColor;

  // Soft alpha fade at silhouette edge
  float edgeFade = smoothstep(R, R * 0.88, sqrt(r2));

  // SwiftUI expects premultiplied colour, and reduced quality renders into an opaque layer,
  // so fade into the background colour rather than through alpha
  return half4(mix(color.rgb, half3(clamp(lit, 0.0, 2.0)), half(edgeFade)), 1.0h);
}

// ── Distortion Effects ──────────────────────────────────────────────────────

[[stitchable]] float2 warpDistortion(float2 pos, float2 size, float time, float amplitude, float frequency, float speed) {
  float2 uv = pos / size;
  float t = time * speed * 0.5;
  float dx = sin(uv.y * frequency * M_PI_F + t) * amplitude;
  float dy = sin(uv.x * frequency * M_PI_F + t * 0.8) * amplitude;
  return pos + float2(dx, dy) * min(size.x, size.y) * 0.05;
}

[[stitchable]] float2 rippleDistortion(float2 pos, float2 size, float time, float amplitude, float frequency, float speed) {
  float2 center = size * 0.5;
  float2 delta = pos - center;
  float dist = length(delta) / min(size.x, size.y);
  float t = time * speed;
  float wave = sin(dist * frequency * M_PI_F * 2.0 - t) * amplitude;
  float2 dir = length(delta) > 0.001 ? normalize(delta) : float2(0, 1);
  return pos + dir * wave * min(size.x, size.y) * 0.05;
}

[[stitchable]] float2 pinchDistortion(float2 pos, float2 size, float time, float strength, float radius, float speed) {
  float2 center = size * 0.5;
  float2 delta = pos - center;
  float dist = length(delta) / min(size.x, size.y);
  float t = sin(time * speed * 0.5) * 0.5 + 0.5;
  float falloff = 1.0 - smoothstep(0.0, radius, dist);
  float pinch = 1.0 - strength * t * falloff;
  return center + delta * pinch;
}

// ── Layer Effects ───────────────────────────────────────────────────────────

[[stitchable]] half4 flutedGlass(float2 pos, SwiftUI::Layer layer, float2 size, float /*time*/,
                                  float shape, float fluteWidth, float highlights,
                                  float shadows, float angle, float distortion,
                                  float shift, float stretch, float blur, float edges) {
  float2 uv = pos / size;
  float rad  = angle * M_PI_F / 180.0;
  float cosA = cos(rad), sinA = sin(rad);

  float2 perpDir = float2(-sinA,  cosA);  // across flutes — refraction axis
  float2 alongDir = float2( cosA,  sinA); // along flutes  — stretch axis

  float2 c    = uv - 0.5;
  float along = dot(c, alongDir);
  float perp  = dot(c, perpDir);

  // Flute tiling with phase shift
  float fw = max(0.005, fluteWidth);
  float fluteCoord = (perp + shift * 0.5) / fw;
  float t  = fract(fluteCoord);    // 0..1 within flute
  float tc = t * 2.0 - 1.0;       // -1..1

  // Lens profile
  float profile;
  int s = int(round(shape));
  if (s == 0) {
    // Lines: smooth cylindrical sine
    profile = sin(t * 2.0 * M_PI_F);
  } else if (s == 1) {
    // Irregular: fbm warps the flute coordinate for organic, flowing variation
    float warp = fbm(float2(fluteCoord * 0.4, along * 0.8), 3) * 0.35;
    profile = sin((t + warp) * 2.0 * M_PI_F);
  } else if (s == 2) {
    // Wave: two harmonics → richer banding
    profile = sin(t * 2.0 * M_PI_F) * 0.65 + sin(t * 4.0 * M_PI_F) * 0.35;
  } else if (s == 3) {
    // Zigzag: triangle wave
    profile = (t < 0.5 ? t * 4.0 - 1.0 : 3.0 - t * 4.0);
  } else {
    // Pattern: cubic sawtooth
    profile = tc - sign(tc) * tc * tc * 0.6;
  }

  float dim = min(size.x, size.y);

  // Progressive falloff along the flute axis (jtrivedi technique):
  // distortion tapers toward the far end, giving natural depth perspective.
  float alongFalloff = 1.0 - clamp(abs(along) * 1.2, 0.0, 0.6);

  // Primary refraction: across flutes (distortion)
  float perpDisp = profile * distortion * fw * dim * alongFalloff;

  // Secondary displacement: along flutes (stretch) using profile derivative
  float profileDeriv = cos(t * 2.0 * M_PI_F);
  float alongDisp = profileDeriv * stretch * fw * dim * alongFalloff;

  float2 refractOffset = perpDir * perpDisp + alongDir * alongDisp;

  // Sample with optional blur along the flute axis
  half4 col;
  if (blur < 0.005) {
    col = layer.sample(pos + refractOffset);
  } else {
    float blurR = blur * dim * 0.03;
    half4 acc = half4(0);
    const int N = 9;
    for (int i = 0; i < N; i++) {
      float w = (float(i) / float(N - 1) - 0.5) * 2.0;
      acc += layer.sample(pos + refractOffset + alongDir * w * blurR);
    }
    col = acc / float(N);
  }

  // Highlights on crest
  float hiMask = max(0.0, profile); hiMask *= hiMask;
  col.rgb = clamp(col.rgb + half3(hiMask * highlights * 0.8), 0.0h, 1.0h);

  // Shadows in trough
  float shMask = max(0.0, -profile); shMask *= shMask;
  col.rgb = clamp(col.rgb - half3(shMask * shadows * 0.75), 0.0h, 1.0h);

  // Edge glints at flute seams
  float edgeDist = min(t, 1.0 - t) * 2.0; // 0 at seam, 1 at center
  float edgeMask = pow(max(0.0, 1.0 - edgeDist), 5.0);
  col.rgb = clamp(col.rgb + half3(edgeMask * edges * 0.7), 0.0h, 1.0h);

  return col;
}

// ── Rain Glass ───────────────────────────────────────────────────────────────
// Based on "Heartfelt" by Martijn Steinrucken aka BigWings - 2017
// https://www.shadertoy.com/view/ltffzl
//
// Licence: the rest of Shader Lab is MIT, but this section, from here to the end of
// `rainGlass`, adapts Heartfelt and so keeps its licence, CC BY-NC-SA 3.0:
// https://creativecommons.org/licenses/by-nc-sa/3.0/
// SPDX-License-Identifier: CC-BY-NC-SA-3.0

// Sine-free 1D hash: this runs for every drop layer of every pixel
float rain_N(float t) {
  float p = fract(t * 0.1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

float3 rain_N13(float p) {
  float3 p3 = fract(float3(p) * float3(0.1031, 0.11369, 0.13787));
  p3 += dot(p3, p3.yzx + 19.19);
  return fract(float3((p3.x + p3.y) * p3.z,
                      (p3.x + p3.z) * p3.y,
                      (p3.y + p3.z) * p3.x));
}

float rain_Saw(float b, float t) {
  return smoothstep(0.0, b, t) * smoothstep(1.0, b, t);
}

// `wobble` is how much the drops wander side to side as they run: 1 on a still window
float2 rain_DropLayer2(float2 uv, float t, float wobble) {
  float2 UV = uv;
  uv.y += t * 0.75;
  float2 a = float2(6.0, 1.0);
  float2 grid = a * 2.0;
  float2 id = floor(uv * grid);

  float colShift = rain_N(id.x);
  uv.y += colShift;

  id = floor(uv * grid);
  float3 n = rain_N13(id.x * 35.2 + id.y * 2376.1);
  float2 st = fract(uv * grid) - float2(0.5, 0.0);

  float x = n.x - 0.5;
  float y = UV.y * 20.0;
  float wiggle = sin(y + sin(y));
  x += wiggle * (0.5 - abs(x)) * (n.z - 0.5) * wobble;
  x *= 0.7;

  float ti = fract(t + n.z);
  y = (rain_Saw(0.85, ti) - 0.5) * 0.9 + 0.5;
  float2 p = float2(x, y);

  float d = length((st - p) * a.yx);
  float mainDrop = smoothstep(0.4, 0.0, d);

  float r = sqrt(smoothstep(1.0, y, st.y));
  float cd = abs(st.x - x);
  float trail = smoothstep(0.23 * r, 0.15 * r * r, cd);
  float trailFront = smoothstep(-0.02, 0.02, st.y - y);
  trail *= trailFront * r * r;

  // (An earlier sin-based droplet term lived here, but its result was overwritten below
  // before anything read it, so it was pure cost.)
  y = fract(UV.y * 10.0) + (st.y - 0.5);
  float dd = length(st - float2(x, y));
  float droplets = smoothstep(0.3, 0.0, dd);
  float m = mainDrop + droplets * r * trailFront;

  return float2(m, trail);
}

float rain_StaticDrops(float2 uv, float t) {
  uv *= 40.0;
  float2 id = floor(uv);
  uv = fract(uv) - 0.5;
  float3 n = rain_N13(id.x * 107.45 + id.y * 3543.654);
  float2 dp = (n.xy - 0.5) * 0.7;
  float d = length(uv - dp);
  float fade = rain_Saw(0.025, fract(t + n.z));
  return smoothstep(0.3, 0.0, d) * fract(n.z * 10.0) * fade;
}

float2 rain_Drops(float2 uv, float t, float l0, float l1, float l2, float wobble) {
  float s   = rain_StaticDrops(uv, t) * l0;
  // A layer whose weight is zero (light rain) contributes nothing, so don't compute it
  float2 m1 = l1 > 0.0 ? rain_DropLayer2(uv, t, wobble) * l1 : float2(0.0);
  float2 m2 = l2 > 0.0 ? rain_DropLayer2(uv * 1.85, t, wobble) * l2 : float2(0.0);
  float c = smoothstep(0.3, 1.0, s + m1.x + m2.x);
  return float2(c, max(m1.y * l0, m2.y * l1));
}

// The eight blur directions, fixed. Computing cos/sin for them per pixel was 16 trig calls
// for the same eight answers.
constant float2 rainBlurRing[8] = {
  float2( 1.0,        0.0),       float2( 0.70710678,  0.70710678),
  float2( 0.0,        1.0),       float2(-0.70710678,  0.70710678),
  float2(-1.0,        0.0),       float2(-0.70710678, -0.70710678),
  float2( 0.0,       -1.0),       float2( 0.70710678, -0.70710678),
};

// Signed distance to a box of half-size b with corners rounded by r, centred on the origin
float rain_RoundBox(float2 p, float2 b, float r) {
  float2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// ── A late-night flight (Rain's plane window) ───────────────────────────────
// A row of windows along a dark cabin wall. The one in the middle is in focus and shows the
// rain; the others blur, dim and fade with distance, their shades half down, like the rest of
// a cabin at night beyond the seat you're in.

struct RainCabin {
  float2 halfSize;  // a window's
  float radius;     // its corners'
  float spacing;    // between window centres
};

RainCabin rain_CabinLayout(float2 size) {
  float height = min(size.y * 0.66, size.x * 0.8 / 0.68);
  RainCabin cabin;
  cabin.halfSize = float2(0.34, 0.5) * height;
  cabin.radius = 0.92 * cabin.halfSize.x;
  cabin.spacing = 3.3 * cabin.halfSize.x;
  return cabin;
}

// The outside at night: darker, cooler and a little greyer
float3 rain_Night(float3 c) {
  float grey = dot(c, float3(0.3, 0.59, 0.11));
  return mix(float3(grey), c, 0.75) * float3(0.55, 0.64, 0.85);
}

// The cabin around the windows. `view` is what the window in focus shows: the rain over the
// photo. `flight` is how far the scenery has drifted, in points. `glow` is the colour the photo
// casts, which the cabin's lights take on.
half4 rain_NightCabin(SwiftUI::Layer layer, float2 pos, float2 size, float time, float2 flight, half4 view,
                      half4 glow) {
  RainCabin cabin = rain_CabinLayout(size);
  float2 p = pos - size * 0.5;
  float k = clamp(round(p.x / cabin.spacing), -3.0, 3.0);
  float far = abs(k);
  float2 c = p - float2(k * cabin.spacing, 0.0);  // from this window's centre
  float w = cabin.halfSize.x, h = cabin.halfSize.y;
  float d = rain_RoundBox(c, cabin.halfSize, cabin.radius);
  float2 out = normalize(float2(
    rain_RoundBox(c + float2(1.0, 0.0), cabin.halfSize, cabin.radius) - rain_RoundBox(c - float2(1.0, 0.0), cabin.halfSize, cabin.radius),
    rain_RoundBox(c + float2(0.0, 1.0), cabin.halfSize, cabin.radius) - rain_RoundBox(c - float2(0.0, 1.0), cabin.halfSize, cabin.radius)) + 1e-6);
  // Depth of field: edges soften the further a window is from the middle, and the light falls
  // off smoothly along the row
  float soft = max(1.0, far * 0.12 * w);
  float dim = pow(0.5, abs(p.x) / cabin.spacing);
  float2 light = normalize(float2(-0.3, -1.0));  // the cabin's own light, from above; y points down
  // The cabin's light: the photo's colour at full brightness, softened a little toward white
  float3 photo = float3(glow.rgb);
  float3 cabinLight = mix(float3(1.0), photo / max(max(photo.r, photo.g), max(photo.b, 1e-3)), 0.85);
  float3 moon = float3(0.55, 0.66, 0.9);
  float rim = 0.09 * w, reveal = 0.12 * w;

  // The wall: near black, warmed by a seat light below each window (this one's and its
  // neighbours', so the glow runs on unbroken from window to window)
  float3 col = float3(0.075, 0.077, 0.088);
  for (int j = -1; j <= 1; j++) {
    float2 lamp = (p - float2((k + float(j)) * cabin.spacing - 0.55 * w, 1.35 * h)) / (1.2 * w);
    col += cabinLight * 0.16 * exp(-dot(lamp, lamp));
  }
  // Reading lights further down the cabin, out of focus, up near the ceiling
  float between = (round(p.x / cabin.spacing - 0.5) + 0.5) * cabin.spacing;
  float bokehSoft = max(2.0, 0.12 * w * abs(between) / cabin.spacing);
  col += cabinLight * 0.22 * (1.0 - smoothstep(0.045 * w, 0.045 * w + bokehSoft, length(p - float2(between, -1.3 * h))));

  // The trim around the opening: a rounded lip, warm from below, moonlit on its inner slope
  float lip = clamp(d / rim, 0.0, 1.0);
  float facing = dot(out, light) * -cos(lip * M_PI_F);
  float3 trim = float3(0.1, 0.1, 0.11) * (0.8 + 0.5 * facing) + moon * 0.05 * (1.0 - lip);
  col = mix(col, trim, 1.0 - smoothstep(rim - soft, rim + soft, d));

  // The bevel down to the pane, catching moonlight from outside
  float deep = clamp(-d / reveal, 0.0, 1.0);
  float3 bevel = mix(float3(0.11, 0.11, 0.12), float3(0.03, 0.035, 0.045), deep) * (0.8 + 0.3 * dot(-out, light))
               + moon * 0.07 * deep;
  col = mix(col, bevel, 1.0 - smoothstep(-soft, soft, d));

  // The pane
  float into = -d - reveal;
  float paneMask = 1.0 - smoothstep(-soft, soft, -into);
  float3 pane;
  if (far == 0.0) {
    pane = rain_Night(float3(view.rgb)) * (0.55 + 0.45 * smoothstep(0.0, 0.14 * w, into));
    // The cabin's warm light reflected in the glass
    float2 glare = (c - float2(-0.42 * w, -0.5 * h)) / (0.55 * w);
    pane += cabinLight * 0.05 * exp(-dot(glare, glare));
    // The wing's red light, blinking out in the dark
    float2 wing = c - float2(0.32 * w, 0.46 * h);
    float beat = fract(time / 1.4);
    float blink = smoothstep(0.0, 0.02, beat) * (1.0 - smoothstep(0.08, 0.18, beat));
    pane += float3(1.0, 0.14, 0.08) * blink * (exp(-length(wing) / (0.012 * w)) + 0.22 * exp(-length(wing) / (0.14 * w)));
    // The outer pane's edge, a hairline just inside the inner one, and the breather hole
    pane = mix(pane, pane * 1.35 + 0.02, 0.3 * (1.0 - smoothstep(0.0, 1.0, abs(into - 0.05 * w))));
    float hole = length(c - float2(0.0, 0.78 * h)) - 0.022 * w;
    pane = mix(pane, pane * 0.35, 1.0 - smoothstep(-0.5, 0.5, hole));
  } else {
    // A neighbour: its view blurred right out, and its shade half down
    half4 blurred = half4(0.0);
    for (int i = 0; i < 8; i++) {
      blurred += layer.sample(pos + flight + rainBlurRing[i] * (soft * 1.2 + 6.0));
    }
    pane = rain_Night(float3(blurred.rgb / 8.0)) * 0.85;
    float drawn = -h + (0.85 + 0.35 * fract(sin(k * 12.9898) * 43758.5453)) * h;
    float shade = 1.0 - smoothstep(-soft, soft, c.y - drawn);
    float3 blind = float3(0.15, 0.145, 0.14) + cabinLight * 0.05 * (1.0 - clamp((drawn - c.y) / h, 0.0, 1.0));
    pane = mix(pane, blind, shade);
  }
  col = mix(col, pane, paneMask);

  // Further windows fall into the dark, and the whole cabin into the edges of the frame
  col *= dim;
  float2 edge = p / (0.5 * size);
  col *= (1.0 - 0.4 * smoothstep(0.45, 1.15, abs(edge.x))) * (1.0 - 0.4 * smoothstep(0.6, 1.2, abs(edge.y)));
  // A little grain, like a photo taken in the dark, which also keeps the dim gradients from banding
  col += (fract(sin(dot(floor(pos), float2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.014;
  return half4(half3(max(col, 0.0)), 1.0h);
}

[[stitchable]] half4 rainGlass(
    float2 pos, SwiftUI::Layer layer, float2 size,
    float time, float rainAmt, float speed, float zoomAmt, float window, half4 glow
) {
  // Based on "Heartfelt" by Martijn Steinrucken aka BigWings, 2017 (shadertoy.com/view/ltffzl).
  // Licensed CC BY-NC-SA 3.0 (creativecommons.org/licenses/by-nc-sa/3.0/), unlike the rest of Shader Lab.

  // Heartfelt was written for Shadertoy, where y points up. SwiftUI's y points down,
  // so flip it, or the drops slide up the glass.
  float2 uv = (pos - size * 0.5) / size.y;
  uv.y = -uv.y;
  float2 UV = pos / size;
  float  t  = time * speed * 0.15;

  float l0 = smoothstep(-0.5, 1.0, rainAmt) * 2.0;
  float l1 = smoothstep(0.25, 0.75, rainAmt);
  float l2 = smoothstep(0.0,  0.5,  rainAmt);

  // The window you look through decides which way the water runs. House (0): the drops slide
  // down. Car (1): the wind pushes them up the windshield, quicker and straighter. Plane (2):
  // they streak back along the window. The drops are worked out in a frame turned so they
  // always run toward its -y, then the normals below are taken back on the screen.
  int pane = int(round(window));

  // Through a plane's window at night (see rain_NightCabin), the scenery drifts as the plane
  // flies, with now and then a little bump. Only the window in focus shows rain, so the rest
  // of the cabin skips the drops.
  float2 flight = float2(0.0);
  if (pane == 2) {
    float bumpAge = fract(time / 9.0) * 9.0;
    float bump = exp(-3.0 * bumpAge) * sin(bumpAge * 28.0);
    flight = size.y * float2(0.012 * sin(time * 0.11), 0.004 * sin(time * 0.6) + 0.005 * bump);
    RainCabin cabin = rain_CabinLayout(size);
    float2 fromCentre = pos - size * 0.5;
    bool inFocus = abs(fromCentre.x) < 0.5 * cabin.spacing;
    if (!inFocus || rain_RoundBox(fromCentre, cabin.halfSize, cabin.radius) > 1.5) {
      return rain_NightCabin(layer, pos, size, time, flight, half4(0.0h), glow);
    }
  }
  float2 runs = pane == 1 ? float2(0.0, 1.0) : pane == 2 ? normalize(float2(1.0, 0.35)) : float2(0.0, -1.0);
  float2 paneY = -runs, paneX = float2(paneY.y, -paneY.x);
  auto onPane = [&](float2 q) { return float2(dot(q, paneX), dot(q, paneY)); };
  float pace = pane == 1 ? 1.8 : pane == 2 ? 2.4 : 1.0;
  float wobble = pane == 1 ? 0.3 : pane == 2 ? 0.0 : 1.0;
  float tDrops = t * pace;

  float2 c = rain_Drops(onPane(uv), tDrops, l0, l1, l2, wobble);

  // Surface normals via finite differences, which means evaluating the whole drop pattern
  // twice more. Most of the glass has no drop on it, and there the normal is zero, so the
  // two extra evaluations only run where there is actually water.
  float2 n = float2(0.0);
  if (c.x > 0.0) {
    float2 e  = float2(0.001, 0.0);
    float  cx = rain_Drops(onPane(uv + e),    tDrops, l0, l1, l2, wobble).x;
    float  cy = rain_Drops(onPane(uv + e.yx), tDrops, l0, l1, l2, wobble).x;
    n = float2(cx - c.x, -(cy - c.x));  // back to y-down for sampling
  }

  float maxBlur = mix(3.0, 6.0, rainAmt);
  float focus   = mix(maxBlur - c.y, 2.0, smoothstep(0.1, 0.2, c.x));

  // Global parallax zoom — slow breathe that separates the glass layer from the background
  float zoom     = 1.05 + zoomAmt * (sin(time * 0.3) * 0.5 + 0.5);
  float2 zoomUV  = (UV - 0.5) / zoom + 0.5;

  // Radial-blur sample to approximate frosted-glass LOD
  float2 basePos = (zoomUV + n) * size + flight;
  float  blurR   = focus * 2.5;
  half4  col     = half4(0.0);
  for (int i = 0; i < 8; i++) {
    col += layer.sample(basePos + rainBlurRing[i] * blurR);
  }
  col /= 8.0;

  // Subtle cool colour cast
  float colFade = sin(t * 0.5) * 0.5 + 0.5;
  col.rgb = mix(col.rgb, col.rgb * half3(0.82h, 0.92h, 1.25h), half(colFade * 0.35));

  // Vignette
  float2 vUV = UV - 0.5;
  col.rgb   *= half(1.0 - dot(vUV, vUV) * 1.1);

  if (pane == 2) return rain_NightCabin(layer, pos, size, time, flight, col, glow);
  return col;
}

// ── Elemental Reveal ─────────────────────────────────────────────────────────

// Ripple+pinch distortion that, on tap, reveals a fire/ice/rain elemental effect.
// mode: 0=Fire  1=Ice  2=Rain
[[stitchable]] half4 elementalReveal(
    float2 pos, SwiftUI::Layer layer, float2 size,
    float time, float tapTime,
    float mode, float speed, float amplitude, float frequency
) {
  float2 uv = pos / size;

  // Combined ripple + pinch distortion
  float2 center = size * 0.5;
  float2 delta  = pos - center;
  float  dist   = length(delta) / min(size.x, size.y);
  float  t      = time * speed * 0.5;

  float  wave   = sin(dist * frequency * M_PI_F * 2.0 - t) * amplitude;
  float2 dir    = length(delta) > 0.001 ? normalize(delta) : float2(0, 1);
  float2 sPos   = pos + dir * wave * min(size.x, size.y) * 0.05;

  float pinchT  = sin(time * speed * 0.25) * 0.5 + 0.5;
  float falloff = 1.0 - smoothstep(0.0, 0.5, dist);
  float pinch   = 1.0 - 0.35 * pinchT * falloff;
  sPos = mix(sPos, center + (sPos - center) * pinch, 0.5);

  half4 original = layer.sample(sPos);

  // Reveal progress: rises 0→1 over 1.5 s, fades out by 4.5 s
  float elapsed  = time - tapTime;
  float progress = 0.0;
  if (elapsed >= 0.0 && elapsed < 4.5) {
    progress = smoothstep(0.0, 1.2, elapsed) * (1.0 - smoothstep(2.8, 4.5, elapsed));
  }
  if (progress < 0.001) return original;

  // Per-pixel noise threshold for an organic reveal edge
  float noiseVal = fbm(uv * 5.0 + float2(time * 0.04, 0.0), 3);
  noiseVal = mapRangeClamped(noiseVal, -1.0, 1.0, 0.0, 1.0);

  float edge = progress - noiseVal;
  if (edge < 0.0) return original;

  float blend    = smoothstep(0.0, 0.15, edge);
  float edgeGlow = smoothstep(0.0, 0.05, edge) * (1.0 - smoothstep(0.05, 0.18, edge));

  int m = int(round(mode));
  half3 elementColor;
  half3 glowColor;

  if (m == 0) { // Fire
    float fy  = uv.y - time * speed * 0.4;
    float fn1 = fbm(float2(uv.x * 3.5, fy * 5.0), 4);
    fn1 = clamp(fn1 * 2.0 + 0.6, 0.0, 1.0);
    elementColor = mix(half3(0.9, 0.04, 0.0), half3(1.0, 0.85, 0.05), half(fn1));
    glowColor    = half3(1.0, 0.45, 0.0);
  } else if (m == 1) { // Ice
    float fn2 = fbm(uv * 12.0 + float2(time * 0.08, time * 0.05), 3);
    fn2 = clamp(fn2 * 1.5 + 0.55, 0.0, 1.0);
    elementColor = mix(half3(0.25, 0.55, 0.88), half3(0.88, 0.95, 1.0), half(fn2));
    float cr = fract((uv.x * 0.7 - uv.y * 1.3) * 18.0 + time * 0.03);
    elementColor = mix(elementColor, half3(1.0), half(smoothstep(0.88, 1.0, cr) * 0.5));
    glowColor    = half3(0.4, 0.75, 1.0);
  } else { // Rain
    float rxc = fract(uv.x * 22.0 + floor(uv.y * 4.0) * 0.57);
    float ryc = fract(uv.y * 14.0 - time * speed * 0.6 + floor(uv.x * 22.0) * 0.43);
    float drop = step(0.91, rxc) * step(0.84, ryc) * step(ryc, 0.99);
    float rainBg = fbm(uv * 2.5 + float2(0.0, time * 0.15 * speed), 2);
    rainBg = mapRangeClamped(rainBg, -1.0, 1.0, 0.05, 0.35);
    elementColor = mix(half3(0.02, 0.05, 0.14), half3(0.55, 0.72, 1.0), half(drop));
    elementColor += half3(rainBg * 0.08, rainBg * 0.12, rainBg * 0.2);
    glowColor    = half3(0.25, 0.45, 1.0);
  }

  half4 result = mix(original, half4(elementColor, 1.0h), half(blend));
  result.rgb   = clamp(result.rgb + glowColor * half(edgeGlow * 2.5), 0.0h, 1.0h);
  return result;
}

[[stitchable]] half4 chromaticAberration(float2 pos, SwiftUI::Layer layer, float2 size, float /*time*/, float amount, float angle) {
  float2 center = size * 0.5;
  float2 delta = pos - center;
  float len = length(delta);
  float2 normDir = len > 0.001 ? delta / len : float2(0, 1);
  float cosA = cos(angle), sinA = sin(angle);
  float2 rotDir = float2(cosA*normDir.x - sinA*normDir.y, sinA*normDir.x + cosA*normDir.y);
  float2 offset = rotDir * amount * (len / length(center));
  half4 r = layer.sample(pos + offset);
  half4 g = layer.sample(pos);
  half4 b = layer.sample(pos - offset);
  return half4(r.r, g.g, b.b, max(r.a, max(g.a, b.a)));
}
