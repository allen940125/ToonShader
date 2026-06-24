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
        Emission = 9
    }

    [Header("全局渲染除錯")]
    public DebugViewMode debugMode = DebugViewMode.None;

    private void Update()
    {
        // 核心一字：直接向 GPU 廣播，開銷為零
        Shader.SetGlobalInt("_DebugViewMode", (int)debugMode);
    }
}