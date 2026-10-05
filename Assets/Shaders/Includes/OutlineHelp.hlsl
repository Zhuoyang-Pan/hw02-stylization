SAMPLER(sampler_point_clamp);

void GetDepth_float(float2 uv, out float Depth)
{
    Depth = SHADERGRAPH_SAMPLE_SCENE_DEPTH(uv);
}


void GetNormal_float(float2 uv, out float3 Normal)
{
    Normal = SAMPLE_TEXTURE2D(_NormalsBuffer, sampler_point_clamp, uv).rgb;
}

// ---------------------------------------------------------------------------
// HW2 outline helpers
// ---------------------------------------------------------------------------

float OL_Hash(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float OL_Noise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(OL_Hash(i), OL_Hash(i + float2(1, 0)), u.x),
                lerp(OL_Hash(i + float2(0, 1)), OL_Hash(i + float2(1, 1)), u.x), u.y);
}

float OL_EyeDepth(float2 uv)
{
    float d;
    GetDepth_float(uv, d);
    return LinearEyeDepth(d, _ZBufferParams);
}

float3 OL_ViewNormal(float2 uv)
{
    float3 n;
    GetNormal_float(uv, n);
    return n * 2.0 - 1.0;
}

// Sobel on linear eye depth. The sample position gets pushed around by noise that only
// changes every time step, which makes the lines "boil" like hand drawn animation.
// The gradient is divided by the center depth so the threshold works up close and far away.
// NearUV is the tap closest to the camera, used later to color the line by the object in front.
// CenterDepth comes from the Scene Depth node (Eye mode) in the graph.
void DepthOutline_float(float2 UV, float CenterDepth, float SteppedTime, float Thickness, float Threshold,
    float WobbleAmount, float WobbleScale, out float Edge, out float2 NearUV)
{
    float2 texel = 1.0 / _ScreenParams.xy;

    float2 q = UV * WobbleScale + SteppedTime * 3.17;
    float2 wobble = float2(OL_Noise(q), OL_Noise(q + 17.3)) - 0.5;
    float2 uv = UV + wobble * WobbleAmount * texel;

    // thickness varies a bit along the line too (like pen pressure)
    float t = Thickness * lerp(0.6, 1.4, OL_Noise(q * 0.5 + 5.1));
    float2 o = texel * t;

    float2 offsets[9] = {
        float2(-1, -1), float2(0, -1), float2(1, -1),
        float2(-1,  0), float2(0,  0), float2(1,  0),
        float2(-1,  1), float2(0,  1), float2(1,  1)
    };
    float d[9];
    float nearest = 1e9;
    NearUV = uv;
    [unroll]
    for (int i = 0; i < 9; i++)
    {
        float2 suv = uv + offsets[i] * o;
        d[i] = OL_EyeDepth(suv);
        if (d[i] < nearest)
        {
            nearest = d[i];
            NearUV = suv;
        }
    }

    float gx = (d[2] + 2.0 * d[5] + d[8]) - (d[0] + 2.0 * d[3] + d[6]);
    float gy = (d[6] + 2.0 * d[7] + d[8]) - (d[0] + 2.0 * d[1] + d[2]);
    float g = sqrt(gx * gx + gy * gy) / max(min(d[4], CenterDepth), 0.001);

    Edge = smoothstep(Threshold, Threshold * 1.5, g);
}

// Robert's cross on the normal buffer. No wobble here on purpose so the inner
// lines keep the shapes readable.
void NormalOutline_float(float2 UV, float Thickness, float Threshold, out float Edge)
{
    float2 o = Thickness / _ScreenParams.xy;
    float3 n0 = OL_ViewNormal(UV + float2(-o.x, -o.y));
    float3 n1 = OL_ViewNormal(UV + float2( o.x,  o.y));
    float3 n2 = OL_ViewNormal(UV + float2( o.x, -o.y));
    float3 n3 = OL_ViewNormal(UV + float2(-o.x,  o.y));
    float3 a = n1 - n0;
    float3 b = n3 - n2;
    float e = sqrt(dot(a, a) + dot(b, b));
    Edge = smoothstep(Threshold, Threshold + 0.15, e);
}

// In the concept the lines aren't black: darker parts get a deep blue line and the white
// clouds get a light cyan one. Pick between the two based on how bright the thing in front is.
void LineColor_float(UnityTexture2D SceneTex, float2 NearUV, float3 DarkLine, float3 LightLine, float Cutoff,
    out float3 Color)
{
    float3 c = SAMPLE_TEXTURE2D(SceneTex.tex, sampler_point_clamp, NearUV).rgb;
    float lum = dot(c, float3(0.2126, 0.7152, 0.0722));
    Color = lerp(DarkLine, LightLine, smoothstep(Cutoff - 0.08, Cutoff + 0.08, lum));
}

void CompositeOutline_float(float3 SceneColor, float3 LineColor, float DepthEdge, float NormalEdge,
    float NormalStrength, out float3 OUT)
{
    float e = saturate(max(DepthEdge, NormalEdge * NormalStrength));
    OUT = lerp(SceneColor, LineColor, e);
}
