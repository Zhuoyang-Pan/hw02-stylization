// Helpers for the full screen post effects (day "paper" look and the night mode).

float PP_Hash(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float PP_Noise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(PP_Hash(i), PP_Hash(i + float2(1, 0)), u.x),
                lerp(PP_Hash(i + float2(0, 1)), PP_Hash(i + float2(1, 1)), u.x), u.y);
}

float PP_Fbm(float2 p)
{
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++)
    {
        v += a * PP_Noise(p);
        p = p * 2.03 + 7.1;
        a *= 0.5;
    }
    return v;
}

float PP_Luma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// signed distance to a rounded box centered at 0
float PP_RoundBox(float2 p, float2 halfSize, float r)
{
    float2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Day look: little bit of saturation, paper grain, and a soft pastel frame around the edges
// that fades into the background like the border of the illustration.
void PastelPaper_float(float3 Color, float2 UV, float Saturation, float GrainStrength, float GrainScale,
    float3 FrameColorA, float3 FrameColorB, float FrameSize, float FrameSoftness, float FrameStrength,
    out float3 OUT)
{
    float3 col = lerp(PP_Luma(Color).xxx, Color, Saturation);

    // grain is in pixel units so it doesn't stretch with the aspect ratio
    float2 px = UV * _ScreenParams.xy;
    float grain = PP_Fbm(px / max(GrainScale, 0.01));
    float fibers = PP_Noise(float2(px.x * 0.015, px.y * 0.6));
    col *= 1.0 + ((grain - 0.5) + (fibers - 0.5) * 0.35) * GrainStrength;

    float aspect = _ScreenParams.x / _ScreenParams.y;
    float2 p = (UV - 0.5) * 2.0 * float2(aspect, 1.0);
    float sd = PP_RoundBox(p, float2(aspect, 1.0) * FrameSize, 0.35);
    sd += (PP_Noise(UV * 7.0) - 0.5) * 0.12;   // wavy painted edge
    float frame = smoothstep(-FrameSoftness, FrameSoftness, sd);
    float3 frameCol = lerp(FrameColorA, FrameColorB, saturate(UV.x * 0.6 + (1.0 - UV.y) * 0.4));
    OUT = lerp(col, frameCol, frame * FrameStrength);
}

// Night look: gradient-map the image towards blues, replace the empty sky with a night
// gradient, and sprinkle twinkling stars that only show up where nothing was drawn.
void NightGrade_float(float3 Color, float2 UV, float RawDepth, float SteppedTime,
    float3 ShadowTint, float3 MidTint, float3 HighTint, float KeepColor,
    float3 SkyTop, float3 SkyBottom, float StarDensity, float StarBrightness, float VignetteStrength,
    out float3 OUT)
{
    float lum = PP_Luma(Color);
    float3 grad = lum < 0.5 ? lerp(ShadowTint, MidTint, lum * 2.0) : lerp(MidTint, HighTint, lum * 2.0 - 1.0);
    // really bright things (stars, cockpit, nav lights) keep their own color so they read as glowing
    float keep = lerp(KeepColor, 1.0, smoothstep(0.45, 0.8, lum));
    float3 col = lerp(grad, Color, keep);

#if UNITY_REVERSED_Z
    float sky = step(RawDepth, 0.000001);
#else
    float sky = step(0.999999, RawDepth);
#endif

    float3 skyCol = lerp(SkyBottom, SkyTop, smoothstep(0.0, 1.0, UV.y));
    col = lerp(col, skyCol, sky);

    // stars on a jittered grid, each cell rolls a new twinkle value every step
    float aspect = _ScreenParams.x / _ScreenParams.y;
    float2 g = float2(UV.x * aspect, UV.y) * StarDensity;
    float2 cell = floor(g);
    float2 f = frac(g) - 0.5;
    float2 jitter = (float2(PP_Hash(cell + 7.1), PP_Hash(cell + 3.3)) - 0.5) * 0.6;
    float2 d = f - jitter;
    float core = smoothstep(0.08, 0.0, length(d));
    float rays = smoothstep(0.03, 0.0, abs(d.x)) * smoothstep(0.25, 0.0, abs(d.y)) +
                 smoothstep(0.03, 0.0, abs(d.y)) * smoothstep(0.25, 0.0, abs(d.x));
    float exists = step(0.72, PP_Hash(cell));
    float twinkle = lerp(0.25, 1.0, step(0.45, PP_Hash(cell + floor(SteppedTime * 4.0) * 1.37)));
    float star = saturate(core + rays * 0.6) * exists * twinkle;
    col += star * sky * StarBrightness * HighTint;

    float2 v = UV - 0.5;
    col *= saturate(1.0 - dot(v, v) * VignetteStrength);
    OUT = col;
}
