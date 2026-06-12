using UnityEngine;
using UnityEngine.Rendering;

[ExecuteAlways]
public class DayNightSystemPro : MonoBehaviour
{
    [Header("--- 時間與軌道設定 ---")]
    [Range(0f, 24f)] public float timeOfDay = 12f;
    public float timeSpeed = 1.0f;
    public bool pauseTime = false;
    public GameObject centerPoint;
    public Vector3 rotationAxis = new Vector3(1.0f, 0.0f, 0.0f);
    public float orbitDistance = 100f;

    [Header("--- APV 混合模式控制 ---")]
    [Tooltip("總開關：是否啟用 APV (Adaptive Probe Volumes) 資料切換")]
    public bool enableAPV = true; // 核心新增：APV 總開關
    public bool useDuskScenario = true; 
    public string dayScenarioName = "Day";
    public string duskScenarioName = "Dusk";
    public string nightScenarioName = "Night";
    
    [Tooltip("三階段模式：0=Day, 1=Dusk, 2=Night \n兩階段模式：直接使用 Night Weight Curve")]
    public AnimationCurve apvMasterCurve; 
    public AnimationCurve nightWeightCurve; 

    [Header("--- 後期處理 Volume ---")]
    public Volume dayVolume;
    public Volume nightVolume;

    [Header("--- 燈光與環境 ---")]
    public Light sunLight;
    public float sunIntensityMultiplier = 1.5f;
    public AnimationCurve sunIntensityCurve;
    public Gradient sunColorGradient;
    public Light moonLight;
    public float moonIntensityMultiplier = 0.5f;
    public AnimationCurve moonIntensityCurve;
    public Color moonColor = new Color(0.6f, 0.8f, 1.0f);
    public bool useGradientAmbient = true;
    public Gradient ambientSkyColor;
    public Gradient ambientEquatorColor;
    public Gradient ambientGroundColor;
    public Gradient fogColor;
    public Material skyboxMaterial; 
    public bool useMaterialSwap = false;
    public Material daySkybox;
    public Material nightSkybox;
    public bool usePhysicalLight = true;
    public AnimationCurve sunTemperature; 
    public Gradient sunFilterColor;

    [Header("--- Shader 全域陰影偏置 ---")]
    [Tooltip("隨時間變化的陰影色調偏置。白天保持白色(1,1,1)，晚上可調成冷色。")]
    public Gradient globalShadowColorBias;
    
    private ProbeReferenceVolume probeVolume;

    void Start() { InitializeSystem(); }
    void Update()
    {
        if (Application.isPlaying && !pauseTime)
            timeOfDay = (timeOfDay + Time.deltaTime * timeSpeed * 0.1f) % 24f;

        ExecuteOrbit();
        ExecuteLighting();
        UpdateEnvironment();
        UpdateAPVAndVolumes(); // 方法名稱更新以符合實際邏輯

        UpdateShaderGlobals();
    }

    private void UpdateShaderGlobals()
    {
        float timePercent = timeOfDay / 24f;
        Color shadowBias = globalShadowColorBias.Evaluate(timePercent);
        Shader.SetGlobalColor("_GlobalShadowColorBias", shadowBias);
    }
    
    private void InitializeSystem()
    {
        if (enableAPV) probeVolume = ProbeReferenceVolume.instance;
        if (apvMasterCurve == null || apvMasterCurve.length == 0)
            apvMasterCurve = new AnimationCurve(new Keyframe(0, 2), new Keyframe(12, 0), new Keyframe(18, 1), new Keyframe(24, 2));
    }

    private void ExecuteOrbit()
    {
        if (centerPoint == null) return;
        float sunAngle = (timeOfDay - 6f) * 15f;
        centerPoint.transform.rotation = Quaternion.AngleAxis(sunAngle, rotationAxis);

        if (sunLight != null) {
            sunLight.transform.position = centerPoint.transform.position + (-centerPoint.transform.forward * orbitDistance);
            sunLight.transform.LookAt(centerPoint.transform);
        }
        if (moonLight != null) {
            moonLight.transform.position = centerPoint.transform.position + (centerPoint.transform.forward * orbitDistance);
            moonLight.transform.LookAt(centerPoint.transform);
        }
    }

    private void ExecuteLighting()
    {
        float timePercent = timeOfDay / 24f;
    
        // 計算 Dot 時防呆，確保光源存在
        float sunDot = sunLight != null ? Mathf.Max(Vector3.Dot(sunLight.transform.forward, Vector3.down), 0f) : 0f;
        float moonDot = moonLight != null ? Mathf.Max(Vector3.Dot(moonLight.transform.forward, Vector3.down), 0f) : 0f;

        if (sunLight != null) 
        {
            // 1. 先計算出最終強度
            float currentSunIntensity = sunIntensityCurve.Evaluate(timeOfDay) * sunIntensityMultiplier * SmoothStep(0f, 0.15f, sunDot);
        
            // 2. 只有當強度具有實質意義時，才啟動物件，拔除所有寫死的時間判斷
            sunLight.gameObject.SetActive(currentSunIntensity > 0.001f);
            sunLight.intensity = currentSunIntensity;
        
            if (usePhysicalLight) {
                sunLight.useColorTemperature = true;
                sunLight.colorTemperature = sunTemperature.Evaluate(timeOfDay);
                sunLight.color = sunFilterColor.Evaluate(timePercent);
            } else {
                sunLight.color = sunColorGradient.Evaluate(timePercent);
            }
        }

        if (moonLight != null) 
        {
            // 1. 計算月亮最終強度
            float currentMoonIntensity = moonIntensityCurve.Evaluate(timeOfDay) * moonIntensityMultiplier * SmoothStep(0f, 0.15f, moonDot);
        
            // 2. 完全依賴曲線與 Dot 值來決定生死
            moonLight.gameObject.SetActive(currentMoonIntensity > 0.001f);
            moonLight.intensity = currentMoonIntensity;
            moonLight.color = moonColor;
        }
    }

    private void UpdateAPVAndVolumes()
    {
        float nightWeight = 0;
        float currentApvPhase = 0; // 暫存階段值供 APV 使用

        // 1. 獨立計算權重 (無論 APV 是否開啟，Volume 都需要這些數據)
        if (useDuskScenario)
        {
            currentApvPhase = apvMasterCurve.Evaluate(timeOfDay);
            if (currentApvPhase <= 1.0f) {
                nightWeight = currentApvPhase * 0.5f;
            } else {
                float secondWeight = currentApvPhase - 1.0f;
                nightWeight = 0.5f + (secondWeight * 0.5f);
            }
        }
        else
        {
            nightWeight = nightWeightCurve.Evaluate(timeOfDay);
        }

        // 2. 條件執行 APV 邏輯
        if (enableAPV)
        {
            if (probeVolume == null) probeVolume = ProbeReferenceVolume.instance;
            if (probeVolume != null)
            {
                if (useDuskScenario)
                {
                    if (currentApvPhase <= 1.0f) {
                        probeVolume.lightingScenario = dayScenarioName;
                        probeVolume.BlendLightingScenario(duskScenarioName, currentApvPhase);
                    } else {
                        float secondWeight = currentApvPhase - 1.0f;
                        probeVolume.lightingScenario = duskScenarioName;
                        probeVolume.BlendLightingScenario(nightScenarioName, secondWeight);
                    }
                }
                else
                {
                    probeVolume.lightingScenario = dayScenarioName;
                    probeVolume.BlendLightingScenario(nightScenarioName, nightWeight);
                }
            }
        }

        // 3. 執行 Volume 權重更新
        if (dayVolume != null) dayVolume.weight = 1f - nightWeight;
        if (nightVolume != null) nightVolume.weight = nightWeight;
    }

    private void UpdateEnvironment()
    {
        float timePercent = timeOfDay / 24f;
        float blendFactor = nightWeightCurve.Evaluate(timeOfDay);

        if (useGradientAmbient) {
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = ambientSkyColor.Evaluate(timePercent);
            RenderSettings.ambientEquatorColor = ambientEquatorColor.Evaluate(timePercent);
            RenderSettings.ambientGroundColor = ambientGroundColor.Evaluate(timePercent);
        } else RenderSettings.ambientMode = AmbientMode.Skybox;

        if (RenderSettings.fog) RenderSettings.fogColor = fogColor.Evaluate(timePercent);

        if (useMaterialSwap) {
            bool isNightTime = (timeOfDay >= 18.5f || timeOfDay <= 5.5f);
            Material targetMat = isNightTime ? nightSkybox : daySkybox;
            if (RenderSettings.skybox != targetMat && targetMat != null) {
                RenderSettings.skybox = targetMat;
                DynamicGI.UpdateEnvironment();
            }
        } else if (skyboxMaterial != null) {
            float timeMap = (timeOfDay >= 0f && timeOfDay < 12f) ? (timeOfDay - 6f) / 6f : (18f - timeOfDay) / 6f;
            skyboxMaterial.SetFloat("_TimeMapping", timeMap);
            
            if (sunLight != null) skyboxMaterial.SetVector("_SunDir", -sunLight.transform.forward);
            if (moonLight != null) skyboxMaterial.SetVector("_MoonDir", -moonLight.transform.forward);
            
            if (skyboxMaterial.HasProperty("_Exposure"))
                skyboxMaterial.SetFloat("_Exposure", Mathf.Lerp(1.0f, 0.05f, blendFactor));
            if (RenderSettings.skybox != skyboxMaterial) RenderSettings.skybox = skyboxMaterial;
        }
    }

    private float SmoothStep(float edge0, float edge1, float x) {
        x = Mathf.Clamp((x - edge0) / (edge1 - edge0), 0.0f, 1.0f);
        return x * x * (3 - 2 * x);
    }

#if UNITY_EDITOR
    private void OnGUI()
    {
        if (!Application.isPlaying) return;
        GUIStyle style = new GUIStyle();
        style.fontSize = 18;
        style.normal.textColor = Color.cyan;

        string apvStatus = enableAPV ? "ON" : "OFF";
        string modeText = useDuskScenario ? "3-Phase (With Dusk)" : "2-Phase (Direct Day-Night)";
        string debugText = $"[APV System]: {apvStatus} | Mode: {modeText}\nTime: {timeOfDay:F2}\n";

        if (useDuskScenario) {
            float apvPhase = apvMasterCurve.Evaluate(timeOfDay);
            if (apvPhase <= 1.0f) debugText += $"Volume Blending: Day -> Dusk ({apvPhase*100:F0}%)";
            else debugText += $"Volume Blending: Dusk -> Night ({(apvPhase-1f)*100:F0}%)";
        } else {
            float w = nightWeightCurve.Evaluate(timeOfDay);
            debugText += $"Volume Blending: Day -> Night ({w*100:F0}%)";
        }

        GUI.Label(new Rect(20, 20, 500, 200), debugText, style);
    }
#endif
}