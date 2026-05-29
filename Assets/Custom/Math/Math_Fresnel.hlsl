#ifndef MATH_FRESNEL_INCLUDED
#define MATH_FRESNEL_INCLUDED

// 純數學：給入法線、視角、強度、顏色，它只負責吐出算好的發光數值
inline half3 CalculateFresnelGlow(float3 normalWS, float3 viewDirWS, float power, half3 color)
{
    float NdotV = saturate(dot(normalWS, viewDirWS));
    float fresnelTerm = pow(1.0 - NdotV, power);
    return fresnelTerm * color;
}

#endif