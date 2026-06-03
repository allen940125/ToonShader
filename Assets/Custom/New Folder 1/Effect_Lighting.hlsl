#ifndef EFFECT_LIGHTING_INCLUDED
#define EFFECT_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/Runtime/Lighting/ProbeVolume/ProbeVolume.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"

// ------------------------------------------------------------------
// 1. 間接漫反射 (GI / Ambient) – 你原有的 APV / SH 邏輯
// ------------------------------------------------------------------
inline half3 GetIndirectDiffuse(float3 positionWS, float3 normalWS, float3 viewDirWS)
{
    float2 screenPos = float2(0,0); // 若無螢幕空間需求可填 0
    uint renderingLayer = 0;
    float3 envLight = 0;

    #if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
    EvaluateAdaptiveProbeVolume(positionWS, normalWS, viewDirWS, screenPos, renderingLayer, envLight);
    #else
    envLight = SampleSH(normalWS);
    #endif

    envLight *= _IndirectLightMultiplier;
    return max(envLight, _MinBrightness);
}

// ------------------------------------------------------------------
// 2. 附加直接光源 – Additional Lights
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
            // 簡單的高光（可選，保留給反射處理，此處可註解掉）
            // 但若你希望附加光也有形狀高光，可在此加入
            contribution += diffuse * albedo;
        }
        contribution *= _AddLightIntensity;
    #endif
    return contribution;
}

// ------------------------------------------------------------------
// 3. 間接鏡面反射 – Reflection Probe
// ------------------------------------------------------------------
inline half3 GetIndirectSpecular(float3 positionWS, float3 normalWS, float3 viewDirWS, half3 albedo)
{
    half3 reflectionColor = 0;
    #if defined(_REFLECTION_ON)
        float3 reflectVector = reflect(-viewDirWS, normalWS);
        half perceptualRoughness = 1.0 - _Smoothness;
        // 使用 URP 內建的 GlossyEnvironmentReflection
        half3 envReflection = GlossyEnvironmentReflection(reflectVector, positionWS, perceptualRoughness, 1.0h);
        // 金屬度控制反射顏色：金屬反射帶有自身顏色，非金屬反射白色
        half3 specularColor = lerp(0.04, albedo, _Metallic);
        reflectionColor = envReflection * specularColor * _ReflectionIntensity;
    #endif
    return reflectionColor;
}

// ------------------------------------------------------------------
// 4. 自發光 – Emission
// ------------------------------------------------------------------
inline half3 GetEmission(float2 baseUV)
{
    half3 emission = 0;
    #if defined(_EMISSION_ON)
        float2 uv = baseUV * _EmissionMap_ST.xy + _EmissionMap_ST.zw;
        half4 emissionTex = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, uv);
        emission = emissionTex.rgb * _EmissionColor.rgb;
    #endif
    return emission;
}

// ------------------------------------------------------------------
// 主光照組合函式 (取代原本的 ApplyBasicLighting)
// ------------------------------------------------------------------
inline half3 ComputeFinalLighting(AbyssSurfaceData surface, Light mainLight)
{
    // ---- 直接主光 (你的階梯光) ----
    float NdotL = dot(surface.normalWS, mainLight.direction);
    float halfLambert = NdotL * 0.5 + 0.5;
    float minBand = _BandThreshold - _BandSmoothness;
    float maxBand = _BandThreshold + _BandSmoothness;
    float lightBand = smoothstep(minBand, maxBand, halfLambert);
    float shadowAtten = lerp(1.0, mainLight.shadowAttenuation, _ShadowIntensity);
    lightBand *= shadowAtten;

    // ---- 間接漫反射 ----
    half3 indirectDiffuse = GetIndirectDiffuse(surface.positionWS, surface.normalWS, surface.viewDirWS);

    // ---- 主光顏色混合 ----
    half3 litColor = surface.albedo * (mainLight.color + indirectDiffuse);
    half3 shadowColor = surface.albedo * _ShadowTint.rgb * indirectDiffuse;
    half3 mainResult = lerp(shadowColor, litColor, lightBand);

    // ---- 疊加附加光源 ----
    half3 addLight = GetAdditionalLightsContribution(surface.positionWS, surface.normalWS, surface.viewDirWS, surface.albedo);

    // ---- 疊加間接鏡面反射 ----
    half3 reflection = GetIndirectSpecular(surface.positionWS, surface.normalWS, surface.viewDirWS, surface.albedo);

    // ---- 最終組合 (不含 Emission，Emission 留在外部疊加) ----
    return mainResult + addLight + reflection;
}

#endif