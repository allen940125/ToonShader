#ifndef ABYSS_PASS_EYE_FORWARD_INCLUDED
#define ABYSS_PASS_EYE_FORWARD_INCLUDED

#include "AbyssCore.hlsl"
#include "AbyssSurfaceSetup.hlsl"
#include "AbyssPass_Utilities.hlsl"
#include "Effect_Lighting.hlsl" 

// 【修正】：頂部不再需要宣告任何變數，全部交由 AbyssCore.hlsl 統一管理

Varyings vert_forward(Attributes input)
{
    Varyings output = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.positionOS = input.positionOS.xyz;
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    
    real sign = input.tangentOS.w * GetOddNegativeScale();
    output.tangentWS = float4(TransformObjectToWorldDir(input.tangentOS.xyz), sign);
    
    output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
    
    return output;
}

half4 frag_forward(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    
    AbyssSurfaceData surface;
    InitializeSurfaceData(input, surface);
    
    // 【眼球特化】：視差偏移 (Parallax) 運算
    half2 uvMask = abs(input.uv - half2(0.5, 0.5)) * _SphereMaskRange;
    half dist = length(uvMask);
    half sphereMask = saturate(1.0 - dist * dist);

    half3 tangentWS = normalize(input.tangentWS.xyz);
    half3 bitangentWS = normalize(cross(surface.normalWS, tangentWS) * input.tangentWS.w);
    half3x3 TBN = half3x3(tangentWS, bitangentWS, surface.normalWS);
    
    float3 tanViewdir = normalize(mul(TBN, surface.viewDirWS));
    float2 para_offset = (tanViewdir.xy / (tanViewdir.z + 0.42f)) * _Parallax * sphereMask;
    
    // 重新採樣帶有視差偏移的基礎貼圖
    half4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv + para_offset);
    surface.albedo = baseColor.rgb;
    surface.alpha = baseColor.a;

    // =======================================================
    // 眼球特化 MatCap (基於假球體法線)
    // =======================================================
    half2 centeredUV = (input.uv - 0.5) * 2.0;
    half sphereZ = sqrt(max(0.0, 1.0 - dot(centeredUV, centeredUV)));
    half3 fakeNormalTS = normalize(half3(centeredUV.x, centeredUV.y, sphereZ));
    half3 fakeNormalWS = normalize(mul(fakeNormalTS, TBN));
    half3 fakeNormalVS = normalize(mul((float3x3)GetWorldToViewMatrix(), fakeNormalWS));
    
    // 【修正】：因為是 NoScaleOffset，直接映射到 0~1 空間，不用 _ST
    half2 matcapUV = fakeNormalVS.xy * 0.5 + 0.5;
    
    // 【修正】：統一使用 _MatCapMap 與 _MatCapIntensity
    half3 matcapColor = SAMPLE_TEXTURE2D(_MatCapMap, sampler_LinearClamp, matcapUV).rgb * _MatCapIntensity;
    
    // =======================================================
    // 呼叫中央光照引擎
    // =======================================================
    float4 shadowCoord = TransformWorldToShadowCoord(surface.positionWS);
    Light mainLight = GetMainLight(shadowCoord);
    
    half3 finalColor = surface.albedo;
    #if defined(_USE_LIGHTING)
        // 觸發 ABYSS_MATERIAL_EYE 分支 (Lighting_Eye.hlsl)
        finalColor = ComputeFinalLighting(surface, mainLight, 1.0);
    #endif

    finalColor += matcapColor;

    return half4(finalColor, surface.alpha);
}
#endif