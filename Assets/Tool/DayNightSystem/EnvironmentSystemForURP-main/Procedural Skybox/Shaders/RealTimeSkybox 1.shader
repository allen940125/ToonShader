Shader "Abyss/Pro_Skybox_Integrated"
{
    Properties
    {
        _TimeMapping ("Time Mapping (-1 to 1)", Range(-1, 1)) = 0

        [Header(Day Sky Layering)]
        _DayZenithColor ("Day Zenith Color (Top)", Color) = (0.1, 0.4, 0.8, 1)
        _DayHorizonColor ("Day Horizon Color (Bottom)", Color) = (0.5, 0.8, 1, 1)
        _SunHaloSize ("Sun Halo Size", Range(0.01, 0.5)) = 0.1
        _SunHaloIntensity ("Sun Halo Intensity", Range(0, 10)) = 2

        [Header(Night Sky Cubemap)]
        [NoScaleOffset] _NightCube ("Night Sky Cubemap", Cube) = "black" {}
        _NightCubeIntensity ("Night Cube Intensity", Range(0, 5)) = 1
        _NightHorizonColor ("Night Horizon Color", Color) = (0.02, 0.02, 0.05, 1)

        [Header(Sun Settings)]
        [Toggle(_USE_SUN_TEXTURE)] _UseSunTex("Use Sun Texture (PNG)", Float) = 0
        [NoScaleOffset] _SunTexture("Sun Texture", 2D) = "black" {}
        _SunTexScale("Sun Texture Scale", Range(0.1, 50)) = 10
        
        _SunColor ("Sun Color", Color) = (1, 0.9, 0.7, 1)
        _SunSize ("Sun Size (Math Mode)", Range(0.0001, 0.01)) = 0.001 

        [Header(Moon Settings)]
        [Toggle(_USE_MOON_TEXTURE)] _UseMoonTex("Use Moon Texture (PNG)", Float) = 0
        [NoScaleOffset] _MoonTexture("Moon Texture", 2D) = "black" {}
        _MoonTexScale("Moon Texture Scale", Range(0.1, 50)) = 10
        
        _MoonColor ("Moon Color", Color) = (0.8, 0.8, 0.9, 1)
        _MoonSize ("MoonSize (Math Mode)", Range(0.0001, 0.01)) = 0.001
        _MoonMaskOffset ("Moon Crescent Offset", Range(-1, 1)) = 0.1
    }

    SubShader
    {
        Tags { "RenderType"="Background" "Queue"="Background" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            // 啟用本地 Shader 變體開關
            #pragma shader_feature_local _USE_SUN_TEXTURE
            #pragma shader_feature_local _USE_MOON_TEXTURE
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes {
                float4 positionOS : POSITION;
            };

            struct Varyings {
                float4 positionCS : SV_POSITION;
                float3 viewDirWS : TEXCOORD0;
            };

            TEXTURECUBE(_NightCube); SAMPLER(sampler_NightCube);
            TEXTURE2D(_SunTexture);  SAMPLER(sampler_SunTexture);
            TEXTURE2D(_MoonTexture); SAMPLER(sampler_MoonTexture);

            CBUFFER_START(UnityPerMaterial)
                float _TimeMapping;
                half4 _DayZenithColor;
                half4 _DayHorizonColor;
                half _SunHaloSize;
                half _SunHaloIntensity;
                half4 _NightHorizonColor;
                half _NightCubeIntensity;
                
                half4 _SunColor;
                half _SunSize;
                float _SunTexScale;
                
                half4 _MoonColor;
                half _MoonSize;
                half _MoonMaskOffset;
                float _MoonTexScale;
                
                float4 _SunDir;
                float4 _MoonDir;
            CBUFFER_END

            // --- 封裝：2D 貼圖的球面投影運算 ---
            half4 SampleCelestialTexture(Texture2D tex, SamplerState samp, float3 viewDir, float3 lightDir, float scale)
            {
                // 1. 計算該光源的局部切線空間 (Tangent Space)
                // 注意：若光源恰好在正上方 (0,1,0)，外積會失效。加上極小偏移值 0.001 避免數學死鎖。
                float3 right = normalize(cross(float3(0.001, 1.0, 0.001), lightDir));
                float3 up = cross(lightDir, right);
                
                // 2. 將 3D 視角投影到 2D 平面 (UV)
                float2 uv = float2(dot(viewDir, right), dot(viewDir, up));
                
                // 3. 縮放並將中心點移至 UV 的 (0.5, 0.5)
                uv = uv * scale + 0.5;
                
                // 4. 採樣貼圖。若 UV 超出 [0,1] 範圍則剔除 (避免貼圖重複填滿整個天空)
                half4 color = SAMPLE_TEXTURE2D(tex, samp, uv);
                float mask = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
                
                // 5. 確保只在「面對光源」的那一面顯示
                float frontFace = step(0.0, dot(viewDir, lightDir));
                
                return color * mask * frontFace;
            }

            Varyings vert(Attributes IN) {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.viewDirWS = IN.positionOS.xyz; 
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target {
                float3 viewDir = normalize(IN.viewDirWS);
                
                float3 sunDir = normalize(_SunDir.xyz);
                float3 moonDir = normalize(_MoonDir.xyz);

                // --- 1. 白天邏輯 (Daytime) ---
                float horizonFactor = saturate(viewDir.y);
                half3 daySkyGradient = lerp(_DayHorizonColor.rgb, _DayZenithColor.rgb, pow(horizonFactor, 0.8));
                
                float sunDoc = dot(viewDir, sunDir);
                half sunGlow = pow(saturate(sunDoc), 1.0 / _SunHaloSize) * _SunHaloIntensity;
                
                half3 finalSun = 0;
                #if defined(_USE_SUN_TEXTURE)
                    // 使用 PNG 貼圖 (利用貼圖的 Alpha 通道融合)
                    half4 sunTex = SampleCelestialTexture(_SunTexture, sampler_SunTexture, viewDir, sunDir, _SunTexScale);
                    finalSun = (sunTex.rgb * _SunColor.rgb * sunTex.a * 5.0) + (_SunColor.rgb * sunGlow);
                #else
                    // 使用純數學圓形
                    float sunThreshold = 1.0 - _SunSize;
                    half sunDisc = smoothstep(sunThreshold - 0.0005, sunThreshold, sunDoc);
                    finalSun = (_SunColor.rgb * sunDisc * 10.0) + (_SunColor.rgb * sunGlow);
                #endif

                // --- 2. 晚上邏輯 (Nighttime) ---
                half3 nightCube = SAMPLE_TEXTURECUBE(_NightCube, sampler_NightCube, viewDir).rgb * _NightCubeIntensity;
                half3 nightSky = lerp(_NightHorizonColor.rgb, nightCube, horizonFactor);

                half3 finalMoon = 0;
                #if defined(_USE_MOON_TEXTURE)
                    // 使用 PNG 貼圖
                    half4 moonTex = SampleCelestialTexture(_MoonTexture, sampler_MoonTexture, viewDir, moonDir, _MoonTexScale);
                    finalMoon = (moonTex.rgb * _MoonColor.rgb * moonTex.a * 3.0);
                #else
                    // 使用純數學月牙
                    float moonDoc = dot(viewDir, moonDir);
                    float moonThreshold = 1.0 - _MoonSize;
                    half moonDisc = smoothstep(moonThreshold - 0.0005, moonThreshold, moonDoc);

                    float3 moonRight = normalize(cross(float3(0, 1, 0), moonDir));
                    float3 maskDir = normalize(moonDir + moonRight * _MoonMaskOffset);
                    float moonMaskDoc = dot(viewDir, maskDir);
                    half moonMask = smoothstep(moonThreshold - 0.0005, moonThreshold, moonMaskDoc);

                    finalMoon = _MoonColor.rgb * saturate(moonDisc - moonMask) * 5.0;
                #endif

                // --- 3. 混合 (Final Blend) ---
                float dayWeight = smoothstep(-0.2, 0.2, _TimeMapping);
                half3 finalColor = lerp(nightSky + finalMoon, daySkyGradient + finalSun, dayWeight);

                if(viewDir.y < -0.01) finalColor = half3(0.02, 0.02, 0.03); 

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}