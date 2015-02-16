Shader "Custom/HeightShader" {
	
	SubShader {
	    Pass {
	
	CGPROGRAM
	#pragma vertex vert
	#pragma fragment frag
	#include "UnityCG.cginc"
	
	struct v2f {
	    float4 pos : SV_POSITION;
	    float height : TEXCOORD0;
	};
	
	v2f vert (appdata_base v)
	{
	    v2f o;
	    o.pos = mul (UNITY_MATRIX_MVP, v.vertex);
	    o.height = mul (_Object2World, v.vertex).y;
	    return o;
	}
	
	float4 frag (v2f i) : COLOR
	{
	    return float4(i.height, i.height, i.height, 1.0);
	}
	ENDCG
	
	    }
	}

	FallBack "Diffuse"
}
