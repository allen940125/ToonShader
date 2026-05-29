Shader "Abyss/NPR_StrictIntegration_MultiStep_ShadowBias"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        
        [Header(Render Mode Switch)]
        [Space(10)]
        [Toggle(_USE_RAMP)] _UseRamp("Use Texture Ramp Mode", Float) = 0

        [Header(1st Shade Settings)]
        _ShadowTint("1st Shadow Tint", Color) = (0.7, 0.7, 0.7, 1)
        _1st_ToonThreshold("1st Threshold", Range(0, 1)) = 0.5
        _1st_ToonSmoothness("1st Smoothness", Range(0, 1)) = 0.05

        [Header(2nd Shade Settings)]
        [Toggle(_USE_2ND_SHADE)] _Use2ndShade("Enable 2nd Shade", Float) = 0
        _2nd_ShadowColor("2nd Shadow Color", Color) = (0.5, 0.5, 0.6, 1)
        _2nd_ToonThreshold("2nd Threshold", Range(0, 1)) = 0.3
        _2nd_ToonSmoothness("2nd Smoothness", Range(0, 1)) = 0.05

        [Header(3rd Shade Settings)]
        [Toggle(_USE_3RD_SHADE)] _Use3rdShade("Enable 3rd Shade", Float) = 0
        _3rd_ShadowColor("3rd Shadow Color", Color) = (0.2, 0.2, 0.3, 1)
        _3rd_ToonThreshold("3rd Threshold", Range(0, 1)) = 0.1
        _3rd_ToonSmoothness("3rd Smoothness", Range(0, 1)) = 0.05

        [Header(Mode 2 Ramp Settings)]
        [NoScaleOffset] _RampMap("Ramp Map", 2D) = "white" {}

        [Header(Shadow Artifact Control)]
        [Space(10)]
        _AbyssShadowBias("Receive Shadow Bias (Forward)", Range(0, 1)) = 0.05
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline" 
            "Queue" = "Geometry"
        }

        // ==========================================
        // PASS 1: ForwardLit (處理光照與接收陰影)
        // ==========================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #pragma shader_feature_local _USE_RAMP
            #pragma shader_feature_local _USE_2ND_SHADE
            #pragma shader_feature_local _USE_3RD_SHADE
            
            // URP 陰影編譯指令
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Custom/Abyss_NPR_Lib.hlsl"

            // 【新增宣告】：接收 Unity 引擎在繪製陰影時傳遞的全域燈光參數
            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
            };

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_RampMap); SAMPLER(sampler_RampMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                
                half4 _ShadowTint;
                half  _1st_ToonThreshold;
                half  _1st_ToonSmoothness;

                half4 _2nd_ShadowColor;
                half  _2nd_ToonThreshold;
                half  _2nd_ToonSmoothness;

                half4 _3rd_ShadowColor;
                half  _3rd_ToonThreshold;
                half  _3rd_ToonSmoothness;

                float _AbyssShadowBias; // 加入 Bias 變數
            CBUFFER_END

            Varyings Vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(OUT.positionWS);
                OUT.normalWS   = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv         = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                half4 albedoMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half3 baseColor = albedoMap.rgb * _BaseColor.rgb;
                half3 firstShadowColor = baseColor * _ShadowTint.rgb;

                float3 normalWS = normalize(IN.normalWS);
                Light mainLight = GetMainLight();
                float3 lightDirWS = normalize(mainLight.direction);

                // ----------------------------------------
                // [物理事實] 接收陰影的 Bias 偏移運算
                // 將採樣坐標沿著光線方向往回推，避免模型低模切面造成的自遮擋暗瘡 (Shadow Acne)
                // ----------------------------------------
                float3 shadowTestPosWS = IN.positionWS + lightDirWS * _AbyssShadowBias;
                float4 shadowCoord = TransformWorldToShadowCoord(shadowTestPosWS);
                half shadowAtten = MainLightRealtimeShadow(shadowCoord);

                half3 finalLitColor = 0;

                // 將 URP 傳回的軟陰影數值，強制硬切成卡通風格的 0 或 1，避免狗啃邊緣糊掉
                half toonCastShadow = step(0.5, shadowAtten);

                #ifdef _USE_RAMP
                    // Ramp 模式：將投影陰影直接疊加進 UV 運算，強制採樣點往貼圖左側（暗部）移動
                    float rampUV = CalculateAbyssRampUV(normalWS, lightDirWS) * toonCastShadow;
                    half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap, float2(rampUV, 0.5)).rgb;
                    finalLitColor = baseColor * rampColor;
                #else
                    // ----------------------------------------
                    // 1st Shade (一階陰影)
                    // ----------------------------------------
                    half mask1 = CalculateAbyssToonMask(normalWS, lightDirWS, _1st_ToonThreshold, _1st_ToonSmoothness);
                    
                    // 投影陰影只作用於一階！被擋住的地方，強制切換為一階陰影色
                    mask1 *= toonCastShadow; 
                    half3 shadedColor = lerp(firstShadowColor, baseColor, mask1);

                    // ----------------------------------------
                    // 2nd Shade (二階陰影)
                    // ----------------------------------------
                    #ifdef _USE_2ND_SHADE
                        half mask2 = CalculateAbyssToonMask(normalWS, lightDirWS, _2nd_ToonThreshold, _2nd_ToonSmoothness);
                        // 絕對不可乘上 toonCastShadow，二階完全由法線決定
                        shadedColor = lerp(_2nd_ShadowColor.rgb, shadedColor, mask2);
                    #endif

                    // ----------------------------------------
                    // 3rd Shade (三階陰影)
                    // ----------------------------------------
                    #ifdef _USE_3RD_SHADE
                        half mask3 = CalculateAbyssToonMask(normalWS, lightDirWS, _3rd_ToonThreshold, _3rd_ToonSmoothness);
                        // 絕對不可乘上 toonCastShadow，三階完全由法線決定
                        shadedColor = lerp(_3rd_ShadowColor.rgb, shadedColor, mask3);
                    #endif

                    finalLitColor = shadedColor;
                #endif

                // 【關鍵修復】最後輸出時，"絕對不可以" 再乘上 shadowAtten！
                half3 finalRGB = finalLitColor * mainLight.color * mainLight.distanceAttenuation;
                return half4(finalRGB, 1.0);
            }
            ENDHLSL
        }

        // ==========================================
        // PASS 2: ShadowCaster (處理投射陰影)
        // [邏輯核心] 決定該模型寫入 ShadowMap 的形狀
        // ==========================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            // URP ShadowCaster 核心功能指令
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings ShadowPassVertex(Attributes IN)
            {
                Varyings OUT;
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);

                // ----------------------------------------
                // [物理事實] 投射陰影的法線偏移 (Normal Bias)
                // URP 底層函數 GetLightDirectionAndAttenuation 與 ApplyShadowBias
                // 負責消除光暗交界處的鋸齒 (Shadow Terminator Artifacts)
                // ----------------------------------------
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition.xyz - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                // 套用全域/物件的 Shadow Bias 偏移，計算出最終寫入 ShadowMap 的裁剪空間坐標
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

                // 深度偏移修正 (避免 Z-Fighting)
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                OUT.positionCS = positionCS;
                return OUT;
            }

            half4 ShadowPassFragment(Varyings IN) : SV_Target
            {
                return 0; // ShadowCaster 不需要回傳顏色，只需要寫入深度緩衝區 (ZWrite On)
            }
            ENDHLSL
        }
    }
}