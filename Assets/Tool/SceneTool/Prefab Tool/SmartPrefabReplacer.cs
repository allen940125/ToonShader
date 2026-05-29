using UnityEngine;
using System.Collections.Generic;
using System.Text.RegularExpressions;
#if UNITY_EDITOR
using UnityEditor;
#endif

public class SmartPrefabReplacer : MonoBehaviour
{
    [Header("搜尋與過濾設定")]
    public bool includeAllChildren = true; 

    [Tooltip("開啟後，僅替換自身或【第一層子節點】帶有 Mesh 的物件，防止誤刪最外層分類資料夾。")]
    public bool replaceOnlyMeshes = true;

    public bool keepPrefabOriginalScale = false; 

    public enum MatchType
    {
        Contains, 
        Exact     
    }

    [System.Serializable]
    public class PrefabOption
    {
        public GameObject prefab;
        [Range(0f, 100f)] public float weight = 10f; 
    }

    [System.Serializable]
    public class ReplacementRule
    {
        [Tooltip("勾選：執行此規則\n取消勾選：停用此規則(無視設定)")]
        public bool isActive = true; // 核心新增：規則獨立開關

        public string nameFilter;
        public MatchType matchType = MatchType.Exact; 
        public bool renameToRule = true; 
        public List<PrefabOption> prefabOptions;
    }

    [Header("替換規則清單")]
    public List<ReplacementRule> replacementRules;

#if UNITY_EDITOR
    public void ExecuteReplacement()
    {
        if (replacementRules == null || replacementRules.Count == 0) return;

        List<Transform> candidates = new List<Transform>();
        
        if (includeAllChildren)
        {
            Transform[] allTransforms = GetComponentsInChildren<Transform>(true);
            foreach (Transform t in allTransforms) if (t != this.transform) candidates.Add(t);
        }
        else
        {
            foreach (Transform child in transform) candidates.Add(child);
        }

        int replaceCount = 0;
        int skippedCount = 0;

        Undo.IncrementCurrentGroup();
        Undo.SetCurrentGroupName("Replace Prefabs");
        var undoGroup = Undo.GetCurrentGroup();

        Transform[] safeCandidates = candidates.ToArray();

        foreach (Transform target in safeCandidates)
        {
            if (target == null) continue;

            if (replaceOnlyMeshes)
            {
                bool hasMesh = CheckMeshInSelfOrDirectChildren(target);
                if (!hasMesh) 
                { 
                    skippedCount++; 
                    continue; 
                }
            }

            string cleanName = GetCleanName(target.name);
            ReplacementRule targetRule = FindMatchingRule(target.name, cleanName);

            if (targetRule != null && targetRule.prefabOptions.Count > 0)
            {
                GameObject selectedPrefab = GetWeightedRandomPrefab(targetRule.prefabOptions);

                if (selectedPrefab != null)
                {
                    GameObject newObj = (GameObject)PrefabUtility.InstantiatePrefab(selectedPrefab);
                    Undo.RegisterCreatedObjectUndo(newObj, "Create New Prefab");

                    newObj.transform.SetParent(target.parent); 
                    newObj.transform.localPosition = target.localPosition;
                    newObj.transform.localRotation = target.localRotation;

                    if (!keepPrefabOriginalScale)
                    {
                        newObj.transform.localScale = target.localScale;
                    }

                    string prefabName = selectedPrefab.name;
                    string extraTag = "";

                    if (prefabName.Contains("_"))
                    {
                        int lastUnderscore = prefabName.LastIndexOf('_');
                        extraTag = prefabName.Substring(lastUnderscore); 
                    }

                    newObj.name = targetRule.renameToRule ? targetRule.nameFilter + extraTag : prefabName;

                    Undo.DestroyObjectImmediate(target.gameObject);
                    replaceCount++;
                }
            }
        }
        
        Undo.CollapseUndoOperations(undoGroup);
        Debug.Log($"<color=green><b>嚴謹替換完成！</b></color> 成功: {replaceCount} | 條件不符跳過: {skippedCount}");
    }

    private bool CheckMeshInSelfOrDirectChildren(Transform target)
    {
        if (target.GetComponent<MeshFilter>() != null || target.GetComponent<SkinnedMeshRenderer>() != null)
            return true;

        foreach (Transform child in target)
        {
            if (child.GetComponent<MeshFilter>() != null || child.GetComponent<SkinnedMeshRenderer>() != null)
                return true;
        }

        return false; 
    }

    private string GetCleanName(string originalName)
    {
        return Regex.Replace(originalName, @"\s\(\d+\)$", "");
    }

    private ReplacementRule FindMatchingRule(string rawName, string cleanName)
    {
        foreach (var rule in replacementRules)
        {
            // 核心邏輯修改：若規則未啟用，直接跳過後續比對
            if (!rule.isActive) continue; 
            
            if (string.IsNullOrEmpty(rule.nameFilter)) continue;

            if (rule.matchType == MatchType.Exact && cleanName.Equals(rule.nameFilter)) return rule;
            if (rule.matchType == MatchType.Contains && rawName.Contains(rule.nameFilter)) return rule;
        }
        return null;
    }

    private GameObject GetWeightedRandomPrefab(List<PrefabOption> options)
    {
        float totalWeight = 0f;
        foreach (var option in options) totalWeight += option.weight;

        float randomValue = Random.Range(0, totalWeight);
        float currentWeight = 0f;

        foreach (var option in options)
        {
            currentWeight += option.weight;
            if (randomValue <= currentWeight) return option.prefab;
        }
        return options[0].prefab;
    }
#endif
}

#if UNITY_EDITOR
[CustomEditor(typeof(SmartPrefabReplacer))]
public class SmartPrefabReplacerEditor : Editor
{
    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();
        SmartPrefabReplacer script = (SmartPrefabReplacer)target;

        GUILayout.Space(20);
        GUI.backgroundColor = new Color(1f, 0.9f, 0.4f); 
        if (GUILayout.Button("執行嚴謹替換", GUILayout.Height(40)))
        {
            script.ExecuteReplacement();
        }
        GUI.backgroundColor = Color.white;
    }
}
#endif