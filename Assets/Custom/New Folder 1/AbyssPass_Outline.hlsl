#ifndef ABYSS_PASS_OUTLINE_INCLUDED
#define ABYSS_PASS_OUTLINE_INCLUDED

#include "AbyssCore.hlsl"
#include "AbyssPass_Utilities.hlsl"
#include "Effect_Outline.hlsl"

Varyings vert_outline(Attributes input)
{
    Varyings output = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    
    #if defined(_USE_OUTLINE)
        float positionVS_Z = TransformWorldToView(output.positionWS).z;
        float outlineMultiplier = GetOutlineCameraFovAndDistanceFixMultiplier(positionVS_Z);
        float finalOutlineWidth = _OutlineWidth * outlineMultiplier;
        float3 posOS = input.positionOS.xyz + input.normalOS * finalOutlineWidth;
        output.positionHCS = TransformObjectToHClip(posOS);
    #else
        output.positionHCS = float4(0, 0, 0, 0);
    #endif

    output.screenPos = ComputeScreenPos(output.positionHCS);
    return output;
}

half4 frag_outline(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    
    half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
    DoTransparencyClip(alpha, input.screenPos.xy / input.screenPos.w);
    
    return _OutlineColor;
}
#endif