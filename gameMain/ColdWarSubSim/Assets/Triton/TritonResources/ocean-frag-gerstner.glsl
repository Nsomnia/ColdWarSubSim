
#ifdef OPENGL32
in vec3 V;
in vec3 N;
in float foam;
in vec2 foamTexCoords;
in float fogFactor;
in float transparency;
#ifdef PROPELLER_WASH
in vec3 washTexCoords;
#endif
out vec4 fragColor;
#else
varying vec3 V;
varying vec3 N;
varying float foam;
varying vec2 foamTexCoords;
varying float fogFactor;
varying float transparency;
#ifdef PROPELLER_WASH
varying vec3 washTexCoords;
#endif
#endif

uniform vec3 L;
uniform vec3 lightColor;
uniform vec3 ambientColor;
uniform vec3 refractColor;
uniform float shininess;
uniform bool hasEnvMap;
uniform samplerCube cubeMap;
uniform sampler2D foamTex;
uniform sampler2D washTex;
uniform float foamBlend;
uniform mat3 cubeMapMatrix;
uniform mat3 invBasis;
uniform sampler2D planarReflectionMap;
uniform bool hasPlanarReflectionMap;
uniform mat3 planarReflectionMapMatrix;
uniform float planarReflectionDisplacementScale;
uniform vec3 fogColor;
uniform float planarReflectionBlend;

void main()
{
    const float IOR = 1.34;

    vec3 vNorm = normalize(V);
    vec3 nNorm = normalize(N);

    vec3 reflection = reflect(vNorm, nNorm);
    vec3 refraction = refract(vNorm, nNorm, 1.0 / IOR);

    // We don't need no stinkin Fresnel approximation, do it for real

    float cos_theta1 = (dot(vNorm, nNorm));
    float cos_theta2 = (dot(refraction, nNorm));

    float Fp = (cos_theta1 - (IOR * cos_theta2)) /
               (cos_theta1 + (IOR * cos_theta2));
    float Fs = (cos_theta2 - (IOR * cos_theta1)) /
               (cos_theta2 + (IOR * cos_theta1));
    Fp = Fp * Fp;
    Fs = Fs * Fs;

    float reflectivity = clamp((Fs + Fp) * 0.5, 0.0, 1.0);

#ifdef OPENGL32
    vec3 envColor = hasEnvMap ? texture(cubeMap, cubeMapMatrix * reflection).xyz : ambientColor;
#else
    vec3 envColor = hasEnvMap ? textureCube(cubeMap, cubeMapMatrix * reflection).xyz : ambientColor;
#endif
    if( hasPlanarReflectionMap ) {
        vec3 up = invBasis * vec3( 0., 0., 1. );
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
        envColor = mix( envColor.rgb, planarColor.rgb, planarColor.a * planarReflectionBlend );
    }

#ifndef HDR
    vec3 Clight = min(ambientColor + lightColor * dot(L, nNorm), 1.0);
#else
    vec3 Clight = ambientColor + lightColor * dot(L, nNorm);
#endif

    vec3 Cskylight = mix(refractColor * Clight, envColor, reflectivity);
#ifdef OPENGL32
    vec3 Cfoam = texture(foamTex, foamTexCoords).xyz * ambientColor;
#else
    vec3 Cfoam = texture2D(foamTex, foamTexCoords).xyz * ambientColor;
#endif
    vec3 R = reflect(L, nNorm);
    float S = max(0.0, dot(vNorm, R));
    float depth = gl_FragCoord.z / gl_FragCoord.w;
    vec3 Csunlight = lightColor * pow(S, shininess * depth);

    vec3 Ci = Cskylight + Csunlight;

    Ci = Ci + (Cfoam * foam * foamBlend);

#ifdef PROPELLER_WASH
#ifdef OPENGL32
    vec3 Cwash = texture(washTex, washTexCoords.xy).xyz * ambientColor * washTexCoords.z;
#else
    vec3 Cwash = texture2D(washTex, washTexCoords.xy).xyz * ambientColor * washTexCoords.z;
#endif
    Ci = Ci + Cwash;
#endif

    float alpha = mix(1.0 - transparency, 1.0, reflectivity);
    vec4 waterColor = vec4(Ci, alpha);
    vec4 fogColor4 = vec4(fogColor, 1.0);

    vec4 finalColor = mix(fogColor4, waterColor, fogFactor);

#ifndef HDR
    finalColor = clamp(finalColor, 0.0, 1.0);
#endif

#ifdef OPENGL32
    fragColor = finalColor;
#else
    gl_FragColor = finalColor;
#endif

}
