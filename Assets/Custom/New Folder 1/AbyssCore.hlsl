#ifndef ABYSS_CORE_INCLUDED
#define ABYSS_CORE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

half4 _GlobalShadowColorBias;   
float _GlobalRainIntensity;
float3 _GlobalRainDirection; 

CBUFFER_START(UnityPerMaterial)

    // ==========================================
    // 嚴格依照 Properties 的宣告順序排列 (含 UI 群組變數)
    // 向量 (4維) 必須優先宣告，以確保記憶體對齊
    // ==========================================

    // --- 貼圖 ST 變數 (4 維) ---
    float4 _BaseMap_ST;         
    float4 _EmissionMap_ST;     

    // --- Color 變數 (4 維) ---
    half4  _BaseColor;          
    half4  _EmissionColor;      
    half4  _ShadowTint;         
    half4  _AmbientColor;       
    half4  _RampColorLight;     
    half4  _RampColorShadow;    
    half4  _BorderColor;
    half4  _BounceColor;
    half4  _SpecularColor;      
    half4  _AnisoColor;         
    half4  _FresnelColor;
    half4  _RimColor;  
    half4  _OutlineColor;       

    // ==========================================
    // 標量區塊 (Float / Range / Toggle)
    // 嚴格依照 Properties 的由上往下順序
    // ==========================================

    // 1. Render State
    float  _group_RenderState;
    float  _CullMode;           
    float  _Transparency_Mode;  
    half   _AlphaClipThreshold; 
    half   _DitherThreshold;    
    half   _DitherScale;        

    // 2. Base Surface
    float  _group_BaseSurface;
    half   _NormalScale;        

    // 3. Lighting
    float  _group_Lighting;
    float  _UseLighting;        
    half   _MainLightMultiplier;
    half   _MainLightColorWeight;
    float  _AddLightOn;         
    half   _AddLightIntensity;  
    half   _ReceiveShadowIntensity;
    float  _ShadowSmoothness;

    // 4. PBR
    float  _group_PBR;
    half   _Smoothness;         
    half   _Metallic;           
    float  _ReflectionOn;       
    half   _ReflectionIntensity;
    half   _OcclusionStrength;
    half   _IndirectLightMultiplier; 
    half   _MinBrightness;      
    half   _DiffuseImpact;
    half   _MaxHighlightEnergy;
    half   _AmbientIntensity;

    // 5. Cel Shading
    float  _group_CelShading;
    float  _UseRampMode;
    half   _RampLightIntensity;
    half   _RampShadowIntensity;
    half   _BandThreshold;      
    half   _BandSmoothness;     
    half   _BorderIntensity;
    half   _BorderThreshold;    
    half   _BorderWidth;        
    half   _BounceIntensity;

    // 6. Highlights
    float  _group_Highlights;
    float  _SpecularIntensity;    
    half   _SpecularStep;       
    half   _SpecularFeather;    
    half   _AnisoPower;         
    half   _AnisoIntensity;

    // 7. Overlay
    float  _group_OverlayEffects;
    half   _FresnelPower;       
    half   _FresnelIntensity;   
    float  _UseRimLight;
    half   _RimPower;
    half   _RimThreshold;       
    half   _RimSmoothness;      
    half   _RimShadowMask;
    half   _MatCapIntensity;    

    // 8. Geometry Outline
    float  _group_GeometryOutline;
    float  _UseOutline;         
    float  _OutlineWidth;       

    // 9. Weather
    float  _group_Weather;
    float  _UseWetness;
    float  _LocalWetness;
    float  _WetDirThreshold;
    float  _WetDirContrast;
    float  _WetDarkenIntensity;
    float  _WetSmoothnessMax;

    float  _WetSpecularIntensity;
    float  _WetNormalFlatten;

    float  _RaindropScale;
    float  _RaindropSpeed;

    half   _GlobalPorosity;
CBUFFER_END

TEXTURE2D(_BaseMap);
TEXTURE2D(_RampMap);
TEXTURE2D(_DitherMap);
TEXTURE2D(_NormalMap);
TEXTURE2D(_MatCapMap);
TEXTURE2D(_EmissionMap);
TEXTURE2D(_MaskMap);
TEXTURE2D(_RaindropMap);

SAMPLER(sampler_BaseMap);
SAMPLER(sampler_DitherMap);
SAMPLER(sampler_NormalMap);

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
    float4 tangentWS;   // 世界空間切線 (供各向異性高光等依賴切線空間的特效使用)

    half metallic;
    half smoothness;
    half occlusion;
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
    float4 screenPos : TEXCOORD5;
    UNITY_VERTEX_INPUT_INSTANCE_ID 
};

#endif