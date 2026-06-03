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
    float2 uv = baseUV * _EmissionMap_ST.xy + _EmissionMap_ST.zw;
    half4 emissionTex = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, uv);
    return emissionTex.rgb * _EmissionColor.rgb;
}

// ------------------------------------------------------------------
// 主光照組合函式 (取代原本的 ApplyBasicLighting)
// ------------------------------------------------------------------
inline half3 ComputeFinalLighting(AbyssSurfaceData surface, Light mainLight)
{
    // ---- 1. PBR 物理衰減提取 ----
    float physicalAtten = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
    
    // ---- 2. 幾何角度 (只看模型表面與光線的純粹角度) ----
    float NdotL = dot(surface.normalWS, mainLight.direction);
    float halfLambert = NdotL * 0.5 + 0.5;

    half3 finalDiffuse = 0;

    // 【核心修正】：Ramp 採樣的 UV 絕對只吃 halfLambert，不准乘上 physicalAtten
    half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_BaseMap, float2(halfLambert, 0.5)).rgb;

    // 檢查是否為無貼圖的純白預設狀態
    if (rampColor.r > 0.99 && rampColor.g > 0.99 && rampColor.b > 0.99)
    {
        // ---- 軌道 A：Fallback 數學卡通渲染 (修正版) ----
        float minBand = _BandThreshold - _BandSmoothness;
        float maxBand = _BandThreshold + _BandSmoothness;
        float mathBand = smoothstep(minBand, maxBand, halfLambert);
        
        float shadowFactor = lerp(1.0, mainLight.shadowAttenuation, _ShadowIntensity);
        mathBand *= shadowFactor;

        // 【修正 1】：統一亮暗部的基礎光源能量，讓暗部不再與主光斷聯
        half3 litColor = surface.albedo * mainLight.color;
        half3 shadowColor = surface.albedo * _ShadowTint.rgb * mainLight.color;
        
        finalDiffuse = lerp(shadowColor, litColor, mathBand);

        // 【修正 2】：環境光必須是全局補償，疊加在最後，確保任何角度都有基礎可見度
        half3 indirectDiffuse = GetIndirectDiffuse(surface.positionWS, surface.normalWS, surface.viewDirWS);
        finalDiffuse += surface.albedo * indirectDiffuse * _MinBrightness; 
    }
    else
    {
        // ---- 軌道 B：高階 Ramp 貼圖 + 數學 Border 渲染 (日夜交替升級版) ----
        
        // 1. 取得全局環境光 (GI) - 這是感受日夜變化的「感測器」
        half3 indirectDiffuse = GetIndirectDiffuse(surface.positionWS, surface.normalWS, surface.viewDirWS);

        // 2. 亮部：只受太陽/月亮 (主光) 影響
        half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_BaseMap, float2(halfLambert, 0.5)).rgb;
        half3 litColor = surface.albedo * rampColor * _RampColorLight.rgb * mainLight.color;

        // 【核心大改】3. 暗部：捨棄主光，改由 GI 接管
        half3 shadowRampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_BaseMap, float2(0.01, 0.5)).rgb;
        // 注意看！這裡乘的是 indirectDiffuse！
        // 這樣白天陰影會有天空的藍色，晚上 GI 變暗，陰影就會自然融入黑夜
        half3 shadowColor = surface.albedo * shadowRampColor * _RampColorShadow.rgb * indirectDiffuse;

        // 4. 物理陰影切換
        finalDiffuse = lerp(shadowColor, litColor, physicalAtten);

        // 5. 交界線 (同樣受物理衰減與主光影響)
        float borderBand = smoothstep(_BorderThreshold - _BorderWidth, _BorderThreshold, halfLambert) 
                         - smoothstep(_BorderThreshold, _BorderThreshold + _BorderWidth, halfLambert);
        finalDiffuse = saturate(finalDiffuse + (_BorderColor.rgb * borderBand * surface.albedo * physicalAtten));

        // 6. 全局環境補光 (讓 _AmbientColor 變成 GI 的染色濾鏡)
        // 晚上 indirectDiffuse 為 0 時，這裡也會歸零，不會產生突兀的發光
        finalDiffuse += surface.albedo * indirectDiffuse * _AmbientColor.rgb;
    }

    // ---- 3. NPR 高光 ----
    half3 finalSpecular = 0;
    #if defined(_USE_SPECULAR)
        float3 viewDir = surface.viewDirWS;
        float3 halfVector = normalize(mainLight.direction + viewDir);
        float NdotH = saturate(dot(surface.normalWS, halfVector));
        
        float specBand = smoothstep(_SpecularStep - _SpecularFeather, _SpecularStep + _SpecularFeather, NdotH);
        finalSpecular = specBand * _SpecularColor.rgb * mainLight.color * physicalAtten;
    #endif

    // ---- 4. 附加光源與環境反射 ----
    half3 addLight = GetAdditionalLightsContribution(surface.positionWS, surface.normalWS, surface.viewDirWS, surface.albedo);
    half3 reflection = GetIndirectSpecular(surface.positionWS, surface.normalWS, surface.viewDirWS, surface.albedo);

    return finalDiffuse + finalSpecular + addLight + reflection;
}

#endif