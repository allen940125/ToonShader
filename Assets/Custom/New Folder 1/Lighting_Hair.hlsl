#ifndef LIGHTING_HAIR_INCLUDED
#define LIGHTING_HAIR_INCLUDED

#include "Lighting_Utilities.hlsl"

inline half3 ComputeLighting_Hair(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    // 1. 讀取頭髮特化貼圖 (利用剛才傳入的 surface.uv)
    half hairLine = SAMPLE_TEXTURE2D(_HairLineMap, sampler_BaseMap, surface.uv * _HairLineMap_ST.xy + _HairLineMap_ST.zw).r;
    half anisoNoiseTex = SAMPLE_TEXTURE2D(_AnisoMap, sampler_BaseMap, surface.uv * _AnisoMap_ST.xy + _AnisoMap_ST.zw).r;
    half anisoNoise = anisoNoiseTex * 2.0 - 1.0;

    // 2. 處理基礎色與髮絲染色
    half3 baseColor = lerp(surface.albedo, surface.albedo * _HairSecondColor.rgb, hairLine);
    half3 diffuseBase = baseColor * _HairSpecularOffset; // 對方邏輯：以此作為漫反射基底

    // 3. 漫反射 (Soft Light Ramp)
    float NdotL = dot(surface.normalWS, mainLight.direction);
    half unityShadow = lerp(1.0, mainLight.shadowAttenuation, _GlobalShadowStrength); // 全域陰影強度
    half halfLambert = min((NdotL * 0.5 + 0.5), unityShadow); // 陰影直接切斷半蘭伯特
    
    half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_BaseMap, float2(halfLambert, 0.5)).rgb;
    half3 rawDiffuse = diffuseBase * mainLight.color;
    
    // 柔光混合公式
    half3 softLightDiffuse = (1.0 - 2.0 * rampColor) * rawDiffuse * rawDiffuse + 2.0 * rampColor * rawDiffuse;
    half3 finalDiffuse = lerp(rawDiffuse, softLightDiffuse, _RampStrength) * castShadowMask;

    // 4. 頭頂假光 (Top Light)
    half topNdotL = dot(surface.normalWS, _HeadUp.xyz);
    half topLambert = saturate(topNdotL * 0.5 + 0.5 + _HairTopLightOffset);
    half3 topLightColor = diffuseBase * topLambert * _HairTopLightColor.rgb * _HairTopLightIntensity * castShadowMask;
    finalDiffuse += topLightColor;

    // 5. 天使環：各向異性高光 (Anisotropic Specular)
    // 構建球形法線與副切線
    float3 sphereNormalWS = normalize(surface.positionWS - (_HeadPosition.xyz + float3(0, _HairAnisoPosition, 0)));
    float3 cameraRightWS = UNITY_MATRIX_V[0].xyz; 
    float3 sphereBitangentWS = normalize(cross(sphereNormalWS, cameraRightWS));
    
    // 融合真實法線與球形法線
    sphereNormalWS = lerp(sphereNormalWS, surface.normalWS, 0.25);

    // Kajiya-Kay 高光模型
    half3 halfDir = normalize(_HeadForward.xyz + surface.viewDirWS); // 注意：光向被替換為頭部朝向
    half fresnel = max(0, dot(surface.normalWS, surface.viewDirWS));
    fresnel *= fresnel;
    
    // 主高光環
    half3 anisoOffsetVec = sphereNormalWS * (anisoNoise * _HairAnisoNoise + _HairAnisoOffset);
    half3 binormal = normalize(sphereBitangentWS + anisoOffsetVec);
    half BdotH = dot(binormal, halfDir);
    half specTemp = pow(sqrt(saturate(1.0 - BdotH * BdotH)), _HairAnisoShininess);

    // 斷層副高光環 (Cut Ring)
    half3 anisoOffsetCut = sphereNormalWS * (anisoNoise * _HairAnisoNoise + _HairAnisoOffset + _HairCutOffset);
    half3 binormalCut = normalize(sphereBitangentWS + anisoOffsetCut);
    half BdotHCut = dot(binormalCut, halfDir);
    half cutSpecTemp = pow(sqrt(saturate(1.0 - BdotHCut * BdotHCut)), _HairAnisoShininess * 2.0);
    half anisoCutMask = smoothstep(0.0, 0.1, cutSpecTemp);

    // 高光合成
    half3 specBaseColor = baseColor * (1.0 - _HairSpecularOffset) * mainLight.color;
    half3 finalRingSpec = saturate(specTemp - anisoCutMask) * specBaseColor * _HairSpecularColor.rgb * (surface.specMask * fresnel) * _HairSpecularIntensity * castShadowMask;

    // 標準高光 (用於後髮)
    half3 standardBinormal = normalize(surface.tangentWS.xyz + (surface.normalWS * (anisoNoise * _HairAnisoNoise + _HairAnisoOffset)));
    half standardBdotH = dot(standardBinormal, halfDir);
    half standardSpecTemp = pow(sqrt(saturate(1.0 - standardBdotH * standardBdotH)), _HairAnisoShininess);
    half3 standardSpec = standardSpecTemp * specBaseColor * _HairSpecularColor.rgb * surface.specMask * _HairSpecularIntensity * castShadowMask;

    // 根據前髮遮罩混合兩種高光
    half3 finalSpec = lerp(standardSpec, finalRingSpec, surface.frontHair);

    // 6. 間接光 (GI & Reflection)
    half3 ambient = indirectDiffuse * diffuseBase;
    half3 envSpec = 0;
    #if defined(_REFLECTION_ON)
        half3 reflectDir = reflect(-surface.viewDirWS, surface.normalWS);
        half3 envMap = GlossyEnvironmentReflection(reflectDir, surface.positionWS, _HairEnvSmoothness, 1.0);
        envSpec = envMap * specBaseColor * _HairEnvSpecularColor.rgb * _HairEnvSpecularIntensity;
    #endif

    // 合併最終顏色
    // 呼叫終極邊緣光函數
    half3 inner_rim, final_rim;
    CalculateAnimeRimLight(surface, mainLight, castShadowMask, inner_rim, final_rim);

    // 頭髮：無情拋棄 inner_rim，甚至可以把 final_rim 放大 1.5 倍強化剪影！
    half3 finalColor = finalDiffuse + finalSpec + ((ambient + envSpec) * surface.occlusion);
    finalColor += final_rim * 1.5;

    return finalColor;
}

#endif