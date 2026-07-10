using UnityEngine;

[ExecuteAlways]
public class HairLightController : MonoBehaviour
{
    [Header("光照錨點 (Lighting Anchor)")]
    [Tooltip("請將設定好位置與旋轉的 Empty GameObject 拖曳至此。")]
    public Transform lightingAnchor;

    [Header("Debug 顯示")]
    public bool showGizmos = true;
    [Range(0.1f, 2.0f)]
    public float gizmoLineLength = 0.5f;

    private static readonly int HeadPositionId = Shader.PropertyToID("_HeadPosition");
    private static readonly int HeadForwardId = Shader.PropertyToID("_HeadForward");
    private static readonly int HeadUpId = Shader.PropertyToID("_HeadUp");

    void LateUpdate()
    {
        if (lightingAnchor == null) return;

        // 直接讀取錨點的絕對位置與方向，不再依賴根節點或頭部骨骼的邏輯猜測
        Shader.SetGlobalVector(HeadPositionId, new Vector4(lightingAnchor.position.x, lightingAnchor.position.y, lightingAnchor.position.z, 1.0f));
        Shader.SetGlobalVector(HeadForwardId, new Vector4(lightingAnchor.forward.x, lightingAnchor.forward.y, lightingAnchor.forward.z, 0.0f));
        Shader.SetGlobalVector(HeadUpId, new Vector4(lightingAnchor.up.x, lightingAnchor.up.y, lightingAnchor.up.z, 0.0f));
    }

    // 建議改為 OnDrawGizmos，這樣即使不選取物件也能在 Scene 視窗看到輔助線，方便微調
    private void OnDrawGizmos()
    {
        if (!showGizmos || lightingAnchor == null) return;

        Vector3 pos = lightingAnchor.position;
        Vector3 forward = lightingAnchor.forward;
        Vector3 up = lightingAnchor.up;

        // 1. 原點：天使環球形法線中心
        Gizmos.color = Color.yellow;
        Gizmos.DrawSphere(pos, 0.03f);

        // 2. 藍線：假半角向量 (Fake Half-Vector) 的朝向，必須對齊角色正前方
        Gizmos.color = Color.blue;
        Gizmos.DrawLine(pos, pos + forward * gizmoLineLength);

        // 3. 綠線：頭頂假光的朝向，必須對齊角色正上方
        Gizmos.color = Color.green;
        Gizmos.DrawLine(pos, pos + up * gizmoLineLength);
    }
}