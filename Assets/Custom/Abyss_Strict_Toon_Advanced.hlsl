#ifndef ABYSS_STRICT_TOON_ADVANCED_INCLUDED
#define ABYSS_STRICT_TOON_ADVANCED_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Assets/Custom/Abyss_NPR_Lib.hlsl"

// 【修正】補全 ShadowCaster 所需的全域燈光變數
float3 _LightDirection;
float3 _LightPosition;

// 紋理與採樣器
TEXTURE2D(_BaseMap);
SAMPLER(sampler_BaseMap);
TEXTURE2D(_RampMap);
SAMPLER(sampler_RampMap);
TEXTURE2D(_1st_ShadeMap);

// CBUFFER：所有 Material 屬性（支援 GPU Instancing）
UNITY_INSTANCING_BUFFER_START(Props)
    UNITY_DEFINE_INSTANCED_PROP(half4, _BaseColor)
    UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
    UNITY_DEFINE_INSTANCED_PROP(half, _MinBrightness)
    UNITY_DEFINE_INSTANCED_PROP(half, _IndirectLightMultiplier)
    UNITY_DEFINE_INSTANCED_PROP(half, _Alpha)
    UNITY_DEFINE_INSTANCED_PROP(float, _OutlineWidth)
    UNITY_DEFINE_INSTANCED_PROP(half4, _OutlineColor)
    UNITY_DEFINE_INSTANCED_PROP(half4, _RimColor)
    UNITY_DEFINE_INSTANCED_PROP(half, _RimPower)
    UNITY_DEFINE_INSTANCED_PROP(half, _RimThreshold)
    UNITY_DEFINE_INSTANCED_PROP(half, _RimLightAlign)
    UNITY_DEFINE_INSTANCED_PROP(half4, _SpecularColor)
    UNITY_DEFINE_INSTANCED_PROP(half, _SpecularSize)
    UNITY_DEFINE_INSTANCED_PROP(half, _SpecularSoftness)

    UNITY_DEFINE_INSTANCED_PROP(half, _1st_ToonThreshold)
    UNITY_DEFINE_INSTANCED_PROP(half, _1st_ToonSmoothness)
    UNITY_DEFINE_INSTANCED_PROP(half4, _ShadowColor)

    // 二階陰影
    UNITY_DEFINE_INSTANCED_PROP(half, _2nd_ToonThreshold)
    UNITY_DEFINE_INSTANCED_PROP(half, _2nd_ToonSmoothness)
    UNITY_DEFINE_INSTANCED_PROP(half4, _2nd_ShadowColor)

    // 三階陰影
    UNITY_DEFINE_INSTANCED_PROP(half, _3rd_ToonThreshold)
    UNITY_DEFINE_INSTANCED_PROP(half, _3rd_ToonSmoothness)
    UNITY_DEFINE_INSTANCED_PROP(half4, _3rd_ShadowColor)

    UNITY_DEFINE_INSTANCED_PROP(float, _AbyssShadowBias)
UNITY_INSTANCING_BUFFER_END(Props)

// Dither 裁剪
inline void ApplyAbyssDither(float4 positionCS, half targetAlpha)
{
    uint2 pixelPos = uint2(positionCS.xy);
    const float4x4 ditherMatrix = float4x4(
        0.0625, 0.5625, 0.1875, 0.6875,
        0.8125, 0.3125, 0.9375, 0.4375,
        0.2500, 0.7500, 0.1250, 0.6250,
        1.0000, 0.5000, 0.8750, 0.3750
    );
    float ditherThreshold = ditherMatrix[pixelPos.x % 4][pixelPos.y % 4];
    clip(targetAlpha - ditherThreshold);
}

// 通用頂點結構
struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float2 uv         : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS   : TEXCOORD2;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

// 通用頂點著色器
Varyings VertBase(Attributes IN)
{
    Varyings OUT;
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

    float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
    float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);

#if defined(SHADERPASS) && (SHADERPASS == SHADERPASS_SHADOWCASTER)
    // Shadow Terminator 修正：沿法線方向做 bias 偏移，消除鋸齒
    positionWS = ApplyShadowBias(positionWS, normalWS, _LightDirection);
    OUT.positionCS = TransformWorldToHClip(positionWS);
#else
    OUT.positionCS = TransformWorldToHClip(positionWS);
#endif

    OUT.positionWS = positionWS;
    OUT.normalWS   = normalWS;
    OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
    return OUT;
}

// 核心光照計算
half3 CalculateAbyssToon(
    Light light, half3 normalWS, half3 viewDirWS, float2 uv, half3 texColor,
    half3 baseColor, half3 shadowColorTint, half toonThreshold, half toonSmooth,
    half3 specColor, half specSize, half specSoft,
    half3 rimColor, half rimPower, half rimHardThreshold, half rimAlign)
{
    // 【修正】將 URP 軟陰影轉為 0 或 1 的硬切遮罩
    half toonCastShadow = step(0.5, light.shadowAttenuation);

    // 一階陰影顏色（貼圖或純色）
    #ifdef _USE_SHADEMAP
        half3 shadeMapColor = SAMPLE_TEXTURE2D(_1st_ShadeMap, sampler_BaseMap, uv).rgb;
        half3 firstShadowColor = shadeMapColor * shadowColorTint;
    #else
        half3 firstShadowColor = baseColor * shadowColorTint;
    #endif

    half3 colorResult = 0;

    // ---------- 漫反射 ----------
    #ifdef _USE_RAMP
        // 模式二：呼叫貼圖欺騙模式。投影陰影直接強制 UV 往暗部移動
        float rampUV = CalculateAbyssRampUV(normalWS, light.direction);
        half3 rampColor = SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap, float2(rampUV, 0.5)).rgb;
        colorResult = baseColor * rampColor;
    #else
        // 模式一：純數學多階硬切模式
        // [1st Shade]
        half mask1 = CalculateAbyssToonMask(normalWS, light.direction, toonThreshold, toonSmooth);
        mask1 *= toonCastShadow; // 投影陰影僅剝奪一階
        half3 shadedColor = lerp(firstShadowColor, baseColor, mask1);

        // [2nd Shade]
        #ifdef _USE_2ND_SHADE
            half secondThreshold = UNITY_ACCESS_INSTANCED_PROP(Props, _2nd_ToonThreshold);
            half secondSmooth    = UNITY_ACCESS_INSTANCED_PROP(Props, _2nd_ToonSmoothness);
            half3 secondColor    = UNITY_ACCESS_INSTANCED_PROP(Props, _2nd_ShadowColor).rgb;
            half mask2 = CalculateAbyssToonMask(normalWS, light.direction, secondThreshold, secondSmooth);
            shadedColor = lerp(secondColor, shadedColor, mask2);
        #endif

        // [3rd Shade]
        #ifdef _USE_3RD_SHADE
            half thirdThreshold = UNITY_ACCESS_INSTANCED_PROP(Props, _3rd_ToonThreshold);
            half thirdSmooth    = UNITY_ACCESS_INSTANCED_PROP(Props, _3rd_ToonSmoothness);
            half3 thirdColor    = UNITY_ACCESS_INSTANCED_PROP(Props, _3rd_ShadowColor).rgb;
            half mask3 = CalculateAbyssToonMask(normalWS, light.direction, thirdThreshold, thirdSmooth);
            shadedColor = lerp(thirdColor, shadedColor, mask3);
        #endif

        colorResult = shadedColor;
    #endif

    // ---------- 高光 ----------
    half3 finalSpecular = 0;
    #ifdef _USE_SPECULAR
        half3 H = SafeNormalize(light.direction + viewDirWS);
        half NdotH = saturate(dot(normalWS, H));
        half specThreshold = 1.0 - specSize;
        half toonSpecMask = smoothstep(specThreshold - specSoft, specThreshold + specSoft, NdotH);
        
        half NdotL = dot(normalWS, light.direction);
        half lightMask = saturate(NdotL * 10.0);
        
        // 【修正】高光受硬切投影陰影遮擋
        finalSpecular = specColor * toonSpecMask * lightMask * toonCastShadow;
    #endif

    // ---------- 邊緣光 ----------
    half3 finalRim = 0;
    #ifdef _USE_RIM
        half NdotV = saturate(dot(normalWS, viewDirWS));
        half baseFresnel = pow(1.0 - NdotV, rimPower);
        half toonRimMask = smoothstep(rimHardThreshold - 0.01, rimHardThreshold + 0.01, baseFresnel);
        
        half NdotL_Rim = dot(normalWS, light.direction);
        half lightMaskForRim = saturate(NdotL_Rim + rimAlign);
        
        // 【修正】邊緣光受硬切投影陰影遮擋
        finalRim = rimColor * (toonRimMask * lightMaskForRim * toonCastShadow);
    #endif

    half3 finalColor = colorResult + finalSpecular + finalRim;
    
    // 【修正】絕對不乘上 light.shadowAttenuation，徹底切斷軟陰影的介入
    return finalColor * texColor * light.color * light.distanceAttenuation;
}

// Forward Pass 片段著色器
half4 FragToon(Varyings IN) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(IN);

    half targetAlpha   = UNITY_ACCESS_INSTANCED_PROP(Props, _Alpha);
    half4 baseColor    = UNITY_ACCESS_INSTANCED_PROP(Props, _BaseColor);
    half4 shadowColor  = UNITY_ACCESS_INSTANCED_PROP(Props, _ShadowColor);
    half minBright     = UNITY_ACCESS_INSTANCED_PROP(Props, _MinBrightness);
    half indMultiplier = UNITY_ACCESS_INSTANCED_PROP(Props, _IndirectLightMultiplier);
    half toonThreshold = UNITY_ACCESS_INSTANCED_PROP(Props, _1st_ToonThreshold);
    half toonSmooth    = UNITY_ACCESS_INSTANCED_PROP(Props, _1st_ToonSmoothness);
    float shadowBias   = UNITY_ACCESS_INSTANCED_PROP(Props, _AbyssShadowBias);
    half4 specColor    = UNITY_ACCESS_INSTANCED_PROP(Props, _SpecularColor);
    half specSize      = UNITY_ACCESS_INSTANCED_PROP(Props, _SpecularSize);
    half specSoft      = UNITY_ACCESS_INSTANCED_PROP(Props, _SpecularSoftness);

    ApplyAbyssDither(IN.positionCS, targetAlpha);

    half4 texMap   = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
    half3 texColor = texMap.rgb;

    float3 normalWS  = normalize(IN.normalWS);
    float3 viewDirWS = SafeNormalize(GetCameraPositionWS() - IN.positionWS);

    InputData inputData = (InputData)0;
    inputData.positionWS = IN.positionWS;
    inputData.positionCS = IN.positionCS;
    inputData.normalizedScreenSpaceUV = IN.positionCS.xy / _ScreenParams.xy;
    inputData.normalWS = normalWS;

    // 環境光
    half3 envLight    = SampleSH(normalWS) * indMultiplier;
    half3 ambientBase = max(envLight, minBright);

    // 主燈光
    Light mainLight = GetMainLight();
    // 接收端陰影 Bias 偏移
    float3 shadowTestPosWS = IN.positionWS + mainLight.direction * shadowBias;
    mainLight.shadowAttenuation = MainLightRealtimeShadow(TransformWorldToShadowCoord(shadowTestPosWS));

    half4 rimColor = UNITY_ACCESS_INSTANCED_PROP(Props, _RimColor);
    half rimPower  = UNITY_ACCESS_INSTANCED_PROP(Props, _RimPower);
    half rimThresh = UNITY_ACCESS_INSTANCED_PROP(Props, _RimThreshold);
    half rimAlign  = UNITY_ACCESS_INSTANCED_PROP(Props, _RimLightAlign);

    half3 finalColor = CalculateAbyssToon(
        mainLight, normalWS, viewDirWS, IN.uv, texColor,
        baseColor.rgb, shadowColor.rgb, toonThreshold, toonSmooth,
        specColor.rgb, specSize, specSoft,
        rimColor.rgb, rimPower, rimThresh, rimAlign
    );

    // 附加燈光
    #ifdef _ADDITIONAL_LIGHTS
    uint pixelLightCount = GetAdditionalLightsCount();
    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light addLight = GetAdditionalLight(lightIndex, IN.positionWS);
        float3 addShadowPosWS = IN.positionWS + addLight.direction * shadowBias;
        addLight.shadowAttenuation = AdditionalLightRealtimeShadow(lightIndex, addShadowPosWS);
        finalColor += CalculateAbyssToon(
            addLight, normalWS, viewDirWS, IN.uv, texColor,
            baseColor.rgb, shadowColor.rgb, toonThreshold, toonSmooth,
            specColor.rgb, specSize, specSoft,
            rimColor.rgb, rimPower, rimThresh, rimAlign
        );
    LIGHT_LOOP_END
    #endif

    half3 finalRGB = (texColor * ambientBase) + finalColor;
    return half4(finalRGB, 1.0);
}

// ShadowCaster Pass
half4 FragShadow(Varyings IN) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(IN);
    half targetAlpha = UNITY_ACCESS_INSTANCED_PROP(Props, _Alpha);
    ApplyAbyssDither(IN.positionCS, targetAlpha);
    return 0;
}

// DepthOnly Pass
half4 FragDepth(Varyings IN) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(IN);
    half targetAlpha = UNITY_ACCESS_INSTANCED_PROP(Props, _Alpha);
    ApplyAbyssDither(IN.positionCS, targetAlpha);
    return 0;
}

// Outline Pass 結構
struct AttributesOutline
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct VaryingsOutline
{
    float4 positionCS : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

VaryingsOutline VertOutline(AttributesOutline IN)
{
    VaryingsOutline OUT;
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
    float width = UNITY_ACCESS_INSTANCED_PROP(Props, _OutlineWidth);
    float3 extrudedPositionOS = IN.positionOS.xyz + IN.normalOS * (width * 0.001);
    OUT.positionCS = TransformObjectToHClip(extrudedPositionOS);
    return OUT;
}

half4 FragOutline(VaryingsOutline IN) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(IN);
    half targetAlpha = UNITY_ACCESS_INSTANCED_PROP(Props, _Alpha);
    ApplyAbyssDither(IN.positionCS, targetAlpha);
    half4 color = UNITY_ACCESS_INSTANCED_PROP(Props, _OutlineColor);
    return color;
}

#endif