// 檔案：AbyssSurfaceSetup.hlsl
#ifndef ABYSS_SURFACE_SETUP_INCLUDED
#define ABYSS_SURFACE_SETUP_INCLUDED

#include "AbyssCore.hlsl"

// inline 修飾符提示編譯器展開此函式，減少函式呼叫開銷
inline void InitializeSurfaceData(Varyings input, out AbyssSurfaceData surface)
{
    // 1. 初始化結構體避免編譯警告
    surface = (AbyssSurfaceData)0;
    
    // 1. 空間座標與視角向量初始化
    surface.positionWS = input.positionWS;
    surface.positionOS = input.positionOS;
    surface.uv = input.uv; // 寫入 UV
    // 計算視角方向：攝影機世界座標減去頂點世界座標，並歸一化
    // 設相機位置是(5,8,2) 目標頂點位置是 (3,5,7)
    //(5,8,2) - (3,5,7) = (2,3,-5)，归一化得到 (0.324, 0.486, -0.811)。
    // 向量本身只代表“位移”，头尾由减法顺序决定
    // A - B 得到的是 从 B 指向 A 的向量。
    //
    // 这里 A = 摄像机位置，B = 顶点位置。
    // 所以这个向量 从顶点出发，指向摄像机，即 尾在顶点，头在摄像机。
    //
    // 怎么判断指向哪？
    // 不看数值大小，只看减法顺序。
    // 数值 (2,3,-5) 表示：从顶点出发，往 +X 走 2，往 +Y 走 3，往 -Z 走 5，就到了摄像机。
    // 所以方向是 朝着摄像机。这就是 viewDir 的定义。
    surface.viewDirWS = normalize(GetCameraPositionWS() - input.positionWS);
    
    // 2. 基礎色彩取樣
    // 透過巨集 SAMPLE_TEXTURE2D 進行貼圖取樣，並與材質屬性 _BaseColor 相乘
    // half4 是一个 向量类型，包含 4个分量，比如 (r, g, b, a)。
    // 它只是某个像素上的 一个颜色值，不是一整张图。
    // 比如 texColor = (0.5, 0.2, 0.8, 1.0)，这表示“这个像素的半透明紫色”。
    //
    // 纹理是二维数组，但你一次只取出一个元素，这个元素就是一个 half4（RGBA 颜色）。
    //
    // 对于显卡来说，纹理单元就是一个查询机器，输入 (u,v)，输出该位置的 half4 颜色值。这个查询由硬件并行执行，每个像素各自得到自己的 half4。
    half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
    surface.albedo = texColor.rgb * _BaseColor.rgb;
    surface.alpha = texColor.a * _BaseColor.a;

    // ==========================================
    // 【核心新增】：統一取樣 Mask Map 避免效能浪費 (這是特別的MRA不是Mask)
    // ==========================================
    // 讀取 Mask Map (如果沒放貼圖，引擎預設回傳 1,1,1,1)
    half4 maskTex = SAMPLE_TEXTURE2D(_MaskMap, sampler_BaseMap, input.uv);
    
    // 【靜態分軌】：處理不同材質的 Mask 通道定義
    #if defined(ABYSS_MATERIAL_CLOTH)
        surface.metallic = saturate(maskTex.r * _Metallic);
        surface.smoothness = saturate(maskTex.a * _Smoothness);
        surface.occlusion = saturate((lerp(1.0, maskTex.b, _OcclusionStrength) + _AOOffset) * _AOContrast + 0.5);
    #elif defined(ABYSS_MATERIAL_HAIR)
        // 頭髮的 Mask 定義：R = 1 - FrontHair, G = SpecMask, B = AO
        surface.frontHair = 1.0 - maskTex.r; 
        surface.specMask = maskTex.g;
        surface.occlusion = saturate(maskTex.b + _HairAOOffset);
        surface.metallic = 0.0; // 頭髮非金屬
    surface.smoothness = _HairEnvSmoothness;
    #else
        // 預設 Standard
        surface.metallic = saturate(maskTex.r * _Metallic);
        surface.smoothness = saturate(maskTex.a * _Smoothness);
        surface.occlusion = lerp(1.0, maskTex.b, _OcclusionStrength);
    #endif
    
    // ==========================================
    // 5. 幾何向量與法線貼圖運算 (TBN 矩陣處理)
    // ==========================================
    float3 normalWS = normalize(input.normalWS);
    float3 tangentWS = normalize(input.tangentWS.xyz);
    
    half4 nTex = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv);
    float3 tangentSpaceNormal = UnpackNormalScale(nTex, _NormalScale);
        
    float3 bitangentWS = cross(normalWS, tangentWS) * input.tangentWS.w;
    surface.normalWS = normalize(TransformTangentToWorld(tangentSpaceNormal, half3x3(tangentWS, bitangentWS, normalWS)));
    surface.tangentWS = float4(tangentWS, input.tangentWS.w);

    // ==========================================
    // 6. 自發光 (Emission)
    // ==========================================
    float2 emissionUV = input.uv * _EmissionMap_ST.xy + _EmissionMap_ST.zw;
    half4 emissionTex = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, emissionUV); 
    surface.emission = emissionTex.rgb * _EmissionColor.rgb;
}

#endif