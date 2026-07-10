#ifndef S_CHAR_UTILS_INCLUDED
#define S_CHAR_UTILS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#ifndef S_CHAR_FORWARD_PASS
TEXTURE2D(_BaseColor);
SAMPLER(sampler_BaseColor);

CBUFFER_START(UnityPerMaterial)
    half4 _BaseColor_ST;
    half _AlphaClip;
CBUFFER_END

float _PerObjectShadowEnabled;
#endif

// =======================================================================
// 全局角色边缘光参数 (Global Anime Rim Light)
// =======================================================================
float _Global_OffsetMul;
float _Global_Threshold;
float _Global_Smooth;
half4 _Global_RimLightColor;
float _Global_RimIntensity;
float _Global_RimLightBrightness;

half4 _Global_InnerRimColor;
float _Global_InnerRimPower;
float _Global_InnerRimIntensity;
float _Global_InnerRimBrightness;
float _Global_InnerRimBias;
float _Global_EnableRimLight;
float _Global_ShadowStrength;

float3 _Global_RimLightDirection;
float _Global_RimLightSoftness;
float _Global_RimLightOffset;

TEXTURE2D_X_FLOAT(_CameraDepthTexture);
SAMPLER(sampler_CameraDepthTexture);

TEXTURE2D_X_FLOAT(_PerObjectTransparentDepthTexture);
SAMPLER(sampler_PerObjectTransparentDepthTexture);

// =======================================================================
// 柔光叠加 (Soft Light Blend)
// =======================================================================
half3 BlendSoftLight(half3 base, half3 blend)
{
    return (1.0 - 2.0 * blend) * base * base + 2.0 * blend * base;
}

// =======================================================================
// 自定义屏幕空间阴影采样
// =======================================================================
TEXTURE2D(_PerObjectScreenSpaceShadowMap);

half3 SamplePerObjectScreenSpaceShadowmap(float4 shadowCoord)
{
    if (shadowCoord.w <= 0.0)
        return half3(1.0, 1.0, 1.0);

    shadowCoord.xy /= max(0.00001, shadowCoord.w);
    shadowCoord.xy = UnityStereoTransformScreenSpaceTex(shadowCoord.xy);
    return half3(SAMPLE_TEXTURE2D(_PerObjectScreenSpaceShadowMap, sampler_LinearClamp, shadowCoord.xy).rgb);
}
// =======================================================================
// 等宽屏幕空间边缘光
// =======================================================================
void CalculateAnimeRimLight(
    float3 normalWS, float3 viewDirWS, float NdotL, half3 shadowAtten, half3 baseMapColor,
    float3 positionVS, float4 positionNDC, float3 positionOS,
    out half3 inner_rim, out half3 final_rim)
{
    inner_rim = 0;
    final_rim = 0;

    UNITY_BRANCH
    if (_Global_EnableRimLight < 0.5)
        return;

    // 对象空间X轴遮罩 (控制大范围的左暗右亮)
    float rimPosMask = smoothstep(_Global_RimLightOffset - _Global_RimLightSoftness, _Global_RimLightOffset + _Global_RimLightSoftness, -positionOS.x);

    // 世界空间固定方向法线遮罩 (控制受光面的细节)
    float3 rimLightDir = normalize(_Global_RimLightDirection);
    float rimNdotL = dot(normalWS, rimLightDir);
    float rimDirMask = smoothstep(_Global_RimLightOffset - _Global_RimLightSoftness, _Global_RimLightOffset + _Global_RimLightSoftness, rimNdotL);

    // 两个遮罩共同作用
    float combinedRimMask = rimPosMask * rimDirMask;

    // 阴影遮罩
    shadowAtten = step(0.5, shadowAtten);

    // 内部菲涅尔边缘光 (法线细节)
    half NdotV = saturate(dot(normalWS, viewDirWS));
    half fresnel = saturate(_Global_InnerRimBias + pow(1.0 - NdotV, _Global_InnerRimPower));
    half innerRimMask = saturate(fresnel * shadowAtten * _Global_InnerRimIntensity);
    inner_rim = innerRimMask * ((_Global_InnerRimColor.rgb + baseMapColor) * 0.5) * _Global_InnerRimBrightness * combinedRimMask;

    // 材质级深度边缘光 (硬轮廓)
    half3 normalVS_rim = TransformWorldToViewDir(normalWS, true);
    float3 samplePositionVS = float3(positionVS.xy + normalVS_rim.xy * _Global_OffsetMul, positionVS.z);
    float4 samplePositionCS = mul(UNITY_MATRIX_P, float4(samplePositionVS, 1.0));
    float4 samplePositionVP = ComputeScreenPos(samplePositionCS);
    samplePositionVP /= samplePositionVP.w;

    float depth = positionNDC.z / positionNDC.w;
    float linearEyeDepth = LinearEyeDepth(depth, _ZBufferParams);
    
#ifdef S_CHAR_TRANSPARENT
    float offsetDepth = SAMPLE_TEXTURE2D_X(_PerObjectTransparentDepthTexture, sampler_PerObjectTransparentDepthTexture, samplePositionVP.xy).r;
#else
    float offsetDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, samplePositionVP.xy).r;
#endif

    float linearEyeOffsetDepth = LinearEyeDepth(offsetDepth, _ZBufferParams);
    float depthDiff = linearEyeOffsetDepth - linearEyeDepth;

    float DOR_mask = smoothstep(_Global_Threshold - _Global_Smooth, _Global_Threshold + _Global_Smooth, depthDiff);
    float finalRimMask = saturate(DOR_mask * shadowAtten * _Global_RimIntensity);
    final_rim = finalRimMask * ((_Global_RimLightColor.rgb + baseMapColor) * 0.5) * _Global_RimLightBrightness * combinedRimMask;
}

#ifndef S_CHAR_FORWARD_PASS

// =======================================================================
// 角色外描边 (Outline Pass)
// =======================================================================
TEXTURE2D(_OutLineMask);
SAMPLER(sampler_OutLineMask);
half4 _OutLineMask_ST;
half _OutLine;
half3 _OutLineColor;

struct SChar_OutlineAttributes
{
    float4 positionOS : POSITION;
    float2 uv : TEXCOORD0;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float4 uv7 : TEXCOORD7;
};

struct SChar_OutlineVaryings
{
    float2 uv : TEXCOORD0;
    float4 positionCS : SV_POSITION;
};

SChar_OutlineVaryings SChar_OutlineVert(SChar_OutlineAttributes v)
{
    SChar_OutlineVaryings o;

    VertexNormalInputs VNI = GetVertexNormalInputs(v.normalOS, v.tangentOS);
    float3 smoothNormalWS = VNI.tangentWS * v.uv7.x + VNI.bitangentWS * v.uv7.y + VNI.normalWS * v.uv7.z;

    // 遮罩采样
    float2 maskUV = TRANSFORM_TEX(v.uv, _OutLineMask);
    half outlineMask = SAMPLE_TEXTURE2D_LOD(_OutLineMask, sampler_OutLineMask, maskUV, 0).r;

    float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
    positionWS += smoothNormalWS * (_OutLine * 0.01 * outlineMask);

    o.positionCS = TransformWorldToHClip(positionWS);
    o.uv = TRANSFORM_TEX(v.uv, _BaseColor);
    return o;
}

half4 SChar_OutlineFrag(SChar_OutlineVaryings i) : SV_Target
{
    half4 baseColor = SAMPLE_TEXTURE2D(_BaseColor, sampler_BaseColor, i.uv);
    half alpha = baseColor.a;
    clip(alpha - _AlphaClip);

    half3 outlineColor = baseColor.rgb * _OutLineColor;
    return half4(outlineColor, 1.0);
}

// =======================================================================
// 角色阴影投射 (Shadow Caster Pass)
// =======================================================================
struct SChar_ShadowAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 uv : TEXCOORD0;
};

struct SChar_ShadowVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
};

SChar_ShadowVaryings SChar_ShadowVert(SChar_ShadowAttributes v)
{
    SChar_ShadowVaryings o;
    float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
    float3 normalWS = TransformObjectToWorldNormal(v.normalOS);

    o.uv = TRANSFORM_TEX(v.uv, _BaseColor);

    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _MainLightPosition));

#if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
#else
    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
#endif

    o.positionCS = positionCS;
    return o;
}

half4 SChar_ShadowFrag(SChar_ShadowVaryings i) : SV_Target
{
    clip(0.5 - _PerObjectShadowEnabled);

    half alpha = SAMPLE_TEXTURE2D(_BaseColor, sampler_BaseColor, i.uv).a;
    clip(alpha - _AlphaClip);
    return 0;
}

#endif // S_CHAR_FORWARD_PASS

#endif