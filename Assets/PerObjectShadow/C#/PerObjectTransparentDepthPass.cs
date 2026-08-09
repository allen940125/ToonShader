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
            public RendererListHandle rendererList1; // 第一枚代幣
            public RendererListHandle rendererList2; // 第二枚代幣
            public TextureHandle cameraDepthTarget;
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

            // --- 2. 向 Render Graph 註冊兩張獨立的繪製清單 ---
            SortingCriteria sortingCriteria = SortingCriteria.CommonTransparent;
            DrawingSettings drawingSettings = CreateDrawingSettings(s_ShaderTagId, renderingData, cameraData, lightData, sortingCriteria);
            FilteringSettings filteringSettings = new FilteringSettings(RenderQueueRange.transparent);
            
            RendererListParams rlParams = new RendererListParams(renderingData.cullResults, drawingSettings, filteringSettings);
            
            // 【核心修正】：為兩次 Draw 申請兩枚獨立的代幣
            RendererListHandle rendererList1 = renderGraph.CreateRendererList(rlParams);
            RendererListHandle rendererList2 = renderGraph.CreateRendererList(rlParams);

            // --- 3. 建立 UnsafePass ---
            using (var builder = renderGraph.AddUnsafePass<PassData>("PerObjectTransparentDepth", out var passData))
            {
                passData.pass = this;
                passData.rendererList1 = rendererList1;
                passData.rendererList2 = rendererList2;
                passData.cameraDepthTarget = resourceData.activeDepthTexture; 
                
                // 【核心修正】：必須向系統宣告這兩枚代幣都會被使用
                builder.UseRendererList(rendererList1);
                builder.UseRendererList(rendererList2);
                builder.AllowPassCulling(false);

                if (passData.cameraDepthTarget.IsValid())
                {
                    builder.UseTexture(passData.cameraDepthTarget, AccessFlags.Write);
                }

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
                // 第一次繪製：消耗第一枚代幣
                cmd.SetRenderTarget(m_TransparentDepthTexture);
                cmd.ClearRenderTarget(true, true, Color.black);
                context.cmd.DrawRendererList(data.rendererList1); // 使用 rendererList1

                cmd.SetGlobalTexture(s_TransparentDepthTextureID, m_TransparentDepthTexture.nameID);

                // 第二次繪製：消耗第二枚代幣
                if (data.cameraDepthTarget.IsValid())
                {
                    cmd.SetRenderTarget(data.cameraDepthTarget);
                    context.cmd.DrawRendererList(data.rendererList2); // 使用 rendererList2
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