Shader "Abyss/UberShader_DOTS"
{
    Properties
    {
        // ==========================================
        // 1. Render State (系統渲染狀態)
        // ==========================================
        [Main(RenderState, _, off)] _group_RenderState ("1. Render State (系統渲染狀態)", Float) = 0
        
        // 使用 SubEnum 與 SubKeywordEnum 合併標籤，徹底解決群組脫離問題
        [SubEnum(RenderState, UnityEngine.Rendering.CullMode)] _CullMode("Cull Mode", Float) = 2.0
        [SubKeywordEnum(RenderState, Opaque, Cutout, Dither)] _Transparency_Mode("Transparency Mode", Float) = 0
        [Sub(RenderState)] _AlphaClipThreshold("Alpha Clip Threshold", Range(0.0, 1.0)) = 0.5
        [Sub(RenderState)] [NoScaleOffset] _DitherMap("Dither Pattern (Blue Noise)", 2D) = "white" {}
        [Sub(RenderState)] _DitherThreshold("Dither Threshold", Range(0, 1)) = 0.5
        [Sub(RenderState)] _DitherScale("Dither Tiling Scale", Range(1, 20)) = 10

        // ==========================================
        // 2. Base Surface (基礎表面屬性)
        // ==========================================
        [Main(BaseSurface, _, on)] _group_BaseSurface ("2. Base Surface (基礎表面屬性)", Float) = 0
        
        [Sub(BaseSurface)] [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [Sub(BaseSurface)] [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [Sub(BaseSurface)] [NoScaleOffset] [Normal] _NormalMap("Normal Map", 2D) = "bump" {}
        [Sub(BaseSurface)] _NormalScale("Normal Scale", Range(0.0, 2.0)) = 1.0
        [Sub(BaseSurface)] [HDR] _EmissionColor("Emission Color", Color) = (0,0,0,1)
        [Sub(BaseSurface)] _EmissionMap("Emission Map", 2D) = "white" {}

        // ==========================================
        // 3. Core Lighting & Shadows (光照與陰影核心)
        // ==========================================
        [Main(Lighting, _, on)] _group_Lighting ("3. Core Lighting & Shadows (光照核心)", Float) = 0
        
        // 修正：將 [Sub] [Toggle] 統一重構為 [SubToggle]
        [SubToggle(Lighting, _USE_LIGHTING)] _UseLighting("Enable Lighting & Shadows", Float) = 1
        [Sub(Lighting)] _MainLightMultiplier("Local Main Light Multiplier", Range(0, 5)) = 1.0
        [Sub(Lighting)] _MainLightColorWeight("Main Light Color Weight", Range(0, 1)) = 1.0
        [SubToggle(Lighting, _ADD_LIGHT_ON)] _AddLightOn("Enable Additional Lights", Float) = 1
        [Sub(Lighting)] _AddLightIntensity("Additional Lights Intensity", Range(0,2)) = 1.0
        [Sub(Lighting)] _ShadowTint("Shadow Tint", Color) = (0.9333333, 0.7411765, 0.7098039, 1.0)
        [Sub(Lighting)] _ReceiveShadowIntensity("Receive Shadow Intensity", Range(0.0, 1.0)) = 1.0
        [Sub(Lighting)] _ShadowSmoothness ("接收陰影平滑度 (Shadow Smoothness)", Range(0.0, 0.5)) = 0.05

        // ==========================================
        // 4. PBR & Environment (物理渲染與環境光)
        // ==========================================
        [Main(PBR, _, off)] _group_PBR ("4. PBR & Environment (物理與環境光)", Float) = 0
        
        // 【核心新增】：導入 Mask Map (R:金屬度, G:環境遮蔽, B:自訂, A:平滑度)
        [Sub(PBR)] [NoScaleOffset] _MaskMap("Mask Map (R:Met, G:AO, A:Smooth)", 2D) = "white" {}
        
        // 將這兩個變數的 UI 標籤改為 Multiplier，底層變數名稱保留以相容舊資料
        [Sub(PBR)] _Smoothness("Smoothness Multiplier", Range(0,1)) = 0.5
        [Sub(PBR)] _Metallic("Metallic Multiplier", Range(0,1)) = 0.0
        
        [SubToggle(PBR, _REFLECTION_ON)] _ReflectionOn("Enable Reflection", Float) = 1
        [Sub(PBR)] _ReflectionIntensity("Reflection Intensity", Range(0,2)) = 1.0
        
        // 【移除原本的 _OcclusionMap】，僅保留強度控制
        [Sub(PBR)] _OcclusionStrength("Occlusion Strength", Range(0.0, 1.0)) = 1.0
        [Sub(PBR)] _IndirectLightMultiplier("GI Intensity", Range(0.0, 2.0)) = 1.0
        [Sub(PBR)] _MinBrightness("Min Brightness", Range(0.0, 1.0)) = 0.1
        [Sub(PBR)] _DiffuseImpact("Diffuse Lighting Impact", Range(0.0, 2.0)) = 1.0
        [Sub(PBR)] _MaxHighlightEnergy("Max Highlight Energy", Range(1.0, 3.0)) = 1.3
        [Sub(PBR)] _AmbientColor("Ambient Color", Color) = (1,1,1,1)
        [Sub(PBR)] _AmbientIntensity("Ambient Color Intensity", Range(0, 2)) = 1.0
        
        // ==========================================
        // 5. Stylized Cel Shading (卡通渲染核心設定)
        // ==========================================
        [Main(CelShading, _, on)] _group_CelShading ("5. Stylized Cel Shading (卡通渲染核心)", Float) = 0
        
        [SubEnum(CelShading, Math Mode, 0, Ramp Mode, 1)] _UseRampMode("Lighting Mode", Float) = 0
        [Sub(CelShading)] [NoScaleOffset] _RampMap("Ramp Map (1D)", 2D) = "white" {}
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
        [Main(Highlights, _, off)] _group_Highlights ("6. Highlights (高光處理)", Float) = 0
        
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
        [Main(OverlayEffects, _, off)] _group_OverlayEffects ("7. Overlay & Edge Effects (特殊邊緣特效)", Float) = 0
        
        [Sub(OverlayEffects)] [HDR] _FresnelColor("Fresnel Color", Color) = (0, 1, 1, 1)
        [Sub(OverlayEffects)] _FresnelPower("Fresnel Power", Range(0.1, 10)) = 2.0
        [Sub(OverlayEffects)] _FresnelIntensity("Fresnel Intensity", Range(0, 1)) = 0.0
        // 修正：沒有綁定編譯關鍵字的純 UI Toggle，在 LWGUI 中直接給予空字串參數即可
        [SubToggle(OverlayEffects, _)] _UseRimLight("Enable Rim Light", Float) = 1
        [Sub(OverlayEffects)] [HDR] _RimColor("Rim Color", Color) = (1, 1, 1, 1)
        [Sub(OverlayEffects)] _RimPower("Rim Power", Range(0.1, 10)) = 3.0
        [Sub(OverlayEffects)] _RimThreshold("Rim Threshold", Range(0, 1)) = 0.5
        [Sub(OverlayEffects)] _RimSmoothness("Rim Smoothness", Range(0.001, 1)) = 0.05
        [Sub(OverlayEffects)] _RimShadowMask("Shadow Mask", Range(0, 1)) = 1.0
        [Sub(OverlayEffects)] [NoScaleOffset] _MatCapMap("MatCap Map", 2D) = "black" {}
        [Sub(OverlayEffects)] _MatCapIntensity("MatCap Intensity", Range(0, 1)) = 0.0

        // ==========================================
        // 8. Geometry Effects (幾何特效)
        // ==========================================
        [Main(GeometryOutline, _, off)] _group_GeometryOutline ("8. Geometry Outline (幾何描邊)", Float) = 0
        
        [SubToggle(GeometryOutline, _USE_OUTLINE)] _UseOutline("Enable Outline", Float) = 1
        [Sub(GeometryOutline)] _OutlineWidth("Outline Width", Range(0, 0.1)) = 0.01
        [Sub(GeometryOutline)] _OutlineColor("Outline Color", Color) = (0,0,0,1)
        
        // ==========================================
        // 9. Weather System (動態天氣)
        // ==========================================
        [Main(Weather, _, off)] _group_Weather ("9. Weather System (動態天氣)", Float) = 0
        
        [SubToggle(Weather, _WEATHER_WETNESS_ON)] _UseWetness("Enable Wetness / Rain", Float) = 0
        [Sub(Weather)] _LocalWetness("Local Wetness (Controlled by Script)", Range(0, 1)) = 1.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        // ---- Pass 1: Forward ----
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull [_CullMode]
            
            HLSLPROGRAM
                #define PASS_FORWARD

                #pragma target 3.5
                #pragma multi_compile_instancing

                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
                #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
                #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
                #pragma multi_compile_fragment _ _SHADOWS_SOFT
                #pragma multi_compile _ LIGHTMAP_ON
                #pragma multi_compile _ PROBE_VOLUMES_L1 PROBE_VOLUMES_L2
                #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

                #pragma shader_feature_local _TRANSPARENCY_MODE_OPAQUE _TRANSPARENCY_MODE_CUTOUT _TRANSPARENCY_MODE_DITHER
                #pragma shader_feature_local _USE_LIGHTING
                #pragma shader_feature_local _ADD_LIGHT_ON
                #pragma shader_feature_local _REFLECTION_ON

                #pragma shader_feature_local _WEATHER_WETNESS_ON

                #pragma vertex vert
                #pragma fragment frag
                
                #include "AbyssShared.hlsl"
            ENDHLSL
        }

        // ---- Pass 2: Outline ----
        Pass
        {
            Name "Outline"
            Cull Front

            HLSLPROGRAM
                #define PASS_OUTLINE

                #pragma target 3.5
                #pragma multi_compile_instancing

                #pragma shader_feature_local _TRANSPARENCY_MODE_OPAQUE _TRANSPARENCY_MODE_CUTOUT _TRANSPARENCY_MODE_DITHER
                #pragma shader_feature_local _USE_OUTLINE

                #pragma vertex vert
                #pragma fragment frag

                #include "AbyssShared.hlsl"
            ENDHLSL
        }

        // ---- Pass 3: ShadowCaster ----
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ColorMask 0
            Cull Back
            
            HLSLPROGRAM
                #define PASS_SHADOW_CASTER

                #pragma target 3.5
                #pragma multi_compile_instancing

                #pragma shader_feature_local _TRANSPARENCY_MODE_OPAQUE _TRANSPARENCY_MODE_CUTOUT _TRANSPARENCY_MODE_DITHER

                #pragma vertex vert
                #pragma fragment frag
                #include "AbyssShared.hlsl"
            ENDHLSL
        }

        // ---- Pass 4: DepthOnly ----
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            Cull [_CullMode]
            
            ZWrite On
            ZTest LEqual
            
           HLSLPROGRAM
                #define PASS_DEPTH

                #pragma target 3.5
                #pragma multi_compile_instancing

                #pragma shader_feature_local _TRANSPARENCY_MODE_OPAQUE _TRANSPARENCY_MODE_CUTOUT _TRANSPARENCY_MODE_DITHER

                #pragma vertex vert
                #pragma fragment frag
                #include "AbyssShared.hlsl"
           ENDHLSL
        }
    }

    CustomEditor "LWGUI.LWGUI"
}