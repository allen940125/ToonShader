#ifndef ABYSS_SHARED_INCLUDED
#define ABYSS_SHARED_INCLUDED

#include "AbyssCore.hlsl"
#include "AbyssSurfaceSetup.hlsl"
#include "Effect_Outline.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

#if defined(PASS_FORWARD)
    #include "Effect_Fresnel.hlsl"
    #include "Effect_Lighting.hlsl"
    #include "Effect_Matcap.hlsl"
    #include "Effect_AnisotropicHighlight.hlsl"
#endif

// ---- 透明度裁切（合併 Alpha Clip 與 Dither） ----
inline void DoTransparencyClip(half alpha, float2 screenPos)
{
    #if defined(_TRANSPARENCY_MODE_CUTOUT)
        clip(alpha - _AlphaClipThreshold);
    #elif defined(_TRANSPARENCY_MODE_DITHER)
        float2 ditherUV = screenPos * _ScreenParams.xy / _DitherScale;
        half dither = SAMPLE_TEXTURE2D(_DitherMap, sampler_DitherMap, ditherUV).a;
        clip((alpha * _DitherThreshold) - dither);
    #endif
    // _TRANSPARENCY_MODE_OPAQUE：不執行任何裁切
}

// ---- 統一頂點著色器 ----
Varyings vert(Attributes input)
{
    Varyings output;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    output.uv = input.uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
    output.normalWS = TransformObjectToWorldNormal(input.normalOS);
    real sign = input.tangentOS.w * GetOddNegativeScale();
    output.tangentWS = float4(TransformObjectToWorldDir(input.tangentOS.xyz), sign);

    // ---- 根據 Pass 分支 ----
    #if defined(PASS_OUTLINE)
        #if defined(_USE_OUTLINE)
            float positionVS_Z = TransformWorldToView(output.positionWS).z;
            float outlineMultiplier = GetOutlineCameraFovAndDistanceFixMultiplier(positionVS_Z);
            float finalOutlineWidth = _OutlineWidth * outlineMultiplier;
            float3 posOS = input.positionOS.xyz + input.normalOS * finalOutlineWidth;
            output.positionHCS = TransformObjectToHClip(posOS);
        #else
            output.positionHCS = float4(0, 0, 0, 0);
        #endif
    #elif defined(PASS_SHADOW_CASTER)
        output.positionHCS = TransformWorldToHClip(ApplyShadowBias(output.positionWS, output.normalWS, 0));
    #else
        output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
    #endif

    output.screenPos = ComputeScreenPos(output.positionHCS);
    return output;
}

// ---- 統一片段著色器 ----
half4 frag(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);

    // ---- 1. 陰影投射 Pass ----
    #if defined(PASS_SHADOW_CASTER)
        half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
        DoTransparencyClip(alpha, input.screenPos.xy / input.screenPos.w);
        return 0;
    #endif

    // ---- 2. 深度法線 Pass ----
    #if defined(PASS_DEPTH)
        half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
        DoTransparencyClip(alpha, input.screenPos.xy / input.screenPos.w);
        return 0;
    #endif

    // ---- 3. 描邊 Pass ----
    #if defined(PASS_OUTLINE)
        half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
        DoTransparencyClip(alpha, input.screenPos.xy / input.screenPos.w);
        return _OutlineColor;
    #endif

    // ---- 4. 前向渲染 Pass ----
    #if defined(PASS_FORWARD)
        AbyssSurfaceData surface;
        InitializeSurfaceData(input, surface);

        // 透明度裁切（根據枚舉關鍵字自動選擇）
        DoTransparencyClip(surface.alpha, input.screenPos.xy / input.screenPos.w);

        // 主光源
        float4 shadowCoord = TransformWorldToShadowCoord(surface.positionWS);
        Light mainLight = GetMainLight(shadowCoord);

        // ==========================================
        // 【修正】：AO (環境光遮蔽) 融合系統
        // ==========================================
        float2 screenUV = input.screenPos.xy / input.screenPos.w;
        half ssao = 1.0;
                
        // 1. 讀取 URP 實時 SSAO
        #if defined(_SCREEN_SPACE_OCCLUSION)
        AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(screenUV);
        ssao = aoFactor.indirectAmbientOcclusion; 
        #endif

        // 2. 【核心修正】：直接從 Surface 拿取 AO，不再呼叫 SAMPLE_TEXTURE2D
        half bakedAO = lerp(1.0, surface.occlusion, _OcclusionStrength);

        // 3. 兩者結合 (取最暗的作為最終遮蔽值)
        half finalAO = min(ssao, bakedAO);
        // ==========================================
    
        half3 finalColor = surface.albedo;
        #if defined(_USE_LIGHTING)
        // 將計算好的 finalAO 傳入光照函式
        finalColor = ComputeFinalLighting(surface, mainLight, finalAO);
        #endif

        // 效果疊加（各函式內部自行檢查強度）
        ApplyFresnel(surface);
        ApplyMatCap(surface);
        ApplyAnisotropicHighlight(surface, mainLight);

        // 最終合成
        finalColor += surface.emission;

        return half4(finalColor, surface.alpha);
    #endif

    // Fallback 調試
    return half4(1, 0, 1, 1);
}

#endif // ABYSS_SHARED_INCLUDED