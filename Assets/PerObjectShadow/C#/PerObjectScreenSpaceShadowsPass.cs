using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;

namespace UnityEngine.Rendering.Universal
{
    /// <summary>
    /// 第二阶段：屏幕空间阴影计算 Pass
    /// 利用体积盒 (Volume Box) 重建世界坐标，采样 ShadowMap 并输出到屏幕空间彩色贴图
    /// </summary>
    public class PerObjectScreenSpaceShadowsPass : ScriptableRenderPass
    {
        private static readonly ProfilingSampler s_ProfilingSampler = new ProfilingSampler("PerObject ScreenSpace Shadows");
        
        // Shader 属性映射
        private static readonly int s_ShadowMapID = Shader.PropertyToID("_PerObjectShadowmapTexture");
        private static readonly int s_ShadowParamsID = Shader.PropertyToID("_PerObjectShadowParams");
        private static readonly int s_ShadowAtlasSizeID = Shader.PropertyToID("_PerObjectShadowAtlasSize");
        private static readonly int s_ScreenSpaceShadowMapID = Shader.PropertyToID("_PerObjectScreenSpaceShadowMap");
        
        // 体积投影矩阵属性
        private static readonly int s_VolumeWorldToShadowID = Shader.PropertyToID("_VolumeWorldToShadow");
        private static readonly int s_VolumeWorldToShadowClipID = Shader.PropertyToID("_VolumeWorldToShadowClip");
        private static readonly int s_VolumeUvScaleOffsetID = Shader.PropertyToID("_VolumeUvScaleOffset");
        private static readonly int s_ShadowRampTexID = Shader.PropertyToID("_ShadowRampTex");
        private static readonly int s_UseShadowRampID = Shader.PropertyToID("_UseShadowRamp");
        private static readonly int s_PerObjectShadowEnabledID = Shader.PropertyToID("_PerObjectShadowEnabled");

        // PCF 变体关键字
        private static readonly string k_PCFLowKeyword = "_PCF_LOW";
        private static readonly string k_PCFMediumKeyword = "_PCF_MEDIUM";
        private static readonly string k_PCFHighKeyword = "_PCF_HIGH";
        
        private PerObjectShadowFeature m_Feature;
        private RTHandle m_MainShadowMapTexture;       
        private RTHandle m_VirtualShadowMapTexture;    
        private bool m_EnableVirtualLight;
        private List<PerObjectShadowData> m_ShadowDataList; 
        private int m_ValidObjectCount;                
        private Vector2Int m_EnvironmentShadowMapResolution;
        private int m_EnvironmentTileResolution;
        private Vector2Int m_SelfShadowMapResolution;
        private int m_SelfTileResolution;
        
        private RTHandle m_ScreenSpaceShadowMapTexture;         // 存储最终生成的彩色阴影图
        private RTHandle m_ResolvedScreenSpaceShadowMapTexture;  // MSAA 解析后的纹理
        
        private Material m_ShadowMaterial;                      // 核心渲染材质
        private readonly Dictionary<int, Material> m_SelfStencilMaterials = new Dictionary<int, Material>();// 键值表，用于存储自阴影材质，键为模板值，值为材质
        
        public PerObjectScreenSpaceShadowsPass(PerObjectShadowFeature feature)
        {
            m_Feature = feature;
            
            Shader shader = Shader.Find("Hidden/PerObjectShadowCaster");
            if (shader != null)
                m_ShadowMaterial = new Material(shader);
        }
        
        /// <summary>
        /// 接收第一阶段的渲染数据
        /// </summary>
        public bool Setup(RTHandle mainShadowMap, RTHandle virtualShadowMap, List<PerObjectShadowData> shadowDataList, 
            int validObjectCount, Vector2Int environmentShadowMapResolution, int environmentTileResolution,
            Vector2Int selfShadowMapResolution, int selfTileResolution, bool enableVirtualLight)
        {
            m_MainShadowMapTexture = mainShadowMap;
            m_VirtualShadowMapTexture = virtualShadowMap;
            m_EnableVirtualLight = enableVirtualLight;
            m_ShadowDataList = shadowDataList;
            m_ValidObjectCount = validObjectCount;
            m_EnvironmentShadowMapResolution = environmentShadowMapResolution;
            m_EnvironmentTileResolution = environmentTileResolution;
            m_SelfShadowMapResolution = selfShadowMapResolution;
            m_SelfTileResolution = selfTileResolution;
            
            ConfigureInput(ScriptableRenderPassInput.Depth); // 必须依赖深度图重建坐标
            
            return m_MainShadowMapTexture != null && m_ValidObjectCount > 0;
        }
        
        private class PassData
        {
            public PerObjectScreenSpaceShadowsPass pass;
            public TextureHandle cameraDepthTarget; // 提前抓好的深度圖把手
            public Matrix4x4 gpuVPInverse;          // 提前算好的逆矩陣
        }

        // 全新 Unity 6.4 進入點：RecordRenderGraph
        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (m_ShadowMaterial == null || m_MainShadowMapTexture == null || m_ValidObjectCount == 0)
                return;

            // 從 Unity 6 的 ContextContainer 提取攝影機與資源資料
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();

            // --- 移植原本 OnCameraSetup 的 RT 分配邏輯 ---
            RenderTextureDescriptor descriptor = cameraData.cameraTargetDescriptor;
            descriptor.colorFormat = RenderTextureFormat.ARGB32; 
            descriptor.depthBufferBits = 0; 
            
            int cameraMsaaSamples = descriptor.msaaSamples;
            descriptor.useMipMap = false;
            descriptor.autoGenerateMips = false;

            RenderingUtils.ReAllocateIfNeeded(ref m_ScreenSpaceShadowMapTexture, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_PerObjectScreenSpaceShadowMap");

            if (cameraMsaaSamples > 1)
            {
                RenderTextureDescriptor resolvedDescriptor = descriptor;
                resolvedDescriptor.msaaSamples = 1;
                RenderingUtils.ReAllocateIfNeeded(ref m_ResolvedScreenSpaceShadowMapTexture, resolvedDescriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_PerObjectScreenSpaceShadowMap_Resolved");
            }
            else
            {
                m_ResolvedScreenSpaceShadowMapTexture?.Release();
                m_ResolvedScreenSpaceShadowMapTexture = null;
            }

            // --- 【核心修正 1】：在宣告期提前算好逆矩陣與取得深度圖 ---
            Matrix4x4 viewMatrix = cameraData.GetViewMatrix();
            Matrix4x4 projectionMatrix = cameraData.GetProjectionMatrix();
            Matrix4x4 gpuVP = GL.GetGPUProjectionMatrix(projectionMatrix, false) * viewMatrix;

            // --- 建立相容舊版 CommandBuffer 的 UnsafePass ---
            using (var builder = renderGraph.AddUnsafePass<PassData>("PerObjectScreenSpaceShadow", out var passData))
            {
                passData.pass = this;
                passData.cameraDepthTarget = resourceData.activeDepthTexture; // 提前儲存
                passData.gpuVPInverse = gpuVP.inverse;                        // 提前儲存
                
                builder.AllowPassCulling(false);

                // 【核心修正 2】：必須向管線宣告我們要讀寫這張深度圖
                if (passData.cameraDepthTarget.IsValid())
                {
                    builder.UseTexture(passData.cameraDepthTarget, AccessFlags.ReadWrite);
                }

                builder.SetRenderFunc((PassData data, UnsafeGraphContext context) =>
                {
                    CommandBuffer cmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);
                    data.pass.ExecuteLegacy(cmd, data); // 參數簡化，只傳遞 data
                });
            }
        }

        // 將你原本的 Execute 改名為 ExecuteLegacy，並由 RenderGraph 呼叫
        private void ExecuteLegacy(CommandBuffer cmd, PassData data)
        {
            using (new ProfilingScope(cmd, s_ProfilingSampler))
            {
                cmd.SetGlobalFloat(s_PerObjectShadowEnabledID, 0.0f);
                cmd.SetGlobalTexture(s_ScreenSpaceShadowMapID, Texture2D.whiteTexture);

                bool didDraw = false;
                
                // 直接使用宣告期取得的資料，不再向 resourceData 索取
                if (data.cameraDepthTarget.IsValid())
                {
                    cmd.SetRenderTarget(m_ScreenSpaceShadowMapTexture, data.cameraDepthTarget);
                }
                else
                {
                    cmd.SetRenderTarget(m_ScreenSpaceShadowMapTexture);
                }
                
                cmd.ClearRenderTarget(false, true, Color.white);

                int envVolumePassIndex = m_ShadowMaterial.FindPass("PerObjectShadowVolume_Env");
                int envAllVolumePassIndex = m_ShadowMaterial.FindPass("PerObjectShadowVolume_EnvAll");
                int selfVolumePassIndex = m_ShadowMaterial.FindPass("PerObjectShadowVolume_Self");

                if (envVolumePassIndex == -1 || envAllVolumePassIndex == -1 || selfVolumePassIndex == -1)
                {
                    Debug.LogError("PerObjectShadow: 找不到必要的 Shader Pass，請檢查 Hidden/PerObjectShadowCaster 是否編譯成功");
                    return;
                }

                bool useSelfShadow = m_Feature.selfShadow.enabled && m_EnableVirtualLight && m_VirtualShadowMapTexture != null;

                if (m_Feature.environmentShadow.enabled)
                {
                    didDraw = true;
                    m_Feature.environmentShadow.BakeGradient();
                    
                    Vector4 environmentAtlasSize = new Vector4(m_EnvironmentShadowMapResolution.x, m_EnvironmentShadowMapResolution.y, m_EnvironmentTileResolution, m_EnvironmentTileResolution);
                    cmd.SetGlobalVector(s_ShadowAtlasSizeID, environmentAtlasSize);
                    ApplyShadowParams(cmd, m_Feature.environmentShadow.shadowType, m_Feature.environmentShadow.useRamp, m_Feature.environmentShadow.bakedRampTex, m_Feature.environmentShadow.rampIntensity);
                    UpdatePCFKeywords(cmd, m_Feature.environmentShadow.pcfQuality);

                    int volumePassIndex = useSelfShadow ? envVolumePassIndex : envAllVolumePassIndex;
                    foreach (var shadowData in m_ShadowDataList)
                    {
                        if (shadowData.isCulled || shadowData.projector == null) continue;

                        var mainSlice = shadowData.mainSliceData;
                        cmd.SetGlobalTexture(s_ShadowMapID, m_MainShadowMapTexture.nameID);
                        cmd.SetGlobalMatrix(s_VolumeWorldToShadowID, mainSlice.shadowTransform);
                        cmd.SetGlobalMatrix(s_VolumeWorldToShadowClipID, (mainSlice.projectionMatrix * mainSlice.viewMatrix));
                        cmd.SetGlobalVector(s_VolumeUvScaleOffsetID, mainSlice.uvScaleOffset);
                        cmd.DrawMesh(PerObjectShadowUtils.shadowProjectorMesh, mainSlice.shadowToWorldMatrix, m_ShadowMaterial, 0, volumePassIndex);
                    }
                }

                if (m_Feature.selfShadow.enabled && m_EnableVirtualLight && m_VirtualShadowMapTexture != null)
                {
                    didDraw = true;
                    m_Feature.selfShadow.BakeGradient();

                    Vector4 selfAtlasSize = new Vector4(m_SelfShadowMapResolution.x, m_SelfShadowMapResolution.y, m_SelfTileResolution, m_SelfTileResolution);
                    cmd.SetGlobalVector(s_ShadowAtlasSizeID, selfAtlasSize);
                    ApplyShadowParams(cmd, m_Feature.selfShadow.shadowType, m_Feature.selfShadow.useRamp, m_Feature.selfShadow.bakedRampTex, m_Feature.selfShadow.rampIntensity);
                    UpdatePCFKeywords(cmd, m_Feature.selfShadow.pcfQuality);

                    foreach (var shadowData in m_ShadowDataList)
                    {
                        if (shadowData.isCulled || shadowData.projector == null) continue;

                        var virtualSlice = shadowData.virtualSliceData;
                        int stencilRef = shadowData.projector.stencilRef;
                        
                        if (!m_SelfStencilMaterials.TryGetValue(stencilRef, out var selfMat) || selfMat == null)
                        {
                            selfMat = new Material(m_ShadowMaterial);
                            selfMat.hideFlags = HideFlags.DontSave;
                            selfMat.SetFloat("_StencilRef", stencilRef);
                            m_SelfStencilMaterials[stencilRef] = selfMat;
                        }

                        cmd.SetGlobalTexture(s_ShadowMapID, m_VirtualShadowMapTexture.nameID);
                        cmd.SetGlobalMatrix(s_VolumeWorldToShadowID, virtualSlice.shadowTransform);
                        cmd.SetGlobalMatrix(s_VolumeWorldToShadowClipID, (virtualSlice.projectionMatrix * virtualSlice.viewMatrix));
                        cmd.SetGlobalVector(s_VolumeUvScaleOffsetID, virtualSlice.uvScaleOffset);
                        cmd.DrawMesh(PerObjectShadowUtils.shadowProjectorMesh, virtualSlice.shadowToWorldMatrix, selfMat, 0, selfVolumePassIndex);
                    }
                }

                if (m_ResolvedScreenSpaceShadowMapTexture != null)
                {
                    cmd.ResolveAntiAliasedSurface(m_ScreenSpaceShadowMapTexture, m_ResolvedScreenSpaceShadowMapTexture);
                    cmd.SetGlobalTexture(s_ScreenSpaceShadowMapID, m_ResolvedScreenSpaceShadowMapTexture.nameID);
                }
                else
                {
                    cmd.SetGlobalTexture(s_ScreenSpaceShadowMapID, m_ScreenSpaceShadowMapTexture.nameID);
                }

                cmd.SetGlobalFloat(s_PerObjectShadowEnabledID, didDraw ? 1.0f : 0.0f);
            }
        }

        private PerObjectShadowFeature.PCFQuality? m_CurrentPCFQuality = null;//让PCFQuality可空使得UpdatePCFKeywords完整运行一遍
        // PCF关键字更新方法
        private void UpdatePCFKeywords(CommandBuffer cmd, PerObjectShadowFeature.PCFQuality pcfQuality)
        {
            if (m_CurrentPCFQuality == pcfQuality)
                return;

            cmd.DisableShaderKeyword(k_PCFLowKeyword);
            cmd.DisableShaderKeyword(k_PCFMediumKeyword);
            cmd.DisableShaderKeyword(k_PCFHighKeyword);

            switch (pcfQuality)
            {
                case PerObjectShadowFeature.PCFQuality.Low_3x3:
                    cmd.EnableShaderKeyword(k_PCFLowKeyword);
                    break;
                case PerObjectShadowFeature.PCFQuality.Medium_5x5:
                    cmd.EnableShaderKeyword(k_PCFMediumKeyword);
                    break;
                case PerObjectShadowFeature.PCFQuality.High_7x7:
                    cmd.EnableShaderKeyword(k_PCFHighKeyword);
                    break;
            }
            m_CurrentPCFQuality = pcfQuality;
        }
        // 赋予阴影参数值
        private void ApplyShadowParams(CommandBuffer cmd, PerObjectShadowFeature.ShadowType shadowType, bool useRamp, Texture2D rampTex, float rampIntensity)
        {
            float softShadowEnabled = shadowType == PerObjectShadowFeature.ShadowType.Soft ? 1.0f : 0.0f;
            Vector4 shadowParams = new Vector4(1.0f, rampIntensity, softShadowEnabled, 0.0f);
            cmd.SetGlobalVector(s_ShadowParamsID, shadowParams);

            if (useRamp && rampTex != null)
            {
                cmd.SetGlobalFloat(s_UseShadowRampID, 1.0f);
                cmd.SetGlobalTexture(s_ShadowRampTexID, rampTex);
            }
            else
            {
                cmd.SetGlobalFloat(s_UseShadowRampID, 0.0f);
                // 给一个默认的白色贴图防止采样出错
                cmd.SetGlobalTexture(s_ShadowRampTexID, Texture2D.whiteTexture);
            }
        }
        
        /// <summary>
        /// 清理资源
        /// </summary>
        public void Dispose()
        {
            m_ScreenSpaceShadowMapTexture?.Release();
            m_ScreenSpaceShadowMapTexture = null;
            m_ResolvedScreenSpaceShadowMapTexture?.Release();
            m_ResolvedScreenSpaceShadowMapTexture = null;

            if (m_ShadowMaterial != null)
            {
                CoreUtils.Destroy(m_ShadowMaterial);
                m_ShadowMaterial = null;
            }

            foreach (var kv in m_SelfStencilMaterials)
            {
                if (kv.Value != null)
                    CoreUtils.Destroy(kv.Value);
            }
            m_SelfStencilMaterials.Clear();
        }
    }
}
