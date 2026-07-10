#ifndef LIGHTING_UTILITIES_INCLUDED
#define LIGHTING_UTILITIES_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/Runtime/Lighting/ProbeVolume/ProbeVolume.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

// ------------------------------------------------------------------
// 1. 間接漫反射 (GI / Ambient)
// ------------------------------------------------------------------
inline half3 GetIndirectDiffuse(float3 positionWS, float3 normalWS, float3 viewDirWS)
{
    float2 screenPos = float2(0,0); 
    uint renderingLayer = 0;
    float3 envLight = 0;

    #if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
    EvaluateAdaptiveProbeVolume(positionWS, normalWS, viewDirWS, screenPos, renderingLayer, envLight);
    #else
    envLight = SampleSH(normalWS);
    #endif

    envLight *= _IndirectLightMultiplier;
    return max(envLight, _GlobalMinBrightness);
}

// ------------------------------------------------------------------
// 2. 附加直接光源 (Additional Lights)
// ------------------------------------------------------------------
inline half3 GetAdditionalLightsContribution(float3 positionWS, float3 normalWS, float3 viewDirWS, half3 albedo)
{
    half3 contribution = 0;
    #if defined(_ADD_LIGHT_ON)
        uint pixelLightCount = GetAdditionalLightsCount();
        for (uint i = 0; i < pixelLightCount; ++i)
        {
            Light addLight = GetAdditionalLight(i, positionWS);
            float3 L = addLight.direction;
            float NdotL = saturate(dot(normalWS, L));
            half3 diffuse = addLight.color * addLight.distanceAttenuation * NdotL;
            contribution += diffuse * albedo;
        }
        contribution *= _AddLightIntensity;
    #endif
    return contribution;
}

// ------------------------------------------------------------------
// 3. 間接鏡面反射 (Reflection Probe)
// ------------------------------------------------------------------
inline half3 GetIndirectSpecular(AbyssSurfaceData surface) 
{
    half3 reflectionColor = 0;
    #if defined(_REFLECTION_ON)
    float3 reflectVector = reflect(-surface.viewDirWS, surface.normalWS);
    half perceptualRoughness = 1.0 - surface.smoothness;
    half3 envReflection = GlossyEnvironmentReflection(reflectVector, surface.positionWS, perceptualRoughness, 1.0h);
    half3 specularColor = lerp(0.04, surface.albedo, surface.metallic);
        
    reflectionColor = envReflection * specularColor * _ReflectionIntensity;
    #endif
    return reflectionColor;
}

// ------------------------------------------------------------------
// 4. 自發光 (Emission)
// ------------------------------------------------------------------
inline half3 GetEmission(float2 baseUV)
{
    float2 uv = baseUV * _EmissionMap_ST.xy + _EmissionMap_ST.zw;
    half4 emissionTex = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, uv);
    return emissionTex.rgb * _EmissionColor.rgb;
}

// ------------------------------------------------------------------
// 5. 卡通邊緣光 (Depth Offset Rim 深度偏移升級版)
// ------------------------------------------------------------------
inline void CalculateAnimeRimLight(AbyssSurfaceData surface, Light mainLight, float castShadowMask, out half3 inner_rim, out half3 final_rim)
{
    inner_rim = 0;
    final_rim = 0;

    if (_UseRimLight < 0.5) return;

    // ==========================================
    // 技巧 1：方向與 X 軸遮罩 (強制單側受光)
    // ==========================================
    // 對象空間 X 軸遮罩 (控制大範圍的左暗右亮)
    float rimPosMask = smoothstep(_RimPosOffset - _RimDirSoftness, _RimPosOffset + _RimDirSoftness, -surface.positionOS.x);

    // 世界空間方向遮罩 (控制受光面細節)
    float3 rimLightDir = normalize(_RimLightDirection.xyz);
    float rimNdotL = dot(surface.normalWS, rimLightDir);
    float rimDirMask = smoothstep(_RimPosOffset - _RimDirSoftness, _RimPosOffset + _RimDirSoftness, rimNdotL);

    float combinedRimMask = rimPosMask * rimDirMask;

    // 暴力切斷處於真正陰影中的 Rim
    float shadowMask = step(0.5, castShadowMask);

    // ==========================================
    // 技巧 2：粉彩混色邏輯 (Rim Color + Albedo 取平均)
    // ==========================================
    half3 innerBlendColor = (_InnerRimColor.rgb + surface.albedo) * 0.5;
    half3 finalBlendColor = (_RimColor.rgb + surface.albedo) * 0.5;

    // ==========================================
    // 技巧 3：雙層邊緣光分離
    // ==========================================
    
    // 【內側軟邊緣光 (Inner Rim - Fresnel)】
    if (_UseInnerRim > 0.5)
    {
        half NdotV = saturate(dot(surface.normalWS, surface.viewDirWS));
        half fresnel = saturate(_InnerRimBias + pow(abs(1.0 - NdotV), _InnerRimPower));
        half innerRimMask = saturate(fresnel * shadowMask * _InnerRimIntensity);
        
        inner_rim = innerRimMask * innerBlendColor * combinedRimMask;
    }

    // 【外側硬輪廓光 (Final Rim - Depth Offset)】
    // 即時計算觀察與螢幕空間座標
    float4 positionCS = TransformWorldToHClip(surface.positionWS);
    float4 positionNDC = ComputeScreenPos(positionCS);
    float3 positionVS = TransformWorldToView(surface.positionWS);
    float3 normalVS = TransformWorldToViewDir(surface.normalWS, true);

    // 沿著法線往外推擠取樣點
    float3 samplePositionVS = float3(positionVS.xy + normalVS.xy * _RimOffsetMul, positionVS.z);
    float4 samplePositionCS = mul(UNITY_MATRIX_P, float4(samplePositionVS, 1.0));
    float4 samplePositionVP = ComputeScreenPos(samplePositionCS);
    float2 sampleUV = samplePositionVP.xy / samplePositionVP.w;

    // 比對深度差
    float linearEyeDepth = LinearEyeDepth(positionNDC.z / positionNDC.w, _ZBufferParams);
    float offsetDepth = SampleSceneDepth(sampleUV); 
    float linearEyeOffsetDepth = LinearEyeDepth(offsetDepth, _ZBufferParams);
    float depthDiff = linearEyeOffsetDepth - linearEyeDepth;

    // 產生最終硬輪廓
    float DOR_mask = smoothstep(_RimThreshold - _RimSmoothness, _RimThreshold + _RimSmoothness, depthDiff);
    float finalRimMask = saturate(DOR_mask * shadowMask * _RimIntensity);
    
    final_rim = finalRimMask * finalBlendColor * combinedRimMask;
}

// ------------------------------------------------------------------
// 6. 高光計算（基礎 + 水膜）
// ------------------------------------------------------------------
inline half3 ComputeSpecular(AbyssSurfaceData surface, Light mainLight, float castShadowMask)
{
    float3 halfVector = normalize(mainLight.direction + surface.viewDirWS);
    float NdotH = saturate(dot(surface.normalWS, halfVector));
    float NdotL_spec = dot(surface.normalWS, mainLight.direction);
    float selfShadowMask = smoothstep(0.0, 0.1, NdotL_spec);

    float dynamicSpecStep = lerp(1.0, _SpecularStep, surface.smoothness);
    float dynamicSpecIntensity = _SpecularIntensity * surface.smoothness;
    float baseSpecBand = smoothstep(dynamicSpecStep - _SpecularFeather, dynamicSpecStep + _SpecularFeather, NdotH);
    half3 baseSpecular = baseSpecBand * _SpecularColor.rgb * dynamicSpecIntensity;

    half3 wetSpecular = 0;
    #if defined(_WEATHER_WETNESS_ON)
    float baseWetFactor = saturate(_GlobalRainIntensity * _LocalWetness);
    if (baseWetFactor > 0.001)
    {
        float rainDot = dot(surface.normalWS, -_GlobalRainDirection);
        half upwardFactor = smoothstep(_WetDirThreshold - _WetDirContrast, _WetDirThreshold + _WetDirContrast, rainDot);
        float actualWetness = baseWetFactor * upwardFactor;
        float wetSpecBand = smoothstep(0.98 - 0.005, 0.98 + 0.005, NdotH);
        wetSpecular = wetSpecBand * actualWetness * _WetSpecularIntensity;
    }
    #endif

    return (baseSpecular + wetSpecular) * mainLight.color * selfShadowMask * castShadowMask;
}

#endif