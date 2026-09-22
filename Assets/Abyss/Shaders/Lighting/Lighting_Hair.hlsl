#ifndef LIGHTING_HAIR_INCLUDED
#define LIGHTING_HAIR_INCLUDED

#include "Lighting_Utilities.hlsl"

inline half3 ComputeLighting_Hair(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    // 1. 讀取貼圖與基底色
    half hairLine = SAMPLE_TEXTURE2D(_HairLineMap, sampler_BaseMap, surface.uv * _HairLineMap_ST.xy + _HairLineMap_ST.zw).r;
    half anisoNoiseTex = SAMPLE_TEXTURE2D(_AnisoMap, sampler_BaseMap, surface.uv * _AnisoMap_ST.xy + _AnisoMap_ST.zw).r;
    half anisoNoise = anisoNoiseTex * 2.0 - 1.0;

    half3 baseColor = lerp(surface.albedo, surface.albedo * _HairSecondColor.rgb, hairLine);
    half3 diffuseBase = baseColor * _HairSpecularOffset;

    // ==========================================
    // 【核心修正 1】：全域陰影染色 (同步 DayNightSystemPro)
    // ==========================================
    half shadowAtten = lerp(1.0, castShadowMask, _GlobalShadowStrength);
    half3 globalShadowTint = lerp(_GlobalShadowColor.rgb, half3(1.0, 1.0, 1.0), shadowAtten);

    // 2. 漫反射與 Ramp 混合
    float NdotL = dot(surface.normalWS, mainLight.direction);
    half halfLambert = min((NdotL * 0.5 + 0.5), shadowAtten); 
    
    half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_LinearClamp, float2(halfLambert, 0.5)).rgb;
    half3 rawDiffuse = diffuseBase * mainLight.color;
    
    half3 softLightDiffuse = (1.0 - 2.0 * rampColor) * rawDiffuse * rawDiffuse + 2.0 * rampColor * rawDiffuse;
    
    // 拔除結尾錯誤的 * castShadowMask，改乘上全域陰影濾鏡，確保陰影有顏色而不是死黑
    half3 finalDiffuse = lerp(rawDiffuse, softLightDiffuse, _RampStrength) * globalShadowTint;

    // 3. 頭頂假光 (受控於陰影)
    half topNdotL = dot(surface.normalWS, _HeadUp.xyz);
    half topLambert = saturate(topNdotL * 0.5 + 0.5 + _HairTopLightOffset);
    half3 topLightColor = diffuseBase * topLambert * _HairTopLightColor.rgb * _HairTopLightIntensity * shadowAtten;
    finalDiffuse += topLightColor;

    // ==========================================
    // 4. 天使環與高光 (杜絕噪點的純淨法線運算)
    // ==========================================
    // 完全依賴虛擬球心法線，不混入帶有凹凸細節的 surface.normalWS，徹底消除高光噪點
    float3 sphereNormalWS = normalize(surface.positionWS - (_HeadPosition.xyz + float3(0, _HairAnisoPosition, 0)));
    float3 cameraRightWS = UNITY_MATRIX_V[0].xyz; 
    float3 sphereBitangentWS = normalize(cross(sphereNormalWS, cameraRightWS));
    
    half3 halfDir = normalize(_HeadForward.xyz + surface.viewDirWS); 
    
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

    // 高光合成
    half3 specBaseColor = baseColor * (1.0 - _HairSpecularOffset) * mainLight.color;
    
    // 【核心修正】：重新引入 Fresnel 控制高光邊緣衰減，避免高光像塑膠貼紙一樣死硬
    half viewFresnel = saturate(dot(sphereNormalWS, surface.viewDirWS));
    viewFresnel *= viewFresnel; // 強化邊緣衰減
    
    half3 finalRingSpec = saturate(specTemp - anisoCutMask) * specBaseColor * _HairSpecularColor.rgb * surface.specMask * _HairSpecularIntensity * shadowAtten * viewFresnel;

    // 前後髮混合 (如果你沒有分離 standardSpec，直接使用 finalRingSpec)
    half3 finalSpec = finalRingSpec; 

    // ==========================================
    // 5. 間接光 (GI & Reflection)
    // ==========================================
    half ambientLum = Luminance(indirectDiffuse);
    half3 cleanAmbient = half3(ambientLum, ambientLum, ambientLum);
    half3 ambient = cleanAmbient * baseColor; 
    
    half3 envSpec = 0;
    #if defined(_REFLECTION_ON)
    half3 reflectDir = reflect(-surface.viewDirWS, sphereNormalWS); // 同樣改用平滑法線取樣反射
    half3 envMap = GlossyEnvironmentReflection(reflectDir, surface.positionWS, _HairEnvSmoothness, 1.0);
    envSpec = envMap * specBaseColor * _HairEnvSpecularColor.rgb * _HairEnvSpecularIntensity;
    #endif

    // 先將主體光照合併，並乘上 AO
    half3 finalColor = (finalDiffuse + ambient + envSpec + finalSpec) * surface.occlusion;

    // ==========================================
    // 6. 專為頭髮特化的安全 Rim Light (杜絕破碎與過曝)
    // ==========================================
    half3 finalRim = 0;
    if (_UseRimLight > 0.5)
    {
        // 1. 基底 Fresnel (使用球形法線，避免髮絲面片造成的破碎閃爍)
        half rimNdotV = 1.0 - saturate(dot(sphereNormalWS, surface.viewDirWS));
        half rimFresnel = saturate(pow(rimNdotV, _InnerRimPower));
        
        // 2. 光源方向遮罩
        float3 rimLightDir = normalize(_RimLightDirection.xyz);
        float rimNdotL = dot(sphereNormalWS, rimLightDir);
        float rimDirMask = smoothstep(_RimPosOffset - _RimDirSoftness, _RimPosOffset + _RimDirSoftness, rimNdotL);
        
        // 3. 絕對陰影阻斷 (頭髮投影處絕對不允許發光)
        float rimShadowMask = smoothstep(0.01, 0.1, castShadowMask);
        
        // 4. 頭髮專屬遮罩 (利用 specMask 避免頭髮內層不合理發光)
        float finalRimMask = rimFresnel * rimDirMask * rimShadowMask * surface.specMask * _InnerRimIntensity;
        
        half3 rimColor = (_InnerRimColor.rgb + baseColor) * 0.5;
        // 能量受限於主光與環境光，杜絕夜晚發光
        finalRim = rimColor * finalRimMask * max(mainLight.color, cleanAmbient);
    }

    // 使用 Screen (濾色) 疊加 Rim Light
    finalColor = 1.0 - (1.0 - saturate(finalColor)) * (1.0 - saturate(finalRim));

    return finalColor;
}
#endif