Shader "Abyss/UberShader_DOTS"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1,1,1,1)
        
        [Toggle(_ALPHA_CLIP)] _AlphaClip("Enable Alpha Clipping", Float) = 0
        _AlphaClipThreshold("Alpha Clip Threshold", Range(0.0, 1.0)) = 0.5
        
        [Toggle(_DITHER)] _Dither("Enable Dither Fade", Float) = 0
        _DitherMap("Dither Pattern (Blue Noise)", 2D) = "white" {}
        _DitherThreshold("Dither Threshold (0=全透, 1=全不透明)", Range(0, 1)) = 0.5
        _DitherScale("Dither Tiling Scale", Range(1, 20)) = 10
        
        // 在 Properties 區塊加入：
        [Toggle(_USE_NORMALMAP)] _UseNormalMap("開啟法線貼圖", Float) = 0
        [Normal] _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalScale("Normal Scale (凸起強度)", Range(0.0, 2.0)) = 1.0
        
        [Header(Render State)]
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode("Cull Mode (Off=雙面, Back=單面)", Float) = 2.0
        
        [Header(Additional Lights)]
        [Toggle(_ADD_LIGHT_ON)] _AddLightOn("Enable Additional Lights", Float) = 1
        _AddLightIntensity("Additional Lights Intensity", Range(0,2)) = 1.0

        [Header(Reflection)]
        [Toggle(_REFLECTION_ON)] _ReflectionOn("Enable Reflection", Float) = 1
        _ReflectionIntensity("Reflection Intensity", Range(0,2)) = 1.0
        _Smoothness("Smoothness", Range(0,1)) = 0.5
        _Metallic("Metallic", Range(0,1)) = 0.0

        [Header(Emission)]
        [Toggle(_EMISSION_ON)] _EmissionOn("Enable Emission", Float) = 1
        [HDR] _EmissionColor("Emission Color", Color) = (0,0,0,1)
        _EmissionMap("Emission Map", 2D) = "white" {}
        
        [Header(Environment Lighting)]
        _MinBrightness("Min Brightness", Range(0.0, 1.0)) = 0.1
        _IndirectLightMultiplier("GI Intensity", Range(0.0, 2.0)) = 1.0
        
        [Header(Shadow Settings)]
        [Toggle(_USE_LIGHTING)] _UseLighting("開啟受光與陰影", Float) = 1
        _ShadowTint("Shadow Tint", Color) = (0.3, 0.3, 0.4, 1.0)
        
        [Header(Cel Shading Settings)]
        _BandThreshold("Light Band Threshold", Range(0.0, 1.0)) = 0.5
        _BandSmoothness("Light Band Smoothness", Range(0.001, 0.5)) = 0.05
        _ShadowIntensity("Receive Shadow Intensity", Range(0.0, 1.0)) = 1.0
        
        [Toggle(_USE_FRESNEL)] _UseFresnel("開啟菲涅耳", Float) = 0
        [HDR] _FresnelColor("Fresnel Color", Color) = (0, 1, 1, 1)
        _FresnelPower("Fresnel Power", Range(0.1, 10)) = 2.0
        
        [Toggle(_USE_OUTLINE)] _UseOutline("開啟描邊", Float) = 0
        _OutlineWidth("Outline Width", Range(0, 0.1)) = 0.01
        _OutlineColor("Outline Color", Color) = (0,0,0,1)
        
        [Toggle(_USE_MATCAP)] _UseMatCap("開啟 MatCap 材質捕捉", Float) = 0
        _MatCapMap("MatCap Map (請放圓形材質球貼圖)", 2D) = "black" {}
        
        [Toggle(_USE_ANISOTROPIC)] _UseAnisotropic("開啟各向異性高光", Float) = 0
        _AnisoPower("Anisotropic Power (高光集中度)", Range(1.0, 256.0)) = 64.0
        _AnisoColor("Anisotropic Color", Color) = (1,1,1,1)
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

            #pragma shader_feature_local _ALPHA_CLIP
            #pragma shader_feature_local _DITHER
            #pragma shader_feature_local _USE_NORMALMAP
            #pragma shader_feature_local _USE_FRESNEL
            #pragma shader_feature_local _USE_LIGHTING
            #pragma shader_feature_local _ADD_LIGHT_ON
            #pragma shader_feature_local _REFLECTION_ON
            #pragma shader_feature_local _EMISSION_ON
            #pragma shader_feature_local _USE_MATCAP
            #pragma shader_feature_local _USE_ANISOTROPIC
            
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
            #pragma shader_feature_local _ALPHA_CLIP
            #pragma shader_feature_local _DITHER
            #pragma shader_feature _USE_OUTLINE
            
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
            #pragma shader_feature_local _ALPHA_CLIP
            #pragma shader_feature_local _DITHER
            #define PASS_SHADOW_CASTER
            
            #pragma target 3.5
            #pragma multi_compile_instancing
            
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
            #pragma shader_feature_local _ALPHA_CLIP
            #pragma shader_feature_local _DITHER
            #define PASS_DEPTH
            
            #pragma target 3.5
            #pragma multi_compile_instancing
            
            #pragma vertex vert
            #pragma fragment frag
            
            #include "AbyssShared.hlsl"
            ENDHLSL
        }
    }
}