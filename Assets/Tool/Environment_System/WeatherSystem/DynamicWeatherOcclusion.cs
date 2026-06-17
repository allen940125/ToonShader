using UnityEngine;
using System.Collections.Generic; // 必須引入此命名空間以使用 List

// 【嚴厲警告】：絕對禁止在這裡使用 [ExecuteAlways]！
// 在 Editor 模式下頻繁 Clone 材質球會導致編輯器記憶體直接被塞爆崩潰。
// 這是一個純粹的 Runtime (遊戲執行期) 腳本。
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

    // 【核心修正】：改用 List 來儲存未知數量的材質實例
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

        // 遍歷所有 Renderer
        foreach (Renderer r in targetRenderers)
        {
            if (r == null) continue;

            // 【絕對鐵律】：呼叫複數的 .materials 會強制 Clone 該 Renderer 上的「所有」材質，並回傳陣列
            Material[] mats = r.materials;
            
            // 將這些 Clone 出來的材質全數加入清單中統一管理
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
        // 遍歷清單中的每一個材質實例寫入參數
        for (int i = 0; i < instancedMaterials.Count; i++)
        {
            if (instancedMaterials[i] != null)
            {
                instancedMaterials[i].SetFloat(LocalWetnessID, currentWetness);
            }
        }
    }

    // 【絕對防線】：實例化材質的記憶體回收
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
}