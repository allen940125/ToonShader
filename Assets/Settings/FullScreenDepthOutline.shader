Shader "Abyss/FullScreenDepthOutline"
{
    Properties
    {
        _OutlineColor ("Outline Color (描邊顏色)", Color) = (0, 0, 0, 1)
        _Thickness ("Thickness (線條粗細)", Range(0.1, 5.0)) = 1.0
        _DepthThreshold ("Depth Threshold (深度敏感度)", Range(0.0001, 0.1)) = 0.001
    }
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "DepthOutline"
            // 全螢幕後處理的標準設定：不寫入深度、不剔除背面、永遠通過深度測試
            ZWrite Off
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #pragma vertex FullscreenVert
            #pragma fragment frag

            // 引入 URP 核心庫與深度圖讀取庫
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
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

            // 【黑科技】URP 內建的函數，直接用 3 個頂點生出一個覆蓋全螢幕的三角形，連 Mesh 都不用傳！
            Varyings FullscreenVert(Attributes input)
            {
                Varyings output;
                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
                return output;
            }

            // URP 2022+ 後處理專用的當前畫面貼圖名稱
            TEXTURE2D_X(_BlitTexture);
            SAMPLER(sampler_BlitTexture);

            float4 _OutlineColor;
            float _Thickness;
            float _DepthThreshold;

            float4 frag(Varyings input) : SV_Target
            {
                // 1. 抓取當前螢幕原本的顏色
                float4 originalColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, input.uv);

                // 2. 計算鄰近像素的偏移量 (_ScreenParams.xy 是螢幕的寬高解析度)
                float2 offset = float2(_Thickness / _ScreenParams.x, _Thickness / _ScreenParams.y);

                // 3. 採樣周圍 4 個點的深度 (左上、右下、右上、左下)
                // SampleSceneDepth 是 URP 提供的超方便函數，自動把非線性的深度轉換為 0~1 的線性深度
                float d1 = SampleSceneDepth(input.uv + float2(-offset.x, -offset.y));
                float d2 = SampleSceneDepth(input.uv + float2( offset.x,  offset.y));
                float d3 = SampleSceneDepth(input.uv + float2(-offset.x,  offset.y));
                float d4 = SampleSceneDepth(input.uv + float2( offset.x, -offset.y));

                // 4. 計算深度差異 (經典的 Roberts Cross 邊緣檢測演算法)
                float depthDiff = abs(d1 - d2) + abs(d3 - d4);

                // 5. 判斷：如果深度落差大於設定的閾值，代表這裡是物體邊緣！
                if (depthDiff > _DepthThreshold)
                {
                    // 把描邊顏色直接蓋上去 (也可以用 lerp 讓邊緣稍微柔和一點)
                    return _OutlineColor; 
                }

                // 否則，回傳原本的畫面顏色
                return originalColor;
            }
            ENDHLSL
        }
    }
}