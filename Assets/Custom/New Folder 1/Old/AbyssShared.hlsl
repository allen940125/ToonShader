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
    #include "Effect_Wetness.hlsl"
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

        #if defined(_WEATHER_WETNESS_ON)
            ApplyWeatherWetness(surface, _LocalWetness, input.uv);
        #endif
    
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

        // ==========================================
        // 【偵錯覆蓋：根據 _DebugViewMode 顯示特定數值】
        // ==========================================
        // 1. 先計算視角方向（RimLight 和高光都需要）
        half3 viewDir = SafeNormalize(GetWorldSpaceViewDir(surface.positionWS));

        // 2. 根據模式覆蓋 finalColor
        if (_DebugViewMode == 1.0) // Shadow (陰影)
        {
            finalColor = mainLight.shadowAttenuation.xxx;
        }
        else if (_DebugViewMode == 2.0) // Highlight (高光)
        {
            half3 halfDir = SafeNormalize(mainLight.direction + viewDir);
            half NdotH = max(0.0, dot(surface.normalWS, halfDir));
            half spec = smoothstep(_SpecularStep - _SpecularFeather, _SpecularStep + _SpecularFeather, NdotH);
            finalColor = _SpecularColor * spec * _SpecularIntensity;
        }
        else if (_DebugViewMode == 3.0) // AO (環境光遮蔽)
        {
            finalColor = finalAO.xxx;
        }
        else if (_DebugViewMode == 4.0) // RimLight (邊緣光)
        {
            half rim = 1.0 - max(0.0, dot(surface.normalWS, viewDir));
            rim = pow(rim, _RimPower);
            half rimIntensity = smoothstep(_RimThreshold - _RimSmoothness, _RimThreshold + _RimSmoothness, rim);
            finalColor = _RimColor * rimIntensity;
        }
        else if (_DebugViewMode == 5.0) // Albedo (基礎色)
        {
            finalColor = surface.albedo;
        }
        else if (_DebugViewMode == 6.0) // Normal (法线)
        {
            // 将法线从 [-1,1] 映射到 [0,1] 以便显示
            finalColor = surface.normalWS * 0.5 + 0.5;
        }
        else if (_DebugViewMode == 7.0) // Metallic (金属度)
        {
            finalColor = surface.metallic.xxx;
        }
        else if (_DebugViewMode == 8.0) // Smoothness (平滑度)
        {
            finalColor = surface.smoothness.xxx;
        }
        else if (_DebugViewMode == 9.0) // Emission (自发光)
        {
            // 注意：emission 可能是 HDR 值，直接输出可能会过亮，可以除以一个常数或 clamp
            finalColor = surface.emission; // 或 saturate(surface.emission) 防止刺眼
        }
        // 若為 0 (None)，則不覆蓋，維持原本的渲染結果
        
        return half4(finalColor, surface.alpha);
    #endif

    // Fallback 調試
    return half4(1, 0, 1, 1);
}

#endif // ABYSS_SHARED_INCLUDED