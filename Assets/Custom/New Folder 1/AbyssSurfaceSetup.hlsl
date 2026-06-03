// 檔案：AbyssSurfaceSetup.hlsl
#ifndef ABYSS_SURFACE_SETUP_INCLUDED
#define ABYSS_SURFACE_SETUP_INCLUDED

#include "AbyssCore.hlsl"

// inline 修飾符提示編譯器展開此函式，減少函式呼叫開銷
inline void InitializeSurfaceData(Varyings input, out AbyssSurfaceData surface)
{
    // 1. 空間座標與視角向量初始化
    surface.positionWS = input.positionWS;
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
    
    // 在 InitializeSurfaceData 內部正確處理自發光
    #if defined(_EMISSION_ON)
        float2 emissionUV = input.uv * _EmissionMap_ST.xy + _EmissionMap_ST.zw;
        half4 emissionTex = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, emissionUV); // 可共用 BaseMap 取樣器
        surface.emission = emissionTex.rgb * _EmissionColor.rgb;
    #else
        surface.emission = 0;
    #endif
    
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

    // 3. 幾何向量與法線貼圖運算 (TBN 矩陣處理)
    // 確保經過插值後的法線與切線長度仍為 1
    float3 normalWS = normalize(input.normalWS);
    float3 tangentWS = normalize(input.tangentWS.xyz);

    #if defined(_USE_NORMALMAP)
        // 取樣法線貼圖
        half4 nTex = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv);
        // 解包法線貼圖並套用強度縮放 (_NormalScale)
        float3 tangentSpaceNormal = UnpackNormalScale(nTex, _NormalScale);
        
        // 構建 TBN 矩陣 (Tangent, Bitangent, Normal)
        // 利用叉積 (cross) 求出副切線 (Bitangent)，並乘上 input.tangentWS.w 修正鏡像 UV 導致的反向問題
        float3 bitangentWS = cross(normalWS, tangentWS) * input.tangentWS.w;
        
        // 將切線空間 (Tangent Space) 的法線轉換至世界空間 (World Space)
        surface.normalWS = normalize(TransformTangentToWorld(tangentSpaceNormal, half3x3(tangentWS, bitangentWS, normalWS)));
    #else
        // 若未使用法線貼圖，直接使用幾何法線
        surface.normalWS = normalWS;
    #endif

    surface.tangentWS = tangentWS;
}

#endif