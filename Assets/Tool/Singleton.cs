using UnityEngine;

/// <summary>
/// 通用 MonoBehaviour 單例基類。
/// 確保只有一個實例存在，並能在未實例化時動態創建（如果需要）。
/// </summary>
public abstract class Singleton<T> : MonoBehaviour where T : MonoBehaviour
{
    // 靜態實例欄位
    protected static T _instance;

    // 用於線程安全的鎖定物件 (防止多線程同時訪問，Unity中較少見但仍是好習慣)
    private static readonly object _lock = new object();

    // 應用程式是否正在退出 (避免退出時，其他物件再次嘗試訪問 Instance 造成新的實例被創建)
    private static bool _isQuitting = false;

    public static T Instance
    {
        get
        {
            if (_isQuitting)
            {
                // 如果應用程式正在退出，不要創建或返回實例
                Debug.LogWarning($"[Singleton<{typeof(T).Name}>] 應用正在退出，實例返回 null。");
                return null;
            }

            // 1. 如果已經有實例，直接返回
            if (_instance == null)
            {
                // 2. 進行鎖定，確保線程安全
                lock (_lock)
                {
                    // 3. 嘗試在場景中找到現有實例
                    _instance = FindObjectOfType<T>();

                    // 4. 如果仍未找到，且遊戲正在運行，則動態創建一個
                    if (_instance == null && Application.isPlaying)
                    {
                        GameObject singletonObject = new GameObject($"[Singleton] {typeof(T).Name}");
                        _instance = singletonObject.AddComponent<T>();
                        
                        // 【註】動態創建時，我們仍在這裡執行 DDOL，以確保這個自動生成的物件不會被銷毀
                        DontDestroyOnLoad(singletonObject);
                        Debug.Log($"[Singleton<{typeof(T).Name}>] 動態創建 Singleton：{singletonObject.name}");
                    }
                }
            }
            return _instance;
        }
    }

    /// <summary>
    /// 在實例被喚醒時調用，用於檢查單例的唯一性。
    /// </summary>
    protected virtual void Awake()
    {
        if (_instance != null && _instance != this)
        {
            // 如果場景中已經有一個實例，則銷毀這個重複的物件
            Debug.LogWarning($"[Singleton<{typeof(T).Name}>] 偵測到重複實例，銷毀物件：{gameObject.name}");
            Destroy(gameObject);
            return;
        }

        // 將當前物件設置為實例
        _instance = this as T;

        // 【重要】移除：DontDestroyOnLoad(gameObject);
        // 這將交由 GameManager 或 Bootstrap 腳本來決定。
    }

    /// <summary>
    /// 在應用程式退出時設置標誌，防止在退出過程中意外創建新的實例。
    /// </summary>
    protected virtual void OnApplicationQuit()
    {
        _isQuitting = true;
    }
}