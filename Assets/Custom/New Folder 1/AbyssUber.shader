Shader "Abyss/UberShader_DOTS"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1,1,1,1)

        // ---- 透明度模式 ----
        [KeywordEnum(Opaque, Cutout, Dither)] _Transparency_Mode("Transparency Mode", Float) = 0
        _AlphaClipThreshold("Alpha Clip Threshold", Range(0.0, 1.0)) = 0.5
        _DitherMap("Dither Pattern (Blue Noise)", 2D) = "white" {}
        _DitherThreshold("Dither Threshold", Range(0, 1)) = 0.5
        _DitherScale("Dither Tiling Scale", Range(1, 20)) = 10

        // ---- 法線貼圖（不再用開關） ----
        [Normal] _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalScale("Normal Scale", Range(0.0, 2.0)) = 1.0

        [Header(Render State)]
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode("Cull Mode", Float) = 2.0

        [Header(Additional Lights)]
        [Toggle(_ADD_LIGHT_ON)] _AddLightOn("Enable Additional Lights", Float) = 1
        _AddLightIntensity("Additional Lights Intensity", Range(0,2)) = 1.0

        [Header(Reflection)]
        [Toggle(_REFLECTION_ON)] _ReflectionOn("Enable Reflection", Float) = 1
        _ReflectionIntensity("Reflection Intensity", Range(0,2)) = 1.0
        _Smoothness("Smoothness", Range(0,1)) = 0.5
        _Metallic("Metallic", Range(0,1)) = 0.0

        [Header(Emission)]
        [HDR] _EmissionColor("Emission Color", Color) = (0,0,0,1)
        _EmissionMap("Emission Map", 2D) = "white" {}

        [Header(Environment Lighting)]
        _MinBrightness("Min Brightness", Range(0.0, 1.0)) = 0.1
        _IndirectLightMultiplier("GI Intensity", Range(0.0, 2.0)) = 1.0
        
        [Header(Shadow Settings)]
        [Toggle(_USE_LIGHTING)] _UseLighting("Enable Lighting & Shadows", Float) = 1
        _ShadowTint("Shadow Tint", Color) = (0.3, 0.3, 0.4, 1.0)
        
        [Header(Cel Shading Settings)]
        _BandThreshold("Light Band Threshold", Range(0.0, 1.0)) = 0.5
        _BandSmoothness("Light Band Smoothness", Range(0.001, 0.5)) = 0.05
        _ShadowIntensity("Receive Shadow Intensity", Range(0.0, 1.0)) = 1.0
        
        [Header(Stylized Ramp  Border)]
        _RampMap("Ramp Map (1D)", 2D) = "white" {}
        // 必須補回這三行！否則必定全黑！
        _RampColorLight("Ramp Light Color", Color) = (1,1,1,1)
        _RampColorShadow("Ramp Shadow Color", Color) = (0.3,0.3,0.4,1)
        _AmbientColor("Ambient Color", Color) = (0.5,0.5,0.6,1)
        
        // Border Color (明暗交界色)
        [HDR] _BorderColor("Border Color", Color) = (1, 0.3, 0.1, 1) // 預設給個高飽和橘紅色
        _BorderThreshold("Border Threshold (交界線位置)", Range(0.01, 0.99)) = 0.5
        _BorderWidth("Border Width (交界線寬度)", Range(0.01, 0.5)) = 0.1

        [Header(Specular Highlight)]
        [Toggle(_USE_SPECULAR)] _UseSpecular("Enable Specular", Float) = 1
        [HDR] _SpecularColor("Specular Color", Color) = (1, 1, 1, 1)
        _SpecularStep("Specular Step (高光集中度)", Range(0.01, 1.0)) = 0.8
        _SpecularFeather("Specular Feather (高光邊緣柔和度)", Range(0.001, 0.5)) = 0.05

        [Header(Fresnel)]
        [HDR] _FresnelColor("Fresnel Color", Color) = (0, 1, 1, 1)
        _FresnelPower("Fresnel Power", Range(0.1, 10)) = 2.0
        _FresnelIntensity("Fresnel Intensity", Range(0, 1)) = 0.0

        [Header(Outline)]
        [Toggle(_USE_OUTLINE)] _UseOutline("Enable Outline", Float) = 0
        _OutlineWidth("Outline Width", Range(0, 0.1)) = 0.01
        _OutlineColor("Outline Color", Color) = (0,0,0,1)

        [Header(MatCap)]
        _MatCapMap("MatCap Map", 2D) = "black" {}
        _MatCapIntensity("MatCap Intensity", Range(0, 1)) = 0.0

        [Header(Anisotropic Highlight)]
        _AnisoPower("Anisotropic Power", Range(1.0, 256.0)) = 64.0
        _AnisoColor("Anisotropic Color", Color) = (1,1,1,1)
        _AnisoIntensity("Anisotropic Intensity", Range(0, 1)) = 0.0
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

                // ---- 剩餘的 local 關鍵字 ----
                #pragma shader_feature_local _TRANSPARENCY_MODE_OPAQUE _TRANSPARENCY_MODE_CUTOUT _TRANSPARENCY_MODE_DITHER
                #pragma shader_feature_local _USE_LIGHTING
                #pragma shader_feature_local _ADD_LIGHT_ON
                #pragma shader_feature_local _REFLECTION_ON

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
            //DepthOnly不用是因為DepthNormals才能支援SSAO 不然他會因為沒有Normal數據被踢掉 他需要同時有法線跟深度
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            Cull [_CullMode]
            //ColorMask 0
            
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
}