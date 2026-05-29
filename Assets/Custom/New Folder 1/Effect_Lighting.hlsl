#ifndef EFFECT_LIGHTING_INCLUDED
#define EFFECT_LIGHTING_INCLUDED

// 確保有引入此庫以使用 SampleSH 函數
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

inline half3 ApplyBasicLighting(AbyssSurfaceData surface, Light mainLight)
{
    // --- 新增：1. 獲取場景 GI / APV (間接光) ---
    // 透過法線方向取樣球諧函數，這裡面就包含了 Skybox、Light Probes 與 APV 的顏色資訊
    half3 indirectLight = SampleSH(surface.normalWS);

    // --- 2. 基礎內積計算與映射 (直接光) ---
    float NdotL = dot(surface.normalWS, mainLight.direction);
    float halfLambert = NdotL * 0.5 + 0.5;
    
    // --- 3. 動態計算邊界與模糊 ---
    float minBand = _BandThreshold - _BandSmoothness;
    float maxBand = _BandThreshold + _BandSmoothness;
    float lightBand = smoothstep(minBand, maxBand, halfLambert);
    
    // --- 4. 處理陰影接收強度 ---
    float finalShadowAttenuation = lerp(1.0, mainLight.shadowAttenuation, _ShadowIntensity);
    lightBand *= finalShadowAttenuation;
    
    // --- 5. 顏色指定與混合 (融合 GI) ---
    // 受光面：基礎色 * (主光源顏色 + 環境光)
    half3 litColor = surface.albedo * (mainLight.color + indirectLight); 
    
    // 陰影面：基礎色 * 陰影染色 * 環境光 
    // (卡通陰影通常需要乘上環境光，否則在藍色天空下陰影還是死黑的，會脫離場景)
    half3 shadowColor = surface.albedo * _ShadowTint.rgb * indirectLight;  
    
    // --- 6. 最終輸出 ---
    half3 finalColor = lerp(shadowColor, litColor, lightBand);
    
    return finalColor;
}

#endif