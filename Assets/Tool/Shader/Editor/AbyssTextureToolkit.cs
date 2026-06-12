using UnityEngine;
using UnityEditor;
using System.IO;
using System.Collections.Generic;

public class AbyssTextureToolkit : EditorWindow
{
    private int currentTab = 0;
    private string[] tabs = { "通道打包 (Channel Packer)", "ID 烘焙 (ID Baker)", "漸層烘焙 (Ramp Baker)" };

    // --- 1. 通道打包變數 ---
    private Texture2D texR, texG, texB, texA;
    private string packerOutputName = "NewMaskMap";

    // --- 2. ID 烘焙變數 ---
    private Texture2D idMapSource;
    private string idBakerOutputName = "NewIDMaskMap";
    private float colorTolerance = 0.05f; // 顏色比對容差 (防邊緣壓縮雜訊)
    
    [System.Serializable]
    public class IDRule
    {
        public Color idColor = Color.red;
        [Range(0, 1)] public float metallic = 0f;
        [Range(0, 1)] public float ao = 1f;
        [Range(0, 1)] public float smoothness = 0.5f;
    }
    private List<IDRule> idRules = new List<IDRule>();

    // --- 3. 漸層烘焙 (Ramp Baker) 變數 ---
    private Gradient rampGradient;
    private int rampWidth = 256;
    private string rampOutputName = "NewRampMap";

    [MenuItem("Abyss Tools/Texture Toolkit (材質工具箱)")]
    public static void ShowWindow()
    {
        var window = GetWindow<AbyssTextureToolkit>("Abyss Texture Toolkit");
        window.minSize = new Vector2(450, 600);
    }

    private void OnEnable()
    {
        // 預設給一個硬邊距的二次元 Ramp 漸層
        if (rampGradient == null)
        {
            rampGradient = new Gradient();
            rampGradient.SetKeys(
                new GradientColorKey[] { 
                    new GradientColorKey(new Color(0.4f, 0.45f, 0.6f), 0f), 
                    new GradientColorKey(new Color(0.4f, 0.45f, 0.6f), 0.49f), 
                    new GradientColorKey(Color.white, 0.51f), 
                    new GradientColorKey(Color.white, 1f) 
                },
                new GradientAlphaKey[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) }
            );
        }

        // 預設給定兩組 ID 規則防呆
        if (idRules.Count == 0)
        {
            idRules.Add(new IDRule { idColor = Color.red, metallic = 1f, ao = 1f, smoothness = 0.8f }); // 金屬
            idRules.Add(new IDRule { idColor = Color.green, metallic = 0f, ao = 1f, smoothness = 0.2f }); // 布料
        }
    }

    private void OnGUI()
    {
        GUILayout.Space(10);
        currentTab = GUILayout.Toolbar(currentTab, tabs);
        GUILayout.Space(15);

        switch (currentTab)
        {
            case 0: DrawChannelPacker(); break;
            case 1: DrawIDBaker(); break;
            case 2: DrawRampBaker(); break;
        }
    }

    // ==========================================
    // 模組 1：通道打包器
    // ==========================================
    private void DrawChannelPacker()
    {
        EditorGUILayout.LabelField("將散裝黑白貼圖，打包為 URP 標準 Mask Map", EditorStyles.helpBox);
        GUILayout.Space(10);

        texR = (Texture2D)EditorGUILayout.ObjectField("R: 金屬 (Metallic)", texR, typeof(Texture2D), false);
        texG = (Texture2D)EditorGUILayout.ObjectField("G: 遮蔽 (AO)", texG, typeof(Texture2D), false);
        texB = (Texture2D)EditorGUILayout.ObjectField("B: 空白 (自訂)", texB, typeof(Texture2D), false);
        texA = (Texture2D)EditorGUILayout.ObjectField("A: 平滑 (Smoothness)", texA, typeof(Texture2D), false);

        GUILayout.Space(10);
        packerOutputName = EditorGUILayout.TextField("輸出檔名", packerOutputName);

        GUILayout.Space(10);
        GUI.backgroundColor = new Color(0.7f, 1f, 0.7f);
        if (GUILayout.Button("執行打包 (Pack to RGBA)", GUILayout.Height(40)))
        {
            PackTextures();
        }
        GUI.backgroundColor = Color.white;
    }

    private void PackTextures()
    {
        Texture2D baseTex = texR != null ? texR : (texG != null ? texG : (texA != null ? texA : texB));
        if (baseTex == null) { EditorUtility.DisplayDialog("錯誤", "請至少放入一張貼圖！", "確定"); return; }

        EnsureTextureReadable(texR); EnsureTextureReadable(texG); EnsureTextureReadable(texB); EnsureTextureReadable(texA);

        int w = baseTex.width, h = baseTex.height;
        Texture2D outputTex = new Texture2D(w, h, TextureFormat.RGBA32, false);
        Color[] outPixels = new Color[w * h];

        Color[] pR = texR != null ? texR.GetPixels() : null;
        Color[] pG = texG != null ? texG.GetPixels() : null;
        Color[] pB = texB != null ? texB.GetPixels() : null;
        Color[] pA = texA != null ? texA.GetPixels() : null;

        for (int i = 0; i < outPixels.Length; i++)
        {
            outPixels[i] = new Color(
                pR != null ? pR[i].r : 0f, 
                pG != null ? pG[i].g : 1f, 
                pB != null ? pB[i].b : 0f, 
                pA != null ? pA[i].a : 0f
            );
        }

        SaveAndConfigureTexture(outputTex, packerOutputName, false, TextureWrapMode.Repeat);
    }

    // ==========================================
    // 模組 2：ID 烘焙器
    // ==========================================
    private void DrawIDBaker()
    {
        EditorGUILayout.LabelField("將 Color ID 轉譯為 Mask Map (用記憶體換取 GPU 效能)", EditorStyles.helpBox);
        GUILayout.Space(10);

        idMapSource = (Texture2D)EditorGUILayout.ObjectField("來源 Color ID 貼圖", idMapSource, typeof(Texture2D), false);
        colorTolerance = EditorGUILayout.Slider("顏色容差 (防雜訊)", colorTolerance, 0f, 0.2f);
        
        GUILayout.Space(10);
        EditorGUILayout.LabelField("ID 轉譯規則 (ID Rules)", EditorStyles.boldLabel);
        
        for (int i = 0; i < idRules.Count; i++)
        {
            EditorGUILayout.BeginVertical("box");
            GUILayout.BeginHorizontal();
            idRules[i].idColor = EditorGUILayout.ColorField(GUIContent.none, idRules[i].idColor, false, false, false, GUILayout.Width(50));
            if (GUILayout.Button("移除", GUILayout.Width(50))) { idRules.RemoveAt(i); break; }
            GUILayout.EndHorizontal();

            idRules[i].metallic = EditorGUILayout.Slider("R: 金屬度 (Metallic)", idRules[i].metallic, 0f, 1f);
            idRules[i].ao = EditorGUILayout.Slider("G: 遮蔽 (AO)", idRules[i].ao, 0f, 1f);
            idRules[i].smoothness = EditorGUILayout.Slider("A: 平滑度 (Smoothness)", idRules[i].smoothness, 0f, 1f);
            EditorGUILayout.EndVertical();
        }

        if (GUILayout.Button("+ 新增 ID 規則")) idRules.Add(new IDRule());

        GUILayout.Space(10);
        idBakerOutputName = EditorGUILayout.TextField("輸出檔名", idBakerOutputName);

        GUILayout.Space(10);
        GUI.backgroundColor = new Color(0.7f, 0.8f, 1f);
        if (GUILayout.Button("執行烘焙 (Bake from ID)", GUILayout.Height(40)))
        {
            BakeFromIDMap();
        }
        GUI.backgroundColor = Color.white;
    }

    private void BakeFromIDMap()
    {
        if (idMapSource == null) { EditorUtility.DisplayDialog("錯誤", "請放入 ID 貼圖！", "確定"); return; }
        
        EnsureTextureReadable(idMapSource);
        
        int w = idMapSource.width, h = idMapSource.height;
        Texture2D outputTex = new Texture2D(w, h, TextureFormat.RGBA32, false);
        Color[] inPixels = idMapSource.GetPixels();
        Color[] outPixels = new Color[inPixels.Length];

        for (int i = 0; i < inPixels.Length; i++)
        {
            Color pixelColor = inPixels[i];
            float finalM = 0f, finalAO = 1f, finalS = 0f;

            // 尋找最接近的 ID 規則
            foreach (var rule in idRules)
            {
                float dist = Vector4.Distance(pixelColor, rule.idColor);
                if (dist <= colorTolerance)
                {
                    finalM = rule.metallic;
                    finalAO = rule.ao;
                    finalS = rule.smoothness;
                    break; // 找到就跳出，提升效能
                }
            }
            outPixels[i] = new Color(finalM, finalAO, 0f, finalS);
        }

        SaveAndConfigureTexture(outputTex, idBakerOutputName, false, TextureWrapMode.Repeat);
    }

    // ==========================================
    // 模組 3：漸層烘焙 (Ramp Baker)
    // ==========================================
    private void DrawRampBaker()
    {
        EditorGUILayout.LabelField("生成卡通渲染專用的 1D Ramp 光影階梯貼圖", EditorStyles.helpBox);
        GUILayout.Space(10);

        rampGradient = EditorGUILayout.GradientField("光影過渡漸層 (Left:暗部 -> Right:亮部)", rampGradient);
        rampWidth = EditorGUILayout.IntSlider("貼圖解析度 (寬)", rampWidth, 64, 1024);
        rampOutputName = EditorGUILayout.TextField("輸出檔名", rampOutputName);

        GUILayout.Space(10);
        GUI.backgroundColor = new Color(1f, 0.8f, 0.6f);
        if (GUILayout.Button("生成 Ramp 貼圖 (Generate 1D Texture)", GUILayout.Height(40)))
        {
            GenerateRampTexture();
        }
        GUI.backgroundColor = Color.white;
    }

    private void GenerateRampTexture()
    {
        int height = 4; // 高度給 4 個像素即可，避免引擎過度壓縮導致的一維失真
        Texture2D rampTex = new Texture2D(rampWidth, height, TextureFormat.RGBA32, false);

        for (int x = 0; x < rampWidth; x++)
        {
            // 將 X 座標正規化到 0~1 來採樣漸層
            float t = (float)x / (rampWidth - 1);
            Color c = rampGradient.Evaluate(t);
            
            for (int y = 0; y < height; y++)
            {
                rampTex.SetPixel(x, y, c);
            }
        }

        // Ramp 貼圖的物理防呆：必須是 Clamp 模式，否則邊緣光會採樣到另一端的黑影
        SaveAndConfigureTexture(rampTex, rampOutputName, true, TextureWrapMode.Clamp);
    }

    // ==========================================
    // 底層共用 API
    // ==========================================
    private void SaveAndConfigureTexture(Texture2D tex, string fileName, bool isSRGB, TextureWrapMode wrapMode)
    {
        tex.Apply();
        byte[] bytes = tex.EncodeToPNG();
        string path = EditorUtility.SaveFilePanelInProject("儲存貼圖", fileName, "png", "請選擇儲存路徑");

        if (!string.IsNullOrEmpty(path))
        {
            File.WriteAllBytes(path, bytes);
            AssetDatabase.Refresh();

            TextureImporter importer = AssetImporter.GetAtPath(path) as TextureImporter;
            if (importer != null)
            {
                importer.sRGBTexture = isSRGB;
                importer.wrapMode = wrapMode;
                importer.mipmapEnabled = false; // Ramp 和 Mask 通常不需要 Mipmap
                importer.SaveAndReimport();
            }

            Debug.Log($"<color=green>作業完成！</color> 貼圖已儲存至: {path}");
        }
    }

    private void EnsureTextureReadable(Texture2D tex)
    {
        if (tex == null) return;
        string path = AssetDatabase.GetAssetPath(tex);
        TextureImporter importer = AssetImporter.GetAtPath(path) as TextureImporter;
        if (importer != null && !importer.isReadable)
        {
            importer.isReadable = true;
            importer.SaveAndReimport();
        }
    }
}