#ifndef EFFECT_LIGHTING_INCLUDED
#define EFFECT_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/Runtime/Lighting/ProbeVolume/ProbeVolume.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"

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
    return max(envLight, _MinBrightness);
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
inline half3 GetIndirectSpecular(float3 positionWS, float3 normalWS, float3 viewDirWS, half3 albedo)
{
    half3 reflectionColor = 0;
    #if defined(_REFLECTION_ON)
        float3 reflectVector = reflect(-viewDirWS, normalWS);
        half perceptualRoughness = 1.0 - _Smoothness;
        half3 envReflection = GlossyEnvironmentReflection(reflectVector, positionWS, perceptualRoughness, 1.0h);
        half3 specularColor = lerp(0.04, albedo, _Metallic);
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
// 5. 卡通邊緣光 (Stylized Rim Light) - 修正背光溢光
// ------------------------------------------------------------------
inline half3 GetStylizedRimLight(AbyssSurfaceData surface, Light mainLight)
{
    half3 finalRim = 0;
    
    // 提早攔截：對應 ToggleUI 的靜態分支
    if (_UseRimLight > 0.5) 
    {
        // 1. 基礎菲涅耳邊緣抓取 (只看視角)
        float NdotV = saturate(dot(surface.normalWS, surface.viewDirWS));
        float fresnel = pow(1.0 - NdotV, _RimPower);
        float rimBand = smoothstep(_RimThreshold - _RimSmoothness, _RimThreshold + _RimSmoothness, fresnel);
        
        // 2. 【核心修正】：向光面遮罩 (Lit Side Mask)
        // 計算光源角度，並使用與主光影相同的 Threshold，確保 Rim Light 絕對不越界進入暗部
        float NdotL = dot(surface.normalWS, mainLight.direction);
        float halfLambert = NdotL * 0.5 + 0.5;
        float litSideMask = smoothstep(_BandThreshold - _BandSmoothness, _BandThreshold + _BandSmoothness, halfLambert);
        
        // 3. 實時陰影遮罩 (處理樹木、建築投射的陰影)
        float attenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
        float shadowFactor = lerp(1.0, attenuation, _ShadowIntensity);
        
        // 4. 總遮罩合併：實時陰影 * 向光面遮罩
        float totalMask = shadowFactor * litSideMask;
        float rimMask = lerp(1.0, totalMask, _RimShadowMask);
        
        // 5. 疊加主光能量
        finalRim = rimBand * _RimColor.rgb * rimMask * surface.albedo * mainLight.color;
    }
    return finalRim;
}

// ---------------------------------------------------------------
// 純數學模式（無 Ramp）
// ---------------------------------------------------------------
inline half3 ComputeLighting_MathOnly(
    AbyssSurfaceData surface,
    Light mainLight,
    half3 indirectDiffuse)
    {
        float NdotL =
            dot(surface.normalWS, mainLight.direction);

        float halfLambert =
            NdotL * 0.5 + 0.5;

        float attenuation =
            mainLight.distanceAttenuation *
            mainLight.shadowAttenuation;

        float shadowFactor =
            lerp(1.0, attenuation, _ShadowIntensity);

        float mathBand =
            smoothstep(
                _BandThreshold - _BandSmoothness,
                _BandThreshold + _BandSmoothness,
                halfLambert);

        float finalBand =
            mathBand * shadowFactor;

        half3 ambientColor =
            indirectDiffuse *
            lerp(_ShadowTint.rgb,
                 half3(1,1,1),
                 finalBand);

        half3 directColor =
            surface.albedo *
            mainLight.color *
            finalBand;

        half3 finalDiffuse =
            surface.albedo * ambientColor +
            directColor;

        return finalDiffuse;
    }

// ---------------------------------------------------------------
// Ramp 貼圖模式
// ---------------------------------------------------------------
inline half3 ComputeLighting_Ramp(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse)
{
    float NdotL = dot(surface.normalWS, mainLight.direction);
    float halfLambert = NdotL * 0.5 + 0.5;
    
    float attenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
    float shadowFactor = lerp(1.0, attenuation, _ShadowIntensity);

    float minBand = _BandThreshold - _BandSmoothness;
    float maxBand = _BandThreshold + _BandSmoothness;
    float mathBand = smoothstep(minBand, maxBand, halfLambert);
    
    float lightWeight = saturate(length(mainLight.color) * 10.0);
    float finalBand = mathBand * shadowFactor * lightWeight;

    half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_BaseMap, float2(finalBand, 0.5)).rgb;

    half3 shadowTint = lerp(half3(1,1,1), _RampColorShadow.rgb, _RampShadowIntensity);
    half3 lightTint = lerp(half3(1,1,1), _RampColorLight.rgb, _RampLightIntensity);

    half3 ambientColor = indirectDiffuse * lerp(shadowTint, half3(1, 1, 1), finalBand);
    half3 directColor = mainLight.color * mainLight.distanceAttenuation * rampColor * lightTint * finalBand;

    half3 finalDiffuse = surface.albedo * (ambientColor + directColor);

    float borderBand = smoothstep(_BorderThreshold - _BorderWidth, _BorderThreshold, halfLambert) 
                     - smoothstep(_BorderThreshold, _BorderThreshold + _BorderWidth, halfLambert);
    finalDiffuse += _BorderColor.rgb * borderBand * surface.albedo * finalBand * _BorderIntensity * mainLight.color;

    finalDiffuse += surface.albedo * indirectDiffuse * _AmbientColor.rgb * _AmbientIntensity;

    return saturate(finalDiffuse);
}

// ---------------------------------------------------------------
// 主光照組合函式
// ---------------------------------------------------------------
inline half3 ComputeFinalLighting(AbyssSurfaceData surface, Light mainLight)
{
    // ==========================================
    // 【核心修正】：主光色彩攔截與清洗 (Decouple Tint and Intensity)
    // ==========================================
    // 1. 萃取出主光源的純粹亮度 (取 RGB 中最大值作為粗略能量)
    float lightIntensity = max(mainLight.color.r, max(mainLight.color.g, mainLight.color.b));
    
    // 2. 製作一盞只有亮度、沒有顏色的「中性光」
    half3 neutralLight = half3(lightIntensity, lightIntensity, lightIntensity);
    
    // 3. 根據滑桿，決定要保留多少場景的染色，並覆蓋原本的 mainLight
    mainLight.color = lerp(neutralLight, mainLight.color, _MainLightColorWeight);

    // ==========================================

    // 1. 間接漫反射
    half3 indirectDiffuse = GetIndirectDiffuse(surface.positionWS, surface.normalWS, surface.viewDirWS);

    // 2. 漫反射切換 (靜態分支)
    half3 diffuse = (_UseRampMode > 0.5) ? 
        ComputeLighting_Ramp(surface, mainLight, indirectDiffuse) : 
        ComputeLighting_MathOnly(surface, mainLight, indirectDiffuse);

    // 3. 高光 (利用 Intensity 進行靜態分支提早攔截)
    half3 finalSpecular = 0;
    
    // 只要強度大於 0.001 才執行昂貴的 normalize 與 smoothstep
    if (_SpecularIntensity > 0.001) 
    {
        float3 viewDir = surface.viewDirWS;
        float3 halfVector = normalize(mainLight.direction + viewDir);
        float NdotH = saturate(dot(surface.normalWS, halfVector));
        float specBand = smoothstep(_SpecularStep - _SpecularFeather, _SpecularStep + _SpecularFeather, NdotH);
        
        // 疊加顏色與強度
        finalSpecular = specBand * _SpecularColor.rgb * _SpecularIntensity * mainLight.color * mainLight.distanceAttenuation * mainLight.shadowAttenuation;
    }

    // 4. 卡通邊緣光 (呼叫新增的模組)
    half3 rimLight = GetStylizedRimLight(surface, mainLight);

    // 5. 附加光源與反射
    half3 addLight = GetAdditionalLightsContribution(surface.positionWS, surface.normalWS, surface.viewDirWS, surface.albedo);
    half3 reflection = GetIndirectSpecular(surface.positionWS, surface.normalWS, surface.viewDirWS, surface.albedo);

    // 6. 最終合成
    return diffuse + finalSpecular + rimLight + addLight + reflection;
}

#endif