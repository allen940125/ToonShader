Shader "Abyss/Strict_Toon_Advanced"
{
    Properties
    {
        [Header(Base Settings)]
        [MainColor] _BaseColor("Base Color (Lit)", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        _Alpha("Overall Alpha (Dither Fade)", Range(0.0, 1.0)) = 1.0

        [Space(10)]
        [Header(Render State)]
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode("Cull Mode (Off=雙面, Back=單面)", Float) = 2.0

        [Space(10)]
        [Header(Environment Lighting)]
        _MinBrightness("Min Brightness (Ambient)", Range(0.0, 1.0)) = 0.1
        _IndirectLightMultiplier("GI / APV Intensity", Range(0.0, 2.0)) = 1.0

        [Space(10)]
        [Header(1st Shade)]
        _1st_ToonThreshold("1st Shade Threshold", Range(-1.0, 1.0)) = 0.0
        _1st_ToonSmoothness("1st Shade Smoothness", Range(0.0, 1.0)) = 0.05
        [HDR] _ShadowColor("1st Shadow Color Tint", Color) = (0.7, 0.7, 0.8, 1)
        [Toggle(_USE_SHADEMAP)] _UseShadeMap("Enable 1st Shade Map", Float) = 0.0
        [NoScaleOffset] _1st_ShadeMap("1st Shade Map", 2D) = "white" {}

        [Space(5)]
        [Header(2nd Shade)]
        [Toggle(_USE_2ND_SHADE)] _Use2ndShade("Enable 2nd Shade", Float) = 0.0
        _2nd_ToonThreshold("2nd Shade Threshold", Range(-1.0, 1.0)) = -0.3
        _2nd_ToonSmoothness("2nd Shade Smoothness", Range(0.0, 1.0)) = 0.05
        [HDR] _2nd_ShadowColor("2nd Shadow Color Tint", Color) = (0.5, 0.5, 0.6, 1)

        [Space(5)]
        [Header(3rd Shade)]
        [Toggle(_USE_3RD_SHADE)] _Use3rdShade("Enable 3rd Shade", Float) = 0.0
        _3rd_ToonThreshold("3rd Shade Threshold", Range(-1.0, 1.0)) = -0.6
        _3rd_ToonSmoothness("3rd Shade Smoothness", Range(0.0, 1.0)) = 0.05
        [HDR] _3rd_ShadowColor("3rd Shadow Color Tint", Color) = (0.3, 0.3, 0.4, 1)

        [Space(5)]
        [Header(Cast Shadow Correction)]
        _AbyssShadowBias("Cast Shadow Bias", Range(0.0, 0.5)) = 0.05

        [Space(10)]
        [Header(Specular Settings)]
        [Toggle(_USE_SPECULAR)] _UseSpecular("Enable Specular", Float) = 0.0
        [HDR] _SpecularColor("Specular Color", Color) = (1, 1, 1, 1)
        _SpecularSize("Specular Size", Range(0.0, 1.0)) = 0.1
        _SpecularSoftness("Specular Softness", Range(0.0, 1.0)) = 0.01

        [Space(10)]
        [Header(Feature Toggles)]
        [Toggle(_USE_RAMP)] _UseRamp("Enable Color Ramp (RD)", Float) = 1.0
        [NoScaleOffset] _RampMap("Toon Ramp Map", 2D) = "white" {}

        [Space(10)]
        [Header(Outline Settings)]
        _OutlineWidth("Outline Width", Range(0.0, 5.0)) = 1.0
        _OutlineColor("Outline Color", Color) = (0, 0, 0, 1)

        [Space(10)]
        [Header(Rim Light Settings)]
        [Toggle(_USE_RIM)] _UseRimLight("Enable Rim Light", Float) = 0.0
        [HDR] _RimColor("Rim Color", Color) = (1, 1, 1, 1)
        _RimPower("Rim Power (Thinness)", Range(0.1, 10.0)) = 4.0
        _RimThreshold("Rim Hard Edge Threshold", Range(0.0, 1.0)) = 0.5
        _RimLightAlign("Rim Light Alignment (Light Mask)", Range(-1.0, 1.0)) = 0.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        // Pass 1: ForwardLit
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull [_CullMode]

            HLSLPROGRAM
            #pragma vertex VertBase
            #pragma fragment FragToon
            #pragma multi_compile_instancing

            // 功能開關
            #pragma shader_feature_local _USE_RAMP
            #pragma shader_feature_local _USE_RIM
            #pragma shader_feature_local _USE_SPECULAR
            #pragma shader_feature_local _USE_SHADEMAP
            #pragma shader_feature_local _USE_2ND_SHADE
            #pragma shader_feature_local _USE_3RD_SHADE

            // 光照變體
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _FORWARD_PLUS

            #include "Abyss_Strict_Toon_Advanced.hlsl"
            ENDHLSL
        }

        // Pass 2: ShadowCaster
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ColorMask 0
            ZWrite On

            HLSLPROGRAM
            #pragma vertex VertBase
            #pragma fragment FragShadow
            #pragma multi_compile_instancing
            #include "Abyss_Strict_Toon_Advanced.hlsl"
            ENDHLSL
        }

        // Pass 3: DepthOnly
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ColorMask 0
            ZWrite On

            HLSLPROGRAM
            #pragma vertex VertBase
            #pragma fragment FragDepth
            #pragma multi_compile_instancing
            #include "Abyss_Strict_Toon_Advanced.hlsl"
            ENDHLSL
        }

        // Pass 4: Outline
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Cull Front
            ZWrite On

            HLSLPROGRAM
            #pragma vertex VertOutline
            #pragma fragment FragOutline
            #pragma multi_compile_instancing
            #include "Abyss_Strict_Toon_Advanced.hlsl"
            ENDHLSL
        }
    }
}