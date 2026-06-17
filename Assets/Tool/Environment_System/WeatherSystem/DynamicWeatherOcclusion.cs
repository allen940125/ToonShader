using UnityEngine;

[ExecuteAlways]
public class DynamicWeatherOcclusion : MonoBehaviour
{
    [Header("--- 渲染目標設定 ---")]
    [Tooltip("手動指定需要淋濕的 Renderer。若留空，系統會在 Start 時自動抓取子物件所有的 Renderer")]
    [SerializeField] private Renderer[] targetRenderers;

    [Header("--- 射線偵測設定 ---")]
    [SerializeField] private LayerMask occlusionLayer;
    [SerializeField] private float maxRayDistance = 50f;
    [SerializeField] private float checkInterval = 0.2f;

    [Header("--- 材質過渡設定 ---")]
    [SerializeField] private float wetnessTransitionSpeed = 2.0f;

    // 只需要一個 MPB 實例，就可以給無數個 Renderer 共用
    private MaterialPropertyBlock propBlock;
    
    private float currentWetness = 0f;
    private float targetWetness = 0f;
    private float checkTimer = 0f;
    
    private static readonly int LocalWetnessID = Shader.PropertyToID("_LocalWetness");

    private void Start()
    {
        // --- 核心防呆與自動化邏輯 ---
        // 如果開發者沒有手動拖拉任何 Renderer，就自動抓取自身與所有子物件的 Renderer
        if (targetRenderers == null || targetRenderers.Length == 0)
        {
            targetRenderers = GetComponentsInChildren<Renderer>();
        }

        // 警告提示：如果連子物件都沒有 Renderer，則報錯並關閉腳本
        if (targetRenderers.Length == 0)
        {
            Debug.LogWarning($"[WeatherSystem] 物件 {gameObject.name} 及其子物件上找不到任何 Renderer！已停用天氣遮蔽腳本。");
            enabled = false; 
            return;
        }

        propBlock = new MaterialPropertyBlock();
        checkTimer = Random.Range(0f, checkInterval); 
    }

    private void Update()
    {
        // 1. 物理運算：只算一次
        checkTimer += Time.deltaTime;
        if (checkTimer >= checkInterval)
        {
            PerformOcclusionCheck();
            checkTimer = 0f;
        }

        // 2. 數值過渡：只算一次
        currentWetness = Mathf.MoveTowards(currentWetness, targetWetness, wetnessTransitionSpeed * Time.deltaTime);

        // 3. 渲染套用：利用迴圈一次性同步給所有分離的 Mesh
        ApplyWetnessToAllRenderers();
    }

    private void ApplyWetnessToAllRenderers()
    {
        for (int i = 0; i < targetRenderers.Length; i++)
        {
            Renderer r = targetRenderers[i];
            
            // 安全檢查：防止遊戲過程中某個部位的 Mesh 被銷毀（例如手被砍斷）導致報錯
            if (r == null) continue;

            r.GetPropertyBlock(propBlock);
            propBlock.SetFloat(LocalWetnessID, currentWetness);
            r.SetPropertyBlock(propBlock);
        }
    }

    private void PerformOcclusionCheck()
    {
        if (WeatherManager.Instance == null)
        {
            targetWetness = 0f;
            return;
        }

        Vector3 rayOrigin = GetRayOrigin();
        Vector3 rayDirection = GetRayDirection();

        if (Physics.Raycast(rayOrigin, rayDirection, out RaycastHit hit, maxRayDistance, occlusionLayer))
        {
            targetWetness = 0f;
        }
        else
        {
            targetWetness = WeatherManager.Instance.globalRainIntensity;
        }
    }

    private Vector3 GetRayOrigin()
    {
        // 如果你的父物件在腳底 (0,0,0)，建議把這裡的 0.5f 提高到 1.5f (大約頭部高度)
        // 避免射線從腳底發射打到旁邊的階梯
        return transform.position + Vector3.up * 1.5f; 
    }

    private Vector3 GetRayDirection()
    {
        if (WeatherManager.Instance != null)
        {
            return -WeatherManager.Instance.rainDirection.normalized;
        }
        return Vector3.up; 
    }

    private void OnDrawGizmosSelected()
    {
        Vector3 rayOrigin = GetRayOrigin();
        Vector3 rayDirection = GetRayDirection();

        if (Physics.Raycast(rayOrigin, rayDirection, out RaycastHit hit, maxRayDistance, occlusionLayer))
        {
            Gizmos.color = Color.red; 
            Gizmos.DrawLine(rayOrigin, hit.point);
            Gizmos.DrawWireSphere(hit.point, 0.1f); 
        }
        else
        {
            Gizmos.color = Color.green; 
            Gizmos.DrawLine(rayOrigin, rayOrigin + rayDirection * maxRayDistance);
        }
    }
}