Shader "Custom/FiveLights"
{
    Properties
    {
        [Header(Base)]
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BaseMap ("Base Texture", 2D) = "white" {}

        [Header(Main Light)]
        [Toggle(_MAIN_LIGHT_ON)] _MainLightOn ("Enable Main Light", Float) = 1
        _MainLightIntensity ("Main Light Intensity", Range(0, 2)) = 1

        [Header(Additional Lights)]
        [Toggle(_ADD_LIGHT_ON)] _AddLightOn ("Enable Additional Lights", Float) = 1
        _AddLightIntensity ("Additional Lights Intensity", Range(0, 2)) = 1

        [Header(GI Ambient)]
        [Toggle(_GI_ON)] _GIOn ("Enable GI (Ambient + Baked)", Float) = 1
        _GIIntensity ("GI Intensity", Range(0, 2)) = 1

        [Header(Reflection)]
        [Toggle(_REFLECTION_ON)] _ReflectionOn ("Enable Reflection", Float) = 1
        _ReflectionIntensity ("Reflection Intensity", Range(0, 2)) = 1
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _Metallic ("Metallic", Range(0, 1)) = 0

        [Header(Emission)]
        [Toggle(_EMISSION_ON)] _EmissionOn ("Enable Emission", Float) = 1
        [HDR] _EmissionColor ("Emission Color", Color) = (0,0,0)
        _EmissionMap ("Emission Map", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // 材质关键字
            #pragma shader_feature_local _MAIN_LIGHT_ON
            #pragma shader_feature_local _ADD_LIGHT_ON
            #pragma shader_feature_local _GI_ON
            #pragma shader_feature_local _REFLECTION_ON
            #pragma shader_feature_local _EMISSION_ON

            // URP 核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float _MainLightIntensity;
                float _AddLightIntensity;
                float _GIIntensity;
                float _ReflectionIntensity;
                float _Smoothness;
                float _Metallic;
                float4 _EmissionColor;
                float4 _EmissionMap_ST;
            CBUFFER_END

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_EmissionMap); SAMPLER(sampler_EmissionMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                // 光照贴图UV
                float2 lightmapUV : TEXCOORD1;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                // 主光阴影坐标
                float4 shadowCoord : TEXCOORD3;
                // 光照贴图UV
                float2 lightmapUV : TEXCOORD4;
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;

                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);
                output.normalWS = normalInput.normalWS;

                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);

                // 主光阴影
                output.shadowCoord = TransformWorldToShadowCoord(output.positionWS);

                // 光照贴图UV（GI 需要）
                OUTPUT_LIGHTMAP_UV(input.lightmapUV, unity_LightmapST, output.lightmapUV);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 albedo = baseMap.rgb * _BaseColor.rgb;

                float3 N = normalize(input.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);

                // ============= 1. 主光源（直接漫反射 + 高光）=============
                half3 mainLightContribution = 0;
                #if defined(_MAIN_LIGHT_ON)
                    Light mainLight = GetMainLight();
                    // 主光阴影衰减
                    float shadowAtten = MainLightRealtimeShadow(input.shadowCoord);
                    float3 L = mainLight.direction;
                    float NdotL = saturate(dot(N, L));
                    // 漫反射
                    half3 mainDiffuse = mainLight.color * mainLight.distanceAttenuation * shadowAtten * NdotL;
                    // 简单高光（Blinn-Phong 风格）
                    float3 H = normalize(L + V);
                    float NdotH = saturate(dot(N, H));
                    half specular = pow(NdotH, exp2(10.0 * _Smoothness + 1.0));
                    half3 mainSpecular = mainLight.color * mainLight.distanceAttenuation * shadowAtten * specular * _Metallic;
                    mainLightContribution = (mainDiffuse * albedo + mainSpecular) * _MainLightIntensity;
                #endif

                // ============= 2. 附加光源（逐像素最多 8 个）=============
                half3 addLightContribution = 0;
                #if defined(_ADD_LIGHT_ON)
                    uint pixelLightCount = GetAdditionalLightsCount();
                    for (uint i = 0; i < pixelLightCount; ++i)
                    {
                        Light addLight = GetAdditionalLight(i, input.positionWS);
                        float3 L = addLight.direction;
                        float NdotL = saturate(dot(N, L));
                        half3 addDiffuse = addLight.color * addLight.distanceAttenuation * NdotL;
                        // 高光
                        float3 H = normalize(L + V);
                        float NdotH = saturate(dot(N, H));
                        half addSpecular = pow(NdotH, exp2(10.0 * _Smoothness + 1.0));
                        addLightContribution += (addDiffuse * albedo + addSpecular * _Metallic) * addLight.color * addLight.distanceAttenuation;
                    }
                    addLightContribution *= _AddLightIntensity;
                #endif

                // ============= 3. GI / 环境漫反射 ==============
                half3 giContribution = 0;
                #if defined(_GI_ON)
                    // SAMPLE_GI 自动处理光照贴图和球谐
                    half3 bakedGI = SAMPLE_GI(input.lightmapUV, half3(0,0,0), N);
                    giContribution = bakedGI * albedo * _GIIntensity;
                #endif

                // ============= 4. 反射（间接镜面反射）=============
                half3 reflectionContribution = 0;
                #if defined(_REFLECTION_ON)
                    // 计算反射向量
                    float3 reflectVector = reflect(-V, N);
                    // 使用 URP 的 GlossyEnvironmentReflection 获取环境反射颜色
                    half perceptualRoughness = 1.0 - _Smoothness;
                    half mipLevel = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness) * 6; // 粗略映射
                    half3 reflectionColor = GlossyEnvironmentReflection(reflectVector, input.positionWS, perceptualRoughness, 1.0h);
                    // 金属度影响反射颜色，非金属用固定颜色
                    half3 specularColor = lerp(0.04, albedo, _Metallic);
                    reflectionContribution = reflectionColor * specularColor * _ReflectionIntensity;
                #endif

                // ============= 5. 自发光 ==============
                half3 emissionContribution = 0;
                #if defined(_EMISSION_ON)
                    half4 emissionMap = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, TRANSFORM_TEX(input.uv, _EmissionMap));
                    emissionContribution = emissionMap.rgb * _EmissionColor.rgb;
                #endif

                // ============= 组合最终颜色 ==============
                half3 finalColor = mainLightContribution + addLightContribution + giContribution + reflectionContribution + emissionContribution;

                return half4(finalColor, 1);
            }
            ENDHLSL
        }

        // 阴影投射 Pass（保证物体能投射阴影）
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}