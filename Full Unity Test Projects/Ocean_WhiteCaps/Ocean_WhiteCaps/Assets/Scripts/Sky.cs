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
	public ComputeShader m_writeData;
	
	private RenderTexture m_transmittance, m_inscatter, m_irradiance, m_skyMap;

	void Start () 
	{

		m_skyMap = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBHalf);
		m_skyMap.filterMode = FilterMode.Trilinear;
		m_skyMap.wrapMode = TextureWrapMode.Clamp;
		m_skyMap.anisoLevel = 9;
		m_skyMap.useMipMap = true;
		m_skyMap.Create();

		//Transmittance is responsible for the change in the sun color as it moves
		//The raw file is a 2D array of 32 bit floats with a range of 0 to 1
		string path = Application.dataPath + "/Textures/transmittance.raw";
		
		m_transmittance = new RenderTexture(TRANSMITTANCE_WIDTH, TRANSMITTANCE_HEIGHT, 0, RenderTextureFormat.ARGBHalf);
		m_transmittance.wrapMode = TextureWrapMode.Clamp;
		m_transmittance.filterMode = FilterMode.Bilinear;
		m_transmittance.enableRandomWrite = true;
		m_transmittance.Create();
		
		ComputeBuffer buffer = new ComputeBuffer(TRANSMITTANCE_WIDTH*TRANSMITTANCE_HEIGHT, sizeof(float)*TRANSMITTANCE_CHANNELS);
		
		CBUtility.WriteIntoRenderTexture(m_transmittance, TRANSMITTANCE_CHANNELS, path, buffer, m_writeData);
		
		buffer.Release();
		
		//Iirradiance is responsible for the change in the sky color as the sun moves
		//The raw file is a 2D array of 32 bit floats with a range of 0 to 1
		path = Application.dataPath + "/Textures/irradiance.raw";
		
		m_irradiance = new RenderTexture(IRRADIANCE_WIDTH, IRRADIANCE_HEIGHT, 0, RenderTextureFormat.ARGBHalf);
		m_irradiance.wrapMode = TextureWrapMode.Clamp;
		m_irradiance.filterMode = FilterMode.Bilinear;
		m_irradiance.enableRandomWrite = true;
		m_irradiance.Create();
		
		buffer = new ComputeBuffer(IRRADIANCE_WIDTH*IRRADIANCE_HEIGHT, sizeof(float)*IRRADIANCE_CHANNELS);
		
		CBUtility.WriteIntoRenderTexture(m_irradiance, IRRADIANCE_CHANNELS, path, buffer, m_writeData);
		
		buffer.Release();
		
		//Inscatter is responsible for the change in the sky color as the sun moves
		//The raw file is a 4D array of 32 bit floats with a range of 0 to 1.589844
		//As there is not such thing as a 4D texture the data is packed into a 3D texture 
		//and the shader manually performs the sample for the 4th dimension
		path = Application.dataPath + "/Textures/inscatter.raw";
		
		m_inscatter = new RenderTexture(INSCATTER_WIDTH, INSCATTER_HEIGHT, 0, RenderTextureFormat.ARGBHalf);
		m_inscatter.volumeDepth = INSCATTER_DEPTH;
		m_inscatter.wrapMode = TextureWrapMode.Clamp;
		m_inscatter.filterMode = FilterMode.Bilinear;
		m_inscatter.isVolume = true;
		m_inscatter.enableRandomWrite = true;
		m_inscatter.Create();
		
		buffer = new ComputeBuffer(INSCATTER_WIDTH*INSCATTER_HEIGHT*INSCATTER_DEPTH, sizeof(float)*INSCATTER_CHANNELS);
		
		CBUtility.WriteIntoRenderTexture(m_inscatter, INSCATTER_CHANNELS, path, buffer, m_writeData);
		
		buffer.Release();
		
		InitMaterial(m_skyMapMaterial);
		InitMaterial(m_skyMaterial);
		InitMaterial(m_oceanMaterial); //ocean mat needs some of these uniforms so may as well set them here

	}
	
	void Update () 
	{
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
		
		//Consts, best leave these alone
		mat.SetFloat("M_PI", Mathf.PI);
		mat.SetFloat("SCALE", SCALE);
		mat.SetFloat("Rg", 6360.0f * SCALE);
		mat.SetFloat("Rt", 6420.0f * SCALE);
		mat.SetFloat("Rl", 6421.0f * SCALE);
		mat.SetFloat("RES_R", 32.0f);
		mat.SetFloat("RES_MU", 128.0f);
		mat.SetFloat("RES_MU_S", 32.0f);
		mat.SetFloat("RES_NU", 8.0f);
		mat.SetFloat("SUN_INTENSITY", m_sunIntensity);
		mat.SetVector("EARTH_POS", new Vector3(0.0f, 6360010.0f, 0.0f));
		mat.SetVector("SUN_DIR", m_sun.transform.forward*-1.0f);
		
	}
	
	void OnDestroy()
	{
		m_transmittance.Release();
		m_irradiance.Release();
		m_inscatter.Release();
		m_skyMap.Release();
	}
	
}

