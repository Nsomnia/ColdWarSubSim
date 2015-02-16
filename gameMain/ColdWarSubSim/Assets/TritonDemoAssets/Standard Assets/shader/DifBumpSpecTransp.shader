Shader "Dif_Spec_Transp" {
Properties {
	_Color ("Diffuse Color", Color) = (1,1,1,1)
	_MainTex ("Diffuse Map (RGB)", 2D) = "white" {}	
	_SpecColor ("Specular Color", Color) = (0.5, 0.5, 0.5, 0)
	_Shininess ("Shininess", Range (0.01, 1)) = 0.078125
	_SpecMap ("Specular Map (RGB)", 2D) = "white" {}
	_TranspMap ("Transp Map (R)", 2D) = "white" {}
	_Cutoff ("Alpha cutoff", Range(0,1)) = 0.5
}

SubShader {
	Tags {"Queue"="AlphaTest" "IgnoreProjector"="True" "RenderType"="TransparentCutout"}
	LOD 400
	
	
CGPROGRAM
#pragma surface surf BlinnPhong alphatest:_Cutoff

sampler2D _MainTex;
sampler2D _BumpMap;
fixed4 _Color;
half _Shininess;
sampler2D _SpecMap;
sampler2D _TranspMap;

struct Input {
	float2 uv_MainTex;
	float2 uv_SpecMap;
	float2 uv_TranspMap;
};

void surf (Input IN, inout SurfaceOutput o) {
	fixed4 tex = tex2D(_MainTex, IN.uv_MainTex);
	fixed4 spec = tex2D(_SpecMap, IN.uv_SpecMap);
	fixed4 transp = tex2D(_TranspMap, IN.uv_TranspMap);
	_SpecColor = _SpecColor*spec;
	o.Albedo = tex.rgb * _Color.rgb;
	o.Gloss = spec.r;
	o.Alpha = transp.r * _Color.a;
	o.Specular = _Shininess;

}
ENDCG
}

FallBack "Transparent/VertexLit"
}