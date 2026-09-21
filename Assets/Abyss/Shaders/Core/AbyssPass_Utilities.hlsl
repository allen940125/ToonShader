#ifndef ABYSS_PASS_UTILS_INCLUDED
#define ABYSS_PASS_UTILS_INCLUDED

#include "AbyssCore.hlsl"

// ---- 透明度裁切（合併 Alpha Clip 與 Dither） ----
inline void DoTransparencyClip(half alpha, float2 screenPos)
{
    #if defined(_TRANSPARENCY_MODE_CUTOUT)
        clip(alpha - _AlphaClipThreshold);
    #elif defined(_TRANSPARENCY_MODE_DITHER)
        float2 ditherUV = screenPos * _ScreenParams.xy / _DitherScale;
        half dither = SAMPLE_TEXTURE2D(_DitherMap, sampler_DitherMap, ditherUV).a;
        clip((alpha * _DitherThreshold) - dither);
    #endif
    // _TRANSPARENCY_MODE_OPAQUE：不執行任何裁切
}

#endif