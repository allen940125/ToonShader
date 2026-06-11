Shader "Debug/ShowGI_APV"
{
    Properties
    {
        _GIMultiplier ("GI Multiplier", Range(0, 5)) = 1.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "ShowGI_APV"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // ── 重點：強制包含 APV 的所有變體 ──
            #pragma multi_compile _ PROBE_VOLUMES_L1 PROBE_VOLUMES_L2

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Lighting/ProbeVolume/ProbeVolume.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float4 screenPos  : TEXCOORD2;   // 供 APV 使用
            };

            half _GIMultiplier;

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(OUT.positionWS);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.screenPos = ComputeScreenPos(OUT.positionCS); // 正確的螢幕座標
                return OUT;
            }

            half3 frag(Varyings IN) : SV_Target
            {
                half3 normalWS = normalize(IN.normalWS);
                half3 giColor = half3(0,0,0);

                // 任意一個朝上的視角即可，不影響漫反射 Probe
                float3 viewDirWS = half3(0,1,0);

                #if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
                {
                    uint renderingLayer = 0;
                    EvaluateAdaptiveProbeVolume(IN.positionWS, normalWS, viewDirWS,
                        IN.screenPos, renderingLayer, giColor);
                }
                #else
                {
                    giColor = SampleSH(normalWS);
                }
                #endif

                giColor *= _GIMultiplier;
                return giColor;
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}