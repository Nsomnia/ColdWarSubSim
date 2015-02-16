#define MAX_WAVES 5

uniform float4x4 modelview;
uniform float4x4 projection;
uniform float depthOffset;
uniform float4x4 invModelviewProj;
uniform float3x3 basis;
uniform float3x3 invBasis;
uniform float3 cameraPos;
uniform float4x4 gridScale;
uniform float antiAliasing;
uniform float foamScale;
uniform float foamBlend;
uniform float3 L;
uniform float3 lightColor;
uniform float3 ambientColor;
uniform float3 refractColor;
uniform float shininess;
uniform float3 north;
uniform float3 radii;
uniform float3 oneOverRadii;
uniform bool hasEnvMap;
uniform float fogDensity;
uniform float fogDensityBelow;
uniform float3 fogColor;
uniform float3x3 cubeMapMatrix;
uniform bool doWakes;
uniform bool hasPlanarReflectionMap;
uniform float3x3 planarReflectionMapMatrix;
uniform float planarReflectionDisplacementScale;
uniform float3 floorPlanePoint;
uniform float3 floorPlaneNormal;
uniform float washLength;
uniform float planarReflectionBlend;

struct GerstnerWave {
    float steepness;
    float amplitude;
    float frequency;
    float2  direction;
    float phaseSpeed;
};

uniform GerstnerWave waves[MAX_WAVES];
uniform int numWaves;
uniform float time;
uniform float gridSize;

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
TEXTURE cubeMap;
TEXTURE foamTex;
TEXTURE washTex;
TEXTURE planarReflectionMap;
TEXTURE displacementTexture;

sampler2D gDisplacementTextureSampler = sampler_state {
    Texture = (displacementTexture);
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

sampler2D gPlanarReflectionSampler = sampler_state {
    Texture = (planarReflectionMap);
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

#else

TextureCube cubeMap;
Texture2D foamTex;
Texture2D washTex;
Texture2D planarReflectionMap;
Texture2D displacementTexture;

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

SamplerState gBiLinearSamClamp {
    Filter = MIN_MAG_LINEAR_MIP_POINT;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

#endif

float computeTransparency(in float3 worldPos, in float3 up)
{
    float transparency = 0.0;

    // Compute depth at this position
    float3 l = -up;
    float3 l0 = worldPos;
    float3 n = floorPlaneNormal;
    float3 p0 = floorPlanePoint;
    float numerator = dot((p0 - l0), n);
    float denominator = dot(l, n);
    if (denominator != 0) {
        float depth = numerator / denominator;

        // Compute fog at this distance underwater
        float fogExponent = abs(depth) * fogDensityBelow;
        transparency = clamp(exp(-abs(fogExponent)), 0.0, 1.0);
    }

    return transparency;
}

void applyCircularWaves(inout float3 v, in float3 localPos, out float2 slope, out float foam)
{
    int i;

    float3 slope3 = float3(0.0, 0.0, 0.0);
    float disp = 0.0;

    for (i = 0; i < MAX_CIRCULAR_WAVES; i++) {

        float3 D = (localPos - circularWaves[i].position);
        float dist = length(D);

        float r = dist - circularWaves[i].radius;
        if (abs(r) < circularWaves[i].halfWavelength) {

            float amplitude = circularWaves[i].amplitude;

            float theta = circularWaves[i].k * r;
            disp += amplitude * cos(theta);
            float derivative = amplitude * -cos(theta);
            slope3 +=  D * (derivative / dist);
        }
    }

    v.z += disp;

    slope = mul(slope3, basis).xy;

    foam = length(slope.xy);
}

void applyKelvinWakes(inout float3 v, in float3 localPos, in float3 up, inout float2 slope, inout float foam)
{
    int i;
#ifdef KELVIN_WAKES
    float2 accumSlope = float2(0,0);
    float disp = 0.0;

    for (i = 0; i < MAX_KELVIN_WAKES; i++) {

        float3 X0 = wakes[i].position - wakes[i].shipPosition;
        float3 T = normalize(X0);
        float3 N = up;
        float3 B = normalize(cross(N, T));

        float3 P = localPos - wakes[i].shipPosition;
        float3 X;
        X.x = dot(P, T);
        X.y = dot(P, B);
//      X.z = dot(P, N);

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

            float3 thisnormal = normalize(sample.xyz * 2.0 - 1.0);
            float invmax = rsqrt( max( dot(T,T), dot(B,B) ) );
            float3x3 TBN = float3x3( T * invmax, B * invmax, N );

            thisnormal = normalize(mul(thisnormal, TBN));

            // Convert to z-up
            thisnormal = mul(thisnormal, basis);

            thisnormal.xy *= wakes[i].amplitude;
            thisnormal = normalize(thisnormal);

            accumSlope += float2(thisnormal.x / thisnormal.z, thisnormal.y / thisnormal.z);

            disp += displacement;
        }
    }

    v.z += disp;

    foam += length(accumSlope);
    slope += accumSlope;


#endif
}

void applyPropWash(in float3 v, in float3 localPos, in float3 up, out float3 washTexCoords)
{
#ifdef PROPELLER_WASH

    washTexCoords = float3(0.0, 0.0, 0.0);

    for (int i = 0; i < MAX_PROP_WASHES; i++) {

        if (washes[i].distFromSource == 0) continue;

        float3 C = washes[i].deltaPos;
        float3 A = localPos - washes[i].propPosition;
        float3 B = localPos - (washes[i].propPosition + C);
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
            float3 x1 = washes[i].propPosition;
            float3 x2 = x1 + washes[i].deltaPos;

            float3 aCrossB = cross(A, B);
            float d = length(aCrossB) / length(C);

            // The direction of A X B indicates if we're 'left' or 'right' of the path
            float nd = d / washWidth;

            if (nd >= 0.0 && nd <= 1.0) {
                washTexCoords.x = nd;
                // The t0 parameter from our initial distance test to the line segment makes
                // for a handy t texture coordinate

                washTexCoords.y =  (washes[i].washLength - distFromSource) / washes[i].washWidth;

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

void gerstner(in float3 pt, out float3 P, out float3 normal, in float sampleFreq)
{
    P = pt;
    normal = float3(0, 0, 0);

    int i;
    for (i = 0; i < numWaves; i++) {
        float nyquistLimit = waves[i].frequency * 2.0f;
        if (sampleFreq > nyquistLimit) {
            float nyquistFade = min((sampleFreq - nyquistLimit) / (nyquistLimit * antiAliasing), 1.0);
            float A = waves[i].amplitude * nyquistFade;
            float WA = waves[i].frequency * A;
            float tmp = waves[i].frequency * dot(waves[i].direction, pt.xy) + waves[i].phaseSpeed * time;
            float S = sin(tmp);
            float C = cos(tmp);
            float WAC = WA * C;
            float QAC = waves[i].steepness * A * C;

            P += float3(QAC * waves[i].direction.x,
                        QAC * waves[i].direction.y,
                        waves[i].amplitude * S);

            normal += float3(waves[i].direction.x * WAC,
                             waves[i].direction.y * WAC,
                             waves[i].steepness * WA * S);
        }
    }

    normal = float3(normal.x * -1.0f, normal.y * -1.0f, 1.0f - normal.z);
}

// Intersect a ray of origin P0 and direction v against a unit sphere centered at the origin
bool raySphereIntersect(in float3 p0, in float3 v, out float3 intersection)
{
    float twop0v = 2.0 * dot(p0, v);
    float p02 = dot(p0, p0);
    float v2 = dot(v, v);

    float disc = twop0v * twop0v - (4.0 * v2)*(p02 - 1);
    if (disc > 0) {
        float discSqrt = sqrt(disc);
        float den = 2.0 * v2;
        float t = (-twop0v - discSqrt) / den;
        if (t < 0) {
            t = (-twop0v + discSqrt) / den;
        }
        intersection = p0 + t * v;
        return true;
    } else {
        intersection = float3(0.0, 0.0, 0.0);
        return false;
    }
}

// Intersect a ray against an ellipsoid centered at the origin
bool rayEllipsoidIntersect(in float3 R0, in float3 Rd, out float3 intersection)
{
    // Distort the ray so it aims toward a unit sphere, do a sphere intersection
    // and scale it back to the ellpsoid's space.

    float3 scaledR0 = R0 * oneOverRadii;
    float3 scaledRd = Rd * oneOverRadii;

    float3 sphereIntersection;
    if (raySphereIntersect(scaledR0, scaledRd, sphereIntersection)) {
        intersection = sphereIntersection * radii;
        return true;
    } else {
        intersection = float3(0.0, 0.0, 0.0);
        return false;
    }
}

// Alternate, faster method - but it can't handle viewpoints inside the ellipsoid.
// If you don't need underwater views, this may be better for you.
bool rayEllipsoidIntersectFast(in float3 R0, in float3 Rd, out float3 intersection)
{
    float3 q = R0 * oneOverRadii;
    float3 bUnit = normalize(Rd * oneOverRadii);
    float wMagnitudeSquared = dot(q, q) - 1.0f;

    float t = -dot(bUnit, q);
    float tSquared = t * t;

    if ((t >= 0.0f) && (tSquared >= wMagnitudeSquared)) {
        float temp = t - sqrt(tSquared - wMagnitudeSquared);
        float3 r = (q + temp * bUnit);
        intersection = r * radii;

        return true;
    } else {
        return false;
    }
}

bool projectToSea(in float4 v, out float4 worldPos, out float cellSize)
{
    // Get the line this screen position projects to
    float4 p0 = v;
    p0.z = -1.0f;
    float4 p1 = v;
    p1.z = 1.0f;

    // Transform into world coords
    p0 = mul(p0, invModelviewProj);
    p1 = mul(p1, invModelviewProj);

    float3 p03 = p0.xyz / p0.w;
    float3 p13 = p1.xyz / p1.w;

    // Intersect with the sea level
    float3 intersect;

    if (rayEllipsoidIntersect(p03 + cameraPos, p13 - p03, intersect)) {
        worldPos = float4(intersect.x, intersect.y, intersect.z, 1.0f);

        // Compute projected grid cell size while we're at it
        // Project back to clip space
        float4 worldPosCamera4 = float4(0.0f, 0.0f, 0.0f, 1.0f);
        worldPosCamera4.xyz = worldPos.xyz - cameraPos;
        float4x4 modelviewProj = mul(modelview, projection);
        float4 p2 = mul(worldPosCamera4, modelviewProj);
        p2 /= p2.w;

        // Displace it by one grid cell
        p2.xy += float2(2.0f / gridSize, 2.0f / gridSize);

        // Back to world space
        float4 p21 = p2;
        float4 p22 = p2;
        p21.z = 0.0f;
        p22.z = 1.0f;

        p21 = mul(p21, invModelviewProj);
        p21 /= p21.w;
        p22 = mul(p22, invModelviewProj);
        p22 /= p22.w;

        if (rayEllipsoidIntersect(p21.xyz + cameraPos, (p22.xyz - p21.xyz), intersect)) {
            // Get the projected world distance
            cellSize = length(intersect - worldPos.xyz);

            return true;
        } else {
            cellSize = 0.0;
            return false;
        }
    } else {
        worldPos = float4(0.0, 0.0, 0.0, 0.0);
        cellSize = 0.0;
        return false;
    }
}

float3 computeArcLengths(in float3 worldPos, in float3 northDir, in float3 eastDir)
{
    float3 pt = worldPos - cameraPos;
    return float3(dot(pt, eastDir), dot(pt, northDir), 0);
}

#ifdef DX9
void VS( float4 position : POSITION,

         out float4 oPosition : POSITION0,
         out float4 V : TEXCOORD0,
         out float3 N : TEXCOORD1,
         out float foam : TEXCOORD2,
         out float2 foamTexCoords : TEXCOORD3,
         out float  transparency : TEXCOORD4,
         out float fogFactor : TEXCOORD5,
         out float3 washTexCoords : TEXCOORD6
       )
#else
void VS( float4 position : POSITION,

         out float4 oPosition : SV_POSITION,
         out float4 V : TEXCOORD0,
         out float3 N : TEXCOORD1,
         out float foam : TEXCOORD2,
         out float2 foamTexCoords : TEXCOORD3,
         out float  transparency : TEXCOORD4,
         out float fogFactor : FOG,
         out float3 washTexCoords : TEXCOORD5
       )
#endif
{
    // To avoid precision issues, the translation component of the modelview matrix
    // is zeroed out, and the camera position passed in via cameraPos

    float4 worldPos;
    float cellSize;

    transparency = 0.0f;

    float4 gridPos = mul(position, gridScale);

    washTexCoords = float3(0.0, 0.0, 0.0);

    bool above = true;

    if (projectToSea(gridPos, worldPos, cellSize)) {
        // Here, worldPos is relative to the center of the Earth, since
        // projectToSea added the camera position back in after transforming

        above = length(cameraPos.xyz) > length(worldPos.xyz);
        float3 up = normalize(worldPos.xyz);
        float3 east = normalize(cross(north, up));
        float3 nnorth = normalize(cross(up, east));

        // Transform position on the ellipsoid into a planar reference,
        // x east, y north, z up
        float3 planar = computeArcLengths(worldPos.xyz, nnorth, east);

        // Compute displacement and surface normal from Gerstner waves
        float3 P, normal;
        gerstner(planar, P, normal, (2.0f * 3.14159265f) / cellSize);

        // Add in ship wakes
        float3 wakeNormal = float3( 0.f, 0.f, 1.f );
        if (doWakes) {
            float wakeFoam;
            float2 slope;
            float3 localPos = worldPos.xyz - cameraPos.xyz;
            applyCircularWaves(P, localPos.xyz, slope, wakeFoam);
            applyKelvinWakes(P, localPos.xyz, up, slope, wakeFoam);
            applyPropWash(P, localPos.xyz, up, washTexCoords);

            float3 sx = float3(1.0, 0.0, slope.x);
            float3 sy = float3(0.0, 1.0, slope.y);
            wakeNormal = normalize(cross(sx, sy));
            foam = wakeFoam;

        } else {
            foam = 0;
        }

        float3 disp = P - planar;

        foamTexCoords = planar.xy / foamScale;

        // Transform back into geocentric coords

        worldPos.xyz = worldPos.xyz + disp.x * east + disp.y * nnorth + disp.z * up;

        transparency = computeTransparency(worldPos.xyz, up);

        V.xyz = normalize(worldPos.xyz - cameraPos);
        N = normalize(normal.x * east + normal.y * nnorth + normal.z * up);
        N = normalize(N + wakeNormal - float3(0.0, 0.0, 1.0));

        // Make relative to the camera
        worldPos.xyz -= cameraPos;
        // Project it back again, apply depth offset.
        float4 v = mul(worldPos, modelview);
        v.w -= depthOffset;
        oPosition = mul(v, projection);
        V.w = oPosition.z / oPosition.w;
    } else {
        // No intersection, move the vert out of clip space
        oPosition = float4(gridPos.x, gridPos.y, 2.0f, 1.0f);
        V = float4(0.0, 0.0, 0.0, 1.0);
        N = float3(0.0, 0.0, 0.0);
        foam = 0.0;
        foamTexCoords = float2(0.0, 0.0);
        washTexCoords = float3(0.0, 0.0, 0.0);
    }

    float fogExponent = length(V.xyz) * fogDensity;
    fogFactor = saturate(exp(-abs(fogExponent)));
}

#ifdef DX9
float4 PS(float4 posH : POSITION0,
          float4 V : TEXCOORD0,
          float3 N : TEXCOORD1,
          float foam : TEXCOORD2,
          float2 foamTexCoords : TEXCOORD3,
          float  transparency : TEXCOORD4,
          float fogFactor : TEXCOORD5,
          float3 washTexCoords : TEXCOORD6 ) : COLOR {
#else
float4 PS(float4 posH : SV_POSITION,
float4 V : TEXCOORD0,
float3 N : TEXCOORD1,
float foam : TEXCOORD2,
float2 foamTexCoords : TEXCOORD3,
float  transparency : TEXCOORD4,
float fogFactor : FOG,
float3 washTexCoords : TEXCOORD5 ) : SV_TARGET {
#endif
    const float IOR = 1.34f;

    float3 vNorm = normalize(V.xyz);
    float3 nNorm = normalize(N);

    float3 reflection = reflect(vNorm, nNorm);
    float3 refraction = refract(vNorm, nNorm, 1.0f / IOR);

#ifdef PS30
    // We don't need no stinkin Fresnel approximation, do it for real

    float cos_theta1 = (dot(vNorm, nNorm));
    float cos_theta2 = (dot(refraction, nNorm));

    float Fp = (cos_theta1 - (IOR * cos_theta2)) /
    (cos_theta1 + (IOR * cos_theta2));
    float Fs = (cos_theta2 - (IOR * cos_theta1)) /
    (cos_theta2 + (IOR * cos_theta1));
    Fp = Fp * Fp;
    Fs = Fs * Fs;

    float reflectivity = clamp((Fs + Fp) * 0.5f, 0.0f, 1.0f);
#else
    float reflectivity = clamp(pow((1.0f-dot(reflection, nNorm)),5.0f), 0.0f, 1.0f );
#endif

#ifdef DX9
    float3 envColor = hasEnvMap ? texCUBE(gCubeSampler, mul(reflection, cubeMapMatrix)).xyz : ambientColor;
    float3 foamColor = tex2D(gFoamSampler, foamTexCoords).xyz;
#else
    float3 envColor = hasEnvMap ? cubeMap.Sample(gTriLinearSamWrap, mul(reflection, cubeMapMatrix)).xyz : ambientColor;
    float3 foamColor = foamTex.Sample(gTriLinearSamWrap, foamTexCoords).xyz;
#endif

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
        envColor = lerp( envColor.rgb, planarColor.rgb, planarColor.a * planarReflectionBlend);
    }

#ifndef HDR
    float3 Clight = min(ambientColor + lightColor * dot(L, nNorm), float3(1.0, 1.0, 1.0));
#else
    float3 Clight = ambientColor + lightColor * dot(L, nNorm);
#endif

    float3 Cskylight = lerp(refractColor * Clight, envColor, reflectivity);
    float3 Cfoam = foamColor * ambientColor;

    float3 R = reflect(L, nNorm);
    float S = max(0.0, dot(vNorm, R));
    float depth = V.w;
    float3 Csunlight = lightColor * pow(S, shininess * depth);

    float3 Ci = Cskylight + Csunlight;

    Ci = Ci + (Cfoam * foam * foamBlend);

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

    float4 fogColor4 = float4(fogColor.xyz, 1.0);
    float alpha = lerp(1.0 - transparency, 1.0, reflectivity);
    float4 waterColor = float4(Ci, alpha);

    float4 finalColor = lerp(fogColor4, waterColor, fogFactor);

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

