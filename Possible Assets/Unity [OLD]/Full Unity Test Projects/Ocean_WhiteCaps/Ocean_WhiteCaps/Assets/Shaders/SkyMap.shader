
Shader "Atmosphere/SkyMap" 
{
	SubShader 
	{
    	Pass 
    	{
    	    ZTest Always 

			CGPROGRAM
			#include "UnityCG.cginc"
			#pragma target 4.0
			#pragma vertex vert
			#pragma fragment frag
			#include "Atmosphere.cginc"
		
			struct v2f 
			{
    			float4  pos : SV_POSITION;
    			float2  uv : TEXCOORD0;
			};

			v2f vert(appdata_base v)
			{
    			v2f OUT;
    			OUT.pos = mul(UNITY_MATRIX_MVP, v.vertex);
    			OUT.uv = (v.texcoord.xy-0.5)*2.2;
    			return OUT;
			}
			
			float4 frag(v2f IN) : COLOR
			{
			
			   	float2 u = IN.uv;

			   	float l = dot(u, u);
			    float3 result = float3(0,0,0);
			    
		    	if (l <= 1.02 && l > 1.0) 
				{
		            u = u / l;
		            l = 1.0 / l;
		        }
		
		        // inverse stereographic projection,
		        // from skymap coordinates to world space directions
		        float3 r = float3(2.0 * u, 1.0 - l) / (1.0 + l);
		        
		        float3 extinction;
		        float3 inscatter = SkyRadiance(_WorldSpaceCameraPos, r.xzy, extinction);
		        float3 Esky = SkyIrradiance(EARTH_POS.y, SUN_DIR.y);
		       
			    if (l <= 1.02) 
				{
			        result.rgb = inscatter;
			   	}
			   	else
			   	{
			   		float avgFresnel = 0.17;
			   		result.rgb = Esky / M_PI * avgFresnel;
			   	}
			   	
			   	float3 col = result;

				return float4(col,1.0);
			
			}
			
			ENDCG

    	}
	}
}