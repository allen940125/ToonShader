#ifndef ABYSS_PASS_SHADOW_INCLUDED
#define ABYSS_PASS_SHADOW_INCLUDED

#include "Core/AbyssCore.hlsl"
#include "Core/AbyssPass_Utilities.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

Varyings vert_shadow(Attributes input)
{
    Varyings output = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    
    // 【新增】：取得陰影光源方向
    float3 lightDirectionWS = _MainLightPosition.xyz;
    // 將頂點往遠離光源的方向推移，徹底消除角色自己遮自己的破圖黑斑
    float3 shiftedPositionWS = output.positionWS - (lightDirectionWS * _CharGlobalShadowBias);

    // 陰影偏移處理
    float3 positionWS = ApplyShadowBias(shiftedPositionWS, output.normalWS, lightDirectionWS);
    output.positionHCS = TransformWorldToHClip(positionWS);
    
    #if UNITY_REVERSED_Z
    output.positionHCS.z = min(output.positionHCS.z, output.positionHCS.w * UNITY_NEAR_CLIP_VALUE);
    #else
    output.positionHCS.z = max(output.positionHCS.z, output.positionHCS.w * UNITY_NEAR_CLIP_VALUE);
    #endif

    output.screenPos = ComputeScreenPos(output.positionHCS);
    return output;
}

half4 frag_shadow(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    
    half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
    DoTransparencyClip(alpha, input.screenPos.xy / input.screenPos.w);
    
    return 0;
}
#endif