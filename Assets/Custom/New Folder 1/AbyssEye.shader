Shader "Abyss/Character/Eye"
{
    Properties
    {
        // ==========================================
        // 1. Render State (系統渲染狀態)
        // ==========================================
        [Main(RenderState, _, off)] _group_RenderState ("1. Render State (系統狀態)", Float) = 0
        [SubEnum(RenderState, UnityEngine.Rendering.CullMode)] _CullMode("Cull Mode", Float) = 2.0
        [SubKeywordEnum(RenderState, Opaque, Cutout, Dither)] _Transparency_Mode("Transparency Mode", Float) = 0
        [Sub(RenderState)] _AlphaClipThreshold("Alpha Clip Threshold", Range(0.0, 1.0)) = 0.5
        [Sub(RenderState)] _DitherThreshold("Dither Threshold", Range(0, 1)) = 0.5
        [Sub(RenderState)] _DitherScale("Dither Tiling Scale", Range(1, 20)) = 10

        // ==========================================
        // 2. Base Surface (基礎表面屬性)
        // ==========================================
        [Main(BaseSurface, _, on)] _group_BaseSurface ("2. Base Surface (基礎屬性)", Float) = 0
        [Sub(BaseSurface)] [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [Sub(BaseSurface)] [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [Sub(BaseSurface)] [NoScaleOffset] [Normal] _NormalMap("Normal Map", 2D) = "bump" {}
        [Sub(BaseSurface)] _NormalScale("Normal Scale", Range(0.0, 2.0)) = 1.0
        [Sub(BaseSurface)] [HDR] _EmissionColor("Emission Color", Color) = (0,0,0,1)
        [Sub(BaseSurface)] _EmissionMap("Emission Map", 2D) = "white" {}

        // ==========================================
        // 3. Core Lighting & Shadows (光照與陰影核心)
        // ==========================================
        [Main(Lighting, _, on)] _group_Lighting ("3. Core Lighting & Shadows", Float) = 0
        [SubToggle(Lighting, _USE_LIGHTING)] _UseLighting("Enable Lighting", Float) = 1
        [Sub(Lighting)] _MainLightMultiplier("Local Main Light Multiplier", Range(0, 5)) = 1.0
        [Sub(Lighting)] _MainLightColorWeight("Main Light Color Weight", Range(0, 1)) = 1.0
        [SubToggle(Lighting, _ADD_LIGHT_ON)] _AddLightOn("Enable Additional Lights", Float) = 1
        [Sub(Lighting)] _AddLightIntensity("Additional Lights Intensity", Range(0,2)) = 1.0
        [Sub(Lighting)] _ShadowTint("Shadow Tint (Standard)", Color) = (0.93, 0.74, 0.71, 1.0)
        [Sub(Lighting)] _ReceiveShadowIntensity("Receive Shadow Intensity", Range(0.0, 1.0)) = 1.0
        [Sub(Lighting)] _ShadowSmoothness ("Shadow Smoothness", Range(0.0, 0.5)) = 0.05

        // ==========================================
        // 4. PBR & Environment (物理渲染與環境光)
        // ==========================================
        [Main(PBR, _, off)] _group_PBR ("4. PBR & Environment", Float) = 0
        [Sub(PBR)] [NoScaleOffset] _MaskMap("Mask Map (R:Met, G:AO, A:Smooth)", 2D) = "white" {}
        [Sub(PBR)] _Smoothness("Smoothness Multiplier", Range(0,1)) = 0.5
        [Sub(PBR)] _Metallic("Metallic Multiplier", Range(0,1)) = 0.0
        [SubToggle(PBR, _REFLECTION_ON)] _ReflectionOn("Enable Reflection", Float) = 1
        [Sub(PBR)] _ReflectionIntensity("Reflection Intensity", Range(0,2)) = 1.0
        [Sub(PBR)] _OcclusionStrength("Occlusion Strength", Range(0.0, 1.0)) = 1.0
        [Sub(PBR)] _IndirectLightMultiplier("GI Intensity", Range(0.0, 2.0)) = 1.0
        [Sub(PBR)] _DiffuseImpact("Diffuse Lighting Impact", Range(0.0, 2.0)) = 1.0
        [Sub(PBR)] _MaxHighlightEnergy("Max Highlight Energy", Range(1.0, 3.0)) = 1.3

        // ==========================================
        // 5. Stylized Cel Shading (卡通渲染核心設定)
        // ==========================================
        [Main(CelShading, _, on)] _group_CelShading ("5. Stylized Cel Shading", Float) = 0
        [SubEnum(CelShading, Math Mode, 0, Ramp Mode, 1)] _UseRampMode("Lighting Mode", Float) = 0
        [Sub(CelShading)] [NoScaleOffset] _RampMap("Ramp Map (1D)", 2D) = "white" {}
        [Sub(CelShading)] _RampStrength("Ramp Strength", Range(0, 1)) = 1.0
        [Sub(CelShading)] _RampColorLight("Ramp Light Color", Color) = (1.0,0.95,0.85,1)
        [Sub(CelShading)] _RampLightIntensity("Ramp Light Tint Intensity", Range(0, 1)) = 1.0
        [Sub(CelShading)] _RampColorShadow("Ramp Shadow Color", Color) = (0.55,0.6,0.7,1)
        [Sub(CelShading)] _RampShadowIntensity("Ramp Shadow Tint Intensity", Range(0, 1)) = 1.0
        [Sub(CelShading)] _BandThreshold("Light Band Threshold", Range(0.0, 1.0)) = 0.5
        [Sub(CelShading)] _BandSmoothness("Light Band Smoothness", Range(0.001, 0.5)) = 0.05
        [Sub(CelShading)] [HDR] _BorderColor("Border Color", Color) = (1, 0.3, 0.1, 1)
        [Sub(CelShading)] _BorderIntensity("Border Intensity", Range(0, 1)) = 1.0
        [Sub(CelShading)] _BorderThreshold("Border Threshold", Range(0.01, 0.99)) = 0.5
        [Sub(CelShading)] _BorderWidth("Border Width", Range(0.01, 0.5)) = 0.1
        [Sub(CelShading)] _BounceIntensity("Bounce Light Intensity", Range(0, 3)) = 1.2
        [Sub(CelShading)] [HDR] _BounceColor("Bounce Light Color", Color) = (1, 0.9, 0.8, 1)

        // ==========================================
        // 6. Highlights (高光處理)
        // ==========================================
        [Main(Highlights, _, off)] _group_Highlights ("6. Highlights", Float) = 0
        [Sub(Highlights)] _SpecularIntensity("Enable Specular", Range(0, 1)) = 0.2
        [Sub(Highlights)] [HDR] _SpecularColor("Specular Color", Color) = (1, 1, 1, 1)
        [Sub(Highlights)] _SpecularStep("Specular Step", Range(0.01, 1.0)) = 0.8
        [Sub(Highlights)] _SpecularFeather("Specular Feather", Range(0.001, 0.5)) = 0.1
        [Sub(Highlights)] _AnisoPower("Anisotropic Power", Range(1.0, 256.0)) = 64.0
        [Sub(Highlights)] [HDR] _AnisoColor("Anisotropic Color", Color) = (1,1,1,1)
        [Sub(Highlights)] _AnisoIntensity("Anisotropic Intensity", Range(0, 1)) = 0.0

        // ==========================================
        // 7. Overlay & Edge Effects (覆蓋與邊緣特效)
        // ==========================================
        [Main(OverlayEffects, _, off)] _group_OverlayEffects ("7. Overlay & Edge Effects", Float) = 0
        [SubToggle(OverlayEffects, _)] _UseRimLight("Enable Rim Light", Float) = 1
        
        // 遮罩：控制發光方向與左右側
        [Sub(OverlayEffects)] _RimPosOffset("Rim Pos Offset (左右位置偏移)", Range(-1, 1)) = 0.0
        [Sub(OverlayEffects)] _RimDirSoftness("Rim Dir Softness (方向邊緣柔度)", Range(0.01, 1)) = 0.5
        
        // 內側柔邊緣 (Inner Rim)
        [SubToggle(OverlayEffects, _)] _UseInnerRim("Enable Inner Rim (內側柔輪廓)", Float) = 1
        [Sub(OverlayEffects)] [HDR] _InnerRimColor("Inner Rim Color", Color) = (1, 1, 1, 1)
        [Sub(OverlayEffects)] _InnerRimPower("Inner Rim Power", Range(0.1, 10)) = 3.0
        [Sub(OverlayEffects)] _InnerRimIntensity("Inner Rim Intensity", Range(0, 5)) = 1.0
        [Sub(OverlayEffects)] _InnerRimBias("Inner Rim Bias", Range(0, 1)) = 0.0

        // 外側硬輪廓 (Depth Offset Rim)
        [Sub(OverlayEffects)] [HDR] _RimColor("Depth Rim Color (外側硬輪廓)", Color) = (1, 1, 1, 1)
        [Sub(OverlayEffects)] _RimIntensity("Depth Rim Intensity", Range(0, 5)) = 1.0
        [Sub(OverlayEffects)] _RimThreshold("Depth Threshold", Range(0, 1)) = 0.1
        [Sub(OverlayEffects)] _RimSmoothness("Depth Smoothness", Range(0.001, 0.1)) = 0.01
        [Sub(OverlayEffects)] _RimOffsetMul("Depth Offset Multiplier", Range(0, 0.1)) = 0.01
        
        [Sub(OverlayEffects)] [NoScaleOffset] _MatCapMap("MatCap Map", 2D) = "black" {}
        [Sub(OverlayEffects)] _MatCapIntensity("MatCap Intensity", Range(0, 1)) = 0.0

        // ==========================================
        // 8. Geometry Effects (幾何特效)
        // ==========================================
        [Main(GeometryOutline, _, off)] _group_GeometryOutline ("8. Geometry Outline", Float) = 0
        [SubToggle(GeometryOutline, _USE_OUTLINE)] _UseOutline("Enable Outline", Float) = 1
        [Sub(GeometryOutline)] _OutlineWidth("Outline Width", Range(0, 0.1)) = 0.01
        [Sub(GeometryOutline)] _OutlineColor("Outline Color", Color) = (0,0,0,1)

        // ==========================================
        // 9. Weather System (動態天氣)
        // ==========================================
        [Main(Weather, _, off)] _group_Weather ("9. Weather System", Float) = 0
        [SubToggle(Weather, _WEATHER_WETNESS_ON)] _UseWetness("Enable Wetness / Rain", Float) = 0
        [Sub(Weather)] _LocalWetness("Local Wetness", Range(0, 1)) = 1.0
        [Sub(Weather)] _WetDirThreshold("Direction Threshold", Range(-1, 1)) = 0.0
        [Sub(Weather)] _WetDirContrast("Direction Contrast", Range(0.01, 1.0)) = 0.5
        [Sub(Weather)] _WetDarkenIntensity("Darken Intensity", Range(0.0, 1.0)) = 0.5
        [Sub(Weather)] _WetSmoothnessMax("Max Smoothness", Range(0.0, 1.0)) = 0.95
        [Sub(Weather)] _GlobalPorosity("Global Porosity", Range(0, 1)) = 1.0
        [Sub(Weather)] _WetSpecularIntensity("Specular Intensity", Range(0.0, 5.0)) = 1.0
        [Sub(Weather)] _WetNormalFlatten("Normal Flatten", Range(0, 1)) = 0.5
        [Sub(Weather)] _RaindropScale("Raindrop Scale", Range(0.1, 10.0)) = 2.0
        [Sub(Weather)] _RaindropSpeed("Raindrop Speed", Range(0.0, 5.0)) = 1.0
        
        // ==========================================
        // 10. Eye Specific (眼球專屬特化區塊)
        // ==========================================
        [Main(Eye, _, off)] _group_Eye ("10. Eye Specific (眼球特化參數)", Float) = 0
        
        [Sub(Eye)] _SphereMaskRange ("SphereMask Range (球體遮罩範圍)", Range(0, 5)) = 1.0
        [Sub(Eye)] _Parallax ("Parallax (視差偏移深度)", Range(0, 0.1)) = 0.02

        [Sub(Eye)] _MatCapIntensity1 ("MatCap Intensity", Range(0, 5)) = 1.0
        
        // 供後續實作頭髮遮擋用的參數 (先保留宣告，以防報錯)
        [Sub(Eye)] _HairDepthFade ("Hair Depth Fade", Range(0, 1)) = 0.5
        [Sub(Eye)] _HairOcclusionColor ("Hair Occlusion Color", Color) = (0, 0, 0, 1)
        [Sub(Eye)] _HairOcclusionAlpha ("Hair Occlusion Alpha", Range(0, 1)) = 0.5
        [Sub(Eye)] _StencilEyebrowRef ("Stencil Eyebrow Ref (Bitmask)", Float) = 128
    }
    
    SubShader
    {
        // 定義透明渲染佇列
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent+1" "RenderPipeline" = "UniversalPipeline" }

        // ---- 唯一的 Pass：Forward ----
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            
            // 開啟透明混合，關閉深度寫入
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull [_CullMode]

            // 加入眼球與眉毛層級的 Stencil 遮罩
            Stencil
            {
                Ref [_StencilEyebrowRef] 
                ReadMask [_StencilEyebrowRef]
                WriteMask [_StencilEyebrowRef]
                Comp NotEqual
                Pass Replace
            }
            
           HLSLPROGRAM
                #pragma target 3.5
                #pragma multi_compile_instancing

                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
                #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
                #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
                #pragma multi_compile_fragment _ _SHADOWS_SOFT
                #pragma multi_compile _ LIGHTMAP_ON
                #pragma multi_compile _ PROBE_VOLUMES_L1 PROBE_VOLUMES_L2

                // 【必須補回的編譯巨集橋樑】
                #pragma shader_feature_local _USE_LIGHTING
                #pragma shader_feature_local _ADD_LIGHT_ON
                // (如果你的眼球需要受天氣系統影響，也可將 _WEATHER_WETNESS_ON 補回)

                #define ABYSS_MATERIAL_EYE
                
                #pragma vertex vert_forward
                #pragma fragment frag_forward
                
                #include "AbyssPass_Eye_Forward.hlsl"
            ENDHLSL
        }
    }

    CustomEditor "LWGUI.LWGUI"
}