#ifndef ABYSS_WETNESS_INCLUDED
#define ABYSS_WETNESS_INCLUDED

inline void ApplyWeatherWetness(inout AbyssSurfaceData surface, float localWetness, float2 inputUV)
{
    // 1. 閥門控制
    float baseWetFactor = saturate(_GlobalRainIntensity * localWetness);
    if (baseWetFactor <= 0.001) return;

    // 2. 動態迎風面判定
    float rainDot = dot(surface.normalWS, -_GlobalRainDirection);
    half upwardFactor = smoothstep(_WetDirThreshold - _WetDirContrast, _WetDirThreshold + _WetDirContrast, rainDot);
    
    float finalWetPower = baseWetFactor * upwardFactor;
    if (finalWetPower <= 0.001) return;

    // ==========================================
    // 3. 決定「實際孔隙率」 (核心物理分層，包含 _GlobalPorosity)
    // ==========================================
    // 讀取 MaskMap 的 B 通道 (沒有貼圖時，引擎預設回傳 1.0)
    half texPorosity = SAMPLE_TEXTURE2D(_MaskMap, sampler_BaseMap, inputUV).b;
    
    // 將金屬度排除 (金屬絕不吸水)，並乘上你新增的全局孔隙率滑桿 (_GlobalPorosity)
    // 這樣你就能在沒有 MaskMap 的情況下，透過 UI 面板掌控這一切
    float actualPorosity = saturate(1.0 - surface.metallic) * saturate(texPorosity * _GlobalPorosity);

    // ==========================================
    // 4. 處理「高孔隙」特性：吸水變暗
    // ==========================================
    // 孔隙率越高 (如毛衣)，吸水變暗越嚴重
    float darkenFactor = lerp(1.0, 1.0 - _WetDarkenIntensity, finalWetPower * actualPorosity);
    surface.albedo *= darkenFactor;

    // ==========================================
    // 5. 計算「水膜成型率」(Water Film Power)
    // ==========================================
    // 殘酷的物理法則：孔隙率越高的材質（毛衣），水會滲透進去，【無法】在表面形成平滑水膜。
    // 只有孔隙率低的地方，水膜成型率才會逼近 1.0。
    float waterFilmPower = finalWetPower * saturate(1.0 - actualPorosity);

    // ==========================================
    // 6. 處理「低孔隙」特性：結成水膜 (只有 waterFilmPower > 0 才會發生)
    // ==========================================
    // (A) 填平微觀粗糙度，將平滑度拉升至 _WetSmoothnessMax
    // 毛衣因為 waterFilmPower 為 0，這裡完全不會被執行，徹底解決「毛衣油亮」的問題。
    surface.smoothness = lerp(surface.smoothness, _WetSmoothnessMax, waterFilmPower);

    // (B) 削弱金屬特性
    surface.metallic = lerp(surface.metallic, 0.0, waterFilmPower * 0.8);

    // (C) 抹平法線凹凸
    float3 flattenedNormal = normalize(lerp(surface.normalWS, -_GlobalRainDirection, waterFilmPower * _WetNormalFlatten));
    
    // (D) 顯示水滴法線
    float2 dropUV = inputUV * _RaindropScale;
    dropUV.y -= _Time.y * _RaindropSpeed;
    half4 dropSample = SAMPLE_TEXTURE2D(_RaindropMap, sampler_NormalMap, dropUV);
    float3 dropNormalTS = UnpackNormal(dropSample);

    float3 binormalWS = cross(surface.normalWS, surface.tangentWS.xyz) * surface.tangentWS.w;
    float3x3 tangentToWorld = float3x3(surface.tangentWS.xyz, binormalWS, surface.normalWS);
    float3 dropNormalWS = mul(dropNormalTS, tangentToWorld);

    // 【只有形成水膜的地方，才會有流動的水滴】
    surface.normalWS = normalize(lerp(flattenedNormal, dropNormalWS, waterFilmPower * 0.8));
}

#endif