#ifndef LIGHTING_HAIR_INCLUDED
#define LIGHTING_HAIR_INCLUDED

#include "Lighting_Utilities.hlsl"

inline half3 ComputeLighting_Hair(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    // 1. 讀取貼圖與基底色
    half hairLine = SAMPLE_TEXTURE2D(_HairLineMap, sampler_BaseMap, surface.uv * _HairLineMap_ST.xy + _HairLineMap_ST.zw).r;
    
    // 【毛躁源頭 1：原始噪點貼圖】
    // 若 _AnisoMap 的 Tiling 設得太高，或是貼圖被嚴重壓縮，這裡讀出來的數值就會是碎裂的馬賽克
    half anisoNoiseTex = SAMPLE_TEXTURE2D(_AnisoMap, sampler_BaseMap, surface.uv * _AnisoMap_ST.xy + _AnisoMap_ST.zw).r;
    half anisoNoise = anisoNoiseTex * 2.0 - 1.0;

    // ▶ 除錯 1：解除下方註解，檢查貼圖的原始雜訊。若畫面呈現極細碎的黑白沙粒，調低 Tiling 或檢查貼圖壓縮。
    // return half3(anisoNoiseTex, anisoNoiseTex, anisoNoiseTex);

    half3 baseColor = lerp(surface.albedo, surface.albedo * _HairSecondColor.rgb, hairLine);
    half3 diffuseBase = baseColor * _HairSpecularOffset;

    half shadowAtten = lerp(1.0, castShadowMask, _GlobalShadowStrength);
    half3 globalShadowTint = lerp(_GlobalShadowColor.rgb, half3(1.0, 1.0, 1.0), shadowAtten);

    float NdotL = dot(surface.normalWS, mainLight.direction);
    half halfLambert = min((NdotL * 0.5 + 0.5), shadowAtten); 
    
    half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_LinearClamp, float2(halfLambert, 0.5)).rgb;
    half3 rawDiffuse = diffuseBase * mainLight.color;
    half3 softLightDiffuse = (1.0 - 2.0 * rampColor) * rawDiffuse * rawDiffuse + 2.0 * rampColor * rawDiffuse;
    half3 finalDiffuse = lerp(rawDiffuse, softLightDiffuse, _RampStrength) * globalShadowTint;

    half topNdotL = dot(surface.normalWS, _HeadUp.xyz);
    half topLambert = saturate(topNdotL * 0.5 + 0.5 + _HairTopLightOffset);
    half3 topLightColor = diffuseBase * topLambert * _HairTopLightColor.rgb * _HairTopLightIntensity * shadowAtten;
    finalDiffuse += topLightColor;

    // ==========================================
    // 4. 天使環與高光
    // ==========================================
    float3 sphereNormalWS = normalize(surface.positionWS - (_HeadPosition.xyz + float3(0, _HairAnisoPosition, 0)));
    float3 cameraRightWS = UNITY_MATRIX_V[0].xyz; 
    float3 sphereBitangentWS = normalize(cross(sphereNormalWS, cameraRightWS));
    
    half3 halfDir = normalize(_HeadForward.xyz + surface.viewDirWS); 
    
    // 【毛躁源頭 2：扭曲後的法線向量】
    // anisoNoise 乘上 _HairAnisoNoise 強度後，硬生生把球形法線推歪。強度越大，毛躁感越重。
    half3 anisoOffsetVec = sphereNormalWS * (anisoNoise * _HairAnisoNoise + _HairAnisoOffset);
    half3 binormal = normalize(sphereBitangentWS + anisoOffsetVec);

    // ▶ 除錯 2：解除下方註解，檢查最終的副切線方向。若顏色呈現劇烈的雜訊鋸齒，必須立刻調低面版上的 _HairAnisoNoise。
    // return binormal * 0.5 + 0.5;

    half BdotH = dot(binormal, halfDir);
    
    // 【毛躁源頭 3：高光能量收束】
    // _HairAnisoShininess 越高，高光越細越銳利，這會將前面的法線雜訊無限放大。
    half specTemp = pow(sqrt(saturate(1.0 - BdotH * BdotH)), _HairAnisoShininess);

    // ▶ 除錯 3：解除下方註解，觀看純粹的高光形狀。
    // return half3(specTemp, specTemp, specTemp);

    half3 anisoOffsetCut = sphereNormalWS * (anisoNoise * _HairAnisoNoise + _HairAnisoOffset + _HairCutOffset);
    half3 binormalCut = normalize(sphereBitangentWS + anisoOffsetCut);
    half BdotHCut = dot(binormalCut, halfDir);
    half cutSpecTemp = pow(sqrt(saturate(1.0 - BdotHCut * BdotHCut)), _HairAnisoShininess * 2.0);
    half anisoCutMask = smoothstep(0.0, 0.1, cutSpecTemp);

    half3 specBaseColor = baseColor * (1.0 - _HairSpecularOffset) * mainLight.color;
    half viewFresnel = saturate(dot(sphereNormalWS, surface.viewDirWS));
    viewFresnel *= viewFresnel; 
    
    half3 finalRingSpec = saturate(specTemp - anisoCutMask) * specBaseColor * _HairSpecularColor.rgb * surface.specMask * _HairSpecularIntensity * shadowAtten * viewFresnel;
    half3 finalSpec = finalRingSpec; 

    // ==========================================
    // 5. 間接光 (GI & Reflection)
    // ==========================================
    half ambientLum = Luminance(indirectDiffuse);
    half3 cleanAmbient = half3(ambientLum, ambientLum, ambientLum);
    half3 ambient = cleanAmbient * baseColor; 
    
    half3 envSpec = 0;
    #if defined(_REFLECTION_ON)
    half3 reflectDir = reflect(-surface.viewDirWS, sphereNormalWS);
    half3 envMap = GlossyEnvironmentReflection(reflectDir, surface.positionWS, _HairEnvSmoothness, 1.0);
    envSpec = envMap * specBaseColor * _HairEnvSpecularColor.rgb * _HairEnvSpecularIntensity;
    #endif

    half3 finalColor = (finalDiffuse + ambient + envSpec + finalSpec) * surface.occlusion;

    // ==========================================
    // 6. 安全 Rim Light
    // ==========================================
    half3 finalRim = 0;
    if (_UseRimLight > 0.5)
    {
        half rimNdotV = 1.0 - saturate(dot(sphereNormalWS, surface.viewDirWS));
        half rimFresnel = saturate(pow(rimNdotV, _InnerRimPower));
        
        float3 rimLightDir = normalize(_RimLightDirection.xyz);
        float rimNdotL = dot(sphereNormalWS, rimLightDir);
        float rimDirMask = smoothstep(_RimPosOffset - _RimDirSoftness, _RimPosOffset + _RimDirSoftness, rimNdotL);
        float rimShadowMask = smoothstep(0.01, 0.1, castShadowMask);
        float finalRimMask = rimFresnel * rimDirMask * rimShadowMask * surface.specMask * _InnerRimIntensity;
        
        half3 rimColor = (_InnerRimColor.rgb + baseColor) * 0.5;
        finalRim = rimColor * finalRimMask * max(mainLight.color, cleanAmbient);
    }

    finalColor = 1.0 - (1.0 - saturate(finalColor)) * (1.0 - saturate(finalRim));

    return finalColor;
}
#endif