#ifndef ABYSS_SHARED_INCLUDED
#define ABYSS_SHARED_INCLUDED

// 引入核心定義 (結構、CBUFFER、貼圖)
#include "AbyssCore.hlsl"
#include "AbyssSurfaceSetup.hlsl"
#include "Effect_Outline.hlsl"

// 額外依賴 (ShadowCaster 需要的深度偏差函數)
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

// 利用編譯巨集過濾：僅在 Forward Pass 時才引入光照與視覺特效模組，減少其他 Pass 的編譯負擔
#if defined(PASS_FORWARD)
    #include "Effect_Fresnel.hlsl"
    #include "Effect_Lighting.hlsl"
    #include "Effect_Matcap.hlsl"
    #include "Effect_AnisotropicHighlight.hlsl"
#endif

// ===============================
// 統一的頂點著色器 (Vertex Shader)
// 邏輯目的：處理多個 Pass 共通的空間轉換，並根據巨集決定最終裁剪空間座標的計算方式。
// ===============================
Varyings vert(Attributes input)
{
    Varyings output;
    
    // GPU Instancing 設置
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    // 共通處理：計算 UV 並轉換至世界空間
    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    
    // 處理切線方向與符號：GetOddNegativeScale() 用於處理負縮放 (Negative Scale) 時的法線/切線反轉問題
    real sign = input.tangentOS.w * GetOddNegativeScale();
    output.tangentWS = float4(TransformObjectToWorldDir(input.tangentOS.xyz), sign);

    // ---- 根據不同 Pass 編譯對應的頂點邏輯 ----
    #if defined(PASS_OUTLINE)
        #if defined(_USE_OUTLINE)
            
            // 1. 取得頂點在觀察空間 (View Space) 的 Z 值，即頂點距離攝影機的深度
            float positionVS_Z = TransformWorldToView(output.positionWS).z;
            
            // 2. 應用距離與視野 (FOV) 修正乘數，確保描邊寬度在不同距離和縮放不變形
            float outlineMultiplier = GetOutlineCameraFovAndDistanceFixMultiplier(positionVS_Z);
            
            // 3. 計算最終的描邊寬度 (基礎寬度 * 修正乘數)
            float finalOutlineWidth = _OutlineWidth * outlineMultiplier;
            
            // 4. 法線外擴：將頂點沿著物件空間的法線方向向外推擠
            float3 posOS = input.positionOS.xyz + input.normalOS * finalOutlineWidth;
            
            // 5. 將推擠後的座標轉換至齊次裁剪空間
            output.positionHCS = TransformObjectToHClip(posOS);

        #else
            // 若關閉描邊功能，將頂點收斂至原點 (退化三角形)，光柵化階段會將其直接剔除
            output.positionHCS = float4(0, 0, 0, 0);
        #endif
    #elif defined(PASS_SHADOW_CASTER)
        // 陰影投射 Pass：計算深度偏差 (Shadow Bias) 以解決陰影粉刺 (Shadow Acne) 問題
        output.positionHCS = TransformWorldToHClip(ApplyShadowBias(output.positionWS, output.normalWS, 0));
    #else 
        // 預設 (FORWARD 或 DEPTH Pass)：標準的物件至裁剪空間轉換
        output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
    #endif

    return output;
}

// ===============================
// 統一的片段著色器 (Fragment Shader)
// 邏輯目的：作為一個管線控制器，僅依序呼叫組件，不在此處撰寫具體的數學邏輯。
// ===============================
half4 frag(Varyings input) : SV_Target
{
    // GPU Instancing 設置
    UNITY_SETUP_INSTANCE_ID(input);

    // 陰影與深度 Pass 不需輸出顏色，直接返回 0 節省效能
    #if defined(PASS_SHADOW_CASTER)
    return 0;
    #elif defined(PASS_DEPTH)
    return 0;
    
    // 描邊 Pass 直接輸出材質設定的純色
    #elif defined(PASS_OUTLINE)
    return _OutlineColor;

    // 前向渲染 Pass (Forward) - 核心光照與特效邏輯
    #elif defined(PASS_FORWARD)
        
    AbyssSurfaceData surface;
        
    // ---- 1. 初始化 SurfaceData ----
    // 提取所有幾何數據與基礎貼圖資訊
    InitializeSurfaceData(input, surface);

    // ---- 2. 環境設定與主光源獲取 ----
    half3 finalColor = surface.albedo; 
    
    // 轉換世界座標至陰影貼圖空間，並取得主光源 (Main Light) 資訊 (方向、顏色、陰影衰減)
    float4 shadowCoord = TransformWorldToShadowCoord(surface.positionWS);
    Light mainLight = GetMainLight(shadowCoord);
    
    // ---- 3. 特效組件疊加 (透過巨集開關控制) ----
    #if defined(_USE_LIGHTING)
    finalColor = ApplyBasicLighting(surface, mainLight);
    #endif

    #if defined(_USE_FRESNEL)
    ApplyFresnel(surface); // 通常 Fresnel 會將結果寫入 surface.emission
    #endif
        
    #if defined(_USE_MATCAP)
    ApplyMatCap(surface);  // MatCap 同樣可能修改 albedo 或 emission
    #endif
        
    #if defined(_USE_ANISOTROPIC)
    ApplyAnisotropicHighlight(surface, mainLight); // 各向異性高光疊加
    #endif

    // ---- 4. 最終合成輸出 ----
    // 結合基礎色與所有的附加自發光/高光計算
    finalColor += surface.emission; 
        
    return half4(finalColor, surface.alpha);
    #endif

    // Fallback 顏色，若未定義任何 Pass 巨集則輸出亮洋紅色 (Magenta)，用於快速除錯 (Debug)
    return half4(1, 0, 1, 1);
}

#endif