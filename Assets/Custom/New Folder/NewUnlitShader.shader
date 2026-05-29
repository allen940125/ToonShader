Shader "URP/Unlit_DOTS_Instancing"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1,1,1,1)
        
        // [新增] 關鍵開關：使用 [Toggle] 標籤在面板顯示勾選框
        // 注意：括號內的 _USE_FRESNEL 必須與下面 pragma 對應
        [Toggle(_USE_FRESNEL)] _UseFresnel("開啟菲涅耳效果", Float) = 0
        
        // [新增] 菲涅耳顏色與強度。加上 [HDR] 讓顏色數值可以突破 1，產生真正的發光泛光 (Bloom) 效果
        [HDR] _FresnelColor("Fresnel Color", Color) = (0, 1, 1, 1)
        _FresnelPower("Fresnel Power", Range(0.1, 10)) = 2.0
    }

    SubShader
    {
        // 必須加上 RenderPipeline 標籤，引擎才會用 URP 渲染它
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "UnlitFresnel"
            
            HLSLPROGRAM
            #pragma vertex vert  // 指定 VS (Vertex Shader) 的進入點函數
            #pragma fragment frag  // 指定 PS (Pixel Shader) 的進入點函數
            #pragma target 3.5 //Shader版本

            // --------------------------------------------------
            // 核心效能開關：啟用 GPU Instancing 與 DOTS Instancing 支援
            #pragma multi_compile_instancing 
            //#pragma instancing_options rendering_layer
            // --------------------------------------------------
            // --------------------------------------------------
            // [關鍵] 告訴編譯器：我要根據這個關鍵字產生「變體」
            // shader_feature 適合用於材質球設定，沒用到的變體在打包時會被剔除
            #pragma shader_feature _USE_FRESNEL
            // --------------------------------------------------

            #include "UnlitFresnel.hlsl"
            ENDHLSL
        }
    }
}