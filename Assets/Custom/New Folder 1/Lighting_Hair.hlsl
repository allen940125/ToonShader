#ifndef LIGHTING_HAIR_INCLUDED
#define LIGHTING_HAIR_INCLUDED

#include "Lighting_Utilities.hlsl"

inline half3 ComputeLighting_Hair(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    // 1. 讀取貼圖
    half hairLine = SAMPLE_TEXTURE2D(_HairLineMap, sampler_BaseMap, surface.uv * _HairLineMap_ST.xy + _HairLineMap_ST.zw).r;
    half anisoNoiseTex = SAMPLE_TEXTURE2D(_AnisoMap, sampler_BaseMap, surface.uv * _AnisoMap_ST.xy + _AnisoMap_ST.zw).r;
    half anisoNoise = anisoNoiseTex * 2.0 - 1.0;

    // 2. 基底色
    half3 baseColor = lerp(surface.albedo, surface.albedo * _HairSecondColor.rgb, hairLine);
    half3 diffuseBase = baseColor * _HairSpecularOffset;

    // 3. 漫反射
    float NdotL = dot(surface.normalWS, mainLight.direction);
    half unityShadow = lerp(1.0, mainLight.shadowAttenuation, _GlobalShadowStrength); 
    half halfLambert = min((NdotL * 0.5 + 0.5), unityShadow); 
    
    half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_BaseMap, float2(halfLambert, 0.5)).rgb;
    half3 rawDiffuse = diffuseBase * mainLight.color;
    
    half3 softLightDiffuse = (1.0 - 2.0 * rampColor) * rawDiffuse * rawDiffuse + 2.0 * rampColor * rawDiffuse;
    half3 finalDiffuse = lerp(rawDiffuse, softLightDiffuse, _RampStrength) * castShadowMask;

    // 4. 頭頂假光
    half topNdotL = dot(surface.normalWS, _HeadUp.xyz);
    half topLambert = saturate(topNdotL * 0.5 + 0.5 + _HairTopLightOffset);
    half3 topLightColor = diffuseBase * topLambert * _HairTopLightColor.rgb * _HairTopLightIntensity * castShadowMask;
    finalDiffuse += topLightColor;

    // 5. 天使環與高光準備
    float3 sphereNormalWS = normalize(surface.positionWS - (_HeadPosition.xyz + float3(0, _HairAnisoPosition, 0)));
    float3 cameraRightWS = UNITY_MATRIX_V[0].xyz; 
    float3 sphereBitangentWS = normalize(cross(sphereNormalWS, cameraRightWS));
    
    // ZMD 邏輯：直接混合
    sphereNormalWS = lerp(sphereNormalWS, surface.normalWS, 0.25);

    // ZMD 邏輯：前後髮共用 _HeadForward 假光源，並計算 fresnel
    half3 halfDir = normalize(_HeadForward.xyz + surface.viewDirWS); 
    half fresnel = max(0, dot(surface.normalWS, surface.viewDirWS));
    fresnel *= fresnel;
    
    // 主高光環
    half3 anisoOffsetVec = sphereNormalWS * (anisoNoise * _HairAnisoNoise + _HairAnisoOffset);
    half3 binormal = normalize(sphereBitangentWS + anisoOffsetVec);
    half BdotH = dot(binormal, halfDir);
    half specTemp = pow(sqrt(saturate(1.0 - BdotH * BdotH)), _HairAnisoShininess);

    // 斷層副高光環
    half3 anisoOffsetCut = sphereNormalWS * (anisoNoise * _HairAnisoNoise + _HairAnisoOffset + _HairCutOffset);
    half3 binormalCut = normalize(sphereBitangentWS + anisoOffsetCut);
    half BdotHCut = dot(binormalCut, halfDir);
    half cutSpecTemp = pow(sqrt(saturate(1.0 - BdotHCut * BdotHCut)), _HairAnisoShininess * 2.0);
    half anisoCutMask = smoothstep(0.0, 0.1, cutSpecTemp);

    // 高光合成 (ZMD 邏輯：乘上 fresnel)
    half3 specBaseColor = baseColor * (1.0 - _HairSpecularOffset) * mainLight.color;
    half3 finalRingSpec = saturate(specTemp - anisoCutMask) * specBaseColor * _HairSpecularColor.rgb * (surface.specMask) * _HairSpecularIntensity * castShadowMask;

    // 標準高光 (ZMD 邏輯：使用 bitangent 而不是 tangent)
    half3 bitangentWS = normalize(cross(surface.normalWS, surface.tangentWS.xyz) * surface.tangentWS.w);
    half3 standardBinormal = normalize(bitangentWS + (surface.normalWS * (anisoNoise * _HairAnisoNoise + _HairAnisoOffset)));
    half standardBdotH = dot(standardBinormal, halfDir);
    half standardSpecTemp = pow(sqrt(saturate(1.0 - standardBdotH * standardBdotH)), _HairAnisoShininess);
    half3 standardSpec = standardSpecTemp * specBaseColor * _HairSpecularColor.rgb * surface.specMask * _HairSpecularIntensity * castShadowMask;

    // 前後髮混合
    half3 finalSpec = lerp(standardSpec, finalRingSpec, surface.frontHair);

    // 6. 間接光 (GI & Reflection)
    half3 ambient = indirectDiffuse * baseColor; // ZMD 間接漫反射沒有乘 _SpecularOffset
    half3 envSpec = 0;
    #if defined(_REFLECTION_ON)
        half3 reflectDir = reflect(-surface.viewDirWS, surface.normalWS);
        half3 envMap = GlossyEnvironmentReflection(reflectDir, surface.positionWS, _HairEnvSmoothness, 1.0);
        envSpec = envMap * specBaseColor * _HairEnvSpecularColor.rgb * _HairEnvSpecularIntensity;
    #endif

    // 7. 最終合併 (ZMD 邏輯：AO 暴力覆蓋所有漫反射與高光)
    half3 inner_rim, final_rim;
    CalculateAnimeRimLight(surface, mainLight, castShadowMask, inner_rim, final_rim);

    // 將所有直接與間接光相加後，整體乘上 occlusion (AO)
    half3 finalColor = (finalDiffuse + ambient + envSpec + finalSpec) * surface.occlusion + (final_rim * 1.5);

    return finalSpec;
}

#endif