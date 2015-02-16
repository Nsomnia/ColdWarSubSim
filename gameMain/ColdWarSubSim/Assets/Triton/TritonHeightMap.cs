using System;
using Triton;
using UnityEngine;
using System.Runtime.InteropServices;
using System.IO;


public class TritonHeightMap
{
	private Camera mainCamera = null, heightMapCamera = null;
	private RenderTexture renderTexture;
	private Shader heightShader;
	private GameObject plane;
	private UnityEngine.Vector3 lastUpdatePosition = new UnityEngine.Vector3(0.0f,0.0f,0.0f);
	private float lastHeightMapSize = 0.0f;
	
	private const int texDim = 2048;
	private const float updateFrequency = 0.2f;
	private bool heightMapOn = false;
	private bool newRenderTexture = false;
	
	public float heightMapHeight = 10.0f;
	
	public TritonHeightMap (Camera cam)
	{
		mainCamera = cam;
		CreateObjects ();
	}
	
	public void Destroy()
	{
		if (renderTexture != null) {
			UnityEngine.Object.DestroyImmediate (renderTexture);
			renderTexture = null;
		}
		
		if (heightMapCamera != null) {
			UnityEngine.Object.DestroyImmediate (heightMapCamera.gameObject);
			heightMapCamera = null;
		}
		
		if (plane != null) {
			UnityEngine.Object.DestroyImmediate(plane);
			plane = null;
		}		
	}
	
	public void Render(TritonUnity triton)
	{
		if (triton.coastalEffects && triton.GetEnvironment() != null && heightMapCamera != null && mainCamera != null &&
			plane != null && triton.yIsUp && !triton.geocentricCoordinates && renderTexture != null)  {
			
			if (!renderTexture.IsCreated ()) {
				CreateRenderTexture();	
				triton.Invalidate();
			}
			
			UnityEngine.Vector3 camPos = mainCamera.transform.position;
			
			if ( ((camPos - lastUpdatePosition).magnitude > triton.heightMapArea * updateFrequency) ||
				lastHeightMapSize != triton.heightMapArea || newRenderTexture)
			{
				lastUpdatePosition = camPos;
				lastHeightMapSize = triton.heightMapArea;
				newRenderTexture = false;
			
				plane.transform.position = new UnityEngine.Vector3(camPos.x, -triton.heightMapArea, camPos.z);
				plane.transform.localScale = new UnityEngine.Vector3(triton.heightMapArea, 1.0f, triton.heightMapArea);
				heightMapCamera.orthographicSize = triton.heightMapArea;
				heightMapCamera.transform.position = new UnityEngine.Vector3(camPos.x, triton.GetSeaLevel () + heightMapHeight, camPos.z);
				
				plane.SetActive (true);
				
				heightMapCamera.targetTexture = renderTexture;
				heightMapCamera.Render ();
				
				plane.SetActive (false);
				
				Matrix4x4 scale;
				
				Matrix4x4 trans = Matrix4x4.TRS (new UnityEngine.Vector3(1.0f, 1.0f, 0.0f), Quaternion.identity, new UnityEngine.Vector3(1.0f, 1.0f, 1.0f));
				if (SystemInfo.graphicsDeviceVersion.Contains("OpenGL")) {
					scale = Matrix4x4.Scale (new UnityEngine.Vector3(0.5f, -0.5f, 1.0f));
				}
				else {
					scale = Matrix4x4.Scale (new UnityEngine.Vector3(0.5f, 0.5f, 1.0f));
				}
				Matrix4x4 view = heightMapCamera.worldToCameraMatrix;
				
				Matrix4x4 xformMatrix = (scale * trans * heightMapCamera.projectionMatrix * view);	
				
				double[] m = new double[16];
				m[0] = xformMatrix.m00; m[4] = xformMatrix.m01; m[8] = xformMatrix.m02; m[12] = xformMatrix.m03;
				m[1] = xformMatrix.m10; m[5] = xformMatrix.m11; m[9] = xformMatrix.m12; m[13] = xformMatrix.m13;
				m[2] = xformMatrix.m20; m[6] = xformMatrix.m21; m[10] = xformMatrix.m22; m[14] = xformMatrix.m23;
				m[3] = xformMatrix.m30; m[7] = xformMatrix.m31; m[11] = xformMatrix.m32; m[15] = xformMatrix.m33;
				
				System.IntPtr ptr = renderTexture.GetNativeTexturePtr();
				
				UnityBindings.SetHeightMapFromPtr(ptr, m);
				
				heightMapOn = true;
			}
		} else {
			if (triton.GetEnvironment () != null && heightMapOn) {
				triton.GetEnvironment ().SetHeightMap((IntPtr)0, new Triton.Matrix4());	
				heightMapOn = false;
			}
		}
	}
	
	public void CreateRenderTexture()
	{
		if (renderTexture == null || !renderTexture.IsCreated())
		{
			renderTexture = new RenderTexture(texDim, texDim, 24, RenderTextureFormat.RFloat);
			renderTexture.isPowerOfTwo = true;
	        renderTexture.hideFlags = HideFlags.DontSave;
			renderTexture.wrapMode = TextureWrapMode.Clamp;		
			renderTexture.Create ();
			newRenderTexture = true;
		}
	}
	
	private void CreateObjects()
	{
		GameObject go = new GameObject( "Height map camera for Triton", typeof(Camera));
		go.hideFlags = HideFlags.DontSave;
		go.SetActive (false);
		
		heightMapCamera = go.camera;
		heightMapCamera.orthographic = true;
		heightMapCamera.orthographicSize = 500.0f;
		heightMapCamera.aspect = 1.0f;
		heightMapCamera.transform.position = new UnityEngine.Vector3(0.0f, 500.0f, 0.0f);
		heightMapCamera.transform.Rotate (new UnityEngine.Vector3(90.0f, 0.0f, 0.0f));
		
		CreateRenderTexture ();

		heightShader = Shader.Find ("Custom/HeightShader");
		heightMapCamera.SetReplacementShader(heightShader, "");
		heightMapCamera.clearFlags = CameraClearFlags.Depth;
		
		plane = GameObject.CreatePrimitive(PrimitiveType.Plane);
		plane.SetActive(false);		
	}
}

