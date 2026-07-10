using UnityEngine;

[ExecuteAlways] // 讓你在編輯器模式下也能一鍵 Debug
public class AbyssRenderManager : MonoBehaviour
{
    public enum DebugViewMode
    {
        None = 0,
        Shadow = 1,
        Highlight = 2,
        AO = 3,
        RimLight = 4,
        Albedo = 5,
        Normal = 6,
        Metallic = 7,
        Smoothness = 8,
        Emission = 9,
        MainLightColor = 10,
        MainLightDirection = 11,
        MainLightDistanceAttenuation = 12,
    }

    [Header("--- 全域除錯 (Global Debug) ---")]
    public DebugViewMode debugMode = DebugViewMode.None;

    [Header("--- 全域系統貼圖 (Global Textures) ---")]
    [Tooltip("半透明抖動用的 Blue Noise 貼圖")]
    public Texture2D globalDitherMap;
    [Tooltip("天氣系統共用的雨滴動態法線貼圖")]
    public Texture2D globalRaindropMap;

    private void Update()
    {
        // 1. 推播 Debug 模式 (注意：Shader 端一定要用 float 接收)
        Shader.SetGlobalFloat("_GlobalDebugViewMode", (float)debugMode);

        // 2. 推播系統共用貼圖 (只要這裡有圖，所有包含 AbyssCore 的材質都能直接讀取)
        if (globalDitherMap != null)
        {
            Shader.SetGlobalTexture("_DitherMap", globalDitherMap);
        }
        
        if (globalRaindropMap != null)
        {
            Shader.SetGlobalTexture("_RaindropMap", globalRaindropMap);
        }
    }
}