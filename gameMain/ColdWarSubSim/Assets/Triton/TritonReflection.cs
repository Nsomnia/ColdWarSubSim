using System;
using Triton;
using UnityEngine;
using System.Runtime.InteropServices;
using System.IO;

public class TritonReflection
{
	private Camera mainCamera = null, reflectionCamera = null;
	private RenderTexture reflectionTexture = null;
	private Matrix4x4 reflectionMatrix, xformMatrix;
	private TritonUnity triton;
	private float clipPlaneOffset = 0.07f;
	private int textureDimension = 512;
	System.IntPtr texturePtr = (System.IntPtr)0;
	
	public TritonReflection (Camera mainCam, int texDim)
	{
		mainCamera = mainCam;
		textureDimension = texDim;
		triton = (TritonUnity)(GameObject.FindObjectOfType(typeof(TritonUnity)));
		CreateObjects ();
	}
	
	public void CreateRenderTexture()
	{
		if (reflectionTexture == null || !reflectionTexture.IsCreated ())
		{
			// Reflection render texture
	        reflectionTexture = new RenderTexture( textureDimension, textureDimension, 16 );
	        reflectionTexture.name = "Triton planar reflection";
	        reflectionTexture.isPowerOfTwo = true;
	        reflectionTexture.hideFlags = HideFlags.DontSave;
			reflectionTexture.wrapMode = TextureWrapMode.Clamp;
		}
	}
	
	public void Destroy()
	{
		if (reflectionTexture != null) {
			UnityEngine.Object.DestroyImmediate (reflectionTexture);
			reflectionTexture = null;
		}
		
		if (reflectionCamera != null) {
			UnityEngine.Object.DestroyImmediate (reflectionCamera.gameObject);
			reflectionCamera = null;
		}
	}
	
	public void Render(TritonUnity pTriton)
	{
		if (pTriton.enablePlanarReflections) {
			triton = pTriton;
			SyncCamera ();	
			ComputeTransform ();
			RenderReflections ();
			SyncWithTriton();
		}
		else {
			Triton.Environment env = pTriton.GetEnvironment();
			if (env != null) {
				env.SetPlanarReflectionMap((IntPtr)0, new Triton.Matrix3());	
			}
		}
	}
	
	private void CreateObjects()
	{
		CreateRenderTexture ();
 
        // Camera for reflection
        GameObject go = new GameObject( "Planar reflection camera for Triton", typeof(Camera), typeof(Skybox) );
        reflectionCamera = go.camera;
        reflectionCamera.enabled = false;
        reflectionCamera.transform.position = mainCamera.transform.position;
        reflectionCamera.transform.rotation = mainCamera.transform.rotation;
		reflectionCamera.renderingPath = UnityEngine.RenderingPath.Forward;
        //reflectionCamera.gameObject.AddComponent("FlareLayer");
        go.hideFlags = HideFlags.DontSave;
		go.SetActive (false);
	}
	
	// Calculates reflection matrix around the given plane
    private void CalculateReflectionMatrix (UnityEngine.Vector4 plane)
    {
        reflectionMatrix.m00 = (1F - 2F*plane[0]*plane[0]);
        reflectionMatrix.m01 = (   - 2F*plane[0]*plane[1]);
        reflectionMatrix.m02 = (   - 2F*plane[0]*plane[2]);
        reflectionMatrix.m03 = (   - 2F*plane[3]*plane[0]);
 
        reflectionMatrix.m10 = (   - 2F*plane[1]*plane[0]);
        reflectionMatrix.m11 = (1F - 2F*plane[1]*plane[1]);
        reflectionMatrix.m12 = (   - 2F*plane[1]*plane[2]);
        reflectionMatrix.m13 = (   - 2F*plane[3]*plane[1]);
 
        reflectionMatrix.m20 = (   - 2F*plane[2]*plane[0]);
        reflectionMatrix.m21 = (   - 2F*plane[2]*plane[1]);
        reflectionMatrix.m22 = (1F - 2F*plane[2]*plane[2]);
        reflectionMatrix.m23 = (   - 2F*plane[3]*plane[2]);
 
        reflectionMatrix.m30 = 0F;
        reflectionMatrix.m31 = 0F;
        reflectionMatrix.m32 = 0F;
        reflectionMatrix.m33 = 1F;
    }
	
	private void SyncCamera()
	{
		if (reflectionCamera && mainCamera)
		{
			UpdateCameraModes (mainCamera, reflectionCamera);
			
			UnityEngine.Vector4 reflectionPlaneWorld = new UnityEngine.Vector4(0, 1, 0, clipPlaneOffset - triton.GetSeaLevel()); 
			reflectionMatrix = Matrix4x4.zero;
        	CalculateReflectionMatrix (reflectionPlaneWorld);
		    reflectionCamera.worldToCameraMatrix = mainCamera.worldToCameraMatrix * reflectionMatrix;
			
			Matrix4x4 proj = mainCamera.projectionMatrix;
			UnityEngine.Vector4 reflectionPlaneCamera = CameraSpacePlane (reflectionCamera, new UnityEngine.Vector3(0, triton.GetSeaLevel(), 0),
				new UnityEngine.Vector3(0, 1, 0), 1.0f);
			CalculateObliqueMatrix(ref proj, reflectionPlaneCamera);
			reflectionCamera.projectionMatrix = proj;
		}
	}
	
	private void ComputeTransform()
	{
		Matrix4x4 trans = Matrix4x4.TRS (new UnityEngine.Vector3(1.0f, 1.0f, 0.0f), Quaternion.identity, new UnityEngine.Vector3(1.0f, 1.0f, 1.0f));
		Matrix4x4 scale = Matrix4x4.Scale (new UnityEngine.Vector3(0.5f, 0.5f, 1.0f));
		
		Matrix4x4 view = mainCamera.worldToCameraMatrix;
		//view.SetRow (3, new UnityEngine.Vector4(0, 0, 0, 1));
		
		xformMatrix = scale * trans * mainCamera.projectionMatrix * view;
	}
	
	// Extended sign: returns -1, 0 or 1 based on sign of a
    private static float sgn(float a)
    {
        if (a > 0.0f) return 1.0f;
        if (a < 0.0f) return -1.0f;
        return 0.0f;
    }
	
	// Given position/normal of the plane, calculates plane in camera space.
    private UnityEngine.Vector4 CameraSpacePlane (Camera cam, UnityEngine.Vector3 pos, UnityEngine.Vector3 normal, float sideSign)
    {
        UnityEngine.Vector3 offsetPos = pos + normal * clipPlaneOffset;
        Matrix4x4 m = cam.worldToCameraMatrix;
        UnityEngine.Vector3 cpos = m.MultiplyPoint( offsetPos );
        UnityEngine.Vector3 cnormal = m.MultiplyVector( normal ).normalized * sideSign;
        return new UnityEngine.Vector4( cnormal.x, cnormal.y, cnormal.z, -UnityEngine.Vector3.Dot(cpos,cnormal) );
    }
	
	private static void CalculateObliqueMatrix (ref Matrix4x4 projection, UnityEngine.Vector4 clipPlane)
    {
        UnityEngine.Vector4 q = projection.inverse * new UnityEngine.Vector4(
            sgn(clipPlane.x),
            sgn(clipPlane.y),
            1.0f,
            1.0f
        );
        UnityEngine.Vector4 c = clipPlane * (2.0F / (UnityEngine.Vector4.Dot (clipPlane, q)));
        // third row = clip plane - fourth row
        projection[2] = c.x - projection[3];
        projection[6] = c.y - projection[7];
        projection[10] = c.z - projection[11];
        projection[14] = c.w - projection[15];
    }
	
	private void SyncWithTriton()
	{
		if (triton)
		{
			double[] m = new double[9];
			m[0] = xformMatrix.m00; m[3] = xformMatrix.m01; m[6] = xformMatrix.m02; 
			m[1] = xformMatrix.m10; m[4] = xformMatrix.m11; m[7] = xformMatrix.m12;
			m[2] = xformMatrix.m20; m[5] = xformMatrix.m21; m[8] = xformMatrix.m22;
			
			//if (texturePtr == (System.IntPtr)0) {
				texturePtr = reflectionTexture.GetNativeTexturePtr();
			//}
			UnityBindings.SetPlanarReflectionMapFromPtr(texturePtr, m);
		}
	}
	
	private void RenderReflections()
	{
        reflectionCamera.targetTexture = reflectionTexture;
		UnityEngine.Vector3 oldpos = mainCamera.transform.position;
        UnityEngine.Vector3 newpos = reflectionMatrix.MultiplyPoint( oldpos );
        GL.SetRevertBackfacing (true);
		reflectionCamera.transform.position = newpos;
        UnityEngine.Vector3 euler = mainCamera.transform.eulerAngles;
        reflectionCamera.transform.eulerAngles = new UnityEngine.Vector3(0, euler.y, euler.z);
        reflectionCamera.Render();
		reflectionCamera.transform.position = oldpos;
        GL.SetRevertBackfacing (false);	
	}
	
	private void UpdateCameraModes( Camera src, Camera dest )
    {
        if( dest == null )
            return;
        // set camera to clear the same way as current camera
        //dest.clearFlags = src.clearFlags;
        dest.backgroundColor = src.backgroundColor;        
        if( src.clearFlags == CameraClearFlags.Skybox )
        {
            Skybox sky = src.GetComponent(typeof(Skybox)) as Skybox;
            Skybox mysky = dest.GetComponent(typeof(Skybox)) as Skybox;
            if( !sky || !sky.material )
            {
                mysky.enabled = false;
            }
            else
            {
                mysky.enabled = true;
                mysky.material = sky.material;
            }
        }
        // update other values to match current camera.
        // even if we are supplying custom camera&projection matrices,
        // some of values are used elsewhere (e.g. skybox uses far plane)
        dest.farClipPlane = src.farClipPlane;
        dest.nearClipPlane = src.nearClipPlane;
        dest.orthographic = src.orthographic;
        dest.fieldOfView = src.fieldOfView;
        dest.aspect = src.aspect;
        dest.orthographicSize = src.orthographicSize;
    }
}


