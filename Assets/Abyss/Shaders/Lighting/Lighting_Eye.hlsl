#ifndef LIGHTING_EYE_INCLUDED
#define LIGHTING_EYE_INCLUDED

#include "Lighting_Utilities.hlsl"

inline half3 ComputeLighting_Eye(AbyssSurfaceData surface, Light mainLight, half3 indirectDiffuse, float castShadowMask)
{
    // 1. 捨棄複雜的 Lambert，確保眼球基礎底色不受多邊形起伏影響
    half3 baseColor = surface.albedo;

    // 2. 壓抑實體陰影：讓陰影最多只讓眼球變暗 20%~30%，絕對不能變成死黑
    // (如果你希望眼球完全不受瀏海陰影影響，可以直接把 shadowTint 設為 1.0)
    half shadowTint = lerp(0.8, 1.0, castShadowMask); 

    // 3. 基礎漫反射：僅受到主光顏色與強度的輕微影響
    half3 diffuseLight = baseColor * mainLight.color * shadowTint;

    // 4. 環境光 (GI)：確保在暗處眼球不會自發光，而是跟著環境變暗
    half3 ambientLight = indirectDiffuse * baseColor;

    //return half3(0,0,0);

    // 5. 輸出最終顏色 (不包含高光，高光已在 Forward Pass 的 MatCap 處理)
    return max(diffuseLight, ambientLight);
}

#endif