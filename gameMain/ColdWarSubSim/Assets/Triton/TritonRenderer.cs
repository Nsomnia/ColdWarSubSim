using System;
using Triton;
using UnityEngine;

public class TritonRenderer : MonoBehaviour
{	
	public void Awake()
	{
		triton = (TritonUnity)(GameObject.FindObjectOfType(typeof(TritonUnity)));	
	}
	
	public void OnDisable()
	{
		if (reflection != null)
		{
			reflection.Destroy();
		}
		
		if (heightMap != null)
		{
			heightMap.Destroy ();
		}
	}
	
	public void OnPostRender()
	{
		if (triton != null) {
			if (reflection != null || heightMap != null) {
				triton.WaitForPreviousCamera();
				if (reflection != null) {
					reflection.Render (triton);	
				}
				if (heightMap != null) {
					heightMap.Render (triton);
				}
				triton.Draw (mcamera, false);
			} else {
				triton.Draw (mcamera, true);	
			}
		}
	}
	
	public void SetCamera(Camera pCamera)
	{
		mcamera = pCamera;
		
		if (reflection != null)
		{
			reflection.Destroy ();
		}
		reflection = new TritonReflection(mcamera, 512);
		
		if (heightMap != null)
		{
			heightMap.Destroy ();
		}
		heightMap = new TritonHeightMap(mcamera);
	}
	
	// Recreate RTT textures when Dx9 device loss happens
	// (For lack of a better way.)
	void OnApplicationFocus()
	{
		if (reflection != null)
		{
			reflection.CreateRenderTexture();
		}
		
		if (heightMap != null)
		{
			heightMap.CreateRenderTexture();
		}
	}
	
	private TritonUnity triton;
	private Camera mcamera;
	private TritonReflection reflection = null;
	private TritonHeightMap heightMap = null;
}


