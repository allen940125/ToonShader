#ifndef EFFECT_MATCAP_INCLUDED
#define EFFECT_MATCAP_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

inline void ApplyMatCap(inout AbyssSurfaceData surface)
{
    // 1. 【關鍵修正】使用逐像素的觀察向量，而非攝影機鏡頭朝向
    float3 viewDir = surface.viewDirWS; 
    
    // 2. 世界基準上方向
    float3 worldUp = float3(0.0, 1.0, 0.0);
    
    // 3. 【防呆機制】防止萬向鎖 (Gimbal Lock)
    // 當攝影機從正上方或正下方俯視/仰視物件時，viewDir 與 worldUp 平行
    // 外積會得到 0，導致畫面變成全黑 (NaN)。此時強制切換基準軸。
    if (abs(viewDir.y) > 0.999)
    {
        worldUp = float3(0.0, 0.0, 1.0);
    }
    
    // 4. 重建絕對穩定的視圖 X 軸 (Right) 與 Y 軸 (Up)
    float3 viewRight = normalize(cross(worldUp, viewDir));
    float3 viewUp = normalize(cross(viewDir, viewRight));
    
    // 5. 將世界空間法線投影到這個穩定的自訂平面上
    float2 viewNormalXY;
    viewNormalXY.x = dot(viewRight, surface.normalWS);
    viewNormalXY.y = dot(viewUp, surface.normalWS);
    
    // 6. 映射到 0~1 的 UV 空間
    float2 matcapUV = viewNormalXY * 0.5 + 0.5;
    
    // 7. 邊緣保護計算
    float radiusSqr = dot(viewNormalXY, viewNormalXY);
    half4 matcapColor = SAMPLE_TEXTURE2D(_MatCapMap, sampler_BaseMap, matcapUV);
    half edgeMask = saturate((1.0 - radiusSqr) * 10.0);
    matcapColor.rgb *= edgeMask;
    
    // 8. 疊加輸出
    surface.emission += matcapColor.rgb;
}

#endif