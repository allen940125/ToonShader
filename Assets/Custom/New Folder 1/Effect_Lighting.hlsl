#ifndef EFFECT_LIGHTING_INCLUDED
#define EFFECT_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/Runtime/Lighting/ProbeVolume/ProbeVolume.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"

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
        float shadowFactor = lerp(1.0, attenuation, _ReceiveShadowIntensity);
        
        // 4. 總遮罩合併：實時陰影 * 向光面遮罩
        float totalMask = shadowFactor * litSideMask;
        float rimMask = lerp(1.0, totalMask, _RimShadowMask);
        
        // 5. 疊加主光能量
        finalRim = rimBand * _RimColor.rgb * rimMask * surface.albedo * mainLight.color;
    }
    return finalRim;
}

// ---------------------------------------------------------------
// 純數學模式（無 Ramp） - 接收全域陰影遮罩
// ---------------------------------------------------------------
inline half3 ComputeLighting_MathOnly(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    float NdotL = dot(surface.normalWS, mainLight.direction);
    float halfLambert = NdotL * 0.5 + 0.5;

    float mathBand;

    if (_BandSmoothness <= 0.001)
    {
        float delta = fwidth(halfLambert); 
        mathBand = smoothstep(_BandThreshold - delta, _BandThreshold + delta, halfLambert);
    }
    else
    {
        float safeSmoothness = max(_BandSmoothness, 0.001);
        mathBand = smoothstep(_BandThreshold - safeSmoothness, _BandThreshold + safeSmoothness, halfLambert);
    }
    
    float mainLightPower = saturate(max(mainLight.color.r, max(mainLight.color.g, mainLight.color.b)));
    float lightWeight = saturate(mainLightPower * 10.0); 
    
    // 【直接套用傳入的外部陰影遮罩】
    float finalBand = mathBand * castShadowMask * lightWeight;

    half3 dynamicShadowTint = lerp(half3(1, 1, 1), _ShadowTint.rgb, mainLightPower);
    half3 ambientFilter = lerp(dynamicShadowTint, half3(1, 1, 1), finalBand) * _AmbientColor.rgb * _AmbientIntensity;
    half3 ambientColor = indirectDiffuse * ambientFilter;
    
    // 原本的計算
    half3 directColor = mainLight.color * mainLight.distanceAttenuation * finalBand;

    // ==========================================
    // 【核心新增】：模擬物理反彈光 (Bounce Light)
    // ==========================================
    // 1. 取得與主光相反的方向，模擬打到地面後反彈向上的光線
    float bounceLambert = saturate(dot(surface.normalWS, -mainLight.direction)) * 0.5 + 0.5;
    
    // 2. 反彈遮罩：反彈光只在「主光照不到的陰影區」才具有強烈可見性
    float bounceMask = (1.0 - finalBand); 
    
    // 3. 假設新增一個 _BounceColor (反彈光顏色，通常設為暖棕色或地表顏色) 與 _BounceIntensity
    // 如果不想加新變數，可以直接借用環境光或寫死一個柔和的數值
    half3 bounceLight = bounceLambert * bounceMask * indirectDiffuse * _BounceIntensity * _BounceColor.rgb;
    // 4. 將反彈光加入總能量
    half3 totalLighting = ambientColor + directColor + bounceLight;

    totalLighting = lerp(half3(1, 1, 1), totalLighting, _DiffuseImpact);
    totalLighting = min(totalLighting, _MaxHighlightEnergy);

    half3 finalDiffuse = surface.albedo * totalLighting;

    float borderBand = smoothstep(_BorderThreshold - _BorderWidth, _BorderThreshold, halfLambert) 
                     - smoothstep(_BorderThreshold, _BorderThreshold + _BorderWidth, halfLambert);
    finalDiffuse += _BorderColor.rgb * borderBand * surface.albedo * finalBand * _BorderIntensity * mainLight.color;

    return finalDiffuse;
}

// ---------------------------------------------------------------
// Ramp 貼圖模式 - 接收全域陰影遮罩
// ---------------------------------------------------------------
inline half3 ComputeLighting_Ramp(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    float NdotL = dot(surface.normalWS, mainLight.direction);
    float halfLambert = NdotL * 0.5 + 0.5;
    
    float minBand = _BandThreshold - _BandSmoothness;
    float maxBand = _BandThreshold + _BandSmoothness;
    float mathBand = smoothstep(minBand, maxBand, halfLambert);
    
    float mainLightPower = saturate(max(mainLight.color.r, max(mainLight.color.g, mainLight.color.b)));
    float lightWeight = saturate(mainLightPower * 10.0);
    
    // 【直接套用傳入的外部陰影遮罩】
    float finalBand = mathBand * castShadowMask * lightWeight;

    half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_BaseMap, float2(finalBand, 0.5)).rgb;

    half3 baseShadowTint = lerp(half3(1,1,1), _RampColorShadow.rgb, _RampShadowIntensity);
    half3 dynamicShadowTint = lerp(half3(1, 1, 1), baseShadowTint, mainLightPower);
    
    half3 lightTint = lerp(half3(1,1,1), _RampColorLight.rgb, _RampLightIntensity);

    half3 ambientFilter = lerp(dynamicShadowTint, half3(1, 1, 1), finalBand) * _AmbientColor.rgb * _AmbientIntensity;
    half3 ambientColor = indirectDiffuse * ambientFilter;
    
    half3 directColor = mainLight.color * mainLight.distanceAttenuation * rampColor * lightTint * finalBand;

    half3 totalLighting = ambientColor + directColor;
    totalLighting = lerp(half3(1, 1, 1), totalLighting, _DiffuseImpact);
    totalLighting = min(totalLighting, _MaxHighlightEnergy);

    half3 finalDiffuse = surface.albedo * totalLighting;

    float borderBand = smoothstep(_BorderThreshold - _BorderWidth, _BorderThreshold, halfLambert) 
                     - smoothstep(_BorderThreshold, _BorderThreshold + _BorderWidth, halfLambert);
    finalDiffuse += _BorderColor.rgb * borderBand * surface.albedo * finalBand * _BorderIntensity * mainLight.color;

    return saturate(finalDiffuse);
}

// ---------------------------------------------------------------
// 主光照組合函式
// ---------------------------------------------------------------
inline half3 ComputeFinalLighting(AbyssSurfaceData surface, Light mainLight, half occlusion)
{
    // 1. 主光色彩攔截
    mainLight.color *= _MainLightMultiplier;
    float lightIntensity = max(mainLight.color.r, max(mainLight.color.g, mainLight.color.b));
    half3 neutralLight = half3(lightIntensity, lightIntensity, lightIntensity);
    mainLight.color = lerp(neutralLight, mainLight.color, _MainLightColorWeight);

    // ==========================================
    // 【核心修正】：全域實時陰影遮罩 (帶有平滑度控制)
    // ==========================================
    float rawShadow = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
    
    // 1. 給予安全下限，防止 Smoothness 為 0 時發生除以零的數學崩潰
    float shadowSmooth = max(_ShadowSmoothness, 0.001);
    
    // 2. 以 0.5 (陰影半衰點) 為中心，向左右推展平滑範圍
    float minShadowEdge = 0.5 - shadowSmooth;
    float maxShadowEdge = 0.5 + shadowSmooth;
    
    // 3. 算出帶有可控柔邊的陰影遮罩
    float smoothShadowMask = smoothstep(minShadowEdge, maxShadowEdge, rawShadow);
    
    // 4. 套用面板接收強度權重
    float castShadowMask = lerp(1.0, smoothShadowMask, _ReceiveShadowIntensity);

    // 3. 間接漫反射 (GI)
    half3 indirectDiffuse = GetIndirectDiffuse(surface.positionWS, surface.normalWS, surface.viewDirWS);
    indirectDiffuse *= occlusion;
    
    // 4. 漫反射 (強制將 castShadowMask 作為參數傳入)
    half3 diffuse = (_UseRampMode > 0.5) ? 
        ComputeLighting_Ramp(surface, mainLight, indirectDiffuse, castShadowMask) : 
        ComputeLighting_MathOnly(surface, mainLight, indirectDiffuse, castShadowMask);

    // 5. 高光 (Specular)
    half3 finalSpecular = 0;
    if (_SpecularIntensity > 0.001) 
    {
        float3 halfVector = normalize(mainLight.direction + surface.viewDirWS);
        float NdotH = saturate(dot(surface.normalWS, halfVector));
        float specBand = smoothstep(_SpecularStep - _SpecularFeather, _SpecularStep + _SpecularFeather, NdotH);
        
        float NdotL_spec = dot(surface.normalWS, mainLight.direction);
        float selfShadowMask = smoothstep(0.0, 0.1, NdotL_spec); 
        
        finalSpecular = specBand * _SpecularColor.rgb * _SpecularIntensity * mainLight.color * selfShadowMask * castShadowMask;
    }

    // 6. 卡通邊緣光 (Rim Light)
    half3 rimLight = 0;
    if (_UseRimLight > 0.5) 
    {
        float NdotV = saturate(dot(surface.normalWS, surface.viewDirWS));
        float fresnel = pow(1.0 - NdotV, _RimPower);
        float rimBand = smoothstep(_RimThreshold - _RimSmoothness, _RimThreshold + _RimSmoothness, fresnel);
        
        float NdotL_rim = dot(surface.normalWS, mainLight.direction);
        float litSideMask = smoothstep(_BandThreshold - _BandSmoothness, _BandThreshold + _BandSmoothness, NdotL_rim * 0.5 + 0.5);
        
        float rimMask = lerp(1.0, litSideMask * castShadowMask, _RimShadowMask);
        rimLight = rimBand * _RimColor.rgb * rimMask * surface.albedo * mainLight.color;
    }

    // 7. 附加光源與反射
    half3 addLight = GetAdditionalLightsContribution(surface.positionWS, surface.normalWS, surface.viewDirWS, surface.albedo);
    half3 reflection = GetIndirectSpecular(surface.positionWS, surface.normalWS, surface.viewDirWS, surface.albedo);

    return diffuse + finalSpecular + rimLight + addLight + reflection;
}

#endif