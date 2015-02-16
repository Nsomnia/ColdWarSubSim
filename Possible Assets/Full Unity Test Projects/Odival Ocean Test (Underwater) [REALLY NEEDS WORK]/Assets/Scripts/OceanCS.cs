using UnityEngine;
using System.Collections;
using System.Collections.Generic;

/* Give thanks to the Unity3d community, I'm just one of many to work on this.
 * http://forum.unity3d.com/threads/16540-Wanted-Ocean-shader
 * You are free to use this as you please as long as you do some good deed on the day fist usage.
 * Any changes and improvements you make to this, although not required, would be great
 * if at least shared with me (extra karma points if shared with the community at Unity3d).
 * This version has been optimized for mobile devices.
 * Ported to C# by Joaquin Grech joaquingrech@echoboom.es http://www.echoboomapps.com
 * Updated by Odival Quaresma Neto - reintroduced elements from the original ToreTank's version, including Underwater FX.
 * Added Captain Murphy's system to extend static tiles to the visible distance
 */

 public class OceanCS : MonoBehaviour
{
	public int width = 32;
	public int height = 32;
	public int renderTexWidth = 128;
	public int renderTexHeight = 128;
	public float scale = 0.1f;
	public Vector3 size = new Vector3 (150.0f, 1.0f, 150.0f);
	//public int tiles_x = 9;
	//public int tiles_y = 9;
	//public float waterLevel = 0f;
	public int tiles = 9;
	public float windx=10.0f;
	private float _windDirection = 0f;
	public float windDirection {
		set {
			if (value != _windDirection) {
				if (value > 359) {value= 0;};
				_windDirection = value;
				transform.rotation = Quaternion.Euler(transform.eulerAngles.x,value,transform.eulerAngles.z);
			}
		}
		get {
			return _windDirection;
		}
	}
	private int pNormal_scale=8;
	public int normal_scale {
		get {
			return pNormal_scale;
		}
		set {
			if (value!=pNormal_scale) {
				pNormal_scale=value;
				this.InitWaveGenerator();
				this.GenerateBumpmaps();
			}
		}
	}
	private float pNormalStrength=2f;
	public float normalStrength {
		get {
			return pNormalStrength;
		}
		set {
			if (value!=pNormalStrength) {
				pNormalStrength=value;
				this.GenerateBumpmaps();
			}
		}
	}
	public float choppy_scale = 2.0f;
	private float pUv_speed=0.01f; // not used here?
	public float uv_speed {
		get {
			return pUv_speed;
		}
		set {
			if (value!=pUv_speed) {
				this.pUv_speed=value;
			}
		}
	}
	public Material material;
	public bool followMainCamera = true;
	private int max_LOD = 4;
	private ComplexF[] h0;
	private ComplexF[] t_x;
	private ComplexF[] n0;
	private ComplexF[] n_x;
	private ComplexF[] n_y;
	private ComplexF[] data;
	//private ComplexF[] data_x;
	private Color[] pixelData;
	private Texture2D textureA;
	private Texture2D textureB;
	private Vector3[] baseHeight;
#if USE_UV
	private Vector2[] baseUV;
#endif
	private Mesh baseMesh;
	private GameObject child;
	private List<List<Mesh>> tiles_LOD;
	private int g_height;
	private int g_width;
	private int n_width;
	private int n_height;
	//private bool drawFrame = true; //never called
	private bool normalDone = false;
	private bool reflectionRefractionEnabled = false;
	private Camera depthCam = null;
	private Camera offscreenCam = null;
	private RenderTexture reflectionTexture = null;
	private RenderTexture refractionTexture = null;
	private RenderTexture waterHeightTexture = null;
	private RenderTexture underwaterTexture = null;

	private bool  useCameraRenderTexture = false;
	private RenderTexture underwaterRefractionTexture = null;
	
	private Shader shader = null; //TODO:Change this var name to something less generic
	private Shader depthShader = null;
	private Shader waterBelowShader = null;
	private Material waterCompositionMaterial = null;
	
	public float waterDirtyness = 0.016f;
#if USE_UV
	private Vector2[] uvs;
#endif
	private Vector3[] vertices;
	private Vector3[] normals;
	private Vector4[] tangents;
	public Transform sun;
	public Vector4 SunDir;

	public enum WaterType
	{
		Normal,
		Ice,
		Islands
	}
	public WaterType waterType = WaterType.Normal;
	public Color surfaceColor = new Color (0.3f, 0.5f, 0.3f, 1.0f);
	public Color iceSurfaceColor = new Color (0.3f, 0.5f, 0.3f, 1.0f);
	public Color islandsSurfaceColor = new Color (0.3f, 0.5f, 0.3f, 1.0f);
	public Color waterColor = new Color (0.3f, 0.4f, 0.3f);
	public Color iceWaterColor = new Color (0.3f, 0.4f, 0.3f);
	public Color islandsWaterColor = new Color (0.3f, 0.4f, 0.3f);
	
	private Texture2D texFoam = null; //Never called. But should check what it was suposed to do.
	private Texture2D texFresnel = null;
	private Texture2D texBump = null;
	
	public bool renderReflection = true;
	public bool renderRefraction = true;
	private bool  renderWaterDepth = true;
	public bool  renderUnderwater = true;
	public bool  renderUnderwaterRefraction = true;

	private RenderTexture cameraRenderTexture = null;

	void Waves (float x)
	{
		scale = x;
	}

	public float GetWaterHeightAtLocation(float x, float y)  //Taken from Captain's COP_Ocean.cs
    {
		//try to convert from world pos to parent tile pos
		Vector3 pLoc = this.transform.InverseTransformPoint (new Vector3 (x, 0, y));
		x = pLoc.x;
		y = pLoc.z;

        x = x / size.x;
        x = (x-Mathf.FloorToInt(x)) * width;
        y = y / size.z;
        y = (y-Mathf.FloorToInt(y)) * height;

        int index = (int)width * Mathf.FloorToInt(y) + Mathf.FloorToInt(x);
		if (index > data.Length) 
		{
			return -100;
		}
		return (data[index].Re * scale / (width * height)) + this.transform.position.y;
    }

	float GaussianRnd ()
	{
		float x1 = Random.value;
		float x2 = Random.value;
	
		if (x1 == 0.0f)
			x1 = 0.01f;
	
		return (float)(System.Math.Sqrt (-2.0 * System.Math.Log (x1)) * System.Math.Cos (2.0 * Mathf.PI * x2));
	}

// Phillips spectrum
	float P_spectrum (Vector2 vec_k, Vector2 wind)
	{
		float A = vec_k.x > 0.0f ? 1.0f : 0.05f; // Set wind to blow only in one direction - otherwise we get turmoiling water
	
		float L = wind.sqrMagnitude / 9.81f;
		float k2 = vec_k.sqrMagnitude;
		// Avoid division by zero
		if (vec_k.sqrMagnitude == 0.0f) {
			return 0.0f;
		}
		float vcsq=vec_k.magnitude;	
		return (float)(A * System.Math.Exp (-1.0f / (k2 * L * L) - System.Math.Pow (vcsq * 0.1, 2.0)) / (k2 * k2) * System.Math.Pow (Vector2.Dot (vec_k / vcsq, wind / wind.magnitude), 2.0));// * wind_x * wind_y;
	}

	//Captain's code for static tiles
		GameObject BuildStaticTile (Vector3 pos, Vector3 scale, Quaternion rotation, Mesh mesh, GameObject parentTiles, Material material) {
		GameObject tile = new GameObject ("StaticTile_" + pos.x + "_" + pos.z);
		tile.transform.position=pos;
		MeshFilter mf = tile.AddComponent <MeshFilter>();
		mf.sharedMesh = mesh;
		tile.AddComponent ("MeshRenderer");
		tile.renderer.material = material;
		tile.transform.parent = parentTiles.transform;
		tile.transform.localScale = scale;
		tile.transform.rotation = rotation;
		tile.isStatic = true;

		return tile;
	}
	//End of Captain's code
	
	void Start ()
	{
	
		cameraRenderTexture = new RenderTexture(2048, 2048, 24);
		// normal map size
		n_width = 128;
		n_height = 128;

		textureA = new Texture2D (n_width, n_height);
		textureB = new Texture2D (n_width, n_height);
		textureA.filterMode = FilterMode.Bilinear;
		textureB.filterMode = FilterMode.Bilinear;

		if (!SetupOffscreenRendering ()) {
			// this never gets called ?
			material.SetTexture ("_BumpMap", textureA);
			material.SetTextureScale ("_BumpMap", new Vector2 (normal_scale, normal_scale));

			material.SetTexture ("_BumpMap2", textureB);
			material.SetTextureScale ("_BumpMap2", new Vector2 (normal_scale, normal_scale));
		}
	
		pixelData = new Color[n_width * n_height];

		// Init the water height matrix
		data = new ComplexF[width * height];
		// lateral offset matrix to get the choppy waves
		//data_x = new ComplexF[width * height]; never called

		// tangent
		t_x = new ComplexF[width * height];
		
		n_x = new ComplexF[n_width * n_height];
		n_y = new ComplexF[n_width * n_height];

		// Geometry size
		g_height = height + 1;	
		g_width = width + 1;

		tiles_LOD = new List<List<Mesh>>();
	
		for (int L0D=0; L0D<max_LOD; L0D++) {
			tiles_LOD.Add (new List<Mesh>());
		}

		//Captain's code for static tiles
		//GameObject parentTile=new GameObject("ParentTile");
		GameObject tile;

		//make empty tiles that use a simplified mesh
		Mesh emptyMesh = new Mesh ();
		emptyMesh = CreateMesh(0.5f);

		//build static tiles only
		//take the current position, move to halfway between the end of the active tiles and the farclip
		//float _maxWidth = Camera.main.farClipPlane * 2;
		float _distanceToOffsetX = size.x * tiles;
		float _distanceToOffsetZ = size.z * tiles;
		float _sizeX = size.x * tiles;
		float _sizeZ = size.z * tiles;

		//build the tiles a certain number of spaces away
		// take the main camera's farClipPlane from it, and then creates a count for x and y tiles by 
		//dividing the current tile size by the x/y of the active tiles
		int _staticTilesX = (int)((Camera.main.farClipPlane + (tiles * size.x)) / (tiles * size.x));
		int _staticTilesZ = (int)((Camera.main.farClipPlane + (tiles * size.z)) / (tiles * size.z));
		GameObject _staticTiles = new GameObject ("StaticTiles");
		_staticTiles.transform.parent = transform; //Parent the static tiles to the Ocean GO
		for (int sZ = -_staticTilesZ; sZ < _staticTilesZ; sZ++) {
			for (int sX = -_staticTilesX; sX < _staticTilesX; sX++) {
				if (!(sX == 0 && sZ == 0)) {
					BuildStaticTile (new Vector3 (_distanceToOffsetX * sX, 0, _distanceToOffsetZ * sZ), new Vector3 (_sizeX, 0, _sizeZ),Quaternion.Euler(-180,0,0), emptyMesh, _staticTiles, material);
				}
			}
		}
		
		//build walls along the edge that will keep the user from seeing a gap in the ocean tiles
		float wH = Mathf.Sqrt (Mathf.Pow (20,2) / 2) / 2;
		float wX = tiles / 2f * size.x;
		float wZ = tiles / 2f * size.z;
		BuildStaticTile (new Vector3 (0,-wH + 0.001f, wZ - wH), new Vector3 (_sizeX, 0, 20),Quaternion.AngleAxis(130, Vector3.right), emptyMesh, _staticTiles, material);
		BuildStaticTile (new Vector3 (0,-wH + 0.001f, -wZ + wH), new Vector3 (_sizeX, 0, 20),Quaternion.AngleAxis(-130, Vector3.right), emptyMesh, _staticTiles, material);
		BuildStaticTile (new Vector3 (wX - wH,-wH + 0.001f, 0), new Vector3 (20, 0, _sizeZ),Quaternion.AngleAxis(-130, Vector3.forward), emptyMesh, _staticTiles, material);
		BuildStaticTile (new Vector3 (-wX + wH,-wH + 0.001f, 0), new Vector3 (20, 0, _sizeZ),Quaternion.AngleAxis(130, Vector3.forward), emptyMesh, _staticTiles, material);

		//wall.transform.Rotate (Vector3.right, -45);
		
		//End of Captain's code
		
		//GameObject tile;
		int chDist; // Chebychev distance	
		/*
		for (int y=0; y<tiles_y; y++) {
			for (int x=0; x<tiles_x; x++) {
				chDist = System.Math.Max (System.Math.Abs (tiles_y / 2 - y), System.Math.Abs (tiles_x / 2 - x));
				chDist = chDist > 0 ? chDist - 1 : 0;
				float cy = y - tiles_y / 2f;
				float
				*/
		for (int y=0; y<tiles; y++) {
			for (int x=0; x<tiles; x++) {
				chDist = System.Math.Max (System.Math.Abs (tiles / 2 - y), System.Math.Abs (tiles / 2 - x));
				chDist = chDist > 0 ? chDist - 1 : 0;
				float cy = y - tiles / 2f;
				float cx = x - tiles / 2f;
				tile = new GameObject ("WaterTile" + chDist);
				Vector3 pos=tile.transform.position;
				pos.x = cx * size.x;
				//pos.y = waterLevel;  //Test to make customizable water level
				pos.y =  (-2.0f * chDist); // why not just a simple transform.position.y; ?
				pos.z = cy * size.z;
				tile.transform.position=pos;
				tile.AddComponent (typeof(MeshFilter));
				tile.AddComponent ("MeshRenderer");
				tile.renderer.material = material;
			
				//Make child of this object, so we don't clutter up the
				//scene hierarchy more than necessary.
				tile.transform.parent = transform;
			
				//Also we don't want these to be drawn while doing refraction/reflection passes,
				//so we'll add the to the water layer for easy filtering.
				tile.layer = LayerMask.NameToLayer ("Water");
			
				// Determine which L0D the tile belongs
				//int _tile_LOD = (int)(Vector3.Distance(pos,this.transform.position) / 100);
				//if (_tile_LOD > max_LOD) {_tile_LOD = max_LOD;};
				tiles_LOD[chDist].Add((tile.GetComponent<MeshFilter>()).mesh);				
			}
		}

	
		// Init wave spectra. One for vertex offset and another for normal map
		h0 = new ComplexF[width * height];
		n0 = new ComplexF[n_width * n_height];
		//windx = windDirection;
		
		InitWaveGenerator();
		GenerateHeightmap ();
		GenerateBumpmaps ();
	}
	
	void InitWaveGenerator() {
		// Wind restricted to one direction, reduces calculations
		Vector2 wind = new Vector2 (windx, _windDirection);

		// Initialize wave generator	
		for (int y=0; y<height; y++) {
			for (int x=0; x<width; x++) {
				float yc = y < height / 2f ? y : -height + y;
				float xc = x < width / 2f ? x : -width + x;
				Vector2 vec_k = new Vector2 (2.0f * Mathf.PI * xc / size.x, 2.0f * Mathf.PI * yc / size.z);
				h0 [width * y + x] = new ComplexF (GaussianRnd (), GaussianRnd ()) * 0.707f * (float)System.Math.Sqrt (P_spectrum (vec_k, wind));
			}
		}

		for (int y=0; y<n_height; y++) {
			for (int x=0; x<n_width; x++) {	
				float yc = y < n_height / 2f ? y : -n_height + y;
				float xc = x < n_width / 2f ? x : -n_width + x;
				Vector2 vec_k = new Vector2 (2.0f * Mathf.PI * xc / (size.x / normal_scale), 2.0f * Mathf.PI * yc / (size.z / normal_scale));
				n0 [n_width * y + x] = new ComplexF (GaussianRnd (), GaussianRnd ()) * 0.707f * (float)System.Math.Sqrt (P_spectrum (vec_k, wind));
			}
		}		
	}
	
	void GenerateBumpmaps ()
	{
		if (!normalDone) { 
			for (int idx=0; idx<2; idx++) {
				for (int y = 0; y<n_height; y++) {
					for (int x = 0; x<n_width; x++) {	
						float yc = y < n_height / 2f ? y : -n_height + y;
						float xc = x < n_width / 2f ? x : -n_width + x;
						Vector2 vec_k = new Vector2 (2.0f * Mathf.PI * xc / (size.x / normal_scale), 2.0f * Mathf.PI * yc / (size.z / normal_scale));

						float iwkt = idx == 0 ? 0.0f : Mathf.PI / 2f;
						ComplexF coeffA = new ComplexF ((float)System.Math.Cos (iwkt), (float)System.Math.Sin (iwkt));
						ComplexF coeffB = coeffA.GetConjugate ();

						int ny = y > 0 ? n_height - y : 0;
						int nx = x > 0 ? n_width - x : 0;

						n_x [n_width * y + x] = (n0 [n_width * y + x] * coeffA + n0 [n_width * ny + nx].GetConjugate () * coeffB) * new ComplexF (0.0f, -vec_k.x);				
						n_y [n_width * y + x] = (n0 [n_width * y + x] * coeffA + n0 [n_width * ny + nx].GetConjugate () * coeffB) * new ComplexF (0.0f, -vec_k.y);				
					}
				}
				Fourier.FFT2 (n_x, n_width, n_height, FourierDirection.Backward);
				Fourier.FFT2 (n_y, n_width, n_height, FourierDirection.Backward);
				
				int nwnh=n_width*n_height;
				for (int i=0; i<nwnh; i++) {
					Vector3 bump = Vector3.Normalize(new Vector3(n_x [i].Re * System.Math.Abs (n_x [i].Re), n_y [i].Re * System.Math.Abs (n_y [i].Re), n_width * n_height / scale / normal_scale * normalStrength)) * 0.5f;
					pixelData[i] = new Color (bump.x + 0.5f, bump.y + 0.5f, bump.z + 0.5f);
					//			pixelData[i] = Color (0.5, 0.5, 1.0);			
				}
				if (idx == 0) {
					textureA.SetPixels (pixelData, 0);
					textureA.Apply ();
				} else {
					textureB.SetPixels (pixelData, 0);
					textureB.Apply ();
				}
			}
			normalDone = true;
		}
	
	}

	void GenerateHeightmap ()
	{
		Mesh mesh = new Mesh ();

		int y = 0;
		int x = 0;

		// Build vertices and UVs
		Vector3 []vertices = new Vector3[g_height * g_width];
		Vector4 []tangents = new Vector4[g_height * g_width];
		Vector2 []uv = new Vector2[g_height * g_width];

		Vector2 uvScale = new Vector2 (1.0f / (g_width - 1f), 1.0f / (g_height - 1f));
		Vector3 sizeScale = new Vector3 (size.x / (g_width - 1f), size.y, size.z / (g_height - 1f));

		for (y=0; y<g_height; y++) {
			for (x=0; x<g_width; x++) {
				Vector3 vertex = new Vector3 (x, 0.0f, y);
				vertices [y * g_width + x] = Vector3.Scale (sizeScale, vertex);
				uv [y * g_width + x] = Vector2.Scale (new Vector2 (x, y), uvScale);
			}
		}
	
		mesh.vertices = vertices;
		mesh.uv = uv;

		for (y=0; y<g_height; y++) {
			for (x=0; x<g_width; x++) {
				tangents [y * g_width + x] = new Vector4 (1.0f, 0.0f, 0.0f, -1.0f);
			}
		}
		mesh.tangents = tangents;	
	
		for (int L0D=0; L0D<max_LOD; L0D++) {
			Vector3[] verticesLOD = new Vector3[(int)(height / System.Math.Pow (2, L0D) + 1) * (int)(width / System.Math.Pow (2, L0D) + 1)];
			Vector2[] uvLOD = new Vector2[(int)(height / System.Math.Pow (2, L0D) + 1) * (int)(width / System.Math.Pow (2, L0D) + 1)];
			int idx = 0;
 
			for (y=0; y<g_height; y+=(int)System.Math.Pow(2,L0D)) {
				for (x=0; x<g_width; x+=(int)System.Math.Pow(2,L0D)) {
					verticesLOD [idx] = vertices [g_width * y + x];
					uvLOD [idx++] = uv [g_width * y + x];
				}			
			}
			for (int k=0; k<tiles_LOD[L0D].Count; k++) {
				Mesh meshLOD = tiles_LOD [L0D][k];
				meshLOD.vertices = verticesLOD;
				meshLOD.uv = uvLOD;
			}		
		}

		// Build triangle indices: 3 indices into vertex array for each triangle
		for (int L0D=0; L0D<max_LOD; L0D++) {
			int index = 0;
			int width_LOD = (int)(width / System.Math.Pow (2, L0D) + 1);
			int[] triangles = new int[(int)(height / System.Math.Pow (2, L0D) * width / System.Math.Pow (2, L0D)) * 6];
			for (y=0; y<(int)(height/System.Math.Pow(2,L0D)); y++) {
				for (x=0; x<(int)(width/System.Math.Pow(2,L0D)); x++) {
					// For each grid cell output two triangles
					triangles [index++] = (y * width_LOD) + x;
					triangles [index++] = ((y + 1) * width_LOD) + x;
					triangles [index++] = (y * width_LOD) + x + 1;

					triangles [index++] = ((y + 1) * width_LOD) + x;
					triangles [index++] = ((y + 1) * width_LOD) + x + 1;
					triangles [index++] = (y * width_LOD) + x + 1;
				}
			}
			for (int k=0; k<tiles_LOD[L0D].Count; k++) {
				Mesh meshLOD = tiles_LOD [L0D][k];
				meshLOD.triangles = triangles;
			}
		}
	
		baseMesh = mesh;
	}

/*
Prepares the scene for offscreen rendering; spawns a camera we'll use for for
temporary renderbuffers as well as the offscreen renderbuffers (one for
reflection and one for refraction).
*/
	bool SetupOffscreenRendering ()
	{
		//Check for rendertexture support and return false if not supported
		if( !SystemInfo.supportsRenderTextures)
			return false;
		
		shader = Shader.Find("OceanReflectionRefraction");		
		
		depthShader = Shader.Find("WaterHeight");
		waterCompositionMaterial = new Material(Shader.Find("WaterComposition"));
		waterBelowShader = Shader.Find ("DeepWaterBelow");
		//RenderTexture's width, height and depth (0, 16, 24 values for depth precision).
		underwaterTexture = new RenderTexture(512, 512, 16);
		underwaterTexture.wrapMode = TextureWrapMode.Clamp;
		underwaterTexture.isPowerOfTwo = true;
		
		reflectionTexture = new RenderTexture (renderTexWidth, renderTexHeight, 16);
		refractionTexture = new RenderTexture (renderTexWidth, renderTexHeight, 16);
		
		reflectionTexture.wrapMode = TextureWrapMode.Clamp;
		refractionTexture.wrapMode = TextureWrapMode.Clamp;
		
		reflectionTexture.isPowerOfTwo = true;
		refractionTexture.isPowerOfTwo = true;
		
		underwaterRefractionTexture = new RenderTexture(renderTexWidth, renderTexHeight, 0);
		underwaterRefractionTexture.wrapMode = TextureWrapMode.Clamp;
		underwaterRefractionTexture.isPowerOfTwo = true;
		
		waterHeightTexture = new RenderTexture(renderTexWidth, renderTexHeight, 0);
		waterHeightTexture.wrapMode = TextureWrapMode.Clamp;
		waterHeightTexture.isPowerOfTwo = true;
		waterHeightTexture.format = RenderTextureFormat.Depth;  //Comment this out in order to get this running on a low-end graphics hardware
	
		//Spawn the camera we'll use for offscreen rendering (refraction/reflection)
		GameObject cam = new GameObject ();
		cam.name = "DeepWaterOffscreenCam";
		cam.transform.parent = transform;
		offscreenCam = cam.AddComponent (typeof(Camera)) as Camera;
		offscreenCam.clearFlags = CameraClearFlags.Color;
		//offscreenCam.backgroundColor = RenderSettings.fogColor; //Color.grey;
		offscreenCam.enabled = false;
		
		cam = new GameObject();
		cam.name = "DeepWaterFoamOffscreenCam";
		cam.transform.parent = transform;
		depthCam = cam.AddComponent(typeof(Camera)) as Camera;
		depthCam.enabled = false;
	
		//Hack to make this object considered by the renderer - first make a plane
		//covering the watertiles so we get a decent bounding box, then
		//scale all the vertices to 0 to make it invisible.
		gameObject.AddComponent (typeof(MeshRenderer));
		
		renderer.material.renderQueue = 1001;
		renderer.receiveShadows = false;
		renderer.castShadows = false;
	
		Mesh m = new Mesh ();
		
		Vector3[] verts = new Vector3[4];
		Vector2[] uv = new Vector2[4];
		Vector3[] n = new Vector3[4];
		int[] tris = new int[6];
		
		float minSizeX = -1024;
		float maxSizeX = 1024;
	
		float minSizeY = -1024;
		float maxSizeY = 1024;
		
		verts [0] = new Vector3 (minSizeX, 0.0f, maxSizeY);
		verts [1] = new Vector3 (maxSizeX, 0.0f, maxSizeY);
		verts [2] = new Vector3 (maxSizeX, 0.0f, minSizeY);
		verts [3] = new Vector3 (minSizeX, 0.0f, minSizeY);
	
		tris [0] = 0;
		tris [1] = 1;
		tris [2] = 2;
		
		tris [3] = 2;
		tris [4] = 3;
		tris [5] = 0;
		
		m.vertices = verts;
		m.uv = uv;
		m.normals = n;
		m.triangles = tris;
		
		
		MeshFilter mfilter = gameObject.GetComponent<MeshFilter>();
		
		if (mfilter == null)
			mfilter = gameObject.AddComponent<MeshFilter>();
		
		mfilter.mesh = m;
		
		m.RecalculateBounds ();
		
		//Hopefully the bounds will not be recalculated automatically
		verts [0] = Vector3.zero;
		verts [1] = Vector3.zero;
		verts [2] = Vector3.zero;
		verts [3] = Vector3.zero;
		
		m.vertices = verts;
	
		//Create the material and set up the texture references.
		material = new Material(shader);
		
		Texture2D texBump = Resources.Load("Ocean/Bump") as Texture2D;
		Texture2D texFresnel = Resources.Load("Ocean/Fresnel") as Texture2D;
		Texture2D texFoam = Resources.Load("Ocean/Foam") as Texture2D;
		
		material.SetTexture("_Reflection", reflectionTexture);
		material.SetTexture("_Refraction", refractionTexture);
		material.SetTexture ("_Bump", texBump);
		material.SetTexture("_Fresnel", texFresnel);
		material.SetTexture("_Foam", texFoam);
		material.SetVector("_Size", new Vector4(size.x, size.y, size.z, 0.0f));
		
		material.SetColor("_SurfaceColor", surfaceColor);	
		material.SetColor("_WaterColor", waterColor);
		
		waterCompositionMaterial.SetColor("_WaterColor", waterColor);
		waterCompositionMaterial.SetTexture("_DepthTex", waterHeightTexture);
		waterCompositionMaterial.SetTexture("_UnderwaterTex", underwaterTexture);
		waterCompositionMaterial.SetTexture("_UnderwaterDistortionTex", texBump);
		
		//if (SunLight != null)
		//	material.SetVector("_SunDir", transform.TransformDirection(SunLight.transform.forward));
		
		reflectionRefractionEnabled = true;
	
		UpdateWaterColor (); //TODO:This is Joaquim's code. Check if it's still compatible

		return true;
	}

/*
Delete the offscreen rendertextures on script shutdown.
*/
	void OnDisable ()
	{
		if (reflectionTexture != null)
			DestroyImmediate (reflectionTexture);
			
		if (refractionTexture != null)
			DestroyImmediate (refractionTexture);
			
		reflectionTexture = null;
		refractionTexture = null;

		if (waterHeightTexture != null)
			DestroyImmediate(waterHeightTexture);
		
		if (underwaterTexture != null)
			DestroyImmediate(underwaterTexture);
		
		if (underwaterRefractionTexture)
			DestroyImmediate(underwaterRefractionTexture);
		
		waterHeightTexture = null;
		underwaterTexture = null;
		underwaterRefractionTexture = null;
	}

	// Wave dispersion //TODO: Check if it's stable
	float  disp ( Vector2 vec_k  ){
		return Mathf.Sqrt (9.81f * vec_k.magnitude);
	}
	
	private bool inited=false;
	void FixedUpdate ()
	{
		//Coroutine for non expensive realtime water color update //TODO:Joaquim's code. Check compatibility with the rest of code.
		if (!inited) {
			inited=true;
			UpdateWaterColor ();			
			//material.SetVector ("_SunDir", SunDir);
		}
	
		if (useCameraRenderTexture)
			Camera.main.targetTexture = cameraRenderTexture;
		else
			Camera.main.targetTexture = null;
			
		//Get sun reflection dir from sun object
		if(sun != null){
			Light _sun = sun.GetComponent<Light>();
		    SunDir = sun.transform.forward;
		    material.SetVector ("_WorldLightDir", SunDir);
			material.SetColor ("_SpecularColor",_sun.color);
		}
		
		if (followMainCamera) {
			Vector3 modvec = Vector3.zero;
			Vector3 locdiffvec = transform.InverseTransformPoint(Camera.main.transform.position);
			if(Mathf.Abs (locdiffvec.x) > size.x*0.5f) modvec += size.x*Mathf.Sign (locdiffvec.x)*transform.right;
			if(Mathf.Abs (locdiffvec.z) > size.z*0.5f) modvec += size.z*Mathf.Sign (locdiffvec.z)*transform.forward;

			if (modvec != Vector3.zero) {
				transform.position += modvec;
			};
		}

		float hhalf=height/2f;
		float whalf=width/2f;
		float time=Time.time;
		for (int y = 0; y<height; y++) {
			for (int x = 0; x<width; x++) {
				int idx = width * y + x;
				float yc = y < hhalf ? y : -height + y;
				float xc = x < whalf ? x : -width + x;
				Vector2 vec_k = new Vector2 (2.0f * Mathf.PI * xc / size.x, 2.0f * Mathf.PI * yc / size.z);
				
				float sqrtMagnitude=(float)System.Math.Sqrt((vec_k.x * vec_k.x) + (vec_k.y * vec_k.y));
				float iwkt = (float)System.Math.Sqrt(9.81f * sqrtMagnitude) * time;
				ComplexF coeffA = new ComplexF ((float)System.Math.Cos(iwkt), (float)System.Math.Sin(iwkt));
				ComplexF coeffB;
				coeffB.Re = coeffA.Re;
				coeffB.Im = -coeffA.Im;

				int ny = y > 0 ? height - y : 0;
				int nx = x > 0 ? width - x : 0;

				data [idx] = h0 [idx] * coeffA + h0[width * ny + nx].GetConjugate() * coeffB;				
				t_x [idx] = data [idx] * new ComplexF (0.0f, vec_k.x) - data [idx] * vec_k.y;				

				// Choppy wave calculations
				if (x + y > 0)
					data [idx] += data [idx] * vec_k.x / sqrtMagnitude;
			}
		}
		
		material.SetFloat ("_BlendA", (float)System.Math.Cos(time)); 
		material.SetFloat ("_BlendB", (float)System.Math.Sin(time)); 
		
		Fourier.FFT2 (data, width, height, FourierDirection.Backward);
		Fourier.FFT2 (t_x, width, height, FourierDirection.Backward);
		
		// Get base values for vertices and uv coordinates.
		if (baseHeight == null) {
			baseHeight = baseMesh.vertices;
			
	
#if USE_UV
			baseUV = baseMesh.uv;
			uvs = new Vector2[baseHeight.Length];
#endif
			vertices = new Vector3[baseHeight.Length];
			normals = new Vector3[baseHeight.Length];
			tangents = new Vector4[baseHeight.Length];
		}
		
		
#if USE_UV
		//var vertex;
		Vector2 uv;
		//var normal;
		float n_scale = size.x / width / scale;
#endif
		
		int wh=width*height;
		float scaleA = choppy_scale / wh;
		float scaleB = scale / wh;
		float scaleBinv = 1.0f / scaleB;
	
		for (int i=0; i<wh; i++) {
			int iw = i + i / width;
			vertices [iw] = baseHeight [iw];
			vertices [iw].x += data [i].Im * scaleA;
			vertices [iw].y = data [i].Re * scaleB;

			normals [iw] = Vector3.Normalize(new Vector3 (t_x [i].Re, scaleBinv, t_x [i].Im));
			
#if USE_UV
		uv = baseUV[iw];
		uv.x = uv.x + time * uv_speed;
		uvs[iw] = uv;
#endif
			
			if (((i + 1) % width)==0) {
				int iwi=iw+1;
				int iwidth=i+1-width;
				vertices [iwi] = baseHeight [iwi];
				vertices [iwi].x += data [iwidth].Im * scaleA;
				vertices [iwi].y = data [iwidth].Re * scaleB;

				normals [iwi] = Vector3.Normalize(new Vector3 (t_x [iwidth].Re, scaleBinv, t_x [iwidth].Im));
				
#if USE_UV
			uv = baseUV[iwi];
			uv.x = uv.x + time * uv_speed;
			uvs[iwi] = uv;				
#endif
			}
		}

		int offset = g_width * (g_height - 1);

		for (int i=0; i<g_width; i++) {
			int io=i+offset;
			int mod=i % width;
			vertices [io] = baseHeight [io];
			vertices [io].x += data [mod].Im * scaleA;
			vertices [io].y = data [mod].Re * scaleB;
			
			normals [io] = Vector3.Normalize(new Vector3 (t_x [mod].Re, scaleBinv, t_x [mod].Im));

#if USE_UV
		uv = baseUV[io];
		uv.x = uv.x - time*uv_speed;
		uvs[io] = uv;
#endif
		}
		//Real-time updating of the water colors.
	    material.SetColor("_SurfaceColor", surfaceColor);	
		material.SetColor("_WaterColor", waterColor);
		waterCompositionMaterial.SetColor("_WaterColor", waterColor);
			
		int gwgh=g_width*g_height-1;
		for (int i=0; i<gwgh; i++) {
			
			//Need to preserve w in refraction/reflection mode
			if (!reflectionRefractionEnabled) {
				if (((i + 1) % g_width) == 0) {
					tangents [i] = Vector3.Normalize((vertices [i - width + 1] + new Vector3 (size.x, 0.0f, 0.0f) - vertices [i]));
				} else {
					tangents [i] = Vector3.Normalize((vertices [i + 1] - vertices [i]));
				}
			
				tangents [i].w = 1.0f;
			} else {
				Vector3 tmp;// = Vector3.zero;
			
				if (((i + 1) % g_width) == 0) {
					tmp = Vector3.Normalize(vertices[i - width + 1] + new Vector3 (size.x, 0.0f, 0.0f) - vertices [i]);
				} else {
					tmp = Vector3.Normalize(vertices [i + 1] - vertices [i]);
				}
				
				tangents [i] = new Vector4 (tmp.x, tmp.y, tmp.z, tangents [i].w);
			}
		}
		
		//In reflection mode, use tangent w for foam strength
		if (reflectionRefractionEnabled) {
			for (int y = 0; y < g_height; y++) {
				for (int x = 0; x < g_width; x++) {
					int item=x + g_width * y;
					if (x + 1 >= g_width) {
						tangents [item].w = tangents [g_width * y].w;
					
						continue;
					}
					
					if (y + 1 >= g_height) {
						tangents [item].w = tangents [x].w;
						
						continue;
					}
				
					float right = vertices[(x + 1) + g_width * y].x - vertices[item].x;
					//Vector3 back = vertices [x + g_width * y] - vertices [x + g_width * (y + 1)]; //Never called.
					
					float foam = right / (size.x / g_width);
					
					
					if (foam < 0.0f)
						tangents [item].w = 1f;
					else if (foam < 0.5f)
						tangents [item].w += 3.0f * Time.deltaTime;
					else
						tangents [item].w -= 0.4f * Time.deltaTime;
						
					tangents [item].w = Mathf.Clamp (tangents[item].w, 0.0f, 2.0f);
				}
			}
		}
	
		tangents [gwgh] = Vector4.Normalize(vertices [gwgh] + new Vector3 (size.x, 0.0f, 0.0f) - vertices [1]);

		for (int L0D=0; L0D<max_LOD; L0D++) {
			int den = (int)System.Math.Pow (2f, L0D);
			int itemcount = (int)((height / den + 1) * (width / den + 1));
		
			Vector4[] tangentsLOD = new Vector4[itemcount];
			Vector3[] verticesLOD = new Vector3[itemcount];
			Vector3[] normalsLOD = new Vector3[itemcount];
#if USE_UV
		Vector2 [] uvLOD = new Vector2[(int)((height/System.Math.Pow(2,L0D)+1) * (width/System.Math.Pow(2,L0D)+1))];
#endif
			
			int idx = 0;

			for (int y=0; y<g_height; y+=den) {
				for (int x=0; x<g_width; x+=den) {
					int idx2 = g_width * y + x;
					verticesLOD [idx] = vertices [idx2];
#if USE_UV
				uvLOD[idx] = uvs[idx2];
#endif
					tangentsLOD [idx] = tangents [idx2];
					normalsLOD [idx++] = normals [idx2];
				}			
			}
			for (int k=0; k< tiles_LOD[L0D].Count; k++) {
				Mesh meshLOD = tiles_LOD [L0D][k];
				meshLOD.vertices = verticesLOD;
				meshLOD.normals = normalsLOD;
#if USE_UV
			meshLOD.uv = uvLOD;
#endif
				meshLOD.tangents = tangentsLOD;
			}		
		}
	
	
	}

/*
Called when the object is about to be rendered. We render the refraction/reflection
passes from here, since we only need to do it once per frame, not once per tile.
*/
	void OnWillRenderObject ()
	{
		//Recursion guard, don't let the offscreen cam go into a never-ending loop.
		if (Camera.current == offscreenCam
			|| Camera.current == depthCam)
			return;
			
		if (reflectionTexture == null
		|| refractionTexture == null)
			return;
		
		if (this.renderWaterDepth || this.renderWaterDepth) //It could be troublesome code.
			RenderWaterDepth();
		if (this.renderReflection || this.renderRefraction)
			RenderReflectionAndRefraction ();
	}

/*
Renders the wave height from above for use as a depth comparison map
when blending over/underwater renders.
*/
	void  RenderWaterDepth (){
		if (!renderWaterDepth)
			return;
		
		depthCam.backgroundColor = Color.black;
		Vector3 pos = Camera.current.gameObject.transform.position;
		int waterMask = 1 << LayerMask.NameToLayer("Water");
		
		depthCam.orthographic = true;
		//TODO: Match this with the maximum possible viewplane for the current camera. 50 is WAY
		//      too large, but it works for testing purposes and it makes it possible to see the
		//      heightmap on the rendered output.
		depthCam.orthographicSize = 50;
		depthCam.aspect = 1.0f;
		
		//NOTE: Changes to the 20 unit view distance MUST BE REFLECTED 
		//      in WaterComposition and WaterHeight shaders! This is due
		//      to a hack because I had severe problems getting the clip-space
		//      values to work consistently on Windows and Mac. I figured I'd
		//      just do it this way, so there is no chance for it to break, although
		//      there will be a bit more work if the distance is to change.
		//TODO: Fix the hack, or set this as a parameter to WaterComposition
		//      and WaterHeight. This is left as an excercise for the reader.
		depthCam.nearClipPlane = 0.0f;
		depthCam.farClipPlane = 20.0f;
		
		depthCam.transform.position = new Vector3(pos.x, transform.position.y + 10.0f, pos.z);
		depthCam.transform.eulerAngles = new Vector3(90.0f, 0.0f, 0.0f);
		
		depthCam.targetTexture = waterHeightTexture;
		depthCam.clearFlags = CameraClearFlags.SolidColor;
		depthCam.cullingMask = waterMask;
		depthCam.RenderWithShader(depthShader, "");
	}
	
/*
Renders the reflection and refraction buffers using a second camera copying the current
camera settings.
*/	
	public LayerMask renderLayers = -1;
	
	void RenderReflectionAndRefraction ()
	{
		/*int oldPixelLightCount = QualitySettings.pixelLightCount;
		QualitySettings.pixelLightCount = 0;*/

		Camera renderCamera = Camera.main;
			
		Matrix4x4 originalWorldToCam = renderCamera.worldToCameraMatrix;
		
		int cullingMask = ~(1 << 4) & renderLayers.value;
		;
		
		//Reflection pass
		Matrix4x4 reflection = Matrix4x4.zero;
	
		//TODO: Use local plane here, not global!
	
		float d = -transform.position.y;
		offscreenCam.backgroundColor = RenderSettings.fogColor;
	
		CameraHelper.CalculateReflectionMatrix(ref reflection, new Vector4 (0f, 1f, 0f, d));
		
		offscreenCam.transform.position = reflection.MultiplyPoint (renderCamera.transform.position);
		offscreenCam.transform.rotation = renderCamera.transform.rotation;
		offscreenCam.worldToCameraMatrix = originalWorldToCam * reflection;
	
		offscreenCam.cullingMask = cullingMask;
		offscreenCam.targetTexture = reflectionTexture;
		offscreenCam.clearFlags = renderCamera.clearFlags;
	
		//Need to reverse face culling for reflection pass, since the camera
		//is now flipped upside/down.
		GL.SetRevertBackfacing (true);
		
		Vector4 cameraSpaceClipPlane = CameraHelper.CameraSpacePlane (offscreenCam, new Vector3 (0.0f, transform.position.y, 0.0f), Vector3.up, 1.0f);
		
		Matrix4x4 projection = renderCamera.projectionMatrix;
		Matrix4x4 obliqueProjection = projection;
	
		offscreenCam.fieldOfView = renderCamera.fieldOfView;
		offscreenCam.aspect = renderCamera.aspect;
	
		CameraHelper.CalculateObliqueMatrix (ref obliqueProjection, cameraSpaceClipPlane);
	
		//Do the actual render, with the near plane set as the clipping plane. See the
		//pro water source for details.
		offscreenCam.projectionMatrix = obliqueProjection;
	
		if (!renderReflection)
			offscreenCam.cullingMask = 0;
	
		offscreenCam.Render ();
	
	
		GL.SetRevertBackfacing (false);

		//Refractionpass
		bool  fog = RenderSettings.fog;
		Color fogColor = RenderSettings.fogColor;
		float fogDensity = RenderSettings.fogDensity;
		
		RenderSettings.fog = true;
		RenderSettings.fogColor = Color.grey;
		RenderSettings.fogDensity = waterDirtyness;
		
		//TODO: If we want to use this as a refraction seen from under the seaplane,
		//      the cameraclear should be skybox.
		offscreenCam.clearFlags = CameraClearFlags.Skybox;
		offscreenCam.backgroundColor = Color.grey;
		
		offscreenCam.cullingMask = cullingMask;
		offscreenCam.targetTexture = refractionTexture;
		obliqueProjection = projection;
	
		offscreenCam.transform.position = renderCamera.transform.position;
		offscreenCam.transform.rotation = renderCamera.transform.rotation;
		offscreenCam.worldToCameraMatrix = originalWorldToCam;
	
	
		cameraSpaceClipPlane = CameraHelper.CameraSpacePlane (offscreenCam, Vector3.zero, Vector3.up, -1.0f);
		CameraHelper.CalculateObliqueMatrix (ref obliqueProjection, cameraSpaceClipPlane);
		offscreenCam.projectionMatrix = obliqueProjection;
	
		if (!renderRefraction)
			offscreenCam.cullingMask = 0;
	
		offscreenCam.Render ();
		
		RenderSettings.fog = fog;
		RenderSettings.fogColor = fogColor;
		RenderSettings.fogDensity = fogDensity;
		
		offscreenCam.projectionMatrix = projection;
		
		
		offscreenCam.targetTexture = null;
	
	//Do the passes for the underwater "effect" if the WaterPostEffect script is present on the
		//current camera.
		WaterPostEffect wpe = renderCamera.gameObject.GetComponent<WaterPostEffect>() as WaterPostEffect;
		
		if (wpe != null)
		{			
			int waterMask = 1 << LayerMask.NameToLayer("Water");
			
			offscreenCam.clearFlags = CameraClearFlags.Skybox;
			offscreenCam.backgroundColor = Color.grey;
			
			offscreenCam.cullingMask = cullingMask;
			offscreenCam.targetTexture = underwaterRefractionTexture;
			obliqueProjection = projection;
			
			offscreenCam.transform.position = renderCamera.transform.position;
			offscreenCam.transform.rotation = renderCamera.transform.rotation;
			offscreenCam.worldToCameraMatrix = originalWorldToCam;
			
			cameraSpaceClipPlane = CameraHelper.CameraSpacePlane(offscreenCam, new Vector3(0.0f, transform.position.y, 0.0f), Vector3.up, 1.0f);
			CameraHelper.CalculateObliqueMatrix (ref obliqueProjection, cameraSpaceClipPlane);
			offscreenCam.projectionMatrix = obliqueProjection;
			
			if (!renderUnderwaterRefraction)
				offscreenCam.cullingMask = 0;	
			
			offscreenCam.Render();
			offscreenCam.projectionMatrix = projection;
			offscreenCam.targetTexture = null;

			Shader.SetGlobalTexture("_UnderWaterRefraction", underwaterRefractionTexture);
			Shader.SetGlobalTexture("_UnderWaterBump", texBump);
			Shader.SetGlobalTexture("_Fresnel", texFresnel);
			Shader.SetGlobalVector("_Size", new Vector4(size.x, size.y, size.z, 0.0f));
			
			//Draw underwater
			RenderSettings.fog = true;
			RenderSettings.fogColor = Color.grey;
			RenderSettings.fogDensity = waterDirtyness;
			
			offscreenCam.orthographic = false;
			offscreenCam.backgroundColor = Color.grey;
			offscreenCam.clearFlags = CameraClearFlags.Color;
			offscreenCam.transform.position = renderCamera.transform.position;
			offscreenCam.transform.rotation = renderCamera.transform.rotation;
			offscreenCam.fieldOfView = renderCamera.fieldOfView;
			offscreenCam.nearClipPlane = 0.3f;
			offscreenCam.farClipPlane = 200.0f;
			
			offscreenCam.targetTexture = underwaterTexture;
			
			if (renderUnderwater)
			{				
				//First, draw only the water tiles with inverted normals and a custom, simplified
				//shader, so we can see the surface from below as well.
				offscreenCam.cullingMask = waterMask;
				GL.SetRevertBackfacing (true);
				offscreenCam.RenderWithShader(waterBelowShader, "");
				GL.SetRevertBackfacing (false);
				
				offscreenCam.clearFlags = CameraClearFlags.Nothing;
				offscreenCam.cullingMask = cullingMask & ~(waterMask);
				offscreenCam.Render();
			}
			
			RenderSettings.fog = fog;
			RenderSettings.fogColor = fogColor;
			RenderSettings.fogDensity = fogDensity;
			
			Matrix4x4 depthMV = depthCam.worldToCameraMatrix;
			
			//Matrix4x4 MVP = renderCamera.projectionMatrix * renderCamera.worldToCameraMatrix; //Never called.
			
			waterCompositionMaterial.SetMatrix("_DepthCamMV", depthMV);
			waterCompositionMaterial.SetMatrix("_DepthCamProj", depthCam.projectionMatrix);
			
			wpe.waterCompositionMaterial = waterCompositionMaterial;
		}
		
		//QualitySettings.pixelLightCount = oldPixelLightCount;
	}

	//Captain's code for static tiles
	Mesh CreateMesh(float width)
	{
		Mesh m = new Mesh();
		m.name = "ScriptedMesh";
		m.vertices = new Vector3[] {
			new Vector3(-width, 0.01f, -width),
			new Vector3(width, 0.01f, -width),
			new Vector3(width, 0.01f, width),
			new Vector3(-width, 0.01f, width)
		};
		m.uv = new Vector2[] {
			new Vector2 (0, 0),
			new Vector2 (0, 1),
			new Vector2(1, 1),
			new Vector2 (1, 0)
		};
		m.triangles = new int[] { 0, 1, 2, 0, 2, 3};
		m.RecalculateNormals();
		m.tangents = new Vector4[] {
			new Vector4(0,0,0,0),
			new Vector4(0,0,0,0),
			new Vector4(0,0,0,0),
			new Vector4(0,0,0,0)};
		return m;
	}
	//End of Captain's code
	
	IEnumerable UpdateWaterColor ()
	{

		if (waterType == WaterType.Normal) {	
			material.SetColor ("_WaterColor", waterColor);
			material.SetColor ("_SurfaceColor", surfaceColor);
		} else if (waterType == WaterType.Ice) {	
			material.SetColor ("_WaterColor", iceWaterColor);
			material.SetColor ("_SurfaceColor", iceSurfaceColor);
		} else if (waterType == WaterType.Islands) {
			material.SetColor ("_WaterColor", islandsWaterColor);
			material.SetColor ("_SurfaceColor", islandsSurfaceColor);
		}
		yield return new WaitForSeconds (1f);
	}

}
