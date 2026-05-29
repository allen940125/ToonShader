Shader "Abyss/MathDriven_DOTS"
{
    Properties
    {
        [Header(Base Settings)]
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1,1,1,1)
        
        [Header(Lighting)]
        [Toggle(_USE_LIGHTING)] _UseLighting("開啟受光與陰影", Float) = 1
        
        [Header(Fresnel Glow)]
        [Toggle(_USE_FRESNEL)] _UseFresnel("開啟菲涅耳", Float) = 0
        [HDR] _FresnelColor("Fresnel Color", Color) = (0, 1, 1, 1)
        _FresnelPower("Fresnel Power", Range(0.1, 10)) = 2.0
    }

    SubShader
    {
        // 告訴 Unity 這是不透明物件，並且使用 URP 管線
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "ForwardLit"
            // [關鍵] 必須是 UniversalForward，引擎才會把主燈光與陰影數據傳進來
            Tags { "LightMode" = "UniversalForward" } 
            
            HLSLPROGRAM
            #pragma target 3.5
            
            // --------------------------------------------------
            // 1. 核心效能：DOTS 與 GPU Instancing 支援
            // --------------------------------------------------
            #pragma multi_compile_instancing
            
            // --------------------------------------------------
            // 2. [TA 隱藏細節] URP 陰影系統必備巨集
            // 如果沒有這三行，你的 GetMainLight().shadowAttenuation 永遠只會輸出 1 (沒有陰影)
            // --------------------------------------------------
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _SHADOWS_SOFT
            
            // --------------------------------------------------
            // 3. 你的自定義變體開關
            // --------------------------------------------------
            #pragma shader_feature _USE_LIGHTING
            #pragma shader_feature _USE_FRESNEL
            
            // --------------------------------------------------
            // 4. 註冊 VS 與 PS 進入點
            // --------------------------------------------------
            #pragma vertex vert
            #pragma fragment frag
            
            // --------------------------------------------------
            // 5. 匯入你的中心處理器
            // 由於在同一個資料夾，直接寫檔名即可
            // --------------------------------------------------
            #include "CenterHub.hlsl"
            
            ENDHLSL
        }
        
        // (可選) 這裡可以再補上一個 ShadowCaster Pass，讓這個物件能投射陰影給別人
        // 目前為了保持範例純粹先省略
    }
}