using UnityEngine;
using System.Collections.Generic;
using UnityEngine.Rendering;

public class ChunkCombinerMaster : MonoBehaviour
{
    [Header("狀態監控")]
    [Tooltip("腳本會自動抓取並記錄底下的所有合併器")]
    public List<AdvancedChunkCombiner> combiners = new List<AdvancedChunkCombiner>();

    [ContextMenu("1. 重新抓取所有合併器 (Refresh)")]
    public void FetchAllCombiners()
    {
        // 自動向下搜尋所有子層級的合併器
        combiners = new List<AdvancedChunkCombiner>(GetComponentsInChildren<AdvancedChunkCombiner>(true));
        Debug.Log($"<color=green>【總管】已成功同步 {combiners.Count} 個合併器節點。</color>");
    }

    [ContextMenu("2. [執行] 全場景合併")]
    public void ExecuteAllCombine()
    {
        if (combiners.Count == 0) FetchAllCombiners();
        if (combiners.Count == 0) return;

        foreach (var combiner in combiners)
        {
            if (combiner != null) combiner.ExecuteProfessionalCombine();
        }
        Debug.Log("<color=cyan>【總管】全場景區塊合併作業完畢。</color>");
    }

    [ContextMenu("3. [還原] 全場景解散")]
    public void RestoreAll()
    {
        if (combiners.Count == 0) FetchAllCombiners();
        
        foreach (var combiner in combiners)
        {
            if (combiner != null) combiner.ClearAndRestore();
        }
        Debug.Log("<color=yellow>【總管】全場景區塊已還原為原始獨立狀態。</color>");
    }

    [ContextMenu("⚙️ 覆寫: 強制關閉所有生成的陰影 (極致效能)")]
    public void ForceDisableAllShadows() 
    { 
        ApplyShadowState(false); 
    }

    [ContextMenu("⚙️ 覆寫: 恢復原本應有的陰影 (依賴命名邏輯)")]
    public void RestoreOriginalShadows() 
    { 
        ApplyShadowState(true); 
    }

    private void ApplyShadowState(bool enableShadows)
    {
        int modifiedCount = 0;

        foreach (var combiner in combiners)
        {
            if (combiner == null) continue;

            // 定位該合併器生成的容器
            Transform holder = combiner.transform.Find("--- COMBINED_CHUNKS_HOLDER ---");
            if (holder == null) continue;

            // 抓取容器內所有生成的網格渲染器
            MeshRenderer[] renderers = holder.GetComponentsInChildren<MeshRenderer>(true);
            foreach (var mr in renderers)
            {
                if (!enableShadows)
                {
                    // 強制全部關閉
                    mr.shadowCastingMode = ShadowCastingMode.Off;
                    modifiedCount++;
                }
                else
                {
                    mr.shadowCastingMode = ShadowCastingMode.On;
                    modifiedCount++;
                    // 理性恢復：只針對原本結尾是 "_Shadow" 的網格開啟陰影
                    // if (mr.gameObject.name.EndsWith("_Shadow"))
                    // {
                    //     mr.shadowCastingMode = ShadowCastingMode.On;
                    //     modifiedCount++;
                    // }
                }
            }
        }

        string stateStr = enableShadows ? "恢復原廠設定 (部分開啟)" : "強制關閉 (全滅)";
        Debug.Log($"<color=white>【總管】陰影覆寫完成。模式: {stateStr} | 影響區塊數: {modifiedCount}</color>");
    }
}