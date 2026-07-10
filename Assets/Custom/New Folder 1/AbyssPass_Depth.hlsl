#ifndef ABYSS_PASS_DEPTH_INCLUDED
#define ABYSS_PASS_DEPTH_INCLUDED

#include "AbyssCore.hlsl"
#include "AbyssPass_Utilities.hlsl"

Varyings vert_depth(Attributes input)
{
    Varyings output = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
    output.screenPos = ComputeScreenPos(output.positionHCS);
    
    return output;
}

half4 frag_depth(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    
    half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
    DoTransparencyClip(alpha, input.screenPos.xy / input.screenPos.w);
    
    return 0;
}
#endif