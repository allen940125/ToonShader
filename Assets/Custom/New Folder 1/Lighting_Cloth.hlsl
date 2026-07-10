#ifndef LIGHTING_CLOTH_INCLUDED
#define LIGHTING_CLOTH_INCLUDED

#include "Lighting_Utilities.hlsl"

inline half3 ComputeLighting_Cloth(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    // =============================================================
    // 1. PBR 物理量準備階段 (能量守恆與材質屬性定義)
    // =============================================================
    // 粗糙度轉換 (Smoothness -> Perceptual Roughness -> Roughness)
    // 1. 从表面平滑度转基础粗糙度
    half baseRoughness = 1.0 - surface.smoothness;

    // 2. 区分金属与非金属粗糙度
    half roughness_nonMetal = saturate(baseRoughness + _RoughnessNonMetal);
    roughness_nonMetal = saturate((roughness_nonMetal - 0.5) * _RoughnessContrast + 0.5);
    half roughness_metal = saturate(baseRoughness + _RoughnessMetal);
    roughness_metal = saturate((roughness_metal - 0.5) * _RoughnessContrast + 0.5);
    half roughness = lerp(roughness_nonMetal, roughness_metal, surface.metallic);
    half perceptualRoughness = roughness;
    half smoothness = 1.0 - roughness;
    
    // 基礎反射率 (F0)：非金屬為 4%，金屬為物體原色
    half3 f0 = lerp(half3(0.04, 0.04, 0.04), surface.albedo, surface.metallic);

    // 漫反射基礎色 (去金屬化)：金屬不產生內部漫反射散射
    half3 rawDiffuse = surface.albedo * (1.0 - surface.metallic);
    half3 baseColor = saturate((rawDiffuse - 0.5) * _BaseColorContrast + 0.5);

    // =============================================================
    // 2. 主光方向、半蘭伯特與陰影遮罩
    // =============================================================
    float NdotL = dot(surface.normalWS, mainLight.direction);
    float halfLambert = NdotL * 0.5 + 0.5;

    float shadowAtten = lerp(1.0, castShadowMask, _GlobalShadowStrength);
    half3 shadowColored = lerp(_GlobalShadowColor.rgb, half3(1.0, 1.0, 1.0), shadowAtten);

    // =============================================================
    // 3. 漫反射：純色 vs Ramp 貼圖
    // =============================================================
    half3 grayDiffuse = baseColor * mainLight.color * halfLambert * castShadowMask;
    half3 baseDiffuse;
    
    if (_UseRampMode > 0.5)
    {
        // 【技巧 1：讓陰影改變 Ramp 的 UV 取樣】
        // 這一行非常關鍵！我們把 castShadowMask 考慮進去。
        // 如果這個像素被其他物件的陰影遮住 (castShadowMask 接近 0)，
        // 強制讓它去取樣 Ramp 貼圖最左邊的暗部顏色，避免「身在陰影中卻亮著光」的破綻。
        float rampUV = min(halfLambert, castShadowMask);
        half3 stylizedRamp = SAMPLE_TEXTURE2D(_RampMap, sampler_BaseMap, float2(rampUV, 0.5)).rgb;

        // 準備被混合的底色 (包含主光顏色)
        half3 blendBase = baseColor * mainLight.color;

        // 【技巧 2：Photoshop 柔光混合公式 (Soft Light)】
        // 讓底色與 Ramp 色階完美融合，提亮不瞎眼，加深不死黑
        half3 rampDiffuse = (1.0 - 2.0 * stylizedRamp) * blendBase * blendBase + 2.0 * stylizedRamp * blendBase;

        // 透過 RampStrength 參數控制卡通強弱
        baseDiffuse = lerp(grayDiffuse, rampDiffuse * castShadowMask, _RampStrength);
    }
    else
    {
        baseDiffuse = grayDiffuse;
    }

    // 梯度漸變染色 (基於物件空間 Y 軸)
    half gradient = saturate((surface.positionOS.y - _GradientMinY) / (_GradientMaxY - _GradientMinY + 1e-5));
    half3 diffGradient = lerp(baseDiffuse * _GradientColor.rgb, baseDiffuse, gradient);
    
    // 最終漫反射
    half3 finalDiffuse = diffGradient * shadowColored;

    // =============================================================
    // 4. 直接高光 (Blinn-Phong + Fresnel 能量守恆)
    // =============================================================
    half3 halfDir = normalize(mainLight.direction + surface.viewDirWS);
    half NdotH = max(0, dot(surface.normalWS, halfDir));
    half VdotH = max(0, dot(surface.viewDirWS, halfDir));

    // 保留你的 UI 參數控制邏輯，但與平滑度貼圖聯動
    half shininess = lerp(1.0, _SpecShininess, smoothness);
    half energyConservation = (shininess + 2.0) / (8.0 * 3.1415926);
    
    // Fresnel 效應 (Schlick 近似)
    half3 fresnelTerm = f0 + (1.0 - f0) * pow(abs(1.0 - VdotH), 5.0);
    
    half specTemp = pow(NdotH, shininess) * energyConservation;
    half3 finalSpec = fresnelTerm * mainLight.color * _SpecularColor.rgb * _SpecularIntensity * specTemp * castShadowMask * halfLambert;

    // =============================================================
    // 5. 間接光 (GI 漫反射 & 環境鏡面反射)
    // =============================================================
    half3 ambient = indirectDiffuse * baseColor;
    half3 envSpec = 0;
    
    #if defined(_REFLECTION_ON)
        half3 reflectDir = reflect(-surface.viewDirWS, surface.normalWS);
        // 环境粗糙度独立计算
        half envRoughness = lerp(smoothness, 1.0 - _EnvSmoothness, _EnvSmoothness);
        envRoughness = envRoughness * (1.7 - 0.7 * envRoughness); // 参考的映射公式
        half3 envReflection = GlossyEnvironmentReflection(reflectDir, surface.positionWS, envRoughness, 1.0);
        
        // 环境 Fresnel（考虑粗糙度）
        half NdotV = max(0, dot(surface.normalWS, surface.viewDirWS));
        half3 envFresnel = f0 + (max(smoothness.xxx, f0) - f0) * pow(abs(1.0 - NdotV), 5.0);
        envSpec = envReflection * envFresnel * _EnvSpecularColor.rgb * _EnvSpecularIntensity;
    #endif

    // =============================================================
    // 6. AO 應用與合併輸出
    // =============================================================
    // AO 影響間接光 (環境反射與漫反射)，通常不該壓暗直接高光
    // 呼叫終極邊緣光函數
    half3 inner_rim, final_rim;
    CalculateAnimeRimLight(surface, mainLight, castShadowMask, inner_rim, final_rim);

    // 衣服：兩層 Rim 全都要！
    half3 finalColor = finalDiffuse + finalSpec + ((ambient + envSpec) * surface.occlusion);
    finalColor += inner_rim + final_rim;

    return finalColor;
}

#endif