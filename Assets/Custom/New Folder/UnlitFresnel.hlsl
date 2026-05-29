// [嚴厲警告] 檔案開頭必須加上 Include Guard，避免被其他檔案重複載入導致編譯崩潰
#ifndef UNLIT_FRESNEL_INCLUDED
#define UNLIT_FRESNEL_INCLUDED

// 把 URP 核心庫的引用移到這裡，確保這個 .hlsl 檔案具備獨立編譯的能力
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

// --------------------------------------------------
// 核心效能規範：SRP Batcher 相容性
// --------------------------------------------------
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    half4 _BaseColor;
    half4 _FresnelColor;
    float _FresnelPower;
CBUFFER_END

TEXTURE2D(_BaseMap);
SAMPLER(sampler_BaseMap);

// --------------------------------------------------
// 資料結構定義
// --------------------------------------------------
struct Attributes
{
    float4 positionOS   : POSITION;
    float2 uv           : TEXCOORD0;
    
    #if defined(_USE_FRESNEL)
    float3 normalOS     : NORMAL;
    #endif
    
    UNITY_VERTEX_INPUT_INSTANCE_ID 
};

struct Varyings
{
    float4 positionHCS  : SV_POSITION;
    float2 uv           : TEXCOORD0;

    #if defined(_USE_FRESNEL)
    float3 positionWS   : TEXCOORD1;
    float3 normalWS     : NORMAL;
    #endif
    
    UNITY_VERTEX_INPUT_INSTANCE_ID 
};

// --------------------------------------------------
// 頂點著色器 (Vertex Shader)
// --------------------------------------------------
Varyings vert(Attributes input)
{
    Varyings output;
    
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;

    #if defined(_USE_FRESNEL)
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    #endif
    
    return output;
}

// --------------------------------------------------
// 片元著色器 (Fragment Shader)
// --------------------------------------------------
half4 frag(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    
    half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
    half3 finalColor = texColor.rgb * _BaseColor.rgb;

    #if defined(_USE_FRESNEL)
    float3 normalWS = normalize(input.normalWS);
    float3 viewDirWS = normalize(GetCameraPositionWS() - input.positionWS);
    float NdotV = saturate(dot(normalWS, viewDirWS));
    float fresnelTerm = pow(1.0 - NdotV, _FresnelPower);

    finalColor += fresnelTerm * _FresnelColor.rgb;
    #endif
    
    return half4(finalColor, texColor.a * _BaseColor.a);
}

#endif // 結束 Include Guard