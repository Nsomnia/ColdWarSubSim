using UnityEngine;
using System.Collections;
using System.IO;

public class Sky : MonoBehaviour 
{
	const float SCALE = 1000.0f;
	
	const int TRANSMITTANCE_WIDTH = 256;
	const int TRANSMITTANCE_HEIGHT = 64;
	const int TRANSMITTANCE_CHANNELS = 3;
	
	const int IRRADIANCE_WIDTH = 64;
	const int IRRADIANCE_HEIGHT = 16;
	const int IRRADIANCE_CHANNELS = 3;
	
	const int INSCATTER_WIDTH = 256;
	const int INSCATTER_HEIGHT = 128;
	const int INSCATTER_DEPTH = 32;
	const int INSCATTER_CHANNELS = 4;
	
	public Material m_skyMapMaterial;
	public Material m_skyMaterial;
	public Material m_oceanMaterial;
	public GameObject m_sun;
	public Vector3 m_betaR = new Vector3(0.0058f, 0.0135f, 0.0331f);
	public float m_mieG = 0.75f;
	public float m_sunIntensity = 100.0f;
	public float m_horizon = 0.0f;
	
	RenderTexture m_transmittance, m_inscatter, m_irradiance, m_skyMap;
	int m_frameCount = 0;

	void Start () 
	{

		m_skyMap = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBHalf);
		m_skyMap.filterMode = FilterMode.Trilinear;
		m_skyMap.wrapMode = TextureWrapMode.Clamp;
		m_skyMap.anisoLevel = 9;
		m_skyMap.useMipMap = true;
		m_skyMap.Create();

		m_transmittance = new RenderTexture(TRANSMITTANCE_WIDTH, TRANSMITTANCE_HEIGHT, 0, RenderTextureFormat.ARGBHalf);
		m_transmittance.wrapMode = TextureWrapMode.Clamp;
		m_transmittance.filterMode = FilterMode.Bilinear;
		m_transmittance.Create();
		
		m_irradiance = new RenderTexture(IRRADIANCE_WIDTH, IRRADIANCE_HEIGHT, 0, RenderTextureFormat.ARGBHalf);
		m_irradiance.wrapMode = TextureWrapMode.Clamp;
		m_irradiance.filterMode = FilterMode.Bilinear;
		m_irradiance.Create();
		
		m_inscatter = new RenderTexture(INSCATTER_WIDTH, INSCATTER_HEIGHT*INSCATTER_DEPTH, 0, RenderTextureFormat.ARGBHalf);
		m_inscatter.wrapMode = TextureWrapMode.Clamp;
		m_inscatter.filterMode = FilterMode.Bilinear;
		m_inscatter.Create();

	}
	
	public bool IsCreated()
	{
		//Sometimes Unity will mark render textures as not created when they have been
		//This will check for that. These textures are the important ones.
		if(!m_transmittance.IsCreated()) return false;
		if(!m_irradiance.IsCreated()) return false;
		if(!m_inscatter.IsCreated()) return false;
		if(!m_skyMap.IsCreated()) return false;
		
		return true;
	}
	
	public void Init()
	{
		
		//Transmittance is responsible for the change in the sun color as it moves
		//The raw file is a 2D array of 32 bit floats with a range of 0 to 1
		string path = Application.dataPath + "/Textures/transmittance.raw";
		
		//This function loads the raw file, encodes each channel into a 2D texture
		//and then decodes each channel into a 2D render texture using Graphics.Blit(). 
		EncodeFloat.WriteIntoRenderTexture(m_transmittance, TRANSMITTANCE_CHANNELS, path);
		
		//Iirradiance is responsible for the change in the sky color as the sun moves
		//The raw file is a 2D array of 32 bit floats with a range of 0 to 1
		path = Application.dataPath + "/Textures/irradiance.raw";
		
		EncodeFloat.WriteIntoRenderTexture(m_irradiance, IRRADIANCE_CHANNELS, path);
		
		//Inscatter is responsible for the change in the sky color as the sun moves
		//The raw file is a 4D array of 32 bit floats with a range of 0 to 1.589844
		//As there is not such thing as a 4D texture the data is packed into a 2D texture 
		//and the shader manually performs the sample for the 3rd and 4th dimension
		path = Application.dataPath + "/Textures/inscatter.raw";
		
		EncodeFloat.WriteIntoRenderTexture(m_inscatter, INSCATTER_CHANNELS, path);
		
		InitMaterial(m_skyMapMaterial);
		InitMaterial(m_skyMaterial);
		InitMaterial(m_oceanMaterial); //ocean mat needs some of these uniforms so may as well set them here
		
	}
	
	void Update () 
	{
		
		//These are work arounds for some bugs in Unity 4.0 - 4.2. If your running this in a later version they may have been fixed??
		//In a Unity dx9 build graphics blit does not seam to have any effect on the first frame.
		//The sky object uses graphics blit to initilize some render textures.
		//Call init() to do this but it must be called on the second frame. Strange.
		//This does not seem to be needed in a dx11 build
		if(m_frameCount == 1)
			Init();

		m_frameCount++;
		
		Vector3 pos = Camera.main.transform.position;
		pos.y = 0.0f;
		//centre sky dome at player pos
		transform.localPosition = pos;

		m_skyMaterial.SetFloat("_Horizon", m_horizon);
		
		UpdateMat(m_skyMapMaterial);
		UpdateMat(m_skyMaterial);
		UpdateMat(m_oceanMaterial);

		Graphics.Blit(null, m_skyMap, m_skyMapMaterial);
	}
	
	void UpdateMat(Material mat)
	{	
		mat.SetVector("betaR", m_betaR / SCALE);
		mat.SetFloat("mieG", m_mieG);
		mat.SetVector("SUN_DIR", m_sun.transform.forward*-1.0f);
		mat.SetFloat("SUN_INTENSITY", m_sunIntensity);
	}
	
	void InitMaterial(Material mat)
	{
		
		mat.SetTexture("_Transmittance", m_transmittance);
		mat.SetTexture("_Inscatter", m_inscatter);
		mat.SetTexture("_Irradiance", m_irradiance);
		mat.SetTexture("_SkyMap", m_skyMap);
		
		mat.SetFloat("SUN_INTENSITY", m_sunIntensity);
		mat.SetVector("SUN_DIR", m_sun.transform.forward*-1.0f);
		
		//Dont change this
		mat.SetVector("EARTH_POS", new Vector3(0.0f, 6360010.0f, 0.0f));
		
	}
	
	void OnDestroy()
	{
		m_transmittance.Release();
		m_irradiance.Release();
		m_inscatter.Release();
		m_skyMap.Release();
	}
	
}

