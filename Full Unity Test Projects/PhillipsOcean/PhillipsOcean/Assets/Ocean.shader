Shader "Ocean/Ocean" 
{
	Properties 
	{
		_SeaColor("SeaColor", Color) = (1,1,1,1)
		_SkyBox("SkyBox", CUBE) = "" {}
	}
	SubShader 
	{
		Tags { "RenderType"="Opaque" }
		LOD 200
		
		CGPROGRAM
		#pragma surface surf Lambert

		float3 _SeaColor;
		samplerCUBE _SkyBox;
		uniform sampler2D _FresnelLookUp;
		
		struct Input 
		{
			float3 worldNormal;
			float3 worldPos;
			float3 worldRefl;
		};
		
		float Fresnel(float3 V, float3 N)
		{
			float costhetai = abs(dot(V, N));
			return tex2D(_FresnelLookUp, float2(costhetai, 0.0)).a;
		}

		void surf (Input IN, inout SurfaceOutput o) 
		{
			float3 V = normalize(_WorldSpaceCameraPos-IN.worldPos);
			float3 N = IN.worldNormal;
		
			float fresnel = Fresnel(V, N);
			
			float3 skyColor = texCUBE(_SkyBox, WorldReflectionVector(IN, N)*float3(-1,1,1)).rgb;
		
			o.Albedo = lerp(_SeaColor, skyColor, fresnel);
			o.Alpha = 1.0;
		}
		ENDCG
	} 
	FallBack "Diffuse"
}















