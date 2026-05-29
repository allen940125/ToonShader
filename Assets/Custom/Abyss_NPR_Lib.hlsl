#ifndef ABYSS_NPR_LIB_INCLUDED
#define ABYSS_NPR_LIB_INCLUDED

// ==========================================
// 統一化卡通遮罩運算 (Unified Toon Mask)
// 物理真相：計算 Half-Lambert 並根據指定的閾值與平滑度進行截斷。
// 適用於：1階、2階、3階陰影的邊界判定。
// ==========================================
inline half CalculateAbyssToonMask(float3 normalWS, float3 lightDirWS, half threshold, half smoothness)
{
    // 將內積 [-1, 1] 映射至線性空間 [0, 1]
    half halfLambert = dot(normalWS, lightDirWS) * 0.5 + 0.5;
    
    // 數學硬切：threshold 為明暗交界的絕對中心點
    return smoothstep(threshold - smoothness, threshold + smoothness, halfLambert);
}

// ==========================================
// 貼圖欺騙模式 (Texture Ramp-Shade UV)
// ==========================================
inline float CalculateAbyssRampUV(float3 normalWS, float3 lightDirWS)
{
    return dot(normalWS, lightDirWS) * 0.5 + 0.5; 
}

#endif // ABYSS_NPR_LIB_INCLUDED