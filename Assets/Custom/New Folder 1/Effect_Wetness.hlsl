#ifndef ABYSS_WETNESS_INCLUDED
#define ABYSS_WETNESS_INCLUDED

inline void ApplyWeatherWetness(inout AbyssSurfaceData surface, float localWetness)
{
    // 1. 閥門控制：全域雨勢與局部腳本判定結合
    float baseWetFactor = saturate(_GlobalRainIntensity * localWetness);
    if (baseWetFactor <= 0.001) return;

    // 2. 動態迎風面判定 (取代原本寫死的 normalWS.y)
    // 利用法線與「雨水反方向」的內積，計算出迎風面。
    // 雨如果斜著下，角色的正面或側面就會被判定為受雨面。
    half upwardFactor = saturate(dot(surface.normalWS, -_GlobalRainDirection));
    
    // 最終作用在 PBR 屬性上的濕潤權重
    float finalWetPower = baseWetFactor * upwardFactor;

    // 3. PBR 屬性劫持 (保持不變)
    float porosity = saturate(1.0 - surface.metallic);
    float darkenFactor = lerp(1.0, 0.35, finalWetPower * porosity);
    surface.albedo *= darkenFactor;

    surface.smoothness = lerp(surface.smoothness, 0.95, finalWetPower);
    surface.metallic = lerp(surface.metallic, 0.0, finalWetPower * 0.5);

    // 微觀法線平滑：朝向「雨水反方向」抹平，而不是絕對朝上
    surface.normalWS = normalize(lerp(surface.normalWS, -_GlobalRainDirection, finalWetPower * 0.5));
}

#endif