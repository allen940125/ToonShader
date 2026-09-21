// 檔案：Effect_Outline.hlsl
#ifndef ABYSS_OUTLINE_UTIL_INCLUDED
#define ABYSS_OUTLINE_UTIL_INCLUDED

// 獲取攝影機 FOV
float GetCameraFOV()
{
    float t = unity_CameraProjection._m11;
    float Rad2Deg = 180.0 / 3.14159265;
    float fov = atan(1.0 / t) * 2.0 * Rad2Deg;
    return fov;
}

// 距離過近時的淡出保護機制
float ApplyOutlineDistanceFadeOut(float inputMulFix)
{
    // 如果想要在距離極近時隱藏描邊，可調整這裡。目前使用 saturate 確保下限為 0~1
    // Nilo 原版直接 saturate，這代表距離小於 1 時會開始變細
    return saturate(inputMulFix);
}

// 計算恆定螢幕寬度的修正乘數
float GetOutlineCameraFovAndDistanceFixMultiplier(float positionVS_Z)
{
    float cameraMulFix;
    if(unity_OrthoParams.w == 0)
    {
        // 透視攝影機 (Perspective)
        cameraMulFix = abs(positionVS_Z);
        cameraMulFix = ApplyOutlineDistanceFadeOut(cameraMulFix);
        cameraMulFix *= GetCameraFOV();       
    }
    else
    {
        // 正交攝影機 (Orthographic)
        float orthoSize = abs(unity_OrthoParams.y);
        orthoSize = ApplyOutlineDistanceFadeOut(orthoSize);
        cameraMulFix = orthoSize * 50.0;
    }

    // 【數值邏輯修正】
    // 假設標準攝影機距離為 5，FOV 為 60，cameraMulFix = 300
    // 乘上 0.00333 可以讓它在標準視角下回傳值為 1.0
    // 這樣它就變成了一個純粹的比例乘數，不會破壞你原本 _OutlineWidth 的 Slider 範圍 (0~0.1)
    return cameraMulFix * 0.00333; 
}

#endif