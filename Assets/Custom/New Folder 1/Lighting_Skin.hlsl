#ifndef LIGHTING_SKIN_INCLUDED
#define LIGHTING_SKIN_INCLUDED

#include "Lighting_Utilities.hlsl"

inline half3 ComputeLighting_Skin(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    half3 normalWS = normalize(surface.normalWS);
    half3 viewDirWS = normalize(surface.viewDirWS);

    // ==========================================
    // 1. 陰影強度與全域混合 (補回與 Face 一致的染色邏輯)
    // ==========================================
    half unityShadow = lerp(1.0, castShadowMask, _SkinShadowStrength);
    half ao = saturate(surface.alpha + _SkinAO_Offset);

    // 【修正】：補回缺失的投影染色邏輯
    half3 coloredShadow = lerp(_SkinShadowColor.rgb, half3(1.0, 1.0, 1.0), castShadowMask);
    half3 shadowAtten = lerp(half3(1.0, 1.0, 1.0), castShadowMask.xxx, _SkinShadowStrength) * coloredShadow;

    // ==========================================
    // 2. 漫反射基礎
    // ==========================================
    half NdotL = dot(normalWS, mainLight.direction);
    half halfLambert = min(saturate((NdotL * 0.5 + 0.5) + 0.2), unityShadow);
    
    // ==========================================
    // 3. 邊緣光 (Fresnel) 混合
    // ==========================================
    half NdotV = 1.0 - max(0.0, dot(normalWS, viewDirWS));
    half fresnel = saturate(_FresnelBias + _FresnelIntensity * pow(NdotV, _FresnelPower));
    half3 secondCol = surface.albedo * _SkinSecondColor.rgb; 
    half3 diffuse = lerp(surface.albedo, secondCol, fresnel) * _SkinDarkColor.rgb;

    // ==========================================
    // 4. 光能區分與 Ramp 柔光混合
    // ==========================================
    half3 diffuseDark = diffuse * indirectDiffuse * 1.5; 
    half3 baseDiffuseLight = diffuse * halfLambert * mainLight.color;
    
    half3 ramp = SAMPLE_TEXTURE2D(_RampMap, sampler_LinearClamp, half2(halfLambert, 0.5)).rgb;
    half3 softLightRamp = FaceBlendSoftLight(baseDiffuseLight, ramp);
    half3 diffuseLight = lerp(baseDiffuseLight, softLightRamp, _RampStrength);

    // ==========================================
    // 5. 高光 (Blinn-Phong)
    // ==========================================
    half3 halfDir = normalize(mainLight.direction + viewDirWS);
    half spec = pow(saturate(dot(normalWS, halfDir)), _SpecShininess);
    half3 final_spec = spec * _SpecularColor.rgb * _SpecularIntensity * castShadowMask;

    // 【修正】：將 baseDiffuse 計算結果乘上 shadowAtten
    return max(diffuseDark, diffuseLight) * ao * shadowAtten + final_spec;
}

#endif