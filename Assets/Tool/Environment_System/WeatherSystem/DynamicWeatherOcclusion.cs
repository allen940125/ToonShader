using UnityEngine;
using System.Collections.Generic;

// 絕對禁止在這裡加上 [ExecuteAlways]
public class DynamicWeatherOcclusion : MonoBehaviour
{
    [Header("--- 渲染目標設定 ---")]
    [Tooltip("手動指定需要淋濕的 Renderer。若留空，則自動抓取")]
    [SerializeField] private Renderer[] targetRenderers;

    [Header("--- 射線偵測設定 ---")]
    [SerializeField] private LayerMask occlusionLayer;
    [SerializeField] private float maxRayDistance = 50f;
    [SerializeField] private float checkInterval = 0.2f;

    [Header("--- 材質過渡設定 ---")]
    [SerializeField] private float wetnessTransitionSpeed = 2.0f;

    private List<Material> instancedMaterials = new List<Material>();
    
    private float currentWetness = 0f;
    private float targetWetness = 0f;
    private float checkTimer = 0f;
    
    private static readonly int LocalWetnessID = Shader.PropertyToID("_LocalWetness");

    private void Start()
    {
        if (targetRenderers == null || targetRenderers.Length == 0)
        {
            targetRenderers = GetComponentsInChildren<Renderer>();
        }

        if (targetRenderers.Length == 0)
        {
            enabled = false; 
            return;
        }

        foreach (Renderer r in targetRenderers)
        {
            if (r == null) continue;
            Material[] mats = r.materials;
            instancedMaterials.AddRange(mats);
        }
        
        checkTimer = Random.Range(0f, checkInterval); 
    }

    private void Update()
    {
        checkTimer += Time.deltaTime;
        if (checkTimer >= checkInterval)
        {
            PerformOcclusionCheck();
            checkTimer = 0f;
        }

        currentWetness = Mathf.MoveTowards(currentWetness, targetWetness, wetnessTransitionSpeed * Time.deltaTime);
        ApplyWetnessToInstancedMaterials();
    }

    private void ApplyWetnessToInstancedMaterials()
    {
        for (int i = 0; i < instancedMaterials.Count; i++)
        {
            if (instancedMaterials[i] != null)
            {
                instancedMaterials[i].SetFloat(LocalWetnessID, currentWetness);
            }
        }
    }

    private void OnDestroy()
    {
        if (instancedMaterials != null)
        {
            for (int i = 0; i < instancedMaterials.Count; i++)
            {
                if (instancedMaterials[i] != null)
                {
                    Destroy(instancedMaterials[i]);
                }
            }
            instancedMaterials.Clear();
        }
    }

    private void PerformOcclusionCheck()
    {
        if (WeatherManager.Instance == null)
        {
            targetWetness = 0f;
            return;
        }

        Vector3 rayOrigin = transform.position + Vector3.up * 1.5f; 
        Vector3 rayDirection = -WeatherManager.Instance.rainDirection.normalized;

        if (Physics.Raycast(rayOrigin, rayDirection, out RaycastHit hit, maxRayDistance, occlusionLayer))
        {
            targetWetness = 0f;
        }
        else
        {
            targetWetness = WeatherManager.Instance.globalRainIntensity;
        }
    }

    // ==========================================
    // 【新增】：在 Scene 視窗可視化遮蔽射線
    // 只有在選取該物件時才會繪製，不會干擾畫面
    // ==========================================
    private void OnDrawGizmosSelected()
    {
        // 模擬 PerformOcclusionCheck 中的數學邏輯
        Vector3 rayOrigin = transform.position + Vector3.up * 1.5f; 
        Vector3 rayDirection = Vector3.up;

        // 向 WeatherManager 索取雨水的反方向 (如果雨斜著下，就要斜著往上找屋簷)
        if (WeatherManager.Instance != null)
        {
            rayDirection = -WeatherManager.Instance.rainDirection.normalized;
        }

        // 執行一條純粹用來繪製的物理射線
        if (Physics.Raycast(rayOrigin, rayDirection, out RaycastHit hit, maxRayDistance, occlusionLayer))
        {
            // 命中遮蔽物：畫紅線並標記擊中點
            Gizmos.color = Color.red;
            Gizmos.DrawLine(rayOrigin, hit.point);
            Gizmos.DrawWireSphere(hit.point, 0.1f);
        }
        else
        {
            // 無遮蔽物：畫綠線直通天際
            Gizmos.color = Color.green;
            Gizmos.DrawLine(rayOrigin, rayOrigin + rayDirection * maxRayDistance);
        }
    }
}