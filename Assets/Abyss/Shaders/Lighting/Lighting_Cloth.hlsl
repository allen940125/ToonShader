#ifndef LIGHTING_CLOTH_INCLUDED
#define LIGHTING_CLOTH_INCLUDED

#include "Lighting_Utilities.hlsl"

inline half3 ComputeLighting_Cloth(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    // =============================================================
    // 1. 物理量與基底色準備 (維持不變)
    // =============================================================
    half baseRoughness = 1.0 - surface.smoothness;
    half roughness_nonMetal = saturate((saturate(baseRoughness + _RoughnessNonMetal) - 0.5) * _RoughnessContrast + 0.5);
    half roughness_metal = saturate((saturate(baseRoughness + _RoughnessMetal) - 0.5) * _RoughnessContrast + 0.5);
    half roughness = lerp(roughness_nonMetal, roughness_metal, surface.metallic);
    half smoothness = 1.0 - roughness;
    
    half3 f0 = lerp(half3(0.04, 0.04, 0.04), surface.albedo, surface.metallic);
    half3 rawDiffuse = surface.albedo * (1.0 - surface.metallic);
    half3 baseColor = saturate((rawDiffuse - 0.5) * _BaseColorContrast + 0.5);

    // =============================================================
    // 2. 統一深層陰影染色 (與 Skin/Face 同步，阻斷環境光色偏)
    // =============================================================
    // 從中央管線提取純淨亮度
    half ambientLum = Luminance(indirectDiffuse);
    half3 cleanAmbient = half3(ambientLum, ambientLum, ambientLum);
    
    // 全域陰影遮罩與染色
    float shadowAtten = lerp(1.0, castShadowMask, _GlobalShadowStrength);
    half3 globalShadowTint = lerp(_GlobalShadowColor.rgb, half3(1.0, 1.0, 1.0), shadowAtten);
    
    // 定義絕對純淨的暗部底色
    half3 diffuseDark = baseColor * cleanAmbient * globalShadowTint;

    // =============================================================
    // 3. 漫反射：NPR Ramp 邏輯 (修復雙重陰影疊加)
    // =============================================================
    float NdotL = dot(surface.normalWS, mainLight.direction);
    float halfLambert = min(NdotL * 0.5 + 0.5, castShadowMask); // 遮罩直接限制半蘭伯特
    
    half3 baseDiffuseLight = baseColor * mainLight.color;
    half3 grayDiffuse = baseDiffuseLight * halfLambert;
    half3 diffuseLight;
    
    if (_UseRampMode > 0.5)
    {
        // 取樣 Ramp
        half3 stylizedRamp = SAMPLE_TEXTURE2D(_RampMap, sampler_LinearClamp, float2(halfLambert, 0.5)).rgb;
        // Soft Light 混合
        half3 rampDiffuse = (1.0 - 2.0 * stylizedRamp) * baseDiffuseLight * baseDiffuseLight + 2.0 * stylizedRamp * baseDiffuseLight;
        diffuseLight = lerp(grayDiffuse, rampDiffuse, _RampStrength);
    }
    else
    {
        diffuseLight = grayDiffuse;
    }

    // 梯度染色
    half gradient = saturate((surface.positionOS.y - _GradientMinY) / (_GradientMaxY - _GradientMinY + 1e-5));
    diffuseLight = lerp(diffuseLight * _GradientColor.rgb, diffuseLight, gradient);
    diffuseDark = lerp(diffuseDark * _GradientColor.rgb, diffuseDark, gradient);

    // 【核心修正】：乾淨的合成，暗部自動退回 diffuseDark，絕不二次變黑
    half3 finalDiffuse = max(diffuseDark, diffuseLight);

    // =============================================================
    // 4. PBR 高光與環境反射 (壓抑布料的塑膠感)
    // =============================================================
    half3 halfDir = normalize(mainLight.direction + surface.viewDirWS);
    half NdotH = max(0, dot(surface.normalWS, halfDir));
    half VdotH = max(0, dot(surface.viewDirWS, halfDir));

    half shininess = lerp(1.0, _SpecShininess, smoothness);
    half energyConservation = (shininess + 2.0) / (8.0 * 3.1415926);
    half3 fresnelTerm = f0 + (1.0 - f0) * pow(abs(1.0 - VdotH), 5.0);
    
    // 拔除 halfLambert 破壞，高光嚴格受實體陰影遮蔽
    half specTemp = pow(NdotH, shininess) * energyConservation;
    half3 finalSpec = fresnelTerm * mainLight.color * _SpecularColor.rgb * _SpecularIntensity * specTemp * shadowAtten;

    half3 envSpec = 0;
    #if defined(_REFLECTION_ON)
        half3 reflectDir = reflect(-surface.viewDirWS, surface.normalWS);
        half envRoughness = lerp(smoothness, 1.0 - _EnvSmoothness, _EnvSmoothness);
        envRoughness = envRoughness * (1.7 - 0.7 * envRoughness); 
        half3 envReflection = GlossyEnvironmentReflection(reflectDir, surface.positionWS, envRoughness, 1.0);
        
        half NdotV = max(0, dot(surface.normalWS, surface.viewDirWS));
        half3 envFresnel = f0 + (max(smoothness.xxx, f0) - f0) * pow(abs(1.0 - NdotV), 5.0);
        envSpec = envReflection * envFresnel * _EnvSpecularColor.rgb * _EnvSpecularIntensity * surface.occlusion;
    #endif

    // =============================================================
    // 5. 高品質 NPR Cloth Rim Light (濾色混合)
    // =============================================================
    half3 finalRim = 0;
    if (_UseRimLight > 0.5)
    {
        // 1. 基底 Fresnel
        half rimNdotV = 1.0 - saturate(dot(surface.normalWS, surface.viewDirWS));
        half rimFresnel = saturate(pow(rimNdotV, _InnerRimPower));
        
        // 2. 光源方向遮罩
        float3 rimLightDir = normalize(_RimLightDirection.xyz);
        float rimNdotL = dot(surface.normalWS, rimLightDir);
        float rimDirMask = smoothstep(_RimPosOffset - _RimDirSoftness, _RimPosOffset + _RimDirSoftness, rimNdotL);
        
        // =========================================================
        // 【核心修正】：絕對陰影阻斷
        // 使用純粹的 castShadowMask，當進入實體投影區 (數值趨近 0) 時，
        // 遮罩強制歸零，徹底抹殺該區域的邊緣光。
        // =========================================================
        float rimShadowMask = smoothstep(0.01, 0.1, castShadowMask);
        
        // 計算最終 Rim 遮罩
        float finalRimMask = rimFresnel * rimDirMask * rimShadowMask * _InnerRimIntensity;
        
        // 取得邊緣光顏色並受控於主光/環境光能量
        half3 rimColor = (_InnerRimColor.rgb + baseColor) * 0.5;
        finalRim = rimColor * finalRimMask * max(mainLight.color, cleanAmbient);
    }

    // =============================================================
    // 6. 最終合成 (AO 僅壓暗漫反射，Rim 採濾色混合)
    // =============================================================
    // 合併漫反射與高光
    half3 finalColor = (finalDiffuse * surface.occlusion) + finalSpec + envSpec;
    
    // 【核心修正】：Screen 混合 Rim Light (1 - (1-Base)*(1-Rim))
    // 保證邊緣光柔和、不刺眼、不破壞原本的衣服顏色
    finalColor = 1.0 - (1.0 - saturate(finalColor)) * (1.0 - saturate(finalRim));

    return finalColor;
}

#endif