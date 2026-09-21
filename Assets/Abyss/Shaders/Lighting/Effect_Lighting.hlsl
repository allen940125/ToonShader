#ifndef EFFECT_LIGHTING_INCLUDED
#define EFFECT_LIGHTING_INCLUDED

// 1. 包含公共工具
#include "Lighting_Utilities.hlsl"

// 2. 包含各种表面的具体漫反射算法
#include "Lighting_Standard.hlsl"   
#include "Lighting_Cloth.hlsl"
#include "Lighting_Face.hlsl"
#include "Lighting_Skin.hlsl"
#include "Lighting_Hair.hlsl"
#include "Lighting_Eye.hlsl"

// ---------------------------------------------------------------
// 主光照组合函数（中央调度）
// ---------------------------------------------------------------
inline half3 ComputeFinalLighting(AbyssSurfaceData surface, Light mainLight, half occlusion)
{
    // 1. 主光預處理（公共）
    mainLight.color *= _MainLightMultiplier;
    float lightIntensity = max(mainLight.color.r, max(mainLight.color.g, mainLight.color.b));
    half3 neutralLight = half3(lightIntensity, lightIntensity, lightIntensity);
    mainLight.color = lerp(neutralLight, mainLight.color, _MainLightColorWeight);

    // =======================================================
    // 2. 陰影遮罩（嚴謹修正版）
    // =======================================================
    // 移除對 ShadowAttenuation 的無理 smoothstep，保留 URP 原生陰影平滑邊緣
    // 如果你只需要控制陰影接收的強度，直接使用 lerp 即可
    float castShadowMask = lerp(1.0, mainLight.shadowAttenuation, _ReceiveShadowIntensity);

    // 距離衰減應該獨立作用於光照強度，而非混入陰影遮罩中
    // 避免 distanceAttenuation 歸零時導致 castShadowMask 判定為全陰影
    mainLight.color *= mainLight.distanceAttenuation; 
    // =======================================================

    // 3. 間接漫反射（公共）
    half3 indirectDiffuse = GetIndirectDiffuse(surface.positionWS, surface.normalWS, surface.viewDirWS);
    indirectDiffuse *= occlusion;

    // 4. 【靜態巨集分發】：編譯器會根據外殼 Shader 的 #define 自動抹除多餘分支
    half3 directLighting = 0;
    
    #if defined(ABYSS_MATERIAL_CLOTH)
        directLighting = ComputeLighting_Cloth(surface, mainLight, indirectDiffuse, castShadowMask);
        
    #elif defined(ABYSS_MATERIAL_SKIN)
        directLighting = ComputeLighting_Skin(surface, mainLight, indirectDiffuse, castShadowMask); // 暫時 fallback
        
    #elif defined(ABYSS_MATERIAL_HAIR)
        directLighting = ComputeLighting_Hair(surface, mainLight, indirectDiffuse, castShadowMask); // 暫時 fallback

    #elif defined(ABYSS_MATERIAL_FACE)
        directLighting = ComputeLighting_Face(surface, mainLight, indirectDiffuse, castShadowMask); // 暫時 fallback
    
    #elif defined(ABYSS_MATERIAL_EYE)
        directLighting = ComputeLighting_Eye(surface, mainLight, indirectDiffuse, castShadowMask); // 暫時 fallback

    #else
        // 預設 Standard (若外殼沒寫任何巨集，自動套用此標準光照)
        directLighting = ComputeLighting_Standard(surface, mainLight, indirectDiffuse, castShadowMask);
    #endif

    // 5. 公共附加组件（中央统一处理）
    half3 addLight = GetAdditionalLightsContribution(surface.positionWS, surface.normalWS, surface.viewDirWS, surface.albedo);
    half3 reflection = GetIndirectSpecular(surface);
    //half3 rimLight = GetStylizedRimLight(surface, mainLight, castShadowMask); // 可选：如果所有表面都需要

    // 6. 合并
    return directLighting + addLight + reflection;
}

#endif // EFFECT_LIGHTING_INCLUDED