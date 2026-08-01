Shader "Hidden/StickerOutline"
{
Properties
    {
        [Header(Base Settings)]
        _OutlineColor ("Outline Color", Color) = (1, 1, 1, 1)
        _OutlineWidth ("Outline Width", Range(0.0, 10.0)) = 3.0
        _BlendFactor ("Environment Blend Factor", Range(0.0, 1.0)) = 0.3

        [Header(Abyss Noise Distortion)]
        _NoiseScale ("Noise Scale (噪點縮放)", Range(0.1, 50.0)) = 15.0
        _NoiseStrength ("Noise Strength (擾動強度)", Range(0.0, 5.0)) = 1.5
        _NoiseSpeed ("Noise Speed (蠕動速度)", Range(0.0, 10.0)) = 2.0

        [Header(TopDown Depth Fade)]
        _FadeStart ("Fade Start Depth (開始衰減距離)", Float) = 15.0
        _FadeEnd ("Fade End Depth (完全消失距離)", Float) = 30.0
        
        [Header(Voxel Precision)]
        _DepthTolerance ("Depth Tolerance (微觀寬容度)", Range(0.001, 0.5)) = 0.05
        _SeparationDepth ("Object Separation Depth (物件分離深度落差)", Range(0.1, 10.0)) = 1.0
    }
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "StickerOutlinePass"
            ZWrite Off
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #pragma vertex FullscreenVert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            // 必須引入 URP 深度圖讀取庫
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings FullscreenVert(Attributes input)
            {
                Varyings output;
                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
                return output;
            }

            TEXTURE2D_X(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

            TEXTURE2D(_StickerMaskTex);
            SAMPLER(sampler_StickerMaskTex);

            float4 _OutlineColor;
            float _OutlineWidth;

            float _BlendFactor;
            float _NoiseScale;
            float _NoiseStrength;
            float _NoiseSpeed;
            float _FadeStart;
            float _FadeEnd;
            float _DepthTolerance;

            // 記得在宣告區加入新的參數
            float _SeparationDepth;
            
            float rand(float2 n) { 
                return frac(sin(dot(n, float2(12.9898, 4.1414))) * 43758.5453);
            }
            
            float4 frag(Varyings input) : SV_Target
            {
                //float mask = SAMPLE_TEXTURE2D(_StickerMaskTex, sampler_StickerMaskTex, input.uv).r;
                //return float4(mask, mask, mask, 1);
                
                float4 originalColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, input.uv);
                float centerMask = SAMPLE_TEXTURE2D(_StickerMaskTex, sampler_StickerMaskTex, input.uv).r;

                float currentDepthRaw = SampleSceneDepth(input.uv);
                float currentLinearDepth = LinearEyeDepth(currentDepthRaw, _ZBufferParams);

                float2 texelSize = float2(1.0 / _ScreenParams.x, 1.0 / _ScreenParams.y);
                
                bool drawOutline = false;
                float targetDepthForFade = 99999.0;

                float2 offsets[8] = {
                    float2(-1, 0), float2(1, 0), float2(0, -1), float2(0, 1),
                    float2(-0.707, -0.707), float2(0.707, -0.707), float2(-0.707, 0.707), float2(0.707, 0.707)
                };

                float2 noiseUV = input.uv * _NoiseScale; 
                float noise = (rand(noiseUV + _Time.y * _NoiseSpeed) - 0.5) * 2.0;
                float actualWidth = _OutlineWidth + noise * _NoiseStrength;

                // ==========================================
                // 路徑 A：像素位於遮罩內部 (處理大尺度物件分離)
                // ==========================================
                if (centerMask > 0.1)
                {
                    for (int i = 0; i < 8; i++)
                    {
                        float2 sampleUV = input.uv + offsets[i] * actualWidth * texelSize;
                        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) continue;

                        float sampleMask = SAMPLE_TEXTURE2D(_StickerMaskTex, sampler_StickerMaskTex, sampleUV).r;
                        
                        if (sampleMask > 0.1)
                        {
                            float sampleDepthRaw = SampleSceneDepth(sampleUV);
                            float sampleLinearDepth = LinearEyeDepth(sampleDepthRaw, _ZBufferParams);

                            // 【核心修正】：反轉深度比對方向
                            // 當「當前像素（後景）」深度，大於「周圍採樣像素（前景）」加上分離閾值時
                            // 代表當前像素是被前景擋住的背景物件，我們把白邊畫在它身上（向外擴張）
                            if (currentLinearDepth > sampleLinearDepth + _SeparationDepth)
                            {
                                drawOutline = true;
                                // 衰減基準必須改為前景物件的深度，確保描邊跟隨前景物件一起衰減
                                targetDepthForFade = sampleLinearDepth;
                                break; 
                            }
                        }
                    }
                    
                    if (!drawOutline) return originalColor;
                }
                // ==========================================
                // 路徑 B：像素位於遮罩外部 (處理最外圍剪影)
                // ==========================================
                else 
                {
                    for (int j = 0; j < 8; j++)
                    {
                        float2 sampleUV = input.uv + offsets[j] * actualWidth * texelSize;
                        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) continue;

                        float sampleMask = SAMPLE_TEXTURE2D(_StickerMaskTex, sampler_StickerMaskTex, sampleUV).r;
                        
                        if (sampleMask > 0.1)
                        {
                            float maskDepthRaw = SampleSceneDepth(sampleUV);
                            float maskLinearDepth = LinearEyeDepth(maskDepthRaw, _ZBufferParams);

                            // 基礎精度防禦
                            if (maskLinearDepth <= _ProjectionParams.y + _DepthTolerance) continue;

                            if (currentLinearDepth > maskLinearDepth - _DepthTolerance)
                            {
                                drawOutline = true;
                                targetDepthForFade = min(targetDepthForFade, maskLinearDepth);
                            }
                        }
                    }
                }

                // ==========================================
                // 最終渲染與輸出
                // ==========================================
                if (drawOutline)
                {
                    if (targetDepthForFade > _FadeEnd) return originalColor;
                    
                    float fadeFactor = 1.0 - saturate((targetDepthForFade - _FadeStart) / (_FadeEnd - _FadeStart));
                    float finalBlend = lerp(_BlendFactor, 1.0, 1.0 - fadeFactor);
                    
                    return lerp(_OutlineColor, originalColor, finalBlend);
                }

                return originalColor;
            }
            ENDHLSL
        }
    }
}