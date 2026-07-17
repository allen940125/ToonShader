#ifndef LIGHTING_FACE_INCLUDED
#define LIGHTING_FACE_INCLUDED

#include "Lighting_Utilities.hlsl"

// ------------------------------------------------------------------
// 輔助函數：柔光混合 (Soft Light Blend)
// 用於混合基礎光照與 Ramp 貼圖
// ------------------------------------------------------------------
inline half3 FaceBlendSoftLight(half3 baseColor, half3 blendColor)
{
    half3 limit = step(0.5, blendColor);
    half3 lower = 2.0 * baseColor * blendColor + baseColor * baseColor * (1.0 - 2.0 * blendColor);
    half3 upper = sqrt(baseColor) * (2.0 * blendColor - 1.0) + 2.0 * baseColor * (1.0 - blendColor);
    return lerp(lower, upper, limit);
}

// ------------------------------------------------------------------
// 臉部光照核心邏輯 (SDF + 遮罩特化)
// ------------------------------------------------------------------
inline half3 ComputeLighting_Face(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    // ==========================================
    // 1. 向量與基礎變數準備
    // ==========================================
    half3 normalWS = normalize(surface.normalWS);
    half3 viewDirWS = normalize(surface.viewDirWS);
    half3 headUpDir = normalize(_HeadUp);
    half3 headRightDir = normalize(_HeadRight);
    half3 headForwardDir = normalize(_HeadForward);

    // 取樣臉部基礎貼圖
    half4 sdfRight = SAMPLE_TEXTURE2D(_FaceSDF, sampler_BaseMap, surface.uv);
    half4 sdfLeft  = SAMPLE_TEXTURE2D(_FaceSDF, sampler_BaseMap, float2(1.0 - surface.uv.x, surface.uv.y));

    // ==========================================
    // 2. 陰影強度與全域混合
    // ==========================================
    half finalShadowStrength = _FaceShadowStrength;
    half3 coloredShadow = lerp(_FaceShadowColor.rgb, half3(1.0, 1.0, 1.0), castShadowMask);
    half3 perObjectShadow = lerp(half3(1.0, 1.0, 1.0), castShadowMask.xxx, finalShadowStrength) * coloredShadow;

    // 定義主陰影閥值
    half unityShadow = lerp(1.0, castShadowMask, finalShadowStrength);

    // ==========================================
    // 3. 簡單模式與複雜模式的分支解析
    // ==========================================
    #ifndef _FACE_SIMPLE_MODE
    
        // 讀取臉部專用 ColorMask (R:第二顏色, G:下巴陰影, B:自我陰影, A:高光)
        half4 colorMask = SAMPLE_TEXTURE2D(_FaceColorMask, sampler_BaseMap, surface.uv);
        
        // 注意：原 ZMD 邏輯使用 baseMap.a 作為 AO。此處對齊系統，使用 surface.alpha 代表該資訊
        half ao = saturate(surface.alpha + _FaceAO_Offset);
        
        half secondColorMask = max(colorMask.r, colorMask.g);
        half jawShadow = colorMask.g;
        half selfShadowMask = colorMask.b;
        half specMask = colorMask.a;

        // 計算自陰影遮罩與視角偏移
        half viewSdfDot = dot(viewDirWS, headForwardDir);
        half faceViewBlend = smoothstep(0.0, 0.5, viewSdfDot); 
        half blendedSelfShadowMask = lerp((1.0 - selfShadowMask), (1.0 - jawShadow), faceViewBlend);
        
        half3 shadowAtten = max(perObjectShadow, blendedSelfShadowMask);

        // 擴散光與副色混合
        half3 secondCol = surface.albedo * _FaceSecondColor.rgb;
        half3 diffuse = lerp(surface.albedo, secondCol, secondColorMask) * _FaceDarkColor.rgb;

    #else
        
        // 簡單模式：跳過遮罩與 AO
        half3 diffuse = surface.albedo * _FaceDarkColor.rgb;
    
    #endif

    // 區分暗部與亮部的基礎光能量
    half3 diffuseDark = diffuse * indirectDiffuse * 1.5;
    half3 baseDiffuseLight = diffuse * mainLight.color;

    // ==========================================
    // 4. SDF 光照計算 (核心臉部光影映射)
    // ==========================================
    half3 lightOnHeadPlane = mainLight.direction - headUpDir * dot(mainLight.direction, headUpDir);
    half planeLenSq = max(dot(lightOnHeadPlane, lightOnHeadPlane), 1e-4);
    half3 headPlaneLightDir = lightOnHeadPlane * rsqrt(planeLenSq);

    half sdf_dot = dot(headPlaneLightDir, headForwardDir);
    half LOR = step(dot(headPlaneLightDir, headRightDir), 0.0);
    half softShadow = _FaceSoftShadow * 0.5;
    
    // 依據光照方向切換左右臉 SDF
    half4 activeSdf = lerp(sdfRight, sdfLeft, LOR);

    half frontShadow = smoothstep(sdf_dot + softShadow, max(sdf_dot - softShadow, 0.0), 1.0 - activeSdf.g);
    half dotRemap = saturate(sdf_dot + 1.0);
    half backShadow = smoothstep(min(dotRemap + softShadow, 1.0), dotRemap - softShadow, 1.0 - activeSdf.r);

    half channelBlend = smoothstep(softShadow, -softShadow, sdf_dot);
    
    // 計算最終 SDF 陰影遮罩 (與全域陰影取交集)
    half sdfShadow = min(saturate(lerp(frontShadow, backShadow, channelBlend)), unityShadow);
    half3 sdfRamp = SAMPLE_TEXTURE2D(_FaceDiffuseRamp, sampler_BaseMap, half2(sdfShadow, 0.5)).rgb;

    // SDF 亮部混合
    half3 baseSdfLight = baseDiffuseLight * sdfShadow;
    half3 softLightSdfRamp = FaceBlendSoftLight(baseSdfLight, sdfRamp);
    half3 sdfLight = lerp(baseSdfLight, softLightSdfRamp, _FaceRampStrength);

    // ==========================================
    // 5. 輸出整合 (含 Lambert 回退與高光)
    // ==========================================
    #ifndef _FACE_SIMPLE_MODE
    
        // 計算標準 Lambert (用於下巴、頸部等非 SDF 區域)
        half NdotL = dot(normalWS, mainLight.direction);
        half halfLambert = min(saturate((NdotL * 0.5 + 0.5) + 0.2), unityShadow);
        half3 ramp = SAMPLE_TEXTURE2D(_FaceDiffuseRamp, sampler_BaseMap, half2(halfLambert, 0.5)).rgb;

        half3 baseLambertLight = baseDiffuseLight * halfLambert;
        half3 softLightRamp = FaceBlendSoftLight(baseLambertLight, ramp);
        half3 lambertLight = lerp(baseLambertLight, softLightRamp, _FaceRampStrength);

        // 依據 jawShadow 遮罩，在 SDF 與 Lambert 間過渡
        half3 diffuseLight = lerp(sdfLight, lambertLight, jawShadow);
        half3 final_diff = max(diffuseDark, diffuseLight) * ao * shadowAtten;

        // 計算臉部特化高光 (含唇部高光遮罩)
        half halfMask = step(surface.uv.x, 0.5);
        half lightHM = lerp(halfMask, 1.0 - halfMask, LOR);
        half NdotV = max(0, dot(headForwardDir, viewDirWS));
        
        half fresnel = _FaceSpecularIntensity * saturate(NdotV - 0.75);
        half lipSpecMaskOffset = dot(viewDirWS, headRightDir) * 0.05;
        half2 lipSpecMaskUV = half2(surface.uv.x + lipSpecMaskOffset, surface.uv.y);
        
        half lipSpecMask = SAMPLE_TEXTURE2D(_FaceLipSpecMask, sampler_BaseMap, lipSpecMaskUV).r;
        lipSpecMask *= 1.0 - step(sdf_dot, 0.0);
        
        specMask = specMask * lightHM * fresnel * saturate(sdf_dot) + lipSpecMask;
        half3 final_spec = _FaceSpecularColor.rgb * mainLight.color * specMask * shadowAtten;

        return final_diff + final_spec;
        
    #else
    
        return max(diffuseDark, sdfLight);
        
    #endif
}

#endif