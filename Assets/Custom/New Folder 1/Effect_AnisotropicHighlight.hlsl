#ifndef EFFECT_ANISOTROPIC_INCLUDED
#define EFFECT_ANISOTROPIC_INCLUDED

// 假設你已經將 tangentWS (世界空間切線) 加入了你的 AbyssSurfaceData 結構中
inline void ApplyAnisotropicHighlight(inout AbyssSurfaceData surface, Light mainLight)
{
    // 1. 計算半角向量 H
    float3 H = normalize(mainLight.direction + surface.viewDirWS);
    
    // 2. 獲取切線 T (這裡假設 surface 裡面已經有傳入 tangentWS)
    // 通常為了避免除以零或浮點數精度問題，會稍微 normalize 一下
    float3 T = normalize(surface.tangentWS);
    
    // 3. 計算 T 與 H 的點積 (即 cos 角度)
    float TdotH = dot(T, H);
    
    // 4. 計算 sin(T, H) = sqrt(1 - cos^2)
    // 使用 max(0.001, ...) 防止開根號裡面變成負數導致 NaN
    float sinTH = sqrt(max(0.001, 1.0 - TdotH * TdotH));
    
    // 5. 套用高光指數 (Power 控制光斑的細長程度，數值越大越細)
    float specularIntensity = pow(sinTH, _AnisoPower);
    
    float3 color = mainLight.color * _AnisoColor.rgb;
    
    // 6. 偏移 (Shift) 控制 - 進階選項
    // 如果是頭髮，高光中心通常不會剛好在正中央，會依據副切線方向做些微偏移
    // 這裡示範最簡單的純亮點疊加
    
    // 7. 將高光結果加上去 (這裡我們直接加在 emission，或你該加的 Specular 緩衝區)
    surface.emission += specularIntensity * color;
}

#endif