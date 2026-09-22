using UnityEditor;
using UnityEngine;

public class AbyssStandardShaderGUI : LWGUI.LWGUI 
{
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        base.OnGUI(materialEditor, properties); // 繪製 LWGUI 面板

        Material mat = materialEditor.target as Material;
        
        // 監聽 Transparency Mode 的數值
        int mode = (int)mat.GetFloat("_Transparency_Mode");
        
        if (mode == 3) // Transparent
        {
            mat.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.SrcAlpha);
            mat.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            mat.SetInt("_ZWrite", 1);
            mat.renderQueue = 3000;
        }
        else // Opaque / Cutout / Dither
        {
            mat.SetInt("_SrcBlend", (int)UnityEngine.Rendering.BlendMode.One);
            mat.SetInt("_DstBlend", (int)UnityEngine.Rendering.BlendMode.Zero);
            mat.SetInt("_ZWrite", 1);
            mat.renderQueue = (mode == 0) ? 2000 : 2450; // Opaque = 2000, Cutout = 2450
        }
    }
}