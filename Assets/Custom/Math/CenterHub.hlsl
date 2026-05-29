#ifndef CENTER_HUB_INCLUDED
#define CENTER_HUB_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// 引入純數學算法庫
#include "Math_Fresnel.hlsl"
#include "Math_Lighting.hlsl"

// 資料宣告 (由中心統包)
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    half4  _BaseColor;
    half4  _FresnelColor;
    float  _FresnelPower;
CBUFFER_END

TEXTURE2D(_BaseMap);
SAMPLER(sampler_BaseMap);

// 3. 頂點與片元傳輸結構
struct Attributes
{
    float4 positionOS   : POSITION;
    float2 uv           : TEXCOORD0;
    float3 normalOS     : NORMAL;
    UNITY_VERTEX_INPUT_INSTANCE_ID 
};

struct Varyings
{
    float4 positionHCS  : SV_POSITION;
    float2 uv           : TEXCOORD0;
    float3 positionWS   : TEXCOORD1;
    float3 normalWS     : NORMAL;
    UNITY_VERTEX_INPUT_INSTANCE_ID 
};


Varyings vert(Attributes input)
{
    Varyings output;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    
    return output;
}

// ==========================================
// 核心處理器 (The Hub)
// ==========================================
half4 frag(Varyings input) : SV_Target
{
    // 1. 狀態初始化：由中心親自管理基礎狀態
    half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
    half3 finalColor = texColor.rgb * _BaseColor.rgb;
    
    // 準備共用參數
    float3 normalWS = normalize(input.normalWS);
    float3 viewDirWS = normalize(GetCameraPositionWS() - input.positionWS);

    // 2. 呼叫外部算法，並由中心「親自處理」邏輯
    
    #if defined(_USE_LIGHTING)
        Light mainLight = GetMainLight();
        // 向外部要計算結果
        half3 diffuse = CalculateLambertDiffuse(normalWS, mainLight.direction, mainLight.color, mainLight.shadowAttenuation);
        // 由中心決定：光照是「相乘 (*)」
        finalColor *= diffuse; 
    #endif

    #if defined(_USE_FRESNEL)
        // 向外部要計算結果
        half3 fresnelGlow = CalculateFresnelGlow(normalWS, viewDirWS, _FresnelPower, _FresnelColor.rgb);
        // 由中心決定：發光是「相加 (+)」
        finalColor += fresnelGlow; 
    #endif

    // 3. 輸出最終狀態
    return half4(finalColor, texColor.a * _BaseColor.a);
}

#endif