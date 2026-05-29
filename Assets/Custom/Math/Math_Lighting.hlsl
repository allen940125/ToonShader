#ifndef MATH_LIGHTING_INCLUDED
#define MATH_LIGHTING_INCLUDED

// 純數學：給入法線、燈光方向、燈光顏色、陰影衰減，吐出漫反射顏色
inline half3 CalculateLambertDiffuse(float3 normalWS, float3 lightDirWS, half3 lightColor, float shadowAtten)
{
    float NdotL = saturate(dot(normalWS, lightDirWS));
    return lightColor * NdotL * shadowAtten;
}

#endif