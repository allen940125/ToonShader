#ifndef ABYSS_CORE_INCLUDED
#define ABYSS_CORE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
// DOTS 實例化支援（若專案採用 ECS 架構則需取消註解）
//#include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

// ==============================================================================
// 1. 統一的 CBUFFER (Constant Buffer)
// 邏輯目的：將所有材質屬性打包至 UnityPerMaterial 區塊中。
// 嚴格規範：這是觸發 SRP Batcher 的必要條件。若變數宣告在 CBUFFER 之外，
// 將導致 Draw Call 無法合併，嚴重影響渲染效能。
// ==============================================================================
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;     // 貼圖的 Tiling (xy) 與 Offset (zw)
    half4  _BaseColor;      // 基礎顏色 (half 精度足以應付色彩數據，節省暫存器)

    // 法線參數
    float _NormalScale;     // 法線強度 (float 確保純量計算精度)

    // 環境光控制參數
    half _MinBrightness;
    half _IndirectLightMultiplier;

    // 陰影參數
    half4 _ShadowTint;      // 陰影染色
    float _BandThreshold;   // 卡通渲染的明暗交界閾值
    float _BandSmoothness;  // 邊緣平滑度
    float _ShadowIntensity; // 陰影濃度

    // 邊緣光 (Fresnel) 參數
    half4  _FresnelColor;
    float  _FresnelPower;   // 邊緣光衰減指數
    
    // 描邊 (Outline) 參數
    float  _OutlineWidth;
    half4  _OutlineColor;

    // 各向異性高光 (Anisotropic Highlight) 參數
    float  _AnisoPower;
    half4  _AnisoColor;
CBUFFER_END

// 紋理與採樣器分離宣告
// 邏輯目的：允許不同紋理共用同一個取樣器 (Sampler) 以突破硬體取樣器數量上限。
TEXTURE2D(_BaseMap);
TEXTURE2D(_NormalMap);
TEXTURE2D(_MatCapMap);
SAMPLER(sampler_BaseMap);
SAMPLER(sampler_NormalMap); // 保留獨立取樣器：法線貼圖通常需要線性 (Linear) 且無 Mipmap 過濾，與 BaseMap 可能不同。

// ==============================================================================
// 2. 標準化資料總線：AbyssSurfaceData
// 邏輯目的：作為 Fragment Shader 中各個特效模組 (Effect Blocks) 之間唯一允許傳遞的資料結構。
// 避免變數在不同 Include 檔案中全域污染。
// ==============================================================================
struct AbyssSurfaceData
{
    half3 albedo;       // 最終基礎反射率
    half  alpha;        // 不透明度
    float3 normalWS;    // 世界空間法線 (World Space Normal)
    float3 viewDirWS;   // 世界空間視角方向 (由頂點指向攝影機)
    float3 positionWS;  // 世界空間座標
    half3 emission;     // 自發光/附加光貢獻 (如 Rim Light 會累加於此)
    float3 tangentWS;   // 世界空間切線 (供各向異性高光等依賴切線空間的特效使用)
};

// ==============================================================================
// 3. 頂點與片元傳輸結構 (資料從 CPU -> VS -> PS 的流向)
// ==============================================================================

// VS（Vertex Shader）輸入結構
// 讀取自 Mesh 的頂點緩衝區 (Vertex Buffer)
struct Attributes 
{
    float4 positionOS   : POSITION;  // 物件空間頂點座標
    float2 uv           : TEXCOORD0; // 第一組 UV
    float3 normalOS     : NORMAL;    // 物件空間法線
    float4 tangentOS    : TANGENT;   // 物件空間切線 (w 分量儲存副切線方向符號，用於處理鏡像 UV)
    UNITY_VERTEX_INPUT_INSTANCE_ID   // 支援 GPU Instancing 的宏
};

// VS 輸出 / PS（Fragment Shader）輸入結構
// 由硬體光柵化器 (Rasterizer) 進行線性插值 (Interpolation) 後傳入 PS
struct Varyings
{
    float4 positionHCS  : SV_POSITION; // 齊次裁剪空間座標 (Homogeneous Clip Space)
    float2 uv           : TEXCOORD0;   
    float3 positionWS   : TEXCOORD1;   // 世界空間座標
    float3 normalWS     : NORMAL;      // 世界空間法線
    float4 tangentWS    : TANGENT;     // 世界空間切線 (xyz 為方向，w 仍為符號以供後續計算副切線)
    UNITY_VERTEX_INPUT_INSTANCE_ID 
};

#endif