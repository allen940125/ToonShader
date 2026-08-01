#ifndef ABYSS_CORE_INCLUDED
#define ABYSS_CORE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// ==========================================
// 全域變數區 (Global Variables) - 由 C# 腳本統一推播
// ==========================================
half4 _GlobalShadowColorBias;
float _GlobalRainIntensity;
float3 _GlobalRainDirection; 
float _GlobalDebugViewMode;

float4 _HeadForward;  
float4 _HeadPosition; 
float4 _HeadUp;
float4 _HeadRight;

// --- 剝離出的新全域變數 ---
half4  _GlobalShadowColor;
half   _GlobalShadowStrength;
half4  _GlobalAmbientColor;
half   _GlobalAmbientIntensity;
half   _GlobalMinBrightness;
float4 _RimLightDirection; 

// ==========================================
// 局部材質區 (Local Properties) - 嚴格對齊 Shader 面板
// ==========================================
CBUFFER_START(UnityPerMaterial)

    // 1. Render State
    float  _group_RenderState;
    float  _CullMode;
    float  _Transparency_Mode;
    half   _AlphaClipThreshold;
    half   _DitherThreshold;
    half   _DitherScale;

    // 2. Base Surface
    float  _group_BaseSurface;
    float4 _BaseMap_ST;         
    half4  _BaseColor;
    half   _NormalScale;
    half4  _EmissionColor;
    float4 _EmissionMap_ST;     

    // 3. Core Lighting & Shadows
    float  _group_Lighting;
    float  _UseLighting;
    half   _MainLightMultiplier;
    half   _MainLightColorWeight;
    float  _AddLightOn;
    half   _AddLightIntensity;
    half4  _ShadowTint;
    // (已剝離 _ShadowColor 與 _ShadowStrength)
    half   _ReceiveShadowIntensity;
    float  _ShadowSmoothness;

    // 4. PBR & Environment
    float  _group_PBR;
    half   _Smoothness;
    half   _Metallic;
    float  _ReflectionOn;
    half   _ReflectionIntensity;
    half   _OcclusionStrength;
    half   _IndirectLightMultiplier;
    // (已剝離 _MinBrightness, _AmbientColor, _AmbientIntensity)
    half   _DiffuseImpact;
    half   _MaxHighlightEnergy;

    // 5. Stylized Cel Shading
    float  _group_CelShading;
    float  _UseRampMode;
    half   _RampStrength;
    half4  _RampColorLight;
    half   _RampLightIntensity;
    half4  _RampColorShadow;
    half   _RampShadowIntensity;
    half   _BandThreshold;
    half   _BandSmoothness;
    half4  _BorderColor;
    half   _BorderIntensity;
    half   _BorderThreshold;
    half   _BorderWidth;
    half   _BounceIntensity;
    half4  _BounceColor;

    // 6. Highlights
    float  _group_Highlights;
    float  _SpecularIntensity;
    half4  _SpecularColor;
    half   _SpecularStep;
    half   _SpecularFeather;
    half   _AnisoPower;
    half4  _AnisoColor;
    half   _AnisoIntensity;

    // 7. Overlay & Edge Effects
    float  _group_OverlayEffects;
    float  _UseRimLight;
    // (已剝離 _RimLightDirection)
    float  _RimPosOffset;
    float  _RimDirSoftness;
    float  _UseInnerRim;
    half4  _InnerRimColor;
    half   _InnerRimPower;
    half   _InnerRimIntensity;
    half   _InnerRimBias;
    half4  _RimColor;
    half   _RimIntensity;
    half   _RimThreshold;
    half   _RimSmoothness;
    half   _RimOffsetMul;
    half   _MatCapIntensity;

    // 8. Geometry Outline
    float  _group_GeometryOutline;
    float  _UseOutline;
    float  _OutlineWidth;
    half4  _OutlineColor;

    // 9. Weather System
    float  _group_Weather;
    float  _UseWetness;
    float  _LocalWetness;
    float  _WetDirThreshold;
    float  _WetDirContrast;
    float  _WetDarkenIntensity;
    float  _WetSmoothnessMax;
    half   _GlobalPorosity;
    float  _WetSpecularIntensity;
    float  _WetNormalFlatten;
    float  _RaindropScale;
    float  _RaindropSpeed;

    // 10. Cloth Specific
    float  _group_Cloth;
    half   _BaseColorContrast;
    half4  _GradientColor;
    half   _GradientMinY;
    half   _GradientMaxY;
    half   _RoughnessNonMetal;
    half   _RoughnessMetal;
    half   _RoughnessContrast;
    half   _AOOffset;
    half   _AOContrast;
    half   _SpecShininess;
    half4  _EnvSpecularColor;
    half   _EnvSpecularIntensity;
    half   _EnvSmoothness;

    // ==========================================
    // 11. Face Specific (臉部專屬特化區塊)
    // ==========================================
    float  _group_Face;
    float  _group_Skin;

    half4  _SkinSecondColor;
    half4  _SkinDarkColor;
    half4  _SkinShadowColor;
    half   _SkinShadowStrength;
    half   _SkinAO_Offset;

    float  _FaceSimpleMode;
    half   _FaceSoftShadow;

    half   _FresnelBias;        // Skin 專屬
    half   _FresnelIntensity;   // Skin 專屬
    half   _FresnelPower;       // Skin 專屬
    half   _SkinSpecShininess;      // Skin 專屬

    // 12. Hair Specific
    float  _group_Hair;
    float4 _HairLineMap_ST;          
    float4 _AnisoMap_ST;             
    half4  _HairSecondColor;
    half4  _HairTopLightColor;
    half   _HairTopLightOffset;
    half   _HairTopLightIntensity;
    half   _HairAOOffset;
    half4  _HairSpecularColor;
    half   _HairSpecularOffset;
    half   _HairSpecularIntensity;
    half   _HairAnisoNoise;
    half   _HairAnisoShininess;
    half   _HairAnisoOffset;
    half   _HairAnisoPosition;
    half   _HairCutOffset;
    half4  _HairEnvSpecularColor;
    half   _HairEnvSpecularIntensity;
    half   _HairEnvSmoothness;

CBUFFER_END

TEXTURE2D(_BaseMap);
TEXTURE2D(_RampMap);
TEXTURE2D(_DitherMap);
TEXTURE2D(_NormalMap);
TEXTURE2D(_MatCapMap);
TEXTURE2D(_EmissionMap);
TEXTURE2D(_MaskMap);
TEXTURE2D(_RaindropMap);
TEXTURE2D(_HairLineMap);
TEXTURE2D(_AnisoMap);

// 【新增】：臉部特化專用貼圖
TEXTURE2D(_FaceColorMask);
TEXTURE2D(_FaceSDF);
TEXTURE2D(_FaceLipSpecMask);

SAMPLER(sampler_BaseMap);
SAMPLER(sampler_DitherMap);
SAMPLER(sampler_NormalMap);
SAMPLER(sampler_FaceSDF);


// ==============================================================================
// 2. 標準化資料總線：AbyssSurfaceData
// 邏輯目的：作為 Fragment Shader 中各個特效模組 (Effect Blocks) 之間唯一允許傳遞的資料結構。
// 避免變數在不同 Include 檔案中全域污染。
// ==============================================================================
struct AbyssSurfaceData
{
    half3 albedo;       // 最終基礎反射率
    half  alpha;        // 不透明度
    float2 uv;          // 【新增】：提供光照模組取樣特化貼圖 (如髮絲、噪點、MatCap)
    float3 normalWS;    // 世界空間法線
    float3 viewDirWS;   // 世界空間視角方向
    float3 positionWS;  // 世界空間座標
    float3 positionOS;  // 物件空間座標
    half3 emission;     // 自發光
    float4 tangentWS;   // 世界空間切線

    half metallic;      // 金屬度
    half smoothness;    // 平滑度
    half occlusion;     // 環境遮蔽
    
    // --- 頭髮特化遮罩 ---
    half specMask;      // 【新增】：頭髮專用高光遮罩 (決定哪裡可以產生天使環)
    half frontHair;     // 【新增】：前後髮分層遮罩 (用來處理瀏海半透明與高光覆蓋)
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
    float3 positionOS   : TEXCOORD2;
    float3 normalWS     : NORMAL;      // 世界空間法線
    float4 tangentWS    : TANGENT;     // 世界空間切線 (xyz 為方向，w 仍為符號以供後續計算副切線)
    float4 screenPos : TEXCOORD5;
    UNITY_VERTEX_INPUT_INSTANCE_ID 
};

#endif