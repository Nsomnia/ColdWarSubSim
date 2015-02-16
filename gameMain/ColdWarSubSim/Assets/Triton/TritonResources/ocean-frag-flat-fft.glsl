//#define FAST_FRESNEL
#define DETAIL
#define DETAIL_OCTAVE 8.0
#define DETAIL_BLEND 0.3
//#define BLINN_PHONG

#ifdef OPENGL32
in vec3 V;
in vec2 foamTexCoords;
in vec2 texCoords;
in vec2 noiseTexCoords;
in float fogFactor;
in vec3 wakeSlopeAndFoam;
#ifdef PROPELLER_WASH
in vec3 washTexCoords;
#endif
in float transparency;
in float depth;
#ifdef BREAKING_WAVES
in float breaker;
in float breakerFade;
#endif
out vec4 fragColor;
#else
varying vec3 V;
varying vec2 foamTexCoords;
varying vec2 texCoords;
varying vec2 noiseTexCoords;
varying float fogFactor;
varying vec3 wakeSlopeAndFoam;
#ifdef PROPELLER_WASH
varying vec3 washTexCoords;
#endif
varying float transparency;
varying float depth;

#ifdef BREAKING_WAVES
varying float breaker;
varying float breakerFade;
#endif
#endif

uniform vec3 L;
uniform vec3 lightColor;
uniform vec3 ambientColor;
uniform vec3 refractColor;
uniform float shininess;
uniform bool hasEnvMap;
uniform sampler2D slopeFoamMap;
uniform mat3 basis;
uniform mat3 invBasis;
uniform samplerCube cubeMap;
uniform sampler2D foamTex;
uniform sampler2D noiseTex;
uniform sampler2D washTex;
uniform float noiseAmplitude;
uniform mat3 cubeMapMatrix;
uniform float invNoiseDistance;
uniform sampler2D planarReflectionMap;
uniform bool hasPlanarReflectionMap;
uniform mat3 planarReflectionMapMatrix;
uniform float planarReflectionDisplacementScale;
uniform float foamBlend;
uniform vec3 fogColor;
uniform float textureLODBias;
uniform bool hasHeightMap;
uniform float planarReflectionBlend;
uniform bool depthOnly;

#ifdef BLINN_PHONG
uniform float sunAlpha = 1.0;
#endif

// From user-functions.glsl:
void user_lighting(in vec3 L, in vec3 V, in vec3 N, inout vec3 ambient, inout vec3 diffuse, inout vec3 specular);
void user_fog(in vec3 vNorm, inout vec4 waterColor, inout vec4 fogColor, inout float fogBlend);
void user_tonemap(in vec4 preToneMapColor, inout vec4 postToneMapColor);
void user_reflection_adjust(inout vec4 planarColor);

void main()
{
    if (hasHeightMap && depth < 0) {
        discard;
        return;
    }

    if (depthOnly) {
#ifdef OPENGL32
        fragColor = vec4(0,0,0,1);
#else
        gl_FragColor = vec4(0,0,0,1);
#endif
        return;
    }

    const float IOR = 1.33333;

    float tileFade = exp(-length(V) * invNoiseDistance);

    vec3 vNorm = normalize(V);
#ifdef OPENGL32
    vec3 slopesAndFoam = texture(slopeFoamMap, texCoords, textureLODBias).xyz;
#ifdef DETAIL
    slopesAndFoam += texture(slopeFoamMap, texCoords * DETAIL_OCTAVE, textureLODBias).xyz * DETAIL_BLEND;
#endif
    vec3 normalNoise = normalize( texture(noiseTex, noiseTexCoords).xyz - vec3(0.5, 0.5, 0.5) ) * noiseAmplitude;
#else
    vec3 slopesAndFoam = texture2D(slopeFoamMap, texCoords, textureLODBias).xyz;
#ifdef DETAIL
    slopesAndFoam += texture2D(slopeFoamMap, texCoords * DETAIL_OCTAVE, textureLODBias).xyz * DETAIL_BLEND;
#endif
    vec3 normalNoise = normalize(texture2D(noiseTex, noiseTexCoords).xyz - vec3(0.5, 0.5, 0.5) ) * noiseAmplitude;
#endif
    normalNoise.z = abs( normalNoise.z );

#ifdef BREAKING_WAVES
    vec3 sx = vec3(1.0, 0.0, mix(0.0, slopesAndFoam.x, breakerFade) + wakeSlopeAndFoam.x);
    vec3 sy = vec3(0.0, 1.0, mix(0.0, slopesAndFoam.y, breakerFade) + wakeSlopeAndFoam.y);
#else
    vec3 sx = vec3(1.0, 0.0, slopesAndFoam.x + wakeSlopeAndFoam.x);
    vec3 sy = vec3(0.0, 1.0, slopesAndFoam.y + wakeSlopeAndFoam.y);
#endif

    vec3 nNorm = invBasis * normalize(normalize(cross(sx, sy)) + (normalNoise * (1.0 - tileFade)));

    vec3 P = reflect(vNorm, nNorm);

#if 0
    float reflectionHalfSphere = dot( P, invBasis[2] /* == invBasis * vec3(0,0,1) */ );

    if( reflectionHalfSphere < 0. ) { // make secondary reflection if reflected vector points down
        P = reflect(P, nNorm);
    }
#endif

#ifdef FAST_FRESNEL
    float reflectivity = clamp( 0.02+0.97*pow((1.0-dot(P, nNorm)),5.0), 0.0, 1.0 );
#else
    vec3 S = refract(P, nNorm, 1.0 / IOR);

    float cos_theta1 = (dot(P, nNorm));
    float cos_theta2 = (dot(S, -nNorm));

    float Fp = (cos_theta1 - (IOR * cos_theta2)) /
               ((IOR * cos_theta2) + cos_theta1);
    float Fs = (cos_theta2 - (IOR * cos_theta1)) /
               ((IOR * cos_theta1) + cos_theta2);
    Fp = Fp * Fp;
    Fs = Fs * Fs;

    float reflectivity = clamp((Fs + Fp) * 0.5, 0.0, 1.0);
#endif

#ifdef OPENGL32
    vec3 envColor = hasEnvMap ? texture(cubeMap, cubeMapMatrix * P).xyz : ambientColor;
#else
    vec3 envColor = hasEnvMap ? textureCube(cubeMap, cubeMapMatrix * P).xyz : ambientColor;
#endif

    if( hasPlanarReflectionMap ) {
        vec3 up = invBasis[2]; // == invBasis * vec3( 0.0, 0.0, 1.0 )
        // perturb view vector by normal xy coords multiplied by displacement scale
        // when we do it in world oriented space this perturbation is equal to:
        // ( nNorm - dot( nNorm, up ) * up ) == invBasis * vec3( ( basis * nNorm ).xy, 0 )
        vec3 vNormPerturbed = vNorm + ( nNorm - dot( nNorm, up ) * up ) * planarReflectionDisplacementScale;
        vec3 tc = planarReflectionMapMatrix * vNormPerturbed;
#ifdef OPENGL32
        vec4 planarColor = textureProj( planarReflectionMap, tc );
#else
        vec2 tcProj = vec2(tc.x / tc.z, tc.y / tc.z);
        vec4 planarColor = texture2D(planarReflectionMap, tcProj);
#endif
        user_reflection_adjust(planarColor);
        envColor = mix( envColor.rgb, planarColor.rgb, planarColor.a * planarReflectionBlend);
    }

    vec3 finalAmbient = ambientColor;
    vec3 finalDiffuse = lightColor * dot(L, nNorm);

#ifdef BLINN_PHONG
    vec3 LNorm = normalize(L);

    vec3 halfVector = normalize(LNorm - vNorm);
    float nDotH = dot(nNorm, halfVector);
    float spec = max(0.05, nDotH);

    // No specular highlight if sun is below the horizon
    vec3 localUp = invBasis[2];
    float upDot = dot( LNorm, localUp );
    if ( upDot < 0.0 ) spec = 0.0;

    vec3 finalSpecular = lightColor * pow(spec, shininess) * sunAlpha;
#else
    vec3 R = reflect(L, nNorm);
    float spec = max(0.0, dot(vNorm, R));
    float screenDepth = gl_FragCoord.z / gl_FragCoord.w;
    vec3 finalSpecular = lightColor * pow(spec, shininess * screenDepth);
#endif

    // Allow lighting overrides in the user-functions.glsl
    user_lighting(L, V, nNorm, finalAmbient, finalDiffuse, finalSpecular);

    vec3 Csunlight = finalSpecular;

#ifndef HDR
    vec3 Clight = min(finalAmbient + finalDiffuse, 1.0);
#else
    vec3 Clight = finalAmbient + finalDiffuse;
#endif

    vec3 Cskylight = mix(refractColor * Clight, envColor, reflectivity);

#ifdef OPENGL32
    vec3 Cfoam = texture(foamTex, foamTexCoords).xyz * finalAmbient;
#else
    vec3 Cfoam = texture2D(foamTex, foamTexCoords).xyz * finalAmbient;
#endif

    vec3 Ci = Cskylight + Csunlight;

    // Fade out foam with distance to hide tiling

#ifdef BREAKING_WAVES
    Ci = Ci + (Cfoam * (clamp(slopesAndFoam.z, 0.0, 1.0) * breakerFade + wakeSlopeAndFoam.z) * tileFade * foamBlend);
    Ci += Cfoam * breaker;
#else
    Ci = Ci + (Cfoam * (clamp(slopesAndFoam.z, 0.0, 1.0) + wakeSlopeAndFoam.z) * tileFade * foamBlend);
#endif

#ifdef PROPELLER_WASH
#ifdef OPENGL32
    vec3 Cwash = texture(washTex, washTexCoords.xy).xyz * finalAmbient * washTexCoords.z;
#else
    vec3 Cwash = texture2D(washTex, washTexCoords.xy).xyz * finalAmbient * washTexCoords.z;
#endif

    Ci = Ci + Cwash;
#endif

    float alpha = hasHeightMap ? 1.0 - transparency : mix(1.0 - transparency, 1.0, reflectivity);
    vec4 waterColor = vec4(Ci, alpha);
    vec4 fogColor4 = vec4(fogColor, hasHeightMap ? alpha : 1.0);

    float fogBlend = fogFactor;

    // Allow user override of fog in user-functions.glsl
    user_fog(V, waterColor, fogColor4, fogBlend);

    vec4 finalColor = mix(fogColor4, waterColor, fogBlend);

#ifndef HDR
    vec4 toneMappedColor = clamp(finalColor, 0.0, 1.0);
#else
    vec4 toneMappedColor = finalColor;
#endif

    user_tonemap(finalColor, toneMappedColor);

#ifdef OPENGL32
    fragColor = toneMappedColor;
#else
    gl_FragColor = toneMappedColor;
#endif
}
