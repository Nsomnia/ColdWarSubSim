
Shader "Ocean/OceanWireframe" 
{
	Properties
	{
		_WireColor("WireColor", Color) = (1,1,1,0.1)
	}
	SubShader 
	{
    	Pass 
    	{
    		Tags {"Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent"}
    		ZWrite Off
			Blend SrcAlpha OneMinusSrcAlpha 
		
			CGPROGRAM
			#include "UnityCG.cginc"
			#pragma target 4.0
			#pragma vertex vert
			#pragma fragment frag
			//#pragma glsl

			uniform sampler2D _Map0, _Map3, _Map4;
			uniform float4 _GridSizes, _Choppyness;
			uniform float _MaxLod, _LodFadeDist;
			
			float4 _WireColor;
		
			struct v2f 
			{
    			float4  pos : SV_POSITION;
			};

			v2f vert(appdata_base v)
			{
				float3 worldPos = mul(_Object2World, v.vertex).xyz;
			
				float dist = clamp(distance(_WorldSpaceCameraPos.xyz, worldPos) / _LodFadeDist, 0.0, 1.0);
				float lod = _MaxLod * dist;
				//lod = 0.0;
				
				float2 uv = worldPos.xz;

				v.vertex.y += tex2Dlod(_Map0, float4(uv/_GridSizes.x, 0, lod)).x;
				v.vertex.y += tex2Dlod(_Map0, float4(uv/_GridSizes.y, 0, lod)).y;
				v.vertex.y += tex2Dlod(_Map0, float4(uv/_GridSizes.z, 0, lod)).z;
				v.vertex.y += tex2Dlod(_Map0, float4(uv/_GridSizes.w, 0, lod)).w;
	
				v.vertex.xz += tex2Dlod(_Map3, float4(uv/_GridSizes.x, 0, lod)).xy * _Choppyness.x;
				v.vertex.xz += tex2Dlod(_Map3, float4(uv/_GridSizes.y, 0, lod)).zw * _Choppyness.y;
				v.vertex.xz += tex2Dlod(_Map4, float4(uv/_GridSizes.z, 0, lod)).xy * _Choppyness.z;
				v.vertex.xz += tex2Dlod(_Map4, float4(uv/_GridSizes.w, 0, lod)).zw * _Choppyness.w;
			
    			v2f OUT;
    			OUT.pos = mul(UNITY_MATRIX_MVP, v.vertex);
    			return OUT;
			}
			
			float4 frag(v2f IN) : COLOR
			{
				return _WireColor;
			}
			
			ENDCG

    	}
	}
}