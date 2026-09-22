#ifndef LIGHTING_SKIN_INCLUDED
#define LIGHTING_SKIN_INCLUDED

#include "Lighting_Utilities.hlsl"

inline half3 ComputeLighting_Skin(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    half3 normalWS = normalize(surface.normalWS);
    half3 viewDirWS = normalize(surface.viewDirWS);

    // ==========================================
    // 1. 基底色運算與下限保護
    // ==========================================
    half NdotV = 1.0 - max(0.0, dot(normalWS, viewDirWS));
    half fresnel = saturate(_FresnelBias + _FresnelIntensity * pow(NdotV, _FresnelPower));
    
    half3 secondCol = surface.albedo * _SkinSecondColor.rgb; 
    
    // 【核心修正】：使用接收自 DayNightSystemPro 的全域變數 _GlobalDarkColorMinLimit
    half3 safeDarkColor = max(_SkinDarkColor.rgb, half3(_GlobalDarkColorMinLimit, _GlobalDarkColorMinLimit, _GlobalDarkColorMinLimit));
    
    // 基底色與 Fresnel 混合，並強制乘上經過安全保護的暗色
    half3 diffuse = lerp(surface.albedo, secondCol, fresnel) * safeDarkColor;

    // ==========================================
    // 2. 統一深層陰影染色 (依賴中央管線傳入的 GI)
    // ==========================================
    
    // 1. 接收已經過下限保護的 indirectDiffuse，並強制轉為純灰階 (Luminance)
    // 這一步徹底消除了場景天空盒帶來的藍/灰色偏污染，同時保留了中央管線計算好的正確亮度
    half ambientLum = Luminance(indirectDiffuse);
    half3 cleanAmbient = half3(ambientLum, ambientLum, ambientLum);
    
    // 2. 將 _SkinShadowColor 直接註冊為深層陰影底色
    half3 globalShadowTint = lerp(half3(1.0, 1.0, 1.0), _SkinShadowColor.rgb, _SkinShadowStrength);
    
    // 3. 乾淨的底色 × 乾淨的亮度 × 絕對的陰影染色
    half3 diffuseDark = diffuse * cleanAmbient * 1.5 * globalShadowTint;

    // ==========================================
    // 3. Lambert 光照與 Ramp 柔光混合 (修復 UV 偏移)
    // ==========================================
    half NdotL = dot(normalWS, mainLight.direction);
    // 取得絕對純淨的物理陰影遮罩
    half pureLambertMask = min(saturate((NdotL * 0.5 + 0.5) + 0.2), castShadowMask);
    // 將 shadowStrength 移至最終遮罩，確保強度為 0 時能完全受光
    half finalLambertMask = lerp(1.0, pureLambertMask, _SkinShadowStrength);
    
    // 使用受強度控管的遮罩採樣 Ramp，確保顏色絕對正確
    half3 ramp = SAMPLE_TEXTURE2D(_RampMap, sampler_LinearClamp, half2(finalLambertMask, 0.5)).rgb;
    
    // 計算亮部與過渡帶
    half3 baseLambertLight = diffuse * mainLight.color * finalLambertMask;
    half3 softLightRamp = FaceBlendSoftLight(baseLambertLight, ramp);
    half3 diffuseLight = lerp(baseLambertLight, softLightRamp, _RampStrength);

    // ==========================================
    // 4. 輸出整合 (徹底拔除 shadowAtten 的雙重黑洞)
    // ==========================================
    half ao = saturate(surface.alpha + _SkinAO_Offset);
    
    // 乾淨的合成：深層陰影區 diffuseLight 為 0，自動選擇已染色的 diffuseDark
    half3 final_diff = max(diffuseDark, diffuseLight) * ao;

    // ==========================================
    // 5. 高光 (Blinn-Phong)
    // ==========================================
    half3 halfDir = normalize(mainLight.direction + viewDirWS);
    half spec = pow(saturate(dot(normalWS, halfDir)), _SpecShininess);
    
    // 高光遮蔽獨立計算
    half specShadowMask = lerp(1.0, castShadowMask, _SkinShadowStrength);
    half3 final_spec = spec * _SpecularColor.rgb * _SpecularIntensity * specShadowMask;

    return final_diff + final_spec;
}

#endif