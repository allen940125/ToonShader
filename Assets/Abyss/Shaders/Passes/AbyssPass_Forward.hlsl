#ifndef ABYSS_PASS_FORWARD_INCLUDED
#define ABYSS_PASS_FORWARD_INCLUDED

#include "Core/AbyssCore.hlsl"
#include "Core/AbyssSurfaceSetup.hlsl"
#include "Core/AbyssPass_Utilities.hlsl"

#include "Effects/Effect_Fresnel.hlsl"
#include "Effects/Effect_Matcap.hlsl"
#include "Effects/Effect_AnisotropicHighlight.hlsl"
#include "Effects/Effect_Wetness.hlsl"
#include "Lighting/Effect_Lighting.hlsl"

// =======================================================
// 【解耦設計】：只在開啟功能時才引入套件核心
// =======================================================
#if defined(_USE_CHAR_SHADOW)
    #include "Packages/com.unity.tooncharactershadow/Shaders/DeclareCharacterShadowTexture.hlsl"
#endif

Varyings vert_forward(Attributes input)
{
    Varyings output = (Varyings)0;;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.positionOS = input.positionOS.xyz;
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    
    real sign = input.tangentOS.w * GetOddNegativeScale();
    output.tangentWS = float4(TransformObjectToWorldDir(input.tangentOS.xyz), sign);
    
    output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
    output.screenPos = ComputeScreenPos(output.positionHCS);
    
    return output;
}

half4 frag_forward(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    
    AbyssSurfaceData surface;
    InitializeSurfaceData(input, surface);

    // 透明度裁切
    DoTransparencyClip(surface.alpha, input.screenPos.xy / input.screenPos.w);

    #if defined(_WEATHER_WETNESS_ON)
        ApplyWeatherWetness(surface, _LocalWetness, input.uv);
    #endif

    // 在 frag_forward 中找到計算 shadowCoord 的位置：
    // 取得指向主光源的方向向量
    float3 lightDirWS = _MainLightPosition.xyz;
    // 建立迎向光源推移的偏移座標，消除 CSM 陰影雜斑
    float3 biasedSamplePosWS = surface.positionWS + (lightDirWS * _CSMSampleBias);
    
    float4 shadowCoord = TransformWorldToShadowCoord(biasedSamplePosWS);
    Light mainLight = GetMainLight(shadowCoord);

    // 【新增備份】：把最原始、沒被污染的 URP 原生 CSM 存起來！
    half pureCSMShadow = mainLight.shadowAttenuation;

    // =======================================================
    // 【解耦設計】：角色局部陰影合併 (Per-Object Shadow)
    // =======================================================
    // =======================================================
    // 【解耦設計】：角色局部陰影合併 (Per-Object Shadow)
    // =======================================================
    half localCharShadow = 1.0; 

    #if defined(_USE_CHAR_SHADOW)
    // 1. 先取得套件算出來的原始數值
    half rawCharShadow = SampleCharacterAndTransparentShadow(surface.positionWS, surface.alpha);

    // 2. 智能反轉機制：
    // 如果是透視相機 (_CharShadowIsOrtho == 0)，套用 1.0 - rawCharShadow
    // 如果是正交相機 (_CharShadowIsOrtho == 1)，套用 rawCharShadow
    // (備註：如果你發現正反對調了，就把 lerp 裡面前面兩個參數的位置互換即可！)
    localCharShadow = lerp(1.0 - rawCharShadow, rawCharShadow, _CharShadowIsOrtho);

    // 3. 將 URP 全域陰影與局部陰影合併
    mainLight.shadowAttenuation = min(mainLight.shadowAttenuation, localCharShadow);
    #endif

    // AO 融合系統
    float2 screenUV = input.screenPos.xy / input.screenPos.w;
    half ssao = 1.0;
    #if defined(_SCREEN_SPACE_OCCLUSION)
        AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(screenUV);
        ssao = aoFactor.indirectAmbientOcclusion; 
    #endif
    half bakedAO = lerp(1.0, surface.occlusion, _OcclusionStrength);
    half finalAO = min(ssao, bakedAO);

    half3 finalColor = surface.albedo;
    
    // 3. 呼叫光照大腦 (取得完整 Diffuse + Specular + Rim + Env)
    #if defined(_USE_LIGHTING)
        finalColor = ComputeFinalLighting(surface, mainLight, finalAO);
    #endif

    // 效果疊加
    // ApplyFresnel(surface);
    // ApplyMatCap(surface);
    // ApplyAnisotropicHighlight(surface, mainLight);

    finalColor += surface.emission;

    // =======================================================
    // 全域除錯模式攔截器 (Global Debug View)
    // =======================================================
    // 1. 安全轉型：加上 0.1 確保浮點數轉整數時不會因為精度問題向下取整
    int debugMode = (int)(_GlobalDebugViewMode + 0.1); 

    UNITY_BRANCH
    if (debugMode != 0) 
    {
        switch (debugMode)
        {
            case 1: // Shadow
                finalColor = pureCSMShadow.xxx;
                break;
                
            case 2: // Highlight
                half3 halfDir = SafeNormalize(mainLight.direction + surface.viewDirWS);
                half NdotH = max(0.0, dot(surface.normalWS, halfDir));
                half spec = smoothstep(_SpecularStep - _SpecularFeather, _SpecularStep + _SpecularFeather, NdotH);
                finalColor = _SpecularColor.rgb * spec * _SpecularIntensity;
                break;
                
            case 3: // AO (注意：請確認你當前作用域的變數是 finalAO 還是 surface.occlusion)
                finalColor = surface.occlusion.xxx; 
                break;
                
            case 4: // RimLight (呼叫我們剛寫好的終極邊緣光函數)
                half3 debugInnerRim, debugFinalRim;
                // 這裡傳入 1.0 作為 castShadowMask 確保預覽時邊緣光完整顯示
                CalculateAnimeRimLight(surface, mainLight, 1.0, debugInnerRim, debugFinalRim);
                finalColor = debugInnerRim + debugFinalRim;
                break;
                
            case 5: // Albedo
                finalColor = surface.albedo;
                break;
                
            case 6: // Normal
                finalColor = surface.normalWS * 0.5 + 0.5;
                break;
                
            case 7: // Metallic
                finalColor = surface.metallic.xxx;
                break;
                
            case 8: // Smoothness
                finalColor = surface.smoothness.xxx;
                break;
                
            case 9: // Emission
                finalColor = surface.emission;
                break;
                
            case 10: // MainLightColor
                finalColor = mainLight.color;
                break;
                
            case 11: // MainLightDirection (映射到 0~1 空間，避免負數向量變成純黑)
                finalColor = mainLight.direction * 0.5 + 0.5;
                break;
                
            case 12: // MainLightDistanceAttenuation
                finalColor = mainLight.distanceAttenuation.xxx;
                break;

            // ==========================================
            // 新增：環境光與反射 Debug
            // ==========================================
            case 13: // Indirect Diffuse (球諧函數 SH / Light Probe 採樣)
                // 檢視場景全域照明 (GI) 對模型暗部的基礎染色
                finalColor = GetIndirectDiffuse(surface.positionWS, surface.normalWS, surface.viewDirWS);
                break;
                
            case 14: // Raw Environment Reflection (原始天空盒 / Reflection Probe 採樣)
                // 直接輸出物理環境反射，這將直接暴露導致你金屬變藍/變白的元兇
                half3 reflectDir = reflect(-surface.viewDirWS, surface.normalWS);
                half perceptualRoughness = 1.0 - surface.smoothness;
                // 強制讀取未經 Fresnel 或固有色相乘的原始反射訊號
                finalColor = GlossyEnvironmentReflection(reflectDir, surface.positionWS, perceptualRoughness, 1.0h);
                break;
            // ==========================================
            // 【新增】：角色局部陰影 Debug 視角
            // ==========================================
            case 15: 
                // 直接輸出我們在上面算出來的 localCharShadow 
                //(白 = 受光 / 沒被遮蔽，黑 = 處於角色局部陰影中)
                finalColor = localCharShadow.xxx;
                break;
            
            case 16: // 【新增】：合併後的最終陰影結果 (CSM + Local Char)
                // 因為 mainLight.shadowAttenuation 已經被 min() 處理過了
                finalColor = mainLight.shadowAttenuation.xxx;
                break;
            case 17: // 【純光照模型】：GI (暗部) + 主光源與陰影 (亮部)
                half3 gi = GetIndirectDiffuse(surface.positionWS, surface.normalWS, surface.viewDirWS);
                
                // 太陽光 = 主光顏色 * 半蘭伯特(迎光面) * 陰影遮罩
                half halfLambert = dot(surface.normalWS, mainLight.direction) * 0.5 + 0.5;
                half3 directLight = mainLight.color * halfLambert * mainLight.shadowAttenuation;
                
                // 最終光照 = 環境光 + 太陽光
                finalColor = gi + directLight;
                break;
        }
    }

    return half4(finalColor, surface.alpha);
}
#endif