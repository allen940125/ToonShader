using UnityEngine;
using UnityEditor;
using System.IO;
using System.Collections.Generic;

public class AbyssTextureToolkit : EditorWindow
{
    private int currentTab = 0;
    private string[] tabs = { "通道打包 (Channel Packer)", "ID 烘焙 (ID Baker)", "漸層烘焙 (Ramp Baker)" };

    private Texture2D texR, texG, texB, texA;
    private string packerOutputName = "NewMaskMap";

    private Texture2D idMapSource;
    private string idBakerOutputName = "NewIDMaskMap";
    private float colorTolerance = 0.08f;
    
    [System.Serializable]
    public class IDRule
    {
        public Color idColor = Color.red;
        [Range(0, 1)] public float metallic = 0f;
        [Range(0, 1)] public float ao = 1f;
        [Range(0, 1)] public float smoothness = 0.5f;
    }
    private List<IDRule> idRules = new List<IDRule>();

    private Gradient rampGradient;
    private int rampWidth = 256;
    private string rampOutputName = "NewRampMap";

    [MenuItem("Abyss Tools/Texture Toolkit (材質工具箱)")]
    public static void ShowWindow()
    {
        var window = GetWindow<AbyssTextureToolkit>("Abyss Texture Toolkit");
        window.minSize = new Vector2(450, 650);
    }

    private void OnEnable()
    {
        if (idRules.Count == 0) idRules.Add(new IDRule { idColor = Color.red }); 
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

    private void DrawChannelPacker()
    {
        EditorGUILayout.LabelField("將散裝黑白貼圖，打包為 URP 標準 Mask Map", EditorStyles.helpBox);
        GUILayout.Space(10);

        texR = (Texture2D)EditorGUILayout.ObjectField("R: 金屬 (Metallic)", texR, typeof(Texture2D), false);
        texG = (Texture2D)EditorGUILayout.ObjectField("G: 遮蔽 (AO)", texG, typeof(Texture2D), false);
        texB = (Texture2D)EditorGUILayout.ObjectField("B: 空白 (自訂)", texB, typeof(Texture2D), false);
        texA = (Texture2D)EditorGUILayout.ObjectField("A: 平滑 (Smoothness)", texA, typeof(Texture2D), false);

        GUILayout.Space(5);
        if (GUILayout.Button("一鍵檢查並修復上述貼圖的讀寫權限"))
        {
            FixReadable(texR); FixReadable(texG); FixReadable(texB); FixReadable(texA);
        }

        GUILayout.Space(10);
        packerOutputName = EditorGUILayout.TextField("輸出檔名", packerOutputName);

        GUILayout.Space(10);
        GUI.backgroundColor = new Color(0.7f, 1f, 0.7f);
        if (GUILayout.Button("執行打包 (Pack to RGBA)", GUILayout.Height(40))) PackTextures();
        GUI.backgroundColor = Color.white;
    }

    private void PackTextures()
    {
        Texture2D baseTex = texR != null ? texR : (texG != null ? texG : (texA != null ? texA : texB));
        if (baseTex == null) { EditorUtility.DisplayDialog("錯誤", "請至少放入一張貼圖！", "確定"); return; }

        if (!CheckReadable(texR) || !CheckReadable(texG) || !CheckReadable(texB) || !CheckReadable(texA)) return;

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
        outputTex.SetPixels(outPixels);
        
        SaveAndConfigureTexture(outputTex, packerOutputName, false, TextureWrapMode.Repeat);
    }

    private void DrawIDBaker()
    {
        EditorGUILayout.LabelField("用滴管吸取來源圖顏色，轉譯為所需的遮罩", EditorStyles.helpBox);
        GUILayout.Space(10);

        idMapSource = (Texture2D)EditorGUILayout.ObjectField("來源 Color ID 貼圖", idMapSource, typeof(Texture2D), false);
        
        if (idMapSource != null && !idMapSource.isReadable)
        {
            GUI.backgroundColor = new Color(1f, 0.6f, 0.6f);
            if (GUILayout.Button("點擊修復此 ID 貼圖的讀寫與壓縮設定"))
            {
                FixReadable(idMapSource);
            }
            GUI.backgroundColor = Color.white;
        }

        colorTolerance = EditorGUILayout.Slider("顏色容差", colorTolerance, 0f, 0.3f);
        GUILayout.Space(10);
        
        for (int i = 0; i < idRules.Count; i++)
        {
            EditorGUILayout.BeginVertical("box");
            GUILayout.BeginHorizontal();
            idRules[i].idColor = EditorGUILayout.ColorField(GUIContent.none, idRules[i].idColor, false, false, false, GUILayout.Width(50));
            if (GUILayout.Button("移除", GUILayout.Width(50))) { idRules.RemoveAt(i); break; }
            GUILayout.EndHorizontal();

            idRules[i].metallic = EditorGUILayout.Slider("R: 金屬度", idRules[i].metallic, 0f, 1f);
            idRules[i].ao = EditorGUILayout.Slider("G: 遮蔽", idRules[i].ao, 0f, 1f);
            idRules[i].smoothness = EditorGUILayout.Slider("A: 平滑度", idRules[i].smoothness, 0f, 1f);
            EditorGUILayout.EndVertical();
        }

        if (GUILayout.Button("+ 新增要提取的顏色")) idRules.Add(new IDRule());

        GUILayout.Space(10);
        idBakerOutputName = EditorGUILayout.TextField("輸出檔名", idBakerOutputName);

        GUILayout.Space(10);
        GUILayout.BeginHorizontal();
        GUI.backgroundColor = new Color(0.7f, 0.8f, 1f);
        if (GUILayout.Button("A. 烘焙為 PBR 通道圖\n(輸出 RGBA)", GUILayout.Height(50))) BakeFromIDMap(false);
        
        GUI.backgroundColor = new Color(1f, 0.7f, 0.7f);
        if (GUILayout.Button("B. 提取單純黑白遮罩\n(選中變白，其餘變黑)", GUILayout.Height(50))) BakeFromIDMap(true);
        GUILayout.EndHorizontal();
        GUI.backgroundColor = Color.white;
    }

    private void BakeFromIDMap(bool isSimpleBlackAndWhite)
    {
        if (idMapSource == null) { EditorUtility.DisplayDialog("錯誤", "請放入 ID 貼圖！", "確定"); return; }
        if (!CheckReadable(idMapSource)) return;
        
        int w = idMapSource.width, h = idMapSource.height;
        Texture2D outputTex = new Texture2D(w, h, TextureFormat.RGBA32, false);
        Color[] inPixels = idMapSource.GetPixels();
        Color[] outPixels = new Color[inPixels.Length];

        for (int i = 0; i < inPixels.Length; i++)
        {
            Color pixelColor = inPixels[i];
            bool matched = false;
            float finalM = 0f, finalAO = 1f, finalS = 0f;

            foreach (var rule in idRules)
            {
                // 【核心修正】：閹割掉 Alpha，純看三維 RGB 距離
                float dist = Vector3.Distance(
                    new Vector3(pixelColor.r, pixelColor.g, pixelColor.b),
                    new Vector3(rule.idColor.r, rule.idColor.g, rule.idColor.b)
                );

                if (dist <= colorTolerance)
                {
                    matched = true;
                    finalM = rule.metallic;
                    finalAO = rule.ao;
                    finalS = rule.smoothness;
                    break;
                }
            }

            if (isSimpleBlackAndWhite)
            {
                outPixels[i] = matched ? Color.white : Color.black;
            }
            else
            {
                outPixels[i] = new Color(finalM, finalAO, 0f, finalS);
            }
        }
        outputTex.SetPixels(outPixels);
        
        SaveAndConfigureTexture(outputTex, idBakerOutputName, false, TextureWrapMode.Repeat);
    }

    private void DrawRampBaker()
    {
        EditorGUILayout.LabelField("生成卡通渲染專用的 1D Ramp 光影階梯貼圖", EditorStyles.helpBox);
        GUILayout.Space(10);
        rampGradient = EditorGUILayout.GradientField("光影過渡漸層", rampGradient);
        rampWidth = EditorGUILayout.IntSlider("貼圖解析度 (寬)", rampWidth, 64, 1024);
        rampOutputName = EditorGUILayout.TextField("輸出檔名", rampOutputName);
        GUILayout.Space(10);
        if (GUILayout.Button("生成 Ramp 貼圖", GUILayout.Height(40))) GenerateRampTexture();
    }

    private void GenerateRampTexture()
    {
        int height = 4;
        Texture2D rampTex = new Texture2D(rampWidth, height, TextureFormat.RGBA32, false);
        for (int x = 0; x < rampWidth; x++)
        {
            Color c = rampGradient.Evaluate((float)x / (rampWidth - 1));
            for (int y = 0; y < height; y++) rampTex.SetPixel(x, y, c);
        }
        SaveAndConfigureTexture(rampTex, rampOutputName, true, TextureWrapMode.Clamp);
    }

    private bool CheckReadable(Texture2D tex)
    {
        if (tex == null) return true;
        if (!tex.isReadable)
        {
            EditorUtility.DisplayDialog("錯誤", $"貼圖 {tex.name} 未開啟 Read/Write 權限！請點擊面板上的修復按鈕。", "確定");
            return false;
        }
        return true;
    }

    private void FixReadable(Texture2D tex)
    {
        if (tex == null) return;
        string path = AssetDatabase.GetAssetPath(tex);
        TextureImporter importer = AssetImporter.GetAtPath(path) as TextureImporter;
        if (importer != null)
        {
            importer.isReadable = true;
            importer.sRGBTexture = false; // 強制改為資料流 (Linear)
            importer.textureCompression = TextureImporterCompression.Uncompressed; // 拔除破壞性壓縮
            importer.filterMode = FilterMode.Point; // 防溢色
            importer.SaveAndReimport();
            Debug.Log($"成功解除 {tex.name} 的壓縮限制與色彩空間阻礙。");
        }
    }

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
                importer.mipmapEnabled = false;
                importer.SaveAndReimport();
            }
            Debug.Log($"<color=green>作業完成！</color> 貼圖已儲存至: {path}");
        }
    }
}