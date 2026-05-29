using UnityEngine;
using UnityEditor;

[CustomEditor(typeof(AdvancedChunkCombiner))]
public class AdvancedChunkCombinerEditor : Editor 
{
    public override void OnInspectorGUI() 
    {
        // 1. 繪製腳本中公開的變數 (Chunk Size, Layers, Tags 等)
        DrawDefaultInspector();

        AdvancedChunkCombiner script = (AdvancedChunkCombiner)target;

        EditorGUILayout.Space();
        
        // 2. 顯示原本被 HideInInspector 隱藏的 Layer 選單
        script.targetLayer = EditorGUILayout.LayerField("合併後的目標 Layer", script.targetLayer);

        EditorGUILayout.Space();
        
        // 3. UI 提示區塊，明確告知目前執行的邏輯版本
        EditorGUILayout.HelpBox(
            "【專業級管線】\n" +
            "1. 將嚴格依照「材質 (Material)」進行分群以壓制 Draw Call。\n" +
            "2. 自動略過含有 CombineMarker (ignoreCombine) 的物件。\n" +
            "3. 自動略過 subMeshCount > 1 的複雜模型以防破面。", 
            MessageType.Info);

        EditorGUILayout.Space();

        // 4. 執行按鈕 (加大高度防誤觸)
        if (GUILayout.Button("1. 執行專業級合併 (材質 & 標籤優化版)", GUILayout.Height(35))) 
        {
            script.ExecuteProfessionalCombine();
            // 強制標記場景已修改，確保存檔時會保留合併結果
            UnityEditor.SceneManagement.EditorSceneManager.MarkSceneDirty(script.gameObject.scene);
        }

        GUI.backgroundColor = new Color(1f, 0.5f, 0.5f); // 按鈕標紅警示
        if (GUILayout.Button("2. 快速還原 (拆除區塊並顯示原物件)", GUILayout.Height(30))) 
        {
            script.ClearAndRestore();
            UnityEditor.SceneManagement.EditorSceneManager.MarkSceneDirty(script.gameObject.scene);
        }
        GUI.backgroundColor = Color.white; // 顏色重置
    }
}