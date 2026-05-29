using UnityEngine;

namespace Core.Optimization
{
    public class CombineMarker : MonoBehaviour
    {
        [Header("合併設定")]
        public bool ignoreCombine = false;    // 複雜模型或透明物件勾選此項
        public bool forceNoShadow = false;   // 強制關閉影子
        
        [Header("除錯資訊")]
        public string reason;      // 如果被自動剔除，顯示原因
    }
}