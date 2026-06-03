#ifndef EFFECT_FRESNEL_INCLUDED
#define EFFECT_FRESNEL_INCLUDED

// 接收標準包裹，直接修改裡面的 emission
inline void ApplyFresnel(inout AbyssSurfaceData surface)
{
    if (_FresnelIntensity <= 0.001) return;
    
    float NdotV = saturate(dot(surface.normalWS, surface.viewDirWS));
    float fresnelTerm = pow(1.0 - NdotV, _FresnelPower);
    
    // 將結果疊加到發光通道
    surface.emission += fresnelTerm * _FresnelColor.rgb;
}

#endif