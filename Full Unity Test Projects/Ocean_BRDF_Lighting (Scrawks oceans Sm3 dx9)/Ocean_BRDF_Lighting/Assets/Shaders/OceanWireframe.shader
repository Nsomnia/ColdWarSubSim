
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
			#pragma target 3.0
			#pragma vertex vert
			#pragma fragment frag
			#pragma glsl

			uniform sampler2D _Map0;
			uniform float4 _GridSizes;
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
				
				float ht = 0.0;
				ht += tex2Dlod(_Map0, float4(worldPos.xz/_GridSizes.x, 0, lod)).x;
				ht += tex2Dlod(_Map0, float4(worldPos.xz/_GridSizes.y, 0, lod)).y;
				//ht += tex2Dlod(_Map0, float4(worldPos.xz/_GridSizes.z, 0, lod)).z;
				//ht += tex2Dlod(_Map0, float4(worldPos.xz/_GridSizes.w, 0, lod)).w;
	
				v.vertex.y += ht;
			
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