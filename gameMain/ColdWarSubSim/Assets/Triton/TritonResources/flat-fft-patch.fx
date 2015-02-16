#ifdef PS30
#define DETAIL
#endif
#define DETAIL_OCTAVE 8.0
#define DETAIL_BLEND 0.3

uniform float3 L;
uniform float3 lightColor;
uniform float3 ambientColor;
uniform float3 refractColor;
uniform float shininess;
uniform float4x4 modelview;
uniform float4x4 projection;
uniform float depthOffset;
uniform float4x4 invModelviewProj;
uniform float4 plane;
uniform float3x3 basis;
uniform float3x3 invBasis;
uniform float3 cameraPos;
uniform float4x4 gridScale;
uniform float antiAliasing;
uniform float gridSize;
uniform float2 textureSize;
uniform float foamScale;
uniform bool hasEnvMap;
uniform float fogDensity;
uniform float3 fogColor;
uniform float fogDensityBelow;
uniform float noiseAmplitude;
uniform float3x3 cubeMapMatrix;
uniform float invNoiseDistance;
uniform float invDampingDistance;
uniform bool doWakes;
uniform bool hasPlanarReflectionMap;
uniform float3x3 planarReflectionMapMatrix;
uniform float planarReflectionDisplacementScale;
uniform float3 floorPlanePoint;
uniform float3 floorPlaneNormal;
uniform float foamBlend;
uniform float washLength;
uniform float textureLODBias;
uniform float4x4 modelMatrix;
uniform float planarReflectionBlend;

uniform bool hasHeightMap;
uniform float time;
uniform float seaLevel;
uniform float4x4 heightMapMatrix;

uniform bool depthOnly;

#ifdef BREAKING_WAVES
uniform float kexp;
uniform float breakerWavelength;
uniform float breakerWavelengthVariance;
uniform float4 breakerDirection;
uniform float breakerAmplitude;
uniform float breakerPhaseConstant;
uniform float surgeDepth;
uniform float steepnessVariance;
#endif

#define TWOPI (2.0 * 3.14159265)

struct CircularWave {
    float amplitude;
    float radius;
    float k;
    float halfWavelength;
    float3 position;
};

struct KelvinWake {
    float amplitude;
    float3 position;
    float3 shipPosition;
};

#ifdef PROPELLER_WASH
struct PropWash {
    float3 deltaPos;
    float washWidth;
    float3 propPosition;
    float distFromSource;
    float washLength;
};

uniform PropWash washes[MAX_PROP_WASHES];
#endif

uniform CircularWave circularWaves[MAX_CIRCULAR_WAVES];

uniform KelvinWake wakes[MAX_KELVIN_WAKES];

#ifdef DX9
TEXTURE displacementTexture; // Kelvin wakes
TEXTURE displacementMap; // FFT waves
TEXTURE slopeFoamMap;
TEXTURE cubeMap;
TEXTURE foamTex;
TEXTURE noiseTex;
TEXTURE washTex;
TEXTURE planarReflectionMap;
TEXTURE heightMap;

sampler2D gDisplacementSampler = sampler_state {
    Texture = (displacementMap);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

sampler2D gDisplacementTextureSampler = sampler_state {
    Texture = (displacementTexture);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

sampler2D gHeightSampler = sampler_state {
    Texture = (heightMap);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

sampler2D gSlopeFoamSampler = sampler_state {
    Texture = (slopeFoamMap);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

samplerCUBE gCubeSampler = sampler_state {
    Texture = (cubeMap);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
    AddressW = CLAMP;
};

sampler2D gFoamSampler = sampler_state {
    Texture = (foamTex);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

sampler2D gWashSampler = sampler_state {
    Texture = (washTex);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = CLAMP;
    AddressV = WRAP;
};

sampler2D gNoiseSampler = sampler_state {
    Texture = (noiseTex);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

sampler2D gPlanarReflectionSampler = sampler_state {
    Texture = (planarReflectionMap);
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

#else

Texture2D displacementTexture;
Texture2D displacementMap;
Texture2D slopeFoamMap;
TextureCube cubeMap;
Texture2D foamTex;
Texture2D noiseTex;
Texture2D washTex;
Texture2D planarReflectionMap;
Texture2D heightMap;

SamplerState gBiLinearSamClamp {
    Filter = MIN_MAG_LINEAR_MIP_POINT;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

SamplerState gTriLinearSamWrap {
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

SamplerState gTriLinearSamWash {
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = CLAMP;
    AddressV = WRAP;
};

#endif

void computeTransparency(in float3 worldPos, inout float4 transparencyDepthBreakers)
{
    float depth = 1000.0;
    // Compute depth at this position
    if (hasHeightMap) {

        float4 texCoords = mul(float4(worldPos, 1.0), heightMapMatrix);

        if (texCoords.x >= 0 && texCoords.x <= 1.0 && texCoords.y >= 0 && texCoords.y <= 1.0) {
            float4 tc4 = float4(texCoords.x, texCoords.y, 0.0f, 0.0f);

#ifdef DX9
            float height = tex2Dlod(gHeightSampler, tc4).x;
#else
            float height = heightMap.SampleLevel(gBiLinearSamClamp, texCoords, 0).x;
#endif

            depth = -(height - seaLevel);
        }
    } else {
        float3 up = mul(float3(0, 0, 1), invBasis);
        float3 l = -up;
        float3 l0 = worldPos;
        float3 n = floorPlaneNormal;
        float3 p0 = floorPlanePoint;
        float numerator = dot((p0 - l0), n);
        float denominator = dot(l, n);
        if (denominator != 0.0) {
            depth = numerator / denominator;
        }
    }

    // Compute fog at this distance underwater
    float fogExponent = abs(depth) * fogDensityBelow;
    float transparency = clamp(exp(-abs(fogExponent)), 0.0, 1.0);

    transparencyDepthBreakers.xy = float2(transparency, depth);
}

void applyBreakingWaves(inout float3 v, inout float4 transparencyDepthBreakers)
{
#ifdef BREAKING_WAVES
    float breaker = 0;
    float depth = transparencyDepthBreakers.y;

    if (hasHeightMap && depth > 0 && depth < breakerWavelength * 0.5) {
        float clampedDepth = max(1.0, depth);

        float surgeTerm = ((10.0 * (max(surgeDepth, clampedDepth)) + (clampedDepth)));

        float halfWavelength = breakerWavelength * 0.5;
        float scaleFactor = ((clampedDepth - halfWavelength) / halfWavelength);
        float wavelength = breakerWavelength + (scaleFactor + surgeTerm) * breakerWavelengthVariance;

        float breakHeight = 0.75 * depth;

        float halfKexp = kexp * 0.5;
        scaleFactor = (clampedDepth - halfKexp) / halfKexp;
        scaleFactor *= 1.0 + steepnessVariance;
        float k = kexp + scaleFactor;
        float3 localDir = mul(breakerDirection.xyz, basis);
        float dotResult = dot(localDir.xy, v.xy) * TWOPI / wavelength;

        float finalz = (dotResult + breakerPhaseConstant * time);
        finalz = (sin(finalz) + 1.0) * 0.5;
        finalz = breakerAmplitude * pow(finalz, k);

        if (breakerAmplitude > breakHeight) {
            finalz = min(finalz, depth);
            breaker = finalz / breakerAmplitude;
        } else {
            breaker = finalz / breakHeight;
        }
        // Hide the backs of waves if we're transparent
        float opacity = 1.0 - transparencyDepthBreakers.x;
        finalz = lerp(0.0, finalz, pow(opacity, 6.0));
        v.z += finalz;
    }
    transparencyDepthBreakers.z = breaker;
#endif
}
void applyCircularWaves(inout float3 v, in float fade, out float2 slope, out float foam)
{
    int i;

    slope = float2(0.0, 0.0);
    float disp = 0.0;

    for (i = 0; i < MAX_CIRCULAR_WAVES; i++) {

        float2 D = (v - circularWaves[i].position).xy;
        float dist = length(D);

        float r = dist - circularWaves[i].radius;
        if (abs(r) < circularWaves[i].halfWavelength) {

            float amplitude = circularWaves[i].amplitude;

            float theta = circularWaves[i].k * r;
            disp += amplitude * cos(theta);
            float derivative = amplitude * -cos(theta);
            slope +=  D * (derivative / dist);
        }
    }

    v.z += disp * fade;

    foam = length(slope);
    slope *= fade;
}

void applyKelvinWakes(inout float3 v, in float fade, inout float2 slopeAccum, inout float foam)
{
    int i;
#ifdef KELVIN_WAKES
    float2 slope = float2(0.0, 0.0);
    float disp = 0.0;

    for (i = 0; i < MAX_KELVIN_WAKES; i++) {

        float3 X0 = wakes[i].position - wakes[i].shipPosition;
        float3 T = normalize(X0);
        float3 N = float3(0,0,1);
        float3 B = normalize(cross(N, T));

        float3 P = v - wakes[i].shipPosition;
        float3 X;
        X.x = dot(P.xy, T.xy);
        X.y = dot(P.xy, B.xy);

        float xLen = length(X0);
        float2 tc;
        tc.x = X.x / (1.54 * xLen);
        tc.y = (X.y) / (1.54 * xLen) + 0.5;

        if (tc.x >= 0.01 && tc.x <= 0.99 && tc.y >= 0.01 && tc.y <= 0.99) {
#ifdef DX9
            float4 tc4 = float4(tc.x, tc.y, 0.0f, 0.0f);
            float4 sample = tex2Dlod(gDisplacementTextureSampler, tc4);
#else
            float4 sample = displacementTexture.SampleLevel(gTriLinearSamWrap, tc, 0);
#endif

            float displacement = sample.w;

            displacement *= min(1.0, wakes[i].amplitude);

            float3 normal = normalize(sample.xyz * 2.0 - 1.0);
            float invmax = rsqrt( max( dot(T,T), dot(B,B) ) );
            float3x3 TBN = float3x3( T * invmax, B * invmax, N );

            normal = mul(TBN, normal);
            normal.xy *= wakes[i].amplitude;
            normal = normalize(normal);

            disp += displacement;
            if (normal.z != 0) {
                slope.x += normal.x / normal.z;
                slope.y += normal.y / normal.z;
            }
        }
    }

    v.z += disp * fade;

    foam += min(1.0, length(slope));
    slopeAccum += slope * fade;
#endif
}

void applyPropWash(in float3 v, out float3 washTexCoords)
{
    washTexCoords = float3(0.0, 0.0, 0.0);

#ifdef PROPELLER_WASH

    for (int i = 0; i < MAX_PROP_WASHES; i++) {

        if (washes[i].distFromSource == 0) continue;

        float3 C = washes[i].deltaPos;
        float3 A = v - washes[i].propPosition;
        float3 B = v - (washes[i].propPosition + C);
        float segmentLength = length(C);

        // Compute t
        float t0 = dot(C, A) / dot(C, C);

        // Compute enough overlap to account for curved paths.
        float overlap = (washes[i].washWidth / segmentLength) * 0.5;

        if (t0 >= -overlap && t0 <= 1.0 + overlap) {

            // Compute distance from source
            float distFromSource = washes[i].distFromSource - (1.0 - t0) * segmentLength;

            // Compute wash width
            float washWidth = (washes[i].washWidth * pow(distFromSource, 1.0 / 4.5)) * 0.5;

            // Compute distance to line
            float3 aCrossB = cross(A, B);
            float d = length(aCrossB) / length(C);

            // The direction of A X B indicates if we're 'left' or 'right' of the path
            float nd = d / washWidth;

            if (nd >= 0.0 && nd <= 1.0) {
                washTexCoords.x = nd;
                // The t0 parameter from our initial distance test to the line segment makes
                // for a handy t texture coordinate
                washTexCoords.y =  (washes[i].washLength - distFromSource) / washes[i].washWidth;

                //washTexCoords.x = nd;
                //washTexCoords.y =  (washes[i].washLength - distFromSource) / washes[i].washWidth;

                // We stuff the blend factor into the r coordinate.

                float blend = max(0.0, 1.0 - distFromSource / (washLength));
                float distFromCenter = d / washWidth;
                blend *= max(0.0, 1.0 - distFromCenter * distFromCenter);
                //if (washes[i].number == 0) blend *= 1.0 - clamp(t0 * t0, 0.0, 1.0);
                //blend *= smoothstep(0, 0.1, nd);
                washTexCoords.z = blend;
            }
        }
    }
#endif
}

void displace(inout float3 v, inout float2 texCoords, inout float2 foamTexCoords, inout float2 noiseTexCoords,
              out float2 slope, out float foam, out float3 washTexCoords, inout float4 transparencyDepthBreakers)
{
    // Transform so z is up
    float3 localV = mul(v, basis);

    texCoords = localV.xy / textureSize;
    float4 tc4 = float4(texCoords.x, texCoords.y, 0.0f, 0.0f);

#ifdef DX9
    float3 displacement = tex2Dlod(gDisplacementSampler, tc4).xyz;
#else
    float3 displacement = displacementMap.SampleLevel(gTriLinearSamWrap, texCoords, 0).xyz;
#endif

    float opacity = 1.0 - transparencyDepthBreakers.x;
    displacement.z = lerp(0.0, displacement.z, pow(opacity, 6.0));

    float fade = 1.0 - smoothstep(0.0, 1.0, length(v - cameraPos) * invDampingDistance);

#ifdef BREAKING_WAVES
    // Fade out waves in the surge zone
    float depthFade = 1.0;

    if (surgeDepth > 0) {
        depthFade = min(surgeDepth, transparencyDepthBreakers.y) / surgeDepth;
    }

    fade *= depthFade;
    transparencyDepthBreakers.w = depthFade;
#endif

    localV.xy += displacement.xy * fade;

    if (doWakes) {
        slope = float2(0,0);
        applyCircularWaves(localV, fade, slope, foam);
        applyKelvinWakes(localV, fade, slope, foam);
        applyPropWash(localV, washTexCoords);
    } else {
        washTexCoords = float3(0.0, 0.0, 0.0);
        slope = float2( 0.f, 0.f );
        foam = 0.f;
    }

    localV.z += displacement.z * fade;

    applyBreakingWaves(localV, transparencyDepthBreakers);

    foamTexCoords = localV.xy / foamScale;
    noiseTexCoords = texCoords * 0.03f;

    v = mul(localV, invBasis);
}


#ifdef DX9
void VS( float4 position : POSITION,

         out float4 oPosition : POSITION0,
         out float2 texCoords : TEXCOORD0,
         out float2 foamTexCoords : TEXCOORD1,
         out float2 noiseTexCoords : TEXCOORD2,
         out float4 V : TEXCOORD3,
         out float4  transparencyDepthBreakers : TEXCOORD4,
         out float3 wakeSlopesAndFoam : TEXCOORD5,
         out float  fogFactor : TEXCOORD6,
         out float3 washTexCoords : TEXCOORD7
       )
#else
void VS( float4 position : POSITION,

         out float4 oPosition : SV_POSITION,
         out float2 texCoords : TEXCOORD0,
         out float2 foamTexCoords : TEXCOORD1,
         out float2 noiseTexCoords : TEXCOORD2,
         out float4 V : TEXCOORD3,
         out float4  transparencyDepthBreakers : TEXCOORD4,
         out float3 wakeSlopesAndFoam : TEXCOORD5,
         out float  fogFactor : FOG,
         out float3 washTexCoords : TEXCOORD6
       )
#endif
{
    float4 worldPos = mul(position, modelMatrix);

    wakeSlopesAndFoam = float3( 0.f, 0.f, 0.f );
    transparencyDepthBreakers = float4(0.0f, 0.0f, 0.0f, 0.0f);

    // Displace
    float2 slope;
    float foam;

    computeTransparency(worldPos.xyz, transparencyDepthBreakers);

    displace(worldPos.xyz, texCoords, foamTexCoords, noiseTexCoords, slope, foam, washTexCoords, transparencyDepthBreakers);
    wakeSlopesAndFoam.xy = slope;
    wakeSlopesAndFoam.z = foam;

    float3 V3 = (worldPos.xyz - cameraPos);

    // Project it back again, apply depth offset.
    float4 v = mul(worldPos, modelview);
    v.w -= depthOffset;
    oPosition = mul(v, projection);

    V = float4(V3.x, V3.y, V3.z, oPosition.z / oPosition.w);

    float fogExponent = length(V.xyz) * fogDensity;
    fogFactor = saturate(exp(-abs(fogExponent)));
}

#ifdef DX9
float4 PS(float2 texCoords : TEXCOORD0,
          float2 foamTexCoords : TEXCOORD1,
          float2 noiseTexCoords : TEXCOORD2,
          float4 V : TEXCOORD3,
          float4 transparencyDepthBreakers : TEXCOORD4,
          float3 wakeSlopesAndFoam : TEXCOORD5,
          float  fogFactor : TEXCOORD6,
          float3 washTexCoords : TEXCOORD7 ) : COLOR {
#else
float4 PS(float4 posH : SV_POSITION,
float2 texCoords : TEXCOORD0,
float2 foamTexCoords : TEXCOORD1,
float2 noiseTexCoords : TEXCOORD2,
float4 V : TEXCOORD3,
float4  transparencyDepthBreakers : TEXCOORD4,
float3 wakeSlopesAndFoam : TEXCOORD5,
float  fogFactor : FOG,
float3 washTexCoords : TEXCOORD6 ) : SV_TARGET {
#endif

    if (hasHeightMap && transparencyDepthBreakers.y < 0) {
        discard;
    }

#ifdef PS30
    if (depthOnly) {
        return float4(V.w, V.w, V.w, 1.0);
    }
#endif

    const float IOR = 1.33333f;

    float tileFade = exp(-length(V.xyz) * invNoiseDistance);

    float3 vNorm = normalize(V.xyz);

#ifdef DX9
    float4 tc = float4(texCoords.x, texCoords.y, 0.0, textureLODBias);
    float3 slopesAndFoam = tex2Dbias(gSlopeFoamSampler, tc).xyz;
#ifdef DETAIL
    tc.xy *= DETAIL_OCTAVE;
    slopesAndFoam += tex2Dbias(gSlopeFoamSampler, tc).xyz * DETAIL_BLEND;
#endif
    float3 normalNoise = (tex2D(gNoiseSampler, noiseTexCoords).xyz - float3(0.5f, 0.5f, 0.5f)) * noiseAmplitude;
#else
    float3 slopesAndFoam = slopeFoamMap.SampleBias(gTriLinearSamWrap, texCoords, textureLODBias).xyz;
#ifdef DETAIL
    slopesAndFoam += slopeFoamMap.SampleBias(gTriLinearSamWrap, texCoords * DETAIL_OCTAVE, textureLODBias).xyz * DETAIL_BLEND;
#endif
    float3 normalNoise = (noiseTex.Sample(gTriLinearSamWrap, noiseTexCoords).xyz - float3(0.5f, 0.5f, 0.5f)) * noiseAmplitude;
#endif

#ifdef BREAKING_WAVES
    float breakerFade = transparencyDepthBreakers.w;
    float3 sx = float3(1.0f, 0.0f, lerp(0.0, slopesAndFoam.x, breakerFade) + wakeSlopesAndFoam.x);
    float3 sy = float3(0.0f, 1.0f, lerp(0.0, slopesAndFoam.y, breakerFade) + wakeSlopesAndFoam.y);
#else
    float3 sx = float3(1.0f, 0.0f, slopesAndFoam.x + wakeSlopesAndFoam.x);
    float3 sy = float3(0.0f, 1.0f, slopesAndFoam.y + wakeSlopesAndFoam.y);
#endif

    float3 nNorm = mul(normalize(normalize(cross(sx, sy)) + (normalNoise * (1.0f - tileFade))), invBasis);

    float3 P = reflect(vNorm, nNorm);

    float3 S = refract(P, nNorm, 1.0 / IOR);

#ifdef PS30
    // We don't need no stinkin Fresnel approximation, do it for real

    float cos_theta1 = (dot(P, nNorm));
    float cos_theta2 = (dot(S, -nNorm));

    float Fp = (cos_theta1 - (IOR * cos_theta2)) /
    (cos_theta1 + (IOR * cos_theta2));
    float Fs = (cos_theta2 - (IOR * cos_theta1)) /
    (cos_theta2 + (IOR * cos_theta1));
    Fp = Fp * Fp;
    Fs = Fs * Fs;

    float reflectivity = clamp((Fs + Fp) * 0.5f, 0.0f, 1.0f);
#else
    float reflectivity = clamp(pow((1.0f-dot(P, nNorm)),5.0f), 0.0f, 1.0f );
#endif

#ifdef DX9
    float3 envColor = hasEnvMap ? texCUBE(gCubeSampler, mul(P, cubeMapMatrix)).xyz : ambientColor;
    float3 foamColor = tex2D(gFoamSampler, foamTexCoords).xyz;
#else
    float3 envColor = hasEnvMap ? cubeMap.Sample(gTriLinearSamWrap, mul(P, cubeMapMatrix)).xyz : ambientColor;
    float3 foamColor = foamTex.Sample(gTriLinearSamWrap, foamTexCoords).xyz;
#endif

#ifdef PS30
    if( hasPlanarReflectionMap ) {
        float3 up = mul( float3( 0., 0., 1. ), invBasis );
        // perturb view vector by normal xy coords multiplied by displacement scale
        // when we do it in world oriented space this perturbation is equal to:
        // ( nNorm - dot( nNorm, up ) * up ) == invBasis * vec3( ( basis * nNorm ).xy, 0 )
        float3 vNormPerturbed = vNorm + ( nNorm - dot( nNorm, up ) * up ) * planarReflectionDisplacementScale;
        float3 tc = mul( vNormPerturbed, planarReflectionMapMatrix );
#ifdef DX9
        float4 planarColor = tex2Dproj( gPlanarReflectionSampler, float4( tc.xy, 0., tc.z ) );
#else
        float4 planarColor = planarReflectionMap.Sample(gBiLinearSamClamp, tc.xy / tc.z );
#endif
        envColor = lerp( envColor.rgb, planarColor.rgb, planarReflectionBlend);
    }
#endif

#ifndef HDR
    float3 Clight = min(ambientColor + lightColor * dot(L, nNorm), float3(1.0, 1.0, 1.0));
#else
    float3 Clight = ambientColor + lightColor * dot(L, nNorm);
#endif

    float3 Cskylight = lerp(refractColor * Clight, envColor, reflectivity);
    float3 Cfoam = foamColor * ambientColor;

    float3 R = reflect(L, nNorm);
    float spec = max(0.0f, dot(vNorm, R));
    float depth = V.w;
    float3 Csunlight = lightColor * pow(spec, shininess * depth);

    float3 Ci = Cskylight + Csunlight;

    // Fade out foam with distance to hide tiling
#ifdef BREAKING_WAVES
    Ci = Ci + (Cfoam * (clamp(slopesAndFoam.z, 0.0, 1.0) + wakeSlopesAndFoam.z) * tileFade * foamBlend * breakerFade);
    Ci += Cfoam * transparencyDepthBreakers.z;
#else
    Ci = Ci + (Cfoam * (clamp(slopesAndFoam.z, 0.0, 1.0) + wakeSlopesAndFoam.z) * tileFade * foamBlend);
#endif

#ifdef PROPELLER_WASH
#ifdef DX9
#ifdef PS30
    float3 Cw = tex2D(gWashSampler, washTexCoords.xy).xyz * ambientColor * washTexCoords.z;
    Ci = Ci + Cw;
#endif
#else
    float3 Cw = washTex.Sample(gTriLinearSamWash, washTexCoords.xy ).xyz * ambientColor * washTexCoords.z;
    Ci = Ci + Cw;
#endif
#endif

#ifdef PS30
    float alpha = hasHeightMap ? 1.0 - transparencyDepthBreakers.x : lerp(1.0 - transparencyDepthBreakers.x, 1.0, reflectivity);
    float4 waterColor = float4(Ci, alpha);
    float4 fogColor4 = float4(fogColor, hasHeightMap ? alpha : 1.0);

    float4 finalColor = lerp(fogColor4, waterColor, fogFactor);
#else
    float4 finalColor = float4(Ci, 1.0);
#endif

#ifndef HDR
    finalColor = clamp(finalColor, 0.0f, 1.0f);
#endif

    return finalColor;
}

#ifdef DX11
technique11 ColorTech {
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_5_0, PS() ) );
    }
}
#endif

#ifdef DX10
technique10 ColorTech {
    pass P0
    {
        SetVertexShader( CompileShader( vs_4_0, VS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0, PS() ) );
    }
}
#endif

#ifdef DX10LEVEL9
technique10 ColorTech {
    pass P0
    {
        SetVertexShader( CompileShader( vs_4_0_level_9_1, VS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0_level_9_1, PS() ) );
    }
}
#endif

#ifdef DX9
technique {
    pass P0
    {
        SetVertexShader( CompileShader( vs_3_0, VS() ) );
#ifdef PS30
        SetPixelShader( CompileShader( ps_3_0, PS() ) );
#else
        SetPixelShader( CompileShader( ps_2_0, PS() ) );
#endif
    }
}
#endif

