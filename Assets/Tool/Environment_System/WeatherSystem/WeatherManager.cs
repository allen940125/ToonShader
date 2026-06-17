using UnityEngine;

[ExecuteAlways] // 必須加上這行
public class WeatherManager : Singleton<WeatherManager>
{
    [Header("--- 降雨設定 ---")]
    [Range(0f, 1f)] public float globalRainIntensity = 0f;

    [Header("--- 風場設定 (自定義) ---")]
    public Vector3 windDirection = new Vector3(1, 0, 0); // 風向
    [Range(0f, 10f)] public float windSpeed = 0f;        // 風速
    [Range(0f, 1f)] public float windTurbulence = 0.5f;  // 擾亂度 (用於樹葉或特效飄動)

    public Vector3 rainDirection 
    {
        get 
        {
            // 假設無風時，雨水下落速度為每秒 9.8 米 (垂直向下)
            Vector3 gravityEffect = Vector3.down * 9.81f;
            // 風力產生的橫向推力 = 風向 * 風速
            Vector3 windEffect = windDirection.normalized * windSpeed;
            // 合成最終的雨水速度向量
            return (gravityEffect + windEffect).normalized;
        }
    }
    
    private static readonly int RainIntensityID = Shader.PropertyToID("_GlobalRainIntensity");
    private static readonly int GlobalWindDirID = Shader.PropertyToID("_GlobalWindDir");
    private static readonly int GlobalWindParamsID = Shader.PropertyToID("_GlobalWindParams"); // X:Speed, Y:Turbulence
    
    private void Update()
    {
        // 1. 推播給所有 Shader
        Shader.SetGlobalFloat(RainIntensityID, globalRainIntensity);
        Shader.SetGlobalVector(GlobalWindDirID, windDirection.normalized);
        Shader.SetGlobalVector(GlobalWindParamsID, new Vector4(windSpeed, windTurbulence, 0, 0));
        Shader.SetGlobalVector(Shader.PropertyToID("_GlobalRainDirection"), rainDirection);
    }
}