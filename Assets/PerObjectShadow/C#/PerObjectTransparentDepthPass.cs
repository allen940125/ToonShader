using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule; // 【新增】：必須引入 Render Graph 命名空間

namespace UnityEngine.Rendering.Universal
{
    public class PerObjectTransparentDepthPass : ScriptableRenderPass
    {
        private static readonly ProfilingSampler s_ProfilingSampler = new ProfilingSampler("PerObject Transparent Depth");
        private static readonly int s_TransparentDepthTextureID = Shader.PropertyToID("_PerObjectTransparentDepthTexture");
        private static readonly ShaderTagId s_ShaderTagId = new ShaderTagId("TransparentDepthPrepass");

        private RTHandle m_TransparentDepthTexture;

        // 傳輸包裝結構
        private class PassData
        {
            public PerObjectTransparentDepthPass pass;
            public RendererListHandle rendererList;  // 【核心變更】：Unity 6 繪製物件的專用 Handle
            public RTHandle cameraDepthTarget;
        }

        // ==============================================================
        // 全新 Unity 6.4 進入點：RecordRenderGraph
        // ==============================================================
        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            // 提取 Unity 6 的全域資料容器
            UniversalRenderingData renderingData = frameData.Get<UniversalRenderingData>();
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            UniversalLightData lightData = frameData.Get<UniversalLightData>();
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();

            // --- 1. 移植原本 OnCameraSetup 的 RT 分配邏輯 ---
            RenderTextureDescriptor descriptor = cameraData.cameraTargetDescriptor;
            descriptor.colorFormat = RenderTextureFormat.Depth;
            descriptor.depthBufferBits = 32;
            descriptor.msaaSamples = 1;
            descriptor.bindMS = false;
            descriptor.useMipMap = false;
            descriptor.autoGenerateMips = false;

            RenderingUtils.ReAllocateIfNeeded(ref m_TransparentDepthTexture, descriptor, FilterMode.Point, TextureWrapMode.Clamp, name: "_PerObjectTransparentDepthTexture");

            // --- 2. 【核心變更】：向 Render Graph 註冊要繪製的物件清單 (RendererList) ---
            SortingCriteria sortingCriteria = SortingCriteria.CommonTransparent;
            DrawingSettings drawingSettings = CreateDrawingSettings(s_ShaderTagId, renderingData, cameraData, lightData, sortingCriteria);
            FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.transparent);
            
            RendererListParams rlParams = new RendererListParams(renderingData.cullResults, drawingSettings, filteringSettings);
            RendererListHandle rendererList = renderGraph.CreateRendererList(rlParams);

            // --- 3. 建立 UnsafePass ---
            using (var builder = renderGraph.AddUnsafePass<PassData>("PerObjectTransparentDepth", out var passData))
            {
                passData.pass = this;
                passData.rendererList = rendererList;
                passData.cameraDepthTarget = resourceData.activeDepthTexture; // 抓取主攝影機的深度圖
                
                // 必須宣告使用這個 RendererList，否則 GPU 會剔除它
                builder.UseRendererList(rendererList);
                builder.AllowPassCulling(false);

                // 移交執行權
                builder.SetRenderFunc((PassData data, UnsafeGraphContext context) =>
                {
                    CommandBuffer cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                    data.pass.ExecuteLegacy(cmd, context, data);
                });
            }
        }

        // ==============================================================
        // 實際執行 GPU 指令的底層邏輯
        // ==============================================================
        private void ExecuteLegacy(CommandBuffer cmd, UnsafeGraphContext context, PassData data)
        {
            using (new ProfilingScope(cmd, s_ProfilingSampler))
            {
                // 第一次繪製：畫到我們專屬的透明深度圖上
                cmd.SetRenderTarget(m_TransparentDepthTexture);
                cmd.ClearRenderTarget(true, true, Color.black);
                
                // 【核心變更】：Unity 6 中只能透過 context.cmd 呼叫 DrawRendererList
                context.cmd.DrawRendererList(data.rendererList);

                // 全域廣播變數，讓 Eye Shader 可以讀取
                cmd.SetGlobalTexture(s_TransparentDepthTextureID, m_TransparentDepthTexture.nameID);

                // 第二次繪製：忠實還原你原始腳本的邏輯，將透明深度再次寫回主攝影機深度圖
                if (data.cameraDepthTarget != null)
                {
                    cmd.SetRenderTarget(data.cameraDepthTarget);
                    context.cmd.DrawRendererList(data.rendererList);
                }
            }
        }

        public void Dispose()
        {
            m_TransparentDepthTexture?.Release();
            m_TransparentDepthTexture = null;
        }
    }
}