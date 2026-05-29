#ifndef ABYSS_MAIN_INCLUDED
#define ABYSS_MAIN_INCLUDED

// 1. 載入所有依賴
#include "AbyssCore.hlsl"
#include "Effect_Fresnel.hlsl"
#include "Effect_Lighting.hlsl"
#include "Effect_Matcap.hlsl"
#include "Effect_AnisotropicHighlight.hlsl"

// 2. 頂點著色器：負責空間轉換Cull
Varyings vert(Attributes input)
{
    Varyings output;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    output.tangentWS = TransformObjectToWorldDir(input.tangentOS.xyz);
    
    return output;
}

// 3. 片元著色器：薄中心流水線
half4 frag(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    
    // --- Step 1: 初始化包裹 ---
    AbyssSurfaceData surface;
    half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
    surface.albedo = texColor.rgb * _BaseColor.rgb;
    surface.alpha = texColor.a * _BaseColor.a;
    surface.normalWS = normalize(input.normalWS);
    surface.positionWS = input.positionWS;
    surface.viewDirWS = normalize(GetCameraPositionWS() - input.positionWS);
    surface.emission = 0; // 初始無發光
    surface.tangentWS = normalize(input.tangentWS);
    // 2. 主流程負責向引擎討要目前的燈光資料
    Light mainLight = GetMainLight(); 

    // --- Step 2: 模組化加工 (按嚴格順序) ---
    
    #if defined(_USE_LIGHTING)
        ApplyBasicLighting(surface);
    #endif

    #if defined(_USE_FRESNEL)
        ApplyFresnel(surface);
    #endif

    #if defined(_USE_MATCAP)
        ApplyMatCap(surface);
    #endif
    
    #if defined(_USE_ANISOTROPIC)
        ApplyAnisotropicHighlight(surface, mainLight.direction, mainLight.color);
    #endif
    
    // --- Step 3: 結帳輸出 ---
    half3 finalColor = surface.albedo + surface.emission;
    return half4(finalColor, surface.alpha);
}

#endif