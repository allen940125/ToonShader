using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule; // Unity 6 Render Graph 必須引入

public class StickerMaskFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public LayerMask layerMask;
        public Material overrideMaterial;
        public string targetTextureName = "_StickerMaskTex";
    }

    public Settings settings = new Settings();
    MaskPass pass;

    public override void Create()
    {
        pass = new MaskPass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass);
    }

    protected override void Dispose(bool disposing)
    {
        pass = null;
    }

    class MaskPass : ScriptableRenderPass
    {
        Settings settings;

        class PassData
        {
            public RendererListHandle rendererListHandle;
        }

        public MaskPass(Settings settings)
        {
            this.settings = settings;
            this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (settings.overrideMaterial == null) return;

            UniversalRenderingData renderingData = frameData.Get<UniversalRenderingData>();
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            UniversalLightData lightData = frameData.Get<UniversalLightData>();

            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            
            TextureDesc desc = new TextureDesc(
                cameraData.cameraTargetDescriptor.width,
                cameraData.cameraTargetDescriptor.height
            )
            {
                colorFormat = GraphicsFormat.R8_UNorm,
                depthBufferBits = DepthBits.None,
                msaaSamples = MSAASamples.None,
                clearBuffer = true,       // 由管線接手背景清理
                clearColor = Color.black, // 清理為全黑
                name = settings.targetTextureName
            };
            
            TextureHandle maskTexture = renderGraph.CreateTexture(desc);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("StickerMaskPass", out var passData))
            {
                builder.SetRenderAttachment(maskTexture, 0);
                // 【核心修正】強制作為 Depth Attachment 綁定當前攝影機的場景深度
                // 確保 Mask 的渲染嚴格遵守場景遮擋，消滅 X-Ray 透視亂畫的問題
                if (resourceData.activeDepthTexture.IsValid())
                {
                    builder.SetRenderAttachmentDepth(resourceData.activeDepthTexture, AccessFlags.Read);
                }

                builder.AllowPassCulling(false);
                builder.SetGlobalTextureAfterPass(maskTexture, Shader.PropertyToID(settings.targetTextureName));

                // 【修正核心】使用 Render Graph 專用 API 延長貼圖生命週期並註冊為全域變數
                builder.SetGlobalTextureAfterPass(maskTexture, Shader.PropertyToID(settings.targetTextureName));

                DrawingSettings drawSettings = RenderingUtils.CreateDrawingSettings(
                    new ShaderTagId("UniversalForward"), renderingData, cameraData, lightData, cameraData.defaultOpaqueSortFlags);
                drawSettings.SetShaderPassName(1, new ShaderTagId("UniversalForwardOnly"));
                drawSettings.SetShaderPassName(2, new ShaderTagId("LightweightForward"));
                drawSettings.SetShaderPassName(3, new ShaderTagId("SRPDefaultUnlit")); // 捕捉 SG Unlit 的關鍵
                
                drawSettings.overrideMaterial = settings.overrideMaterial;
                FilteringSettings filterSettings = new FilteringSettings(RenderQueueRange.opaque, settings.layerMask);
                
                passData.rendererListHandle = renderGraph.CreateRendererList(new RendererListParams(renderingData.cullResults, drawSettings, filterSettings));
                builder.UseRendererList(passData.rendererListHandle);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    // 嚴禁在此處呼叫 ClearRenderTarget 或 SetGlobalTexture
                    // 僅保留核心的繪製指令
                    context.cmd.DrawRendererList(data.rendererListHandle);
                });
            }
        }
    }
}