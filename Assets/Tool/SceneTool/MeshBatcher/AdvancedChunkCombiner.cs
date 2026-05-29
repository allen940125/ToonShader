using UnityEngine;
using System.Collections.Generic;
using Core.Optimization;

#if UNITY_EDITOR
using UnityEditor;
using System.IO;
#endif

public class AdvancedChunkCombiner : MonoBehaviour
{
    [Header("基礎設定")]
    public float chunkSize = 25f;
    public LayerMask combineLayers;
    public string targetTag = "StaticEnv"; // 依然用來初步過濾要掃描的物件
    
    [Header("儲存設定")]
    [Tooltip("此合併器的專屬資料夾名稱，必須唯一，否則會誤刪其他合併器的資料")]
    public string bakeGroupName = "ChunkGroup_01";
    
    [HideInInspector] public int targetLayer = 0; 
    
    private const string HOLDER_NAME = "--- COMBINED_CHUNKS_HOLDER ---";

#if UNITY_EDITOR
    // 基礎儲存路徑
    private const string BASE_SAVE_FOLDER = "Assets/BakedChunks";
    
    // 動態生成當前實例的專屬儲存路徑
    private string CurrentSaveFolder => $"{BASE_SAVE_FOLDER}/{bakeGroupName}";
#endif
    
    [ContextMenu("執行專業級合併 (物理視覺剝離版)")]
    public void ExecuteProfessionalCombine()
    {
        ClearAndRestore();
        
        // 1. 物理掃描與空間分群
        var chunkGroups = ScanAndSortIntoChunks();
        
        GameObject holder = new GameObject(HOLDER_NAME);
        holder.transform.parent = this.transform;

        // 2. 針對每個區塊進行優化
        foreach (var chunk in chunkGroups)
        {
            ProcessChunk(chunk.Key, chunk.Value, holder.transform);
        }
        
        Debug.Log("<color=cyan>重構版合併完成！已實現視覺與物理剝離，原生 Collider 完美保留。</color>");
    }

    private Dictionary<Vector2Int, List<MeshFilter>> ScanAndSortIntoChunks()
    {
        var groups = new Dictionary<Vector2Int, List<MeshFilter>>();
        var allFilters = GetComponentsInChildren<MeshFilter>(true);

        foreach (var mf in allFilters)
        {
            if (!IsValidForCombine(mf)) continue;

            Vector2Int coord = new Vector2Int(
                Mathf.FloorToInt(mf.transform.position.x / chunkSize),
                Mathf.FloorToInt(mf.transform.position.z / chunkSize)
            );

            if (!groups.ContainsKey(coord)) groups[coord] = new List<MeshFilter>();
            groups[coord].Add(mf);
        }
        return groups;
    }

    private bool IsValidForCombine(MeshFilter mf)
    {
        // 基本過濾
        if (mf.gameObject == this.gameObject || !mf.gameObject.isStatic) return false;
        
        // 這裡依然檢查 Tag，因為我們只抓取特定環境物件來畫，不畫怪物跟動態物件
        if (!mf.CompareTag(targetTag)) return false;

        // 專業過濾：子網格檢測 (這是破面主因)
        if (mf.sharedMesh.subMeshCount > 1) return false; 

        // 標籤過濾：如果有掛 Marker 且要求忽略，則跳過
        var marker = mf.GetComponent<CombineMarker>();
        if (marker != null && marker.ignoreCombine) return false;

        return true;
    }

    private void ProcessChunk(Vector2Int coord, List<MeshFilter> filters, Transform parent)
    {
        GameObject chunkObj = new GameObject($"Chunk_{coord.x}_{coord.y}");
        chunkObj.transform.parent = parent;

        // 核心邏輯：按「材質」+「影子狀態」分組
        var materialGroups = new Dictionary<Material, Dictionary<bool, List<MeshFilter>>>();

        foreach (var mf in filters)
        {
            var mr = mf.GetComponent<MeshRenderer>();
            var mat = mr.sharedMaterial;
            
            // 判定影子
            var marker = mf.GetComponent<CombineMarker>();
            bool needsShadow = (marker != null) ? !marker.forceNoShadow : (mr.shadowCastingMode != UnityEngine.Rendering.ShadowCastingMode.Off);

            if (!materialGroups.ContainsKey(mat)) materialGroups[mat] = new Dictionary<bool, List<MeshFilter>>();
            if (!materialGroups[mat].ContainsKey(needsShadow)) materialGroups[mat][needsShadow] = new List<MeshFilter>();
            
            materialGroups[mat][needsShadow].Add(mf);
        }

        // 執行合併
        foreach (var matGroup in materialGroups)
        {
            foreach (var shadowGroup in matGroup.Value)
            {
                FinalizeMeshCombine(chunkObj.transform, matGroup.Key, shadowGroup.Value, shadowGroup.Key);
            }
        }
    }

    private void FinalizeMeshCombine(Transform parent, Material mat, List<MeshFilter> filters, bool shadow)
    {
        GameObject obj = new GameObject($"Combined_{mat.name}_{(shadow ? "Shadow" : "NoShadow")}");
        obj.transform.parent = parent;
        obj.isStatic = true;
        obj.layer = targetLayer; // 賦予新視覺區塊目標 Layer

        CombineInstance[] combine = new CombineInstance[filters.Count];
        for (int i = 0; i < filters.Count; i++)
        {
            combine[i].mesh = filters[i].sharedMesh;
            // 轉為 local 空間，避免座標飄移
            combine[i].transform = obj.transform.worldToLocalMatrix * filters[i].transform.localToWorldMatrix;
            
            // --- 關鍵切除手術一：不殺死 GameObject，只關閉視覺渲染 ---
            // 這樣原物件的 BoxCollider、Tag、Layer 以及掛載的邏輯腳本全部正常運作
            var mr = filters[i].GetComponent<MeshRenderer>();
            if (mr != null) mr.enabled = false;
        }

        var mf = obj.AddComponent<MeshFilter>();
        Mesh newMesh = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32 };
        newMesh.CombineMeshes(combine, true, true); // 合併為單一網格
        mf.sharedMesh = newMesh;

        // --- 核心修正：將記憶體中的 Mesh 實體化為硬碟 Asset ---
#if UNITY_EDITOR
        if (!Application.isPlaying) 
        {
            // 1. 確保母資料夾存在
            if (!AssetDatabase.IsValidFolder(BASE_SAVE_FOLDER))
            {
                AssetDatabase.CreateFolder("Assets", "BakedChunks");
            }
            
            // 2. 確保此合併器的專屬子資料夾存在
            if (!AssetDatabase.IsValidFolder(CurrentSaveFolder))
            {
                AssetDatabase.CreateFolder(BASE_SAVE_FOLDER, bakeGroupName);
            }

            // 組合安全的檔名
            string safeMatName = mat.name.Replace("(Instance)", "").Trim();
            string meshName = $"{parent.name}_{safeMatName}_{(shadow ? "Shadow" : "NoShadow")}.asset";
            string assetPath = $"{CurrentSaveFolder}/{meshName}";

            // 儲存 Asset
            AssetDatabase.CreateAsset(newMesh, assetPath);
            AssetDatabase.SaveAssets();
        }
#endif

        var mrFinal = obj.AddComponent<MeshRenderer>();
        
        // 必須明確賦予材質與陰影狀態，否則物件將失去視覺資訊
        mrFinal.sharedMaterial = mat;
        mrFinal.shadowCastingMode = shadow ? UnityEngine.Rendering.ShadowCastingMode.On : UnityEngine.Rendering.ShadowCastingMode.Off;
        
        // --- 關鍵切除手術二：已徹底移除 MeshCollider 的生成邏輯 ---
        // GPU 專心畫圖，CPU 專心算原物件的隱形碰撞。
    }

    public void ClearAndRestore() 
    {
        // 1. 物理刪除合併生成的視覺容器
        Transform holder = transform.Find(HOLDER_NAME);
        if (holder != null) 
        {
            DestroyImmediate(holder.gameObject);
        }

        // --- 核心修正：斬草除根，清空所有實體 Mesh 檔案防止增生 ---
#if UNITY_EDITOR
        if (!Application.isPlaying)
        {
            if (AssetDatabase.IsValidFolder(CurrentSaveFolder))
            {
                AssetDatabase.DeleteAsset(CurrentSaveFolder);
                AssetDatabase.Refresh();
            }
        }
#endif
        
        // 2. 重新啟用所有被隱藏的原物件「渲染器」
        var allRenderers = GetComponentsInChildren<MeshRenderer>(true);
        foreach (var mr in allRenderers) 
        {
            // 只還原符合條件的靜態環境物件
            if (mr.gameObject.isStatic && mr.CompareTag(targetTag)) 
            {
                // --- 關鍵切除手術三：還原時只開啟 enabled ---
                mr.enabled = true;
            }
        }
        Debug.Log("<color=yellow>區塊還原完畢，已恢復原始物件視覺狀態。</color>");
    }
}//