#ifndef LIGHTING_STANDARD_INCLUDED
#define LIGHTING_STANDARD_INCLUDED

#include "Lighting_Utilities.hlsl"

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
    // 原本的 ambientFilter 計算
    half3 ambientFilter = lerp(dynamicShadowTint, half3(1,1,1), finalBand) * _GlobalAmbientColor.rgb * _GlobalAmbientIntensity;

    // ── 加入這一行：全域陰影色調偏置（利用 finalBand 限制只作用在陰影區）──
    ambientFilter *= lerp(_GlobalShadowColorBias.rgb, half3(1,1,1), finalBand);

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

    half3 ambientFilter = lerp(dynamicShadowTint, half3(1, 1, 1), finalBand) * _GlobalAmbientColor.rgb * _GlobalAmbientIntensity;
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


inline half3 ComputeLighting_Standard(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    // 这里直接复制你现有的 ComputeLighting_MathOnly / Ramp 逻辑
    // 可以将 _UseRampMode 判断放在内部，或让外面传参
    // 建议在外面判断，然后调用内部函数，但为了简化，直接在这里判断：
    if (_UseRampMode > 0.5)
        return ComputeLighting_Ramp(surface, mainLight, indirectDiffuse, castShadowMask);
    else
        return ComputeLighting_MathOnly(surface, mainLight, indirectDiffuse, castShadowMask);
}

#endif