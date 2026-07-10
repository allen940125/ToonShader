using UnityEngine;
using UnityEditor;
using UnityEngine.Rendering;

[CustomEditor(typeof(DayNightSystemPro))]
public class DayNightSystemEditor : Editor
{
    public override void OnInspectorGUI()
    {
        DayNightSystemPro script = (DayNightSystemPro)target;

        EditorGUILayout.LabelField("🔧 系統模式設定", EditorStyles.boldLabel);
        script.usePhysicalLight = EditorGUILayout.Toggle("使用物理燈光 (Temperature)", script.usePhysicalLight);
        script.useMaterialSwap = EditorGUILayout.Toggle("開啟天空材質硬切換", script.useMaterialSwap);
        script.useGradientAmbient = EditorGUILayout.Toggle("使用漸層環境光", script.useGradientAmbient);
        
        EditorGUILayout.Space(5);
        DrawDefaultInspector();

        GUILayout.Space(10);
        
        // 功能按鍵 1：生成場景物件
        GUI.backgroundColor = new Color(0.7f, 1f, 0.7f);
        if (GUILayout.Button("🛠️ Setup Scene Objects (Auto-Link)", GUILayout.Height(35)))
        {
            SetupSceneObjects(script);
        }
        
        GUI.backgroundColor = Color.white;
        EditorGUILayout.Space(5);

        // 功能按鍵 2：注入物理參數
        if (GUILayout.Button("✨ 注入專業日夜物理預設 (Pro Preset)", GUILayout.Height(35)))
        {
            Undo.RecordObject(script, "Apply DayNight Pro Preset");
            
            ApplyOrbitDefaults(script);
            ApplyBeautifulPreset(script);
            ApplyPhysicalData(script); 
            
            EditorUtility.SetDirty(script);
            Debug.Log("已成功注入 Pro 等級物理參數，包含軌道邏輯與雙材質預設。");
        }
    }

    private void SetupSceneObjects(DayNightSystemPro script)
    {
        Undo.IncrementCurrentGroup();
        string groupName = "Setup DayNight Objects";

        // 1. 生成 CenterPoint
        if (script.centerPoint == null)
        {
            GameObject cp = new GameObject("--- DayNight_CenterPoint ---");
            cp.transform.position = Vector3.zero;
            script.centerPoint = cp;
            Undo.RegisterCreatedObjectUndo(cp, groupName);
        }

        // 2. 生成 Sun (Directional Light)
        if (script.sunLight == null)
        {
            GameObject sunObj = new GameObject("Directional Light (Sun)");
            Light light = sunObj.AddComponent<Light>();
            light.type = LightType.Directional;
            script.sunLight = light;
            Undo.RegisterCreatedObjectUndo(sunObj, groupName);
        }

        // 3. 生成 Moon (Directional Light)
        if (script.moonLight == null)
        {
            GameObject moonObj = new GameObject("Directional Light (Moon)");
            Light light = moonObj.AddComponent<Light>();
            light.type = LightType.Directional;
            script.moonLight = light;
            Undo.RegisterCreatedObjectUndo(moonObj, groupName);
        }

        EditorUtility.SetDirty(script);
        Debug.Log("場景物件已生成並自動連結。");
    }

    private void ApplyOrbitDefaults(DayNightSystemPro script)
    {
        script.rotationAxis = new Vector3(1f, -1f, 0f);
        script.orbitDistance = 100f;
        script.timeSpeed = 5f;
    }

    private void ApplyPhysicalData(DayNightSystemPro script)
    {
        script.usePhysicalLight = true;
        script.sunTemperature = new AnimationCurve(
            new Keyframe(0f, 10000f),
            new Keyframe(6f, 3000f),
            new Keyframe(12f, 6000f),
            new Keyframe(18f, 2500f),
            new Keyframe(24f, 10000f)
        );

        var filterKeys = new GradientColorKey[] {
            new GradientColorKey(new Color(0.7f, 0.8f, 1f), 0.0f),
            new GradientColorKey(Color.white, 0.5f),
            new GradientColorKey(new Color(1f, 0.9f, 0.8f), 0.75f),
            new GradientColorKey(new Color(0.7f, 0.8f, 1f), 1.0f)
        };
        script.sunFilterColor = new Gradient();
        script.sunFilterColor.SetKeys(filterKeys, new GradientAlphaKey[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) });
    }

    private void ApplyBeautifulPreset(DayNightSystemPro script)
    {
        // 1. APV Master Curve (Dusk 控制)
        script.apvMasterCurve = new AnimationCurve();
        script.apvMasterCurve.AddKey(new Keyframe(0f, 2f));
        script.apvMasterCurve.AddKey(new Keyframe(6f, 1f));
        script.apvMasterCurve.AddKey(new Keyframe(12f, 0f));
        script.apvMasterCurve.AddKey(new Keyframe(18f, 1f));
        script.apvMasterCurve.AddKey(new Keyframe(24f, 2f));
        script.apvMasterCurve.preWrapMode = WrapMode.Loop;
        script.apvMasterCurve.postWrapMode = WrapMode.Loop;

        // 2. Night Weight Curve (你提供的新參數)
        script.nightWeightCurve = new AnimationCurve();
        script.nightWeightCurve.AddKey(new Keyframe(0f, 1f, 0f, 0f));
        script.nightWeightCurve.AddKey(new Keyframe(5f, 0.8f, 0f, -1f));
        script.nightWeightCurve.AddKey(new Keyframe(8f, 0.1f, -1f, 0f));
        script.nightWeightCurve.AddKey(new Keyframe(12f, 0f, 0f, 0f));
        script.nightWeightCurve.AddKey(new Keyframe(16f, 0.1f, 0f, 1f));
        script.nightWeightCurve.AddKey(new Keyframe(19f, 0.8f, 1f, 0f));
        script.nightWeightCurve.AddKey(new Keyframe(24f, 1f, 0f, 0f));
        script.nightWeightCurve.preWrapMode = WrapMode.ClampForever;
        script.nightWeightCurve.postWrapMode = WrapMode.ClampForever;

        // 3. Sun Intensity Curve
        script.sunIntensityCurve = new AnimationCurve();
        script.sunIntensityCurve.AddKey(new Keyframe(0f, 0f));
        script.sunIntensityCurve.AddKey(new Keyframe(5f, 0.05f));
        script.sunIntensityCurve.AddKey(new Keyframe(6.5f, 0.45f));
        script.sunIntensityCurve.AddKey(new Keyframe(8f, 0.95f));
        script.sunIntensityCurve.AddKey(new Keyframe(12f, 1.45f));
        script.sunIntensityCurve.AddKey(new Keyframe(15f, 1.28f));
        script.sunIntensityCurve.AddKey(new Keyframe(18f, 0.15f));
        script.sunIntensityCurve.AddKey(new Keyframe(19f, 0f));
        script.sunIntensityCurve.AddKey(new Keyframe(24f, 0f));

        // 4. Moon Intensity Curve
        script.moonIntensityCurve = new AnimationCurve();
        script.moonIntensityCurve.AddKey(new Keyframe(0f, 1.0f));
        script.moonIntensityCurve.AddKey(new Keyframe(5f, 0.8f));
        script.moonIntensityCurve.AddKey(new Keyframe(6.5f, 0f));
        script.moonIntensityCurve.AddKey(new Keyframe(12f, 0f));
        script.moonIntensityCurve.AddKey(new Keyframe(17.5f, 0f));
        script.moonIntensityCurve.AddKey(new Keyframe(19f, 0.8f));
        script.moonIntensityCurve.AddKey(new Keyframe(24f, 1.0f));
        
        script.moonColor = new Color(0.25f, 0.35f, 0.55f);

        // 5. Gradients (Colors)
        var defaultAlpha = new GradientAlphaKey[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) };
        
        script.sunColorGradient = new Gradient();
        script.sunColorGradient.SetKeys(new GradientColorKey[] {
            new GradientColorKey(HexToColor("#0a0c1d"), 0.00f),
            new GradientColorKey(HexToColor("#14182a"), 0.22f),
            new GradientColorKey(HexToColor("#e08b55"), 0.30f),
            new GradientColorKey(HexToColor("#f9d549"), 0.40f),
            new GradientColorKey(Color.white,          0.50f),
            new GradientColorKey(HexToColor("#f8d96c"), 0.60f),
            new GradientColorKey(HexToColor("#ff6b4a"), 0.72f),
            new GradientColorKey(HexToColor("#0a0c1d"), 1.00f)
        }, defaultAlpha);

        script.fogColor = new Gradient();
        script.fogColor.SetKeys(new GradientColorKey[] {
            new GradientColorKey(HexToColor("#0c1022"), 0.00f),
            new GradientColorKey(HexToColor("#1a1d33"), 0.20f),
            new GradientColorKey(HexToColor("#d87a3e"), 0.28f),
            new GradientColorKey(HexToColor("#f0e6d2"), 0.50f),
            new GradientColorKey(HexToColor("#d87a3e"), 0.72f),
            new GradientColorKey(HexToColor("#0c1022"), 1.00f)
        }, defaultAlpha);

        script.ambientSkyColor = CreateGradient(HexToColor("#05060d"), HexToColor("#4172B7"), HexToColor("#05060d"));
        script.ambientEquatorColor = CreateGradient(HexToColor("#080912"), new Color(0.88f, 0.97f, 1.31f), HexToColor("#080912"));
        script.ambientGroundColor = CreateGradient(Color.black, Color.black, Color.black);
        
        // ==========================================
        // 6. 全域陰影顏色 (Global Shadow Color)
        // 邏輯：中午是中性灰，黃昏帶點暖紫，夜晚變成深冷藍
        // ==========================================
        script.globalShadowColor = new Gradient();
        script.globalShadowColor.SetKeys(
            new GradientColorKey[]
            {
                new GradientColorKey(HexToColor("#1A2035"), 0.00f),  // 午夜：極深的藏青色
                new GradientColorKey(HexToColor("#3A3545"), 0.25f),  // 清晨：帶點紫灰
                new GradientColorKey(HexToColor("#7F7F7F"), 0.50f),  // 正午：50% 中性灰 (由底色決定最終顏色)
                new GradientColorKey(HexToColor("#55434A"), 0.75f),  // 黃昏：暖灰偏紅紫
                new GradientColorKey(HexToColor("#1A2035"), 1.00f)   // 午夜：極深的藏青色
            },
            defaultAlpha
        );

        // ==========================================
        // 7. 全域陰影強度曲線 (Global Shadow Strength)
        // 邏輯：中午對比最強 (1.0)，早晚柔和，半夜因為環境已經很暗，稍微降一點避免死黑
        // ==========================================
        script.globalShadowStrengthCurve = new AnimationCurve();
        script.globalShadowStrengthCurve.AddKey(new Keyframe(0f, 0.6f));   // 半夜：陰影濃度 60%
        script.globalShadowStrengthCurve.AddKey(new Keyframe(6f, 0.4f));   // 清晨：空氣感重，陰影極弱
        script.globalShadowStrengthCurve.AddKey(new Keyframe(12f, 0.85f)); // 正午：陽光直射，陰影極強
        script.globalShadowStrengthCurve.AddKey(new Keyframe(17f, 0.5f));  // 黃昏：夕陽柔和
        script.globalShadowStrengthCurve.AddKey(new Keyframe(24f, 0.6f));

        // ==========================================
        // 8. 邊緣光設定 (Rim Light)
        // 邏輯：預設自動尋找主光源的反方向
        // ==========================================
        script.autoRimLightDirection = true;
        script.customRimLightDirection = new Vector3(1f, 0f, 0f);
        
        script.timeOfDay = 12f;
        script.timeSpeed = 1f;
    }

    private Gradient CreateGradient(Color start, Color mid, Color end)
    {
        Gradient grad = new Gradient();
        grad.SetKeys(
            new GradientColorKey[] { new GradientColorKey(start, 0f), new GradientColorKey(mid, 0.5f), new GradientColorKey(end, 1f) },
            new GradientAlphaKey[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) }
        );
        return grad;
    }

    private Color HexToColor(string hex)
    {
        if (hex.StartsWith("#")) hex = hex.Substring(1);
        byte r = byte.Parse(hex.Substring(0, 2), System.Globalization.NumberStyles.HexNumber);
        byte g = byte.Parse(hex.Substring(2, 2), System.Globalization.NumberStyles.HexNumber);
        byte b = byte.Parse(hex.Substring(4, 2), System.Globalization.NumberStyles.HexNumber);
        return new Color32(r, g, b, 255);
    }
}