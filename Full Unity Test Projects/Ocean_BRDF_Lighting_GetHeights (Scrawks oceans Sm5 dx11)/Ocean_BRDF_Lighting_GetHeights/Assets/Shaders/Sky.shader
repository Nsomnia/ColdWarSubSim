
Shader "Atmosphere/Sky" 
{
	SubShader 
	{
		
    	Pass 
    	{
    		Tags { "RenderType"="Opaque" }
    		//ZWrite Off
			Cull Front
			
			CGPROGRAM
			#include "UnityCG.cginc"
			#pragma target 4.0
			#pragma vertex vert
			#pragma fragment frag
			#include "Atmosphere.cginc"
			
			uniform float _Horizon;
		
			struct v2f 
			{
    			float4  pos : SV_POSITION;
    			float2  uv : TEXCOORD0;
    			float3 worldPos : TEXCOORD1;
			};

			v2f vert(appdata_base v)
			{
    			v2f OUT;
    			OUT.pos = mul(UNITY_MATRIX_MVP, v.vertex);
    			OUT.worldPos = mul(_Object2World, v.vertex).xyz;
    			OUT.worldPos.y -= _Horizon;
    			OUT.uv = v.texcoord.xy;
    			return OUT;
			}
			
			float4 frag(v2f IN) : COLOR
			{
				float3 pos = _WorldSpaceCameraPos;
			    pos.y = 0.0;

			    float3 dir = normalize(IN.worldPos-pos);
			    
			    float sun = step(cos(M_PI / 360.0), dot(dir, SUN_DIR));
			    
			    float3 sunColor = float3(sun,sun,sun) * SUN_INTENSITY;
			    
				float3 extinction;
				float3 inscatter = SkyRadiance(_WorldSpaceCameraPos, dir, extinction);
				float3 col = sunColor * extinction + inscatter;
		
				return float4(hdr(col), 1.0);
			}
			
			ENDCG

    	}
	}
}