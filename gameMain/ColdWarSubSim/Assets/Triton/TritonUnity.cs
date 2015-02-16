// Copyright (c) 2012 Sundog Software LLC. All rights reserved worldwide.
//#define DEBUG

using UnityEngine;
using System.Collections;
using System.Runtime.InteropServices;
using System.IO;
using System.Threading;
using Triton;

public class TritonUnity : MonoBehaviour {
	
	public double windSpeed             = 10.0;
	public double windDirection         = 90.0;
	public double aboveWaterVisibility  = 1000000000.0;
	public double belowWaterVisibility  = 20.0;
	public double worldUnits            = 1.0;
	
	public float depth                  = 1000.0f;
	public float choppiness             = 1.6f;
	public float lightingScale          = 0.8f;
	public float heightMapArea          = 500.0f;
	public float breakingWaveAmplitude  = 0.0f;
	public float depthOffset            = 0.001f;
	
	public bool spray                   = false;
	public bool enablePlanarReflections = true;
	public bool useRenderSettingsFog    = false;
	public bool underwaterFogEffects    = true;
	public bool geocentricCoordinates   = false;
	public bool yIsUp                   = true;
	public bool usingCustomMatrices     = false;
	
	public string resourcePath          = "TritonResources";
	public string userName              = "Unlicensed user";
	public string licenseKey            = "Unlicensed";
	
	public UnityEngine.Camera  gameCamera            = null;
	public UnityEngine.Light   directionalLight      = null;
	public UnityEngine.Cubemap environmentMap        = null;
	public UnityEngine.Color   aboveWaterFogColor    = new UnityEngine.Color(1.0f, 1.0f, 1.0f, 1.0f);
	public UnityEngine.Color   belowWaterFogColor    = new UnityEngine.Color(0.0f, 0.2f, 0.3f, 1.0f);
	public UnityEngine.Vector3 breakingWaveDirection = new UnityEngine.Vector3(1.0f, 0.0f, 0.0f);
	
	public bool headless			    = false;
	
#if UNITY_STANDALONE_OSX
	// Currently not supported on Mac.
	// This hides the option from the editor and also
	// prevents the effects from ever being turned on
	// while affecting a minimal amount of code.
	public bool coastalEffects
	{
		get{ return false; }
	}
#else
	public bool coastalEffects = false;
#endif
	
	
	Triton.Environment environment = null;
	Triton.Ocean ocean = null;
	Triton.ResourceLoader resourceLoader = null;
	bool tritonInitialized = false;
	double lastWindSpeed = 0;
	double lastWindDirection = 0;
	Cubemap lastEnvironmentMap = null;
	bool savedHeadless = false;
	UnityEngine.Vector3 lastCameraTransform;
	bool drawingCubemap = false;
	bool multipleCameras = false;
	bool invalid = false;
	
	// Use for changing Triton's camera at runtime.
	public void SwitchCamera(Camera newCamera) {

        if (gameCamera != null) {

            Component renderer = gameCamera.gameObject.GetComponent<TritonRenderer>();

            if (renderer != null) {
                Destroy(renderer);
            }
        }

        gameCamera = newCamera;
        TritonRenderer newRenderer = (TritonRenderer)newCamera.gameObject.AddComponent(typeof(TritonRenderer));
		newRenderer.SetCamera (newCamera);
    }
	
	// Use for adding additional cameras to Triton for use simultaneously
	public void AddCamera(Camera newCamera) {
        if (newCamera.gameObject.GetComponent<TritonRenderer>() != null)
			return;
		
		TritonRenderer newRenderer = (TritonRenderer)newCamera.gameObject.AddComponent(typeof(TritonRenderer));
		
		newRenderer.SetCamera (newCamera);
		multipleCameras = true;
    }
	
	// Use to detach Triton from a camera added with AddCamera.
	public void RemoveCamera(Camera cam) {
        if (cam != null) {

            Component renderer = cam.gameObject.GetComponent<TritonRenderer>();

            if (renderer != null) {
                Destroy(renderer);
            }
        }		
	}
	
	// Return the point on the ocean surface closest to the point specified.
	public UnityEngine.Vector3 ClosestPointOnBounds(UnityEngine.Vector3 position) {

		if (ocean == null) {
			return new UnityEngine.Vector3();
		}
		
		Triton.Vector3 down = new Triton.Vector3(0, -1, 0);
		Triton.Vector3 normal = new Triton.Vector3();
		Triton.Vector3 tPos = new Triton.Vector3(position.x, position.y, position.z);
		SWIGTYPE_p_float pHeight = TritonOcean.new_floatp();
		bool intersected = ocean.GetHeight(tPos, down, pHeight, normal);
		if (!intersected)
		{
			down = new Triton.Vector3(0, 1, 0);
			ocean.GetHeight (tPos, down, pHeight, normal);
		}
		float seaLevel = gameObject.transform.position.y;
		float y = TritonOcean.floatp_value(pHeight) + seaLevel;
		TritonOcean.delete_floatp(pHeight);
		
		UnityEngine.Vector3 pt = new UnityEngine.Vector3(position.x, y, position.z);
		return pt;
	}
	
	// Perform an intersection test with the ocean surface.
	public bool Raycast (Ray ray, out RaycastHit hitInfo, float distance)
	{
		hitInfo = new RaycastHit();
		
		if (ocean == null) {
			return false;
		}
		
		bool hit = false;
		
		Triton.Vector3 rayOrigin = new Triton.Vector3(ray.origin.x, ray.origin.y, ray.origin.z);
		Triton.Vector3 rayDirection = new Triton.Vector3(ray.direction.x, ray.direction.y, ray.direction.z);
		SWIGTYPE_p_float pHeight = TritonOcean.new_floatp();
		Triton.Vector3 normal = new Triton.Vector3();
		if (ocean.GetHeight (rayOrigin, rayDirection, pHeight, normal)) {
			
			float seaLevel = gameObject.transform.position.y;
			float height = TritonOcean.floatp_value (pHeight) + seaLevel;

			if (height < distance) {
				hitInfo.distance = ray.origin.y - height;
				hitInfo.point = new UnityEngine.Vector3(ray.origin.x, height, ray.origin.z);
				hitInfo.normal = new UnityEngine.Vector3((float)normal.x, (float)normal.y, (float)normal.z);
				hit = true;
			}
		}
		
		TritonOcean.delete_floatp (pHeight);
		
		return hit;
	}
	
	public float GetHeight(float x, float z)
	{
		float height = 0.0f;
		if (ocean == null) {
			return 0.0f;
		}
		
		Triton.Vector3 rayOrigin = new Triton.Vector3(x, 100, z);
		Triton.Vector3 rayDirection = new Triton.Vector3(0, -1, 0);
		
		SWIGTYPE_p_float pHeight = TritonOcean.new_floatp();
		Triton.Vector3 normal = new Triton.Vector3();
		if (ocean.GetHeight (rayOrigin, rayDirection, pHeight, normal)) {
			float seaLevel = gameObject.transform.position.y;
			height = TritonOcean.floatp_value(pHeight) + seaLevel;
		}
		
		TritonOcean.delete_floatp(pHeight);
		
		
		return height;
	}
	
	void Start() {
		TritonRenderer renderer = null;
		if (gameCamera != null) {
			renderer = (TritonRenderer)gameCamera.gameObject.AddComponent(typeof(TritonRenderer));
			renderer.SetCamera(gameCamera);
		} else {
			renderer = (TritonRenderer)Camera.main.gameObject.AddComponent(typeof(TritonRenderer));
			renderer.SetCamera(Camera.main);
		}
#if DEBUG
		Object[] cameras = GameObject.FindObjectsOfType (typeof(Camera));
		for (int i = 0; i < cameras.Length; i++) {
			Camera cam = (Camera)cameras[i];
			if (cam != gameCamera) {
				AddCamera (cam);
			}
		}
#endif
	}
	
	public Environment GetEnvironment() { return environment; }
	public Ocean GetOcean() {return ocean; }
	
	void OnDestroy() {
		// Wait for previous camera to render
		UnityRenderEvent(2);
		UnityBindings.DestroyTriton ();
		if (environment != null) environment.Dispose();
		if (ocean != null) ocean.Dispose();
		if (resourceLoader != null) resourceLoader.Dispose();
		environment = null;
		ocean = null;
		resourceLoader = null;
		tritonInitialized = false;
	}
	
	// GenerateCubeMap should be called from LateUpdate()
	public bool GenerateCubeMap(int mask) {
		if (gameCamera != null) {
			return GenerateCubeMap (gameCamera, mask);
		}
		return false;
	}
	
	// GenerateCubeMap should be called from LateUpdate()
	public bool GenerateCubeMap(Camera camera, int mask) {
		bool ok = false;
		if (camera != null) {
			if (environmentMap == null) {
				environmentMap = new Cubemap(512, TextureFormat.ARGB32, false);
			}	
			
			drawingCubemap = true;
			int oldMask = camera.cullingMask;
			camera.cullingMask = mask;
			ok = camera.RenderToCubemap(environmentMap);
			SetCubeMap (true);
			camera.cullingMask = oldMask;
			drawingCubemap = false;
		}
		
		return ok;
	}
	
	public float GetSeaLevel() {
		return gameObject.transform.position.y;	
	}
	
	void Update() {
		
		if (drawingCubemap) return;
		
		SetWind ();
		
		UpdateLighting();	
		
		HandleUnderwater ();
		
		if (ocean != null && environment != null) {
			
			if( depthOffset != ocean.GetDepthOffset( ) )
			{
				ocean.SetDepthOffset( depthOffset );
			}
			
			if (headless != savedHeadless )
			{
				UnityBindings.SetHeadless (headless);
				savedHeadless = headless;
			}
			
			float seaLevel = gameObject.transform.position.y;
			environment.SetSeaLevel(seaLevel);
			
			//ocean.EnableWireframe (true);
			
			ocean.EnableSpray(spray);
			
			Triton.Vector3 fogColor = null;
			if (useRenderSettingsFog) {
				fogColor = new Triton.Vector3(RenderSettings.fogColor.r, RenderSettings.fogColor.g, RenderSettings.fogColor.b);
				double visibility = 3.912 / RenderSettings.fogDensity;
				environment.SetAboveWaterVisibility(visibility, fogColor);
			} else {
				fogColor = new Triton.Vector3(aboveWaterFogColor.r, aboveWaterFogColor.g, aboveWaterFogColor.b);
				environment.SetAboveWaterVisibility(aboveWaterVisibility, fogColor);
			}
			fogColor = new Triton.Vector3(belowWaterFogColor.r, belowWaterFogColor.g, belowWaterFogColor.b);
			environment.SetBelowWaterVisibility(belowWaterVisibility, fogColor);
			
			ocean.SetDepth (depth, new Triton.Vector3(0.0, 1.0, 0.0));
			ocean.SetChoppiness(choppiness);
			
			Triton.BreakingWavesParameters param = new Triton.BreakingWavesParameters();
			param.SetAmplitude (breakingWaveAmplitude);
			param.SetWaveDirection (new Triton.Vector3(breakingWaveDirection.x, breakingWaveDirection.y, breakingWaveDirection.z));
			environment.SetBreakingWavesParameters(param);
			
			if (multipleCameras) {	
				ocean.UpdateSimulation(Time.timeSinceLevelLoad);
			}
			
#if DEBUG
			Object[] cameras = GameObject.FindObjectsOfType (typeof(Camera));
			Camera cam = (Camera)cameras[0];
			UnityEngine.Vector3 oldPos = cam.transform.position;
			oldPos.x += 0.1f;
			cam.transform.position = oldPos;
			
			cam = (Camera)cameras[1];
			oldPos = cam.transform.position;
			oldPos.y -= 0.1f;
			cam.transform.position = oldPos;
#endif
		}
		
	}
	
	UnityEngine.CameraClearFlags savedClearFlags;
	Color savedFogColor;
	float savedFogDensity;
	Color savedBackgroundColor;
	bool savedFogOn;
	bool needsRestore = false;
	
	private void HandleUnderwater()
	{
		if (underwaterFogEffects) {
			if (gameCamera != null && gameObject != null) {
				if (gameCamera.transform.position.y < gameObject.transform.position.y) {
					if (!needsRestore) {
						// underwater
						savedFogColor = RenderSettings.fogColor;
						savedFogDensity = RenderSettings.fogDensity;
						savedClearFlags = gameCamera.clearFlags;
						savedBackgroundColor = gameCamera.backgroundColor;
						savedFogOn = RenderSettings.fog;
						gameCamera.clearFlags = CameraClearFlags.SolidColor;	
						gameCamera.backgroundColor = new Color(belowWaterFogColor.r, belowWaterFogColor.g, belowWaterFogColor.b);
						RenderSettings.fogColor = belowWaterFogColor;
						RenderSettings.fogDensity = 3.912f / (float)belowWaterVisibility;
						RenderSettings.fog = true;
						needsRestore = true;
					}
				} else {
					if (needsRestore) {
						gameCamera.clearFlags = savedClearFlags;
						gameCamera.backgroundColor = savedBackgroundColor;
						RenderSettings.fogColor = savedFogColor;
						RenderSettings.fogDensity = savedFogDensity;
						RenderSettings.fog = savedFogOn;
						needsRestore = false;
					}
				}
			}
		}
	}
	
	private void SetCubeMap(bool force)
	{
		if (environmentMap != null && (force || environmentMap != lastEnvironmentMap)) {
		
			lastEnvironmentMap = environmentMap;
			if (environmentMap.GetNativeTexturePtr() != System.IntPtr.Zero) {
				UnityBindings.SetEnvironmentMapFromPtr(environmentMap.GetNativeTexturePtr());
			}
		}	
	}
	
	private void InitializeTriton()
	{
		if (!tritonInitialized) {
			tritonInitialized = true;

			string tritonPath = null;
			if (resourcePath == null || resourcePath == "") {
				// Null resource path. See if the Triton SDK's installed, we can grab it there...
				tritonPath = System.Environment.GetEnvironmentVariable("TRITON_PATH");
				tritonPath = Path.Combine (tritonPath, "Resources");
			} else {
				// Otherwise, look relative to the current directory.
				tritonPath = Directory.GetCurrentDirectory();
				tritonPath = Path.Combine (tritonPath, resourcePath);			
			}
#if UNITY_STANDALONE_OSX
			if (!System.IO.File.Exists("./libiomp5.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libiomp5.dylib", "./libiomp5.dylib");
			}
			
			if (!System.IO.File.Exists("./libippcore-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippcore-8.0.dylib", "./libippcore-8.0.dylib");
			}
			
			if (!System.IO.File.Exists("./libippi-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippi-8.0.dylib", "./libippi-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippie9-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippie9-8.0.dylib", "./libippie9-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippig9-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippig9-8.0.dylib", "./libippig9-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippim7-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippim7-8.0.dylib", "./libippim7-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippimx-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippimx-8.0.dylib", "./libippimx-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippip8-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippip8-8.0.dylib", "./libippip8-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippipx-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippipx-8.0.dylib", "./libippipx-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippiu8-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippiu8-8.0.dylib", "./libippiu8-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippi-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippi-8.0.dylib", "./libippi-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippi-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippi-8.0.dylib", "./libippi-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippiv8-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippiv8-8.0.dylib", "./libippiv8-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippiw7-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippiw7-8.0.dylib", "./libippiw7-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippiy8-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippiy8-8.0.dylib", "./libippiy8-8.0.dylib");
			}
			
			if (!System.IO.File.Exists("./libipps-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libipps-8.0.dylib", "./libipps-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippse9-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippse9-8.0.dylib", "./libippse9-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippsg9-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippsg9-8.0.dylib", "./libippsg9-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippsm7-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippsm7-8.0.dylib", "./libippsm7-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippsmx-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippsmx-8.0.dylib", "./libippsmx-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippsp8-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippsp8-8.0.dylib", "./libippsp8-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippspx-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippspx-8.0.dylib", "./libippspx-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippsu8-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippsu8-8.0.dylib", "./libippsu8-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippsv8-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippsv8-8.0.dylib", "./libippsv8-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippsw7-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippsw7-8.0.dylib", "./libippsw7-8.0.dylib");
			}
			if (!System.IO.File.Exists("./libippsy8-8.0.dylib")) {
				System.IO.File.Copy("./Assets/Triton/TritonResources/linux/libippsy8-8.0.dylib", "./libippsy8-8.0.dylib");
			}
#endif
			
			
			string configPath = Path.Combine (tritonPath, "Triton.config");
			
			if (!System.IO.File.Exists(configPath)) {
				// Maybe they put it inside the assets folder.
				tritonPath = Directory.GetCurrentDirectory();
				tritonPath = Path.Combine (tritonPath, "Assets");
				tritonPath = Path.Combine (tritonPath, resourcePath);	
				configPath = Path.Combine (tritonPath, "Triton.config");
				
				if (!System.IO.File.Exists (configPath)) {
					// Maybe they put it under assets/triton
					tritonPath = Directory.GetCurrentDirectory();
					tritonPath = Path.Combine (tritonPath, "Assets");
					tritonPath = Path.Combine (tritonPath, "Triton");
					tritonPath = Path.Combine (tritonPath, resourcePath);	
					configPath = Path.Combine (tritonPath, "Triton.config");
					
					if (!System.IO.File.Exists (configPath)) {
						// Maybe it's an absolute path.
						tritonPath = resourcePath;
						configPath = Path.Combine (tritonPath, "Triton.config");
						if (!System.IO.File.Exists (configPath)) {
							tritonPath = Directory.GetCurrentDirectory();
							tritonPath = Path.Combine (tritonPath, "Assets");
							tritonPath = Path.Combine (tritonPath, "Triton");
							tritonPath = Path.Combine (tritonPath, resourcePath);
#if UNITY_STANDALONE_OSX
							if (System.IO.File.Exists(tritonPath + "Triton.config.mac")) {
								System.IO.File.Copy(tritonPath + "Triton.config.mac", tritonPath + "Triton.config");
							}
#elif UNITY_STANDALONE_WIN
							if (System.IO.File.Exists(tritonPath + "Triton.config.win")) {
								System.IO.File.Copy(tritonPath + "Triton.config.win", tritonPath + "Triton.config");
							}
#endif
							configPath = Path.Combine (tritonPath, "Triton.config");
							if(!System.IO.File.Exists(configPath)) {
								Debug.LogError ("Triton Resources folder not found at relative path " +
									resourcePath + "! Be sure to copy it " +
									"from the Triton for Unity distribution into your project folder.");
								environment = null;
								ocean = null;
								return;
							}
						}
					}
				}
			}
			
			UnityBindings.SetRandomSeed (1234);
			UnityRenderEvent(2);
			int errCode = UnityBindings.InitializeTriton (tritonPath, userName, licenseKey, true, worldUnits, geocentricCoordinates, yIsUp, true, headless);
			
			savedHeadless = headless;
			
			if (errCode == 0) {
				
				System.IntPtr environmentPtr = UnityBindings.UnityGetEnvironment ();
				environment = new Environment(environmentPtr, true);
				
				// Uncomment this to reduce CPU usage on cores other than our own
				environment.EnableOpenMP(false);
				
				System.IntPtr oceanPtr = UnityBindings.UnityGetOcean();
				ocean = new Ocean(oceanPtr, true);
				
				System.IntPtr resourceLoaderPtr = UnityBindings.UnityGetResourceLoader();
				resourceLoader = new ResourceLoader(resourceLoaderPtr, true);
				
				Transform plane = transform.FindChild ("TritonWaterPlaneEditor");
				if (plane != null) {
					plane.gameObject.SetActive (false);
				}
				
			} else {
				environment = null;
				ocean = null;
			}
		}
	}
	
	public void Invalidate()
	{
		invalid = true;	
	}
	
	private void SetWind()
	{
		if (environment != null) {
			if (windSpeed != lastWindSpeed || windDirection != lastWindDirection || invalid) {
				
				WindFetch fetch = new WindFetch();
				
				if (invalid) windDirection += 0.01;
				
				fetch.SetWind (windSpeed, windDirection * (Mathf.PI / 180.0f));
				environment.ClearWindFetches();
				environment.AddWindFetch(fetch);
				
				if (invalid) windDirection -= 0.01;
				
				lastWindSpeed = windSpeed;
				lastWindDirection = windDirection;
				
				invalid = false;
			}
		}
	}
	
	public void UpdateMatrices()
	{
		if (gameCamera == null) {
			gameCamera = (Camera)GameObject.FindObjectOfType(typeof(Camera));	
		}
		
		UpdateMatrices(gameCamera);
	}
	
	public void UpdateMatrices(Camera camera)
	{
		if (environment != null && camera != null) {
			double[] m = new double[16];
			
			if (!usingCustomMatrices) camera.ResetProjectionMatrix();
			Matrix4x4 P = camera.projectionMatrix;
			
			bool d3d = SystemInfo.graphicsDeviceVersion.IndexOf("Direct3D") > -1;
			if (d3d) {
				// Scale and bias from OpenGL -> D3D depth range
				for ( int i = 0; i < 4; i++) { P[2,i] = P[2,i]*0.5f + P[3,i]*0.5f;}
			}

#if UNITY_STANDALONE_WIN
			if (camera.actualRenderingPath == RenderingPath.DeferredLighting || camera.targetTexture != null)
			{
				Matrix4x4 pflip = Matrix4x4.Scale (new UnityEngine.Vector3(1.0f, -1.0f, 1.0f));
				P = pflip * P;
			}
#endif
			
			
			Matrix4x4 projection = P.transpose;
			
			m[0] = projection.m00; m[1] = projection.m01; m[2] = projection.m02; m[3] = projection.m03;
			m[4] = projection.m10; m[5] = projection.m11; m[6] = projection.m12; m[7] = projection.m13;
			m[8] = projection.m20; m[9] = projection.m21; m[10] = projection.m22; m[11] = projection.m23;
			m[12] = projection.m30; m[13] = projection.m31; m[14] = projection.m32; m[15] = projection.m33;
			
			SWIGTYPE_p_double matrix4 = TritonEnvironment.new_double_array(16);
			
			for (int i = 0; i < 16; i++)
			{
			    TritonEnvironment.double_array_setitem(matrix4, i, m[i]);
			}

			environment.SetProjectionMatrix(matrix4);
			TritonEnvironment.delete_double_array(matrix4);			

			
			m = new double[16];
			
			Matrix4x4 mcamera;
						
			if (!usingCustomMatrices) camera.ResetWorldToCameraMatrix();
			mcamera = camera.worldToCameraMatrix.transpose;	
			
			m[0] = mcamera.m00; m[1] = mcamera.m01; m[2] = mcamera.m02; m[3] = mcamera.m03;
			m[4] = mcamera.m10; m[5] = mcamera.m11; m[6] = mcamera.m12; m[7] = mcamera.m13;
			m[8] = mcamera.m20; m[9] = mcamera.m21; m[10] = mcamera.m22; m[11] = mcamera.m23;
			m[12] = mcamera.m30; m[13] = mcamera.m31; m[14] = mcamera.m32; m[15] = mcamera.m33;
			
			
			
			matrix4 = TritonEnvironment.new_double_array(16);
			for (int i = 0; i < 16; i++)
			{
			    TritonEnvironment.double_array_setitem(matrix4, i, m[i]);
			}
			environment.SetCameraMatrix(matrix4);
			TritonEnvironment.delete_double_array(matrix4);	
		}
	}
	
	private void UpdateLighting()
	{
		if (environment != null) {
			environment.SetAmbientLight(new Triton.Vector3(RenderSettings.ambientLight.r, RenderSettings.ambientLight.g,
				RenderSettings.ambientLight.b));
			
			Triton.Vector3 direction = new Triton.Vector3(0, 1.0, 0);
			Triton.Vector3 color = new Triton.Vector3(1.0, 1.0, 1.0);
			if (directionalLight != null) {
				UnityEngine.Vector3 unit = new UnityEngine.Vector3(0.0f, 0.0f, -1.0f);
				unit = directionalLight.transform.rotation * unit;
				direction = new Triton.Vector3(unit.x, unit.y, unit.z);
				
				UnityEngine.Color finalColor = directionalLight.color * directionalLight.intensity * lightingScale;
				color = new Triton.Vector3(finalColor.r, finalColor.g, finalColor.b);
			}
			environment.SetDirectionalLight(direction, color);
		}
	}
	
	[DllImport ("TritonDLL")]
	    public static extern void UnityRenderEvent(int eventID);
	
	public void WaitForPreviousCamera()
	{
		UnityRenderEvent (2);	
	}
	
	public void Draw(Camera camera, bool wait)
	{
		if (drawingCubemap) return;
		
		InitializeTriton ();
		
		UnityBindings.SetUnityTime (Time.timeSinceLevelLoad);
					
		SetCubeMap (false);
		
		// Waits for previous camera to render
		if (wait ) {
			UnityRenderEvent (2);	
		}
		
		UpdateMatrices (camera);

		GL.IssuePluginEvent (1);
	}
}
