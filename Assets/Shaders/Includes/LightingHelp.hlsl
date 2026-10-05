void GetMainLight_float(float3 WorldPos, out float3 Color, out float3 Direction, out float DistanceAtten, out float ShadowAtten)
{
#ifdef SHADERGRAPH_PREVIEW
    Direction = normalize(float3(0.5, 0.5, 0));
    Color = 1;
    DistanceAtten = 1;
    ShadowAtten = 1;
#else
#if SHADOWS_SCREEN
        float4 clipPos = TransformWorldToClip(WorldPos);
        float4 shadowCoord = ComputeScreenPos(clipPos);
#else
    float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
#endif

    Light mainLight = GetMainLight(shadowCoord);
    Direction = mainLight.direction;
    Color = mainLight.color;
    DistanceAtten = mainLight.distanceAttenuation;
    ShadowAtten = mainLight.shadowAttenuation;
#endif
}

void ComputeAdditionalLighting_float(float3 WorldPosition, float3 WorldNormal,
    float2 Thresholds, float3 RampedDiffuseValues,
    out float3 Color, out float Diffuse)
{
    Color = float3(0, 0, 0);
    Diffuse = 0;

#ifndef SHADERGRAPH_PREVIEW

    int pixelLightCount = GetAdditionalLightsCount();
    
    for (int i = 0; i < pixelLightCount; ++i)
    {
        Light light = GetAdditionalLight(i, WorldPosition);
        float4 tmp = unity_LightIndices[i / 4];
        uint light_i = tmp[i % 4];

        half shadowAtten = light.shadowAttenuation * AdditionalLightRealtimeShadow(light_i, WorldPosition, light.direction);
        
        half NdotL = saturate(dot(WorldNormal, light.direction));
        half distanceAtten = light.distanceAttenuation;

        half thisDiffuse = distanceAtten * shadowAtten * NdotL;
        
        half rampedDiffuse = 0;
        
        if (thisDiffuse < Thresholds.x)
        {
            rampedDiffuse = RampedDiffuseValues.x;
        }
        else if (thisDiffuse < Thresholds.y)
        {
            rampedDiffuse = RampedDiffuseValues.y;
        }
        else
        {
            rampedDiffuse = RampedDiffuseValues.z;
        }

        
        if (light.distanceAttenuation <= 0)
        {
            rampedDiffuse = 0.0;
        }

        Color += max(rampedDiffuse, 0) * light.color.rgb;
        Diffuse += rampedDiffuse;
    }
    
    if (Diffuse <= 0.3)
    {
        Color = float3(0, 0, 0);
        Diffuse = 0;
    }
    
#endif
}

void ChooseColor_float(float3 Highlight, float3 Midtone, float3 Shadow, float Diffuse, float2 Thresholds, out float3 OUT)
{
    if (Diffuse < Thresholds.x)
    {
        OUT = Shadow;
    }
    else if (Diffuse < Thresholds.y)
    {
        OUT = Midtone;
    }
    else
    {
        OUT = Highlight;
    }
}

// ---------------------------------------------------------------------------
// HW2 additions
// ---------------------------------------------------------------------------

// Three tone ramp from the lab, but the main light and the additional lights are combined here.
// AddColor / AddDiffuse come straight out of ComputeAdditionalLighting (the tutorial function above),
// so every point light already got stepped into bands and tinted by its own color.
// ShadowMask is 1 in the shadow band and 0 when lit (used for the shadow texture later).
void ToonShade_float(float3 WorldNormal, float3 MainLightDir, float3 MainLightColor, float DistanceAtten, float ShadowAtten,
    float3 AddColor, float AddDiffuse,
    float3 Highlight, float3 Midtone, float3 Shadow, float2 Thresholds, float Smoothness, float AddStrength,
    out float3 Color, out float ShadowMask)
{
    float NdotL = saturate(dot(normalize(WorldNormal), MainLightDir));
    float diffuse = NdotL * DistanceAtten * ShadowAtten;

    // smoothness 0 = hard toon edges, same idea as the lab extra credit
    float w = max(Smoothness * 0.5, 0.0001);
    float toMid = smoothstep(Thresholds.x - w, Thresholds.x + w, diffuse);
    float toHigh = smoothstep(Thresholds.y - w, Thresholds.y + w, diffuse);
    float3 ramp = lerp(lerp(Shadow, Midtone, toMid), Highlight, toHigh);

    // point lights add their own colored band on top of the palette instead of just brightening it
    Color = ramp * MainLightColor + AddColor * Highlight * AddStrength;
    // point lights only lift the shadow halfway so the shadow texture still shows a bit under them
    ShadowMask = (1.0 - toMid) * (1.0 - 0.5 * saturate(AddDiffuse));
}

// Blinn-Phong highlight cut into one hard (or slightly soft) blob, like the white glints in the concept.
void ToonSpecular_float(float3 WorldNormal, float3 ViewDir, float3 MainLightDir, float ShadowAtten,
    float Glossiness, float Size, float Smoothness, out float Specular)
{
    float3 n = normalize(WorldNormal);
    float3 v = normalize(ViewDir);
    float3 h = normalize(MainLightDir + v);
    float spec = pow(saturate(dot(n, h)), Glossiness) * step(0.0, dot(n, MainLightDir)) * ShadowAtten;
    float w = max(Smoothness * 0.25, 0.0001);
    Specular = smoothstep(1.0 - Size - w, 1.0 - Size + w, spec);
}

// Fresnel rim. LightAlign pushes the rim towards the side that faces the light
// (0 = rim all the way around, 1 = only on the lit side).
void ToonRim_float(float3 WorldNormal, float3 ViewDir, float3 MainLightDir,
    float RimSize, float RimSmoothness, float LightAlign, out float Rim)
{
    float3 n = normalize(WorldNormal);
    float3 v = normalize(ViewDir);
    float fresnel = 1.0 - saturate(dot(n, v));
    float side = lerp(1.0, saturate(dot(n, MainLightDir) * 0.5 + 0.5), LightAlign);
    float r = fresnel * side;
    float w = max(RimSmoothness * 0.5, 0.0001);
    Rim = smoothstep(1.0 - RimSize - w, 1.0 - RimSize + w, r);
}

// Custom shadow texture, sampled with the object UVs (the graph does the tiling with Shadow Scale).
// The texture is dark strokes on white, so (1 - Pattern) is how much "ink" there is.
// Only shows up inside the shadow band.
void ShadowTexture_float(float3 Color, float ShadowMask, float Pattern, float3 PatternColor, float Strength,
    out float3 OUT)
{
    float ink = (1.0 - Pattern) * saturate(Strength) * ShadowMask;
    OUT = lerp(Color, PatternColor, ink);
}

// ---------------------------------------------------------------------------
// toolbox functions for the hero shader
// ---------------------------------------------------------------------------
float TB_Bias(float b, float t)
{
    return pow(abs(t), log(b) / log(0.5));
}

float TB_Gain(float g, float t)
{
    if (t < 0.5)
        return TB_Bias(1.0 - g, 2.0 * t) * 0.5;
    return 1.0 - TB_Bias(1.0 - g, 2.0 - 2.0 * t) * 0.5;
}

float TB_Sawtooth(float x, float freq, float amplitude)
{
    return (x * freq - floor(x * freq)) * amplitude;
}

// iq's cosine palette
float3 TB_Palette(float t, float3 a, float3 b, float3 c, float3 d)
{
    return a + b * cos(6.28318 * (c * t + d));
}

float TB_Hash13(float3 p)
{
    p = frac(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}

float TB_Noise3(float3 p)
{
    float3 i = floor(p);
    float3 f = frac(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float n000 = TB_Hash13(i);
    float n100 = TB_Hash13(i + float3(1, 0, 0));
    float n010 = TB_Hash13(i + float3(0, 1, 0));
    float n110 = TB_Hash13(i + float3(1, 1, 0));
    float n001 = TB_Hash13(i + float3(0, 0, 1));
    float n101 = TB_Hash13(i + float3(1, 0, 1));
    float n011 = TB_Hash13(i + float3(0, 1, 1));
    float n111 = TB_Hash13(i + float3(1, 1, 1));
    float a = lerp(lerp(n000, n100, u.x), lerp(n010, n110, u.x), u.y);
    float b = lerp(lerp(n001, n101, u.x), lerp(n011, n111, u.x), u.y);
    return lerp(a, b, u.z);
}

// Special effect for the plane: a pastel rainbow "foil" band that sweeps across it,
// plus a rainbow rim and a few sparkles that pop in and out.
// SteppedTime is floor(time * rate) / rate from the graph, so everything moves in little
// jumps like it was animated on 2s/3s.
void HoloShimmer_float(float3 Color, float3 WorldPos, float3 WorldNormal, float3 ViewDir, float SteppedTime,
    float SweepSpeed, float SweepWidth, float SweepRange, float Strength, float RimAmount, float SparkleDensity,
    out float3 OUT)
{
    float3 n = normalize(WorldNormal);
    float3 v = normalize(ViewDir);
    float fresnel = 1.0 - saturate(dot(n, v));

    // diagonal coordinate across the plane, with some noise so the band edge is wavy
    float coord = dot(WorldPos, normalize(float3(0.8, 0.35, 0.5)));
    coord += (TB_Noise3(WorldPos * 2.0 + SteppedTime * 0.7) - 0.5) * 0.6;

    // sawtooth moves the band from one end to the other, then wraps around
    float sweepPos = TB_Sawtooth(SteppedTime, SweepSpeed, 1.0) * 2.0 * SweepRange - SweepRange;
    float band = saturate(1.0 - abs(coord - sweepPos) / max(SweepWidth, 0.001));
    band = TB_Gain(0.85, band);

    float3 rainbow = TB_Palette(coord * 0.35 + SteppedTime * 0.25,
        float3(0.72, 0.66, 0.84), float3(0.30, 0.32, 0.20),
        float3(1.0, 1.0, 1.0), float3(0.0, 0.33, 0.67));

    float rim = smoothstep(0.45, 0.7, fresnel) * RimAmount;

    // sparkles: random cells light up for one step at a time
    float3 cellPos = WorldPos * SparkleDensity;
    float rnd = TB_Hash13(floor(cellPos) + floor(SteppedTime * 3.0) * 17.0);
    float dist = length(frac(cellPos) - 0.5);
    float sparkle = step(0.94, rnd) * smoothstep(0.4, 0.15, dist);

    float mask = saturate(band + rim) * Strength;
    OUT = lerp(Color, rainbow, mask);
    OUT = lerp(OUT, float3(1, 1, 1), sparkle * Strength);
}

// Cockpit glass. It's transparent, so it never ends up in the depth / normal buffers and the
// post process outline can't see it. Instead it draws its own line with a fresnel cutoff,
// plus a toon specular blob and a couple of diagonal "window glint" streaks.
void GlassToon_float(float3 WorldNormal, float3 ViewDir, float3 MainLightDir,
    float3 GlassColor, float3 EdgeColor, float EdgeWidth, float BaseAlpha, float Glossiness, float SpecSize,
    out float3 Color, out float Alpha)
{
    float3 n = normalize(WorldNormal);
    float3 v = normalize(ViewDir);
    float fresnel = 1.0 - saturate(dot(n, v));

    float edge = smoothstep(1.0 - EdgeWidth - 0.02, 1.0 - EdgeWidth + 0.02, fresnel);

    float3 h = normalize(MainLightDir + v);
    float spec = step(1.0 - SpecSize, pow(saturate(dot(n, h)), Glossiness));

    // streaks: bands in view space so they always read as a reflection on the glass
    float3 vn = mul((float3x3)UNITY_MATRIX_V, n);
    float s = vn.x * 0.8 + vn.y * 0.6;
    float glint = step(0.42, s) * step(s, 0.55) + step(0.6, s) * step(s, 0.66);
    glint *= step(fresnel, 0.75);

    Color = lerp(GlassColor, float3(1, 1, 1), saturate(spec + glint));
    Color = lerp(Color, EdgeColor, edge);
    Alpha = saturate(BaseAlpha + fresnel * 0.35 + spec + glint * 0.8 + edge);
}

// ---------------------------------------------------------------------------
// Extra credit: texture support with procedural shading colors
// ---------------------------------------------------------------------------
float3 PC_RgbToHsv(float3 c)
{
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 PC_HsvToRgb(float3 c)
{
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

// move hue h towards target the short way around the color wheel
float PC_HueTowards(float h, float target, float amount)
{
    float d = target - h;
    d -= round(d);
    return frac(h + d * amount);
}

// Instead of hand picking 3 colors per material, build them from the texture color.
// Shadows don't just get darker: the hue slides towards ShadowHue (purple in this scene)
// and they get more saturated, like an artist would paint them. Highlights get lighter,
// a bit less saturated and pushed slightly warm.
// The math is done in gamma space since that's closer to how the colors were picked.
void ProceduralPalette_float(float3 Base, float3 Tint, float3 ShadowHue, float HueShift, float SatBoost,
    float ShadowValue, float HighlightLift, float HighlightDesat,
    out float3 Highlight, out float3 Midtone, out float3 Shadow)
{
    float3 c = pow(saturate(Base * Tint), 1.0 / 2.2);
    float3 hsv = PC_RgbToHsv(c);
    float target = PC_RgbToHsv(pow(saturate(ShadowHue), 1.0 / 2.2)).x;

    float3 sh = hsv;
    sh.x = PC_HueTowards(hsv.x, target, HueShift);
    // near-white colors get some saturation too, otherwise white would just turn grey
    sh.y = saturate(hsv.y + SatBoost * (1.0 - hsv.y * 0.5));
    sh.z = hsv.z * ShadowValue;

    float3 hi = hsv;
    hi.x = PC_HueTowards(hsv.x, 0.12, HighlightLift * 0.3);
    hi.y = hsv.y * (1.0 - HighlightDesat);
    hi.z = lerp(hsv.z, 1.0, HighlightLift);

    Midtone = pow(c, 2.2);
    Shadow = pow(PC_HsvToRgb(sh), 2.2);
    Highlight = pow(PC_HsvToRgb(hi), 2.2);
}
