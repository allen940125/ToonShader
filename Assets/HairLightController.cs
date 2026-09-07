using UnityEngine;

[ExecuteAlways]
public class HeadLightingController : MonoBehaviour
{
    [Header("光照錨點 (Lighting Anchor)")]
    [Tooltip("請將設定好位置與旋轉的 Empty GameObject (或頭部骨骼) 拖曳至此。")]
    public Transform lightingAnchor;

    [Header("Debug 顯示")]
    public bool showGizmos = true;
    [Range(0.1f, 2.0f)]
    public float gizmoLineLength = 0.5f;

    private static readonly int HeadPositionId = Shader.PropertyToID("_HeadPosition");
    private static readonly int HeadForwardId = Shader.PropertyToID("_HeadForward");
    private static readonly int HeadUpId = Shader.PropertyToID("_HeadUp");
    private static readonly int HeadRightId = Shader.PropertyToID("_HeadRight"); // 臉部 SDF 需要

    void LateUpdate()
    {
        if (lightingAnchor == null) return;

        // 一次性將頭部空間矩陣推播給全域，讓 Hair 和 Face Shader 同時接收
        Shader.SetGlobalVector(HeadPositionId, new Vector4(lightingAnchor.position.x, lightingAnchor.position.y, lightingAnchor.position.z, 1.0f));
        Shader.SetGlobalVector(HeadForwardId, new Vector4(lightingAnchor.forward.x, lightingAnchor.forward.y, lightingAnchor.forward.z, 0.0f));
        Shader.SetGlobalVector(HeadUpId, new Vector4(lightingAnchor.up.x, lightingAnchor.up.y, lightingAnchor.up.z, 0.0f));
        Shader.SetGlobalVector(HeadRightId, new Vector4(lightingAnchor.right.x, lightingAnchor.right.y, lightingAnchor.right.z, 0.0f));
        
        //Debug.Log($"[資料流偵測] 真實座標: {lightingAnchor.position} | 真實朝向: {lightingAnchor.forward}");

    }

    private void OnDrawGizmos()
    {
        if (!showGizmos || lightingAnchor == null) return;

        Vector3 pos = lightingAnchor.position;
        Vector3 forward = lightingAnchor.forward;
        Vector3 up = lightingAnchor.up;
        Vector3 right = lightingAnchor.right;

        // 原點
        Gizmos.color = Color.yellow;
        Gizmos.DrawSphere(pos, 0.03f);

        // 藍線：角色正前方 (髮絲半角 / 臉部 SDF)
        Gizmos.color = Color.blue;
        Gizmos.DrawLine(pos, pos + forward * gizmoLineLength);

        // 綠線：角色正上方 (髮絲頂光 / 臉部 SDF)
        Gizmos.color = Color.green;
        Gizmos.DrawLine(pos, pos + up * gizmoLineLength);

        // 紅線：角色正右方 (臉部 SDF 判斷左右臉用)
        Gizmos.color = Color.red;
        Gizmos.DrawLine(pos, pos + right * gizmoLineLength);
    }
}