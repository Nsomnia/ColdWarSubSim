
// Real-time Realistic Ocean Lighting using Seamless Transitions from Geometry to BRDF
// Copyright (c) 2009 INRIA
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Neither the name of the copyright holders nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
// THE POSSIBILITY OF SUCH DAMAGE.
//
// Author: Eric Bruneton
//
// Modified and ported to Unity by Justin hawkins 04/06/2013
 
Shader "Ocean/OceanWhiteCaps" 
{
	SubShader 
	{
		
    	Pass 
    	{
    		Tags { "RenderType"="Opaque" }
    		
			CGPROGRAM
			#include "UnityCG.cginc"
			#pragma target 4.0
			#pragma vertex vert
			#pragma fragment frag
			#include "Atmosphere.cginc"

			uniform sampler2D _Map0, _Map1, _Map2, _Map3, _Map4;
			uniform sampler2D _SkyMap, _Foam0, _Foam1;
			uniform sampler3D _Variance; 
			uniform float4 _GridSizes, _Choppyness;
			uniform float3 _SeaColor;
			uniform float _MaxLod, _LodFadeDist, _WhiteCapStr;
			
			struct v2f 
			{
    			float4  pos : SV_POSITION;
    			float3 worldPos : TEXCOORD;
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
    			OUT.worldPos = mul(_Object2World, v.vertex).xyz;
    			OUT.pos = mul(UNITY_MATRIX_MVP, v.vertex);
    			return OUT;
			}
			
			float meanFresnel(float cosThetaV, float sigmaV) 
			{
				return pow(1.0 - cosThetaV, 5.0 * exp(-2.69 * sigmaV)) / (1.0 + 22.7 * pow(sigmaV, 1.5));
			}
			
			// V, N in world space
			float MeanFresnel(float3 V, float3 N, float2 sigmaSq) 
			{
			    float2 v = V.xz; // view direction in wind space
			    float2 t = v * v / (1.0 - V.y * V.y); // cos^2 and sin^2 of view direction
			    float sigmaV2 = dot(t, sigmaSq); // slope variance in view direction
			    return meanFresnel(dot(V, N), sqrt(sigmaV2));
			}
			
			// assumes x>0
			float erfc(float x) 
			{
				return 2.0 * exp(-x * x) / (2.319 * x + sqrt(4.0 + 1.52 * x * x));
			}
			
			float erf(float x) 
			{
				float a  = 0.140012;
				float x2 = x*x;
				float ax2 = a*x2;
				return sign(x) * sqrt( 1.0 - exp(-x2*(4.0/M_PI + ax2)/(1.0 + ax2)) );
			}
			
			float Lambda(float cosTheta, float sigmaSq) 
			{
				float v = cosTheta / sqrt((1.0 - cosTheta * cosTheta) * (2.0 * sigmaSq));
			    return max(0.0, (exp(-v * v) - v * sqrt(M_PI) * erfc(v)) / (2.0 * v * sqrt(M_PI)));
				//return (exp(-v * v)) / (2.0 * v * sqrt(M_PI)); // approximate, faster formula
			}

			// L, V, N, Tx, Ty in world space
			float ReflectedSunRadiance(float3 L, float3 V, float3 N, float3 Tx, float3 Ty, float2 sigmaSq) 
			{
			    float3 H = normalize(L + V);
			    float zetax = dot(H, Tx) / dot(H, N);
			    float zetay = dot(H, Ty) / dot(H, N);
			
			    float zL = dot(L, N); // cos of source zenith angle
			    float zV = dot(V, N); // cos of receiver zenith angle
			    float zH = dot(H, N); // cos of facet normal zenith angle
			    float zH2 = zH * zH;
			
			    float p = exp(-0.5 * (zetax * zetax / sigmaSq.x + zetay * zetay / sigmaSq.y)) / (2.0 * M_PI * sqrt(sigmaSq.x * sigmaSq.y));
			
			    float tanV = atan2(dot(V, Ty), dot(V, Tx));
			    float cosV2 = 1.0 / (1.0 + tanV * tanV);
			    float sigmaV2 = sigmaSq.x * cosV2 + sigmaSq.y * (1.0 - cosV2);
			
			    float tanL = atan2(dot(L, Ty), dot(L, Tx));
			    float cosL2 = 1.0 / (1.0 + tanL * tanL);
			    float sigmaL2 = sigmaSq.x * cosL2 + sigmaSq.y * (1.0 - cosL2);
			
			    float fresnel = 0.02 + 0.98 * pow(1.0 - dot(V, H), 5.0);
			
			    zL = max(zL, 0.01);
			    zV = max(zV, 0.01);
			
			    return fresnel * p / ((1.0 + Lambda(zL, sigmaL2) + Lambda(zV, sigmaV2)) * zV * zH2 * zH2 * 4.0);

			}
			
			// V, N, Tx, Ty in world space
			float2 U(float2 zeta, float3 V, float3 N, float3 Tx, float3 Ty) 
			{
			    float3 f = normalize(float3(-zeta, 1.0)); // tangent space
			    float3 F = f.x * Tx + f.y * Ty + f.z * N; // world space
			    float3 R = 2.0 * dot(F, V) * F - V;
			    return R.xz / (1.0 + R.y);
			}
			
			// V, N, Tx, Ty in world space;
			float3 MeanSkyRadiance(float3 V, float3 N, float3 Tx, float3 Ty, float2 sigmaSq) 
			{
			    float4 result;
			
			    const float eps = 0.001;
			    float2 u0 = U(float2(0,0), V, N, Tx, Ty);
			    float2 dux = 2.0 * (U(float2(eps, 0.0), V, N, Tx, Ty) - u0) / eps * sqrt(sigmaSq.x);
			    float2 duy = 2.0 * (U(float2(0.0, eps), V, N, Tx, Ty) - u0) / eps * sqrt(sigmaSq.y);
			
			    result = tex2D(_SkyMap, u0 * (0.5 / 1.1) + 0.5, dux * (0.5 / 1.1), duy * (0.5 / 1.1));

			    //if texture2DLod and texture2DGrad are not defined, you can use this (no filtering):
			    //result = tex2D(_SkyMap, u0 * (0.5 / 1.1) + 0.5);
			
			    return result.rgb;
			}
			
			float whitecapCoverage(float epsilon, float mu, float sigma2) {
				return 0.5*erf((0.5*sqrt(2.0)*(epsilon-mu)*(1.0/sqrt(sigma2)))) + 0.5;
			}
			
			float4 frag(v2f IN) : COLOR
			{

				float2 uv = IN.worldPos.xz;
				
				float2 slope = float2(0,0);
				slope += tex2D(_Map1, uv/_GridSizes.x).xy;
				slope += tex2D(_Map1, uv/_GridSizes.y).zw;
				slope += tex2D(_Map2, uv/_GridSizes.z).xy;
				slope += tex2D(_Map2, uv/_GridSizes.w).zw;
						
			    float3 V = normalize(_WorldSpaceCameraPos-IN.worldPos);

			    float3 N = normalize(float3(-slope.x, 1.0, -slope.y));

			    if (dot(V, N) < 0.0) {
			       N = reflect(N, V); // reflects backfacing normals
			    }
			    
			    float Jxx, Jxy, Jyy, Jyx;
			    
			    Jxx = ddx(uv.x);
			    Jxy = ddy(uv.x);
			    Jyx = ddx(uv.y);
			    Jyy = ddy(uv.y);
			    float A = Jxx * Jxx + Jyx * Jyx;
			    float B = Jxx * Jxy + Jyx * Jyy;
			    float C = Jxy * Jxy + Jyy * Jyy;
			    const float SCALE = 10.0;
			    float ua = pow(A / SCALE, 0.25);
			    float ub = 0.5 + 0.5 * B / sqrt(A * C);
			    float uc = pow(C / SCALE, 0.25);
			    float2 sigmaSq = tex3D(_Variance, float3(ua, ub, uc)).xy;
			
			    sigmaSq = max(sigmaSq, 2e-5);
			    
			    float3 Ty = normalize(float3(0.0, N.z, -N.y));
			    float3 Tx = cross(Ty, N);
			    
			    float fresnel = 0.02 + 0.98 * MeanFresnel(V, N, sigmaSq);
			    
			    float3 Lsun = SunRadiance(_WorldSpaceCameraPos);
			    float3 Esky = SkyIrradiance(_WorldSpaceCameraPos);
			    
			    float3 col = float3(0,0,0);
			    
			    col += ReflectedSunRadiance(SUN_DIR, V, N, Tx, Ty, sigmaSq) * Lsun;
			    
			    col += MeanSkyRadiance(V, N, Tx, Ty, sigmaSq) * fresnel;
			    
			    float3 Lsea = _SeaColor * Esky / M_PI;
    			col +=  Lsea * (1.0 - fresnel);
    			
				// extract mean and variance of the jacobian matrix determinant
				float2 jm1 = tex2D(_Foam0, uv/_GridSizes.x).xy;
				float2 jm2 = tex2D(_Foam0, uv/_GridSizes.y).zw;
				float2 jm3 = tex2D(_Foam1, uv/_GridSizes.z).xy;
				float2 jm4 = tex2D(_Foam1, uv/_GridSizes.w).zw;
				float2 jm  = jm1+jm2+jm3+jm4;
				float jSigma2 = max(jm.y - (jm1.x*jm1.x + jm2.x*jm2.x + jm3.x*jm3.x + jm4.x*jm4.x), 0.0);

				// get coverage
				float W = whitecapCoverage(_WhiteCapStr,jm.x,jSigma2);
			
				// compute and add whitecap radiance
				float3 l = (Lsun * (max(dot(N, SUN_DIR), 0.0)) + Esky) / M_PI;
				float3 R_ftot = float3(W * l * 0.4);
				col += R_ftot;
    
				return float4(hdr(col),1.0);
			}
			
			ENDCG

    	}
	}
}