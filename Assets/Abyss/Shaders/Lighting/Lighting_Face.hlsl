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
    // 2. 陰影強度與全域遮罩
    // ==========================================
    half finalShadowStrength = _SkinShadowStrength;
    // 定義主投影陰影閥值
    half unityShadow = lerp(1.0, castShadowMask, finalShadowStrength);

    // ==========================================
    // 3. 簡單模式與複雜模式的分支解析
    // ==========================================
    #ifndef _FACE_SIMPLE_MODE
    
    half4 colorMask = SAMPLE_TEXTURE2D(_FaceColorMask, sampler_BaseMap, surface.uv);
    half ao = saturate(surface.alpha + _SkinAO_Offset);
        
    half secondColorMask = max(colorMask.r, colorMask.g);
    half jawShadow = colorMask.g;
    half selfShadowMask = colorMask.b;
    half specMask = colorMask.a;

    // 正確的相機跟隨技術 (View-Dependent Shadow Fix)
    half viewSdfDot = dot(viewDirWS, headForwardDir);
    half faceViewBlend = smoothstep(0.0, 0.5, viewSdfDot); 
    
    // 側臉時漸變為 1.0 (無自陰影)，正臉時套用 1.0 - selfShadowMask
    // 徹底排除 jawShadow 的干擾，解決陰影形狀拉扯問題
    //half dynamicSelfShadow = lerp(1.0, 1.0 - selfShadowMask, faceViewBlend);
    half dynamicSelfShadow = 1;
    
    // 生成統一純量遮罩 (包含實體投影與視角自陰影)
    //half globalShadowMask = min(unityShadow, dynamicSelfShadow);

    // ============================================================
    // 3. 基底色運算與下限保護 (由面版 _DarkColorMinLimit 控制)
    // ============================================================
    half3 secondCol = surface.albedo * _SkinSecondColor.rgb;
    // 使用外部參數取代硬編碼的 0.2
    // 【核心修正】：使用接收自 DayNightSystemPro 的全域變數 _GlobalDarkColorMinLimit
    half3 safeDarkColor = max(_SkinDarkColor.rgb, half3(_GlobalDarkColorMinLimit, _GlobalDarkColorMinLimit, _GlobalDarkColorMinLimit));
    half3 diffuse = lerp(surface.albedo, secondCol, secondColorMask) * safeDarkColor;

    #else
        
    half globalShadowMask = unityShadow;
    half3 diffuse = surface.albedo * _SkinDarkColor.rgb;
    
    #endif

    // ============================================================
    // 4. 環境光與暗部底色強制提亮 (由面版 _AmbientMinLight 控制)
    // ============================================================
    // 1. 接收已經過下限保護的 indirectDiffuse，並強制轉為純灰階 (Luminance)
    // 這一步徹底消除了場景天空盒帶來的藍/灰色偏污染，同時保留了中央管線計算好的正確亮度
    half ambientLum = Luminance(indirectDiffuse);
    half3 cleanAmbient = half3(ambientLum, ambientLum, ambientLum);
    
    // 2. 將 _SkinShadowColor 直接註冊為深層陰影底色
    half3 globalShadowTint = lerp(half3(1.0, 1.0, 1.0), _SkinShadowColor.rgb, _SkinShadowStrength);
    
    // 3. 乾淨的底色 × 乾淨的亮度 × 絕對的陰影染色
    half3 diffuseDark = diffuse * cleanAmbient * 1.5 * globalShadowTint;
    
    half3 rawAmbient = SampleSH(half3(0, 0, 0));
    // ============================================================
    // 4. SDF 光照計算 (修正 UV 取樣與強度混合)
    // ============================================================
    half3 baseDiffuseLight = diffuse * mainLight.color;
    
    half3 lightOnHeadPlane = mainLight.direction - headUpDir * dot(mainLight.direction, headUpDir);
    half planeLenSq = max(dot(lightOnHeadPlane, lightOnHeadPlane), 1e-4);
    half3 headPlaneLightDir = lightOnHeadPlane * rsqrt(planeLenSq);
    half sdf_dot = dot(headPlaneLightDir, headForwardDir);
    half LOR = step(dot(headPlaneLightDir, headRightDir), 0.0);
    half softShadow = _FaceSoftShadow * 0.5;
    
    half4 activeSdf = lerp(sdfRight, sdfLeft, LOR);
    half frontShadow = smoothstep(sdf_dot + softShadow, max(sdf_dot - softShadow, 0.0), 1.0 - activeSdf.g);
    half dotRemap = saturate(sdf_dot + 1.0);
    half backShadow = smoothstep(min(dotRemap + softShadow, 1.0), dotRemap - softShadow, 1.0 - activeSdf.r);
    half channelBlend = smoothstep(softShadow, -softShadow, sdf_dot);
    
    // 【邏輯修正 1】：取得最純粹的 0~1 陰影遮罩，絕不混入 shadowStrength
    half rawSdfShadow = saturate(lerp(frontShadow, backShadow, channelBlend));
    half pureSdfMask = min(rawSdfShadow, castShadowMask);
    
    // 使用純粹的遮罩取樣 Ramp，確保顏色絕對正確
    half3 sdfRamp = SAMPLE_TEXTURE2D(_RampMap, sampler_LinearClamp, half2(pureSdfMask, 0.5)).rgb;
    
    // 計算出擁有完整 100% 陰影顏色的 SDF
    half3 baseSdfLight = baseDiffuseLight * pureSdfMask;
    half3 softLightSdfRamp = FaceBlendSoftLight(baseSdfLight, sdfRamp);
    half3 pureSdfLight = lerp(baseSdfLight, softLightSdfRamp, _RampStrength);

    // 【邏輯修正 2】：將 shadowStrength 作為透明度 (Opacity) 來混合受光面與陰影面
    // 這樣調低強度只會讓陰影變淡，絕對不會改變 Ramp 的取樣位置
    half3 sdfLight = lerp(baseDiffuseLight, pureSdfLight, finalShadowStrength);

    // ============================================================
    // 5. 輸出整合 (分離臉部與脖子的染色)
    // ============================================================
    half NdotL = dot(normalWS, mainLight.direction);
    // 脖子的 Lambert 同樣採用純粹遮罩取樣
    half pureLambertMask = min(saturate((NdotL * 0.5 + 0.5) + 0.2), castShadowMask);
    half3 ramp = SAMPLE_TEXTURE2D(_RampMap, sampler_LinearClamp, half2(pureLambertMask, 0.5)).rgb;
    
    half3 baseLambertLight = baseDiffuseLight * pureLambertMask;
    half3 softLightRamp = FaceBlendSoftLight(baseLambertLight, ramp);
    half3 pureLambertLight = lerp(baseLambertLight, softLightRamp, _RampStrength);
    
    // 脖子的強度混合
    half3 lambertLight = lerp(baseDiffuseLight, pureLambertLight, finalShadowStrength);

    // 【邏輯修正 3】：_SkinShadowColor 僅針對下巴與脖子 (jawShadow) 進行染色
    // 臉部正面的 SDF 將完美保留 Ramp 貼圖的色彩，不再被二次覆蓋
    half3 regionalShadowTint = lerp(half3(1.0, 1.0, 1.0), _SkinShadowColor.rgb, jawShadow * finalShadowStrength * (1.0 - pureLambertMask));
    
    half3 diffuseLight = lerp(sdfLight, lambertLight, jawShadow);
    
    // 最終合成：移除外層統一染色，改為區域獨立染色
    half3 final_diff = max(diffuseDark, diffuseLight) * ao * regionalShadowTint;

    // 高光運算 (維持純粹遮罩)
    half halfMask = step(surface.uv.x, 0.5);
    half lightHM = lerp(halfMask, 1.0 - halfMask, LOR);
    half NdotV = max(0, dot(headForwardDir, viewDirWS));
    half fresnel = _SpecularIntensity * saturate(NdotV - 0.75);
    half lipSpecMaskOffset = dot(viewDirWS, headRightDir) * 0.05;
    half2 lipSpecMaskUV = half2(surface.uv.x + lipSpecMaskOffset, surface.uv.y);
    half lipSpecMask = SAMPLE_TEXTURE2D(_FaceLipSpecMask, sampler_BaseMap, lipSpecMaskUV).r;
    lipSpecMask *= 1.0 - step(sdf_dot, 0.0);
    
    specMask = specMask * lightHM * fresnel * saturate(sdf_dot) + lipSpecMask;
    
    // 高光的強度混合
    half globalShadowMask = lerp(1.0, min(pureSdfMask, castShadowMask), finalShadowStrength);
    half3 final_spec = _SpecularColor.rgb * mainLight.color * specMask * globalShadowMask;

    return final_diff + final_spec;
        
    #else
    
        return max(diffuseDark, sdfLight);
        
    #endif
}