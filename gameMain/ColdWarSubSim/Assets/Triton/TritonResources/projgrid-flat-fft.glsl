#define PRECISION_GUARD 2.0

#ifdef OPENGL32
in vec2 vertex;
out vec3 V;
out vec2 foamTexCoords;
out vec2 texCoords;
out vec2 noiseTexCoords;
out vec3 wakeSlopeAndFoam;
#ifdef PROPELLER_WASH
out vec3 washTexCoords;
#endif
out float fogFactor;
out float transparency;
out float depth;
#ifdef BREAKING_WAVES
out float breaker;
out float breakerFade;
#endif
#else
varying vec3 V;
varying vec2 foamTexCoords;
varying vec2 texCoords;
varying vec2 noiseTexCoords;
varying vec3 wakeSlopeAndFoam;
#ifdef PROPELLER_WASH
varying vec3 washTexCoords;
#endif
varying float fogFactor;
varying float transparency;
varying float depth;
#ifdef BREAKING_WAVES
varying float breaker;
varying float breakerFade;
#endif
#endif

uniform float foamScale;
uniform float depthOffset;
uniform mat4 invModelviewProj;
uniform mat4 modelview;
uniform mat4 projection;
uniform vec4 plane;
uniform mat3 basis;
uniform mat3 invBasis;
uniform vec3 cameraPos;
uniform mat4 gridScale;
uniform float antiAliasing;
uniform float gridSize;
uniform sampler2D displacementMap;
uniform vec2 textureSize;
uniform vec3 fogColor;
uniform float fogDensity;
uniform float fogDensityBelow;
uniform float invDampingDistance;
uniform bool doWakes;
uniform vec3 floorPlanePoint;
uniform vec3 floorPlaneNormal;
uniform float washLength;
uniform float time;
uniform float seaLevel;

uniform bool hasHeightMap;
uniform sampler2D heightMap;
uniform mat4 heightMapMatrix;

#ifdef BREAKING_WAVES
uniform float kexp;
uniform float breakerWavelength;
uniform float breakerWavelengthVariance;
uniform vec3 breakerDirection;
uniform float breakerAmplitude;
uniform float breakerPhaseConstant;
uniform float surgeDepth;
uniform float steepnessVariance;
#endif

#define TWOPI (2.0 * 3.14159265)

uniform sampler2D displacementTexture;

struct CircularWave {
    float amplitude;
    float radius;
    float k;
    float halfWavelength;
    vec3 position;
};

struct KelvinWake {
    float amplitude;
    vec3 position;
    vec3 shipPosition;
};

#ifdef PROPELLER_WASH
struct PropWash {
    vec3 deltaPos;
    float washWidth;
    vec3 propPosition;
    float distFromSource;
    float washLength;
};

uniform PropWash washes[MAX_PROP_WASHES];
#endif

uniform CircularWave circularWaves[MAX_CIRCULAR_WAVES];

uniform KelvinWake wakes[MAX_KELVIN_WAKES];

void computeTransparency(in vec3 worldPos)
{
    depth = 1000.0;
    // Compute depth at this position
    if (hasHeightMap) {
        vec2 texCoord = (heightMapMatrix * vec4(worldPos, 1.0)).xy;
        if (clamp(texCoord, vec2(0.0, 0.0), vec2(1.0, 1.0)) == texCoord) {
#ifdef OPENGL32
            float height = texture(heightMap, texCoord).x;
#else
            float height = texture2D(heightMap, texCoord).x;
#endif
            depth = -(height - seaLevel);
        }
    } else {
        vec3 up = invBasis * vec3(0, 0, 1);
        vec3 l = -up;
        vec3 l0 = worldPos;
        vec3 n = floorPlaneNormal;
        vec3 p0 = floorPlanePoint;
        float numerator = dot((p0 - l0), n);
        float denominator = dot(l, n);
        if (denominator != 0.0) {
            depth = numerator / denominator;
        }
    }

    // Compute fog at this distance underwater
    float fogExponent = abs(depth) * fogDensityBelow;
    transparency = clamp(exp(-abs(fogExponent)), 0.0, 1.0);
}

float applyBreakingWaves(inout vec3 v)
{
    float finalz = 0;

#ifdef BREAKING_WAVES
    breaker = 0;

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
        vec3 localDir = basis * breakerDirection;
        float dotResult = dot(localDir.xy, v.xy) * TWOPI / wavelength;

        finalz = (dotResult + breakerPhaseConstant * time);
        finalz = (sin(finalz) + 1.0) * 0.5;
        finalz = breakerAmplitude * pow(finalz, k);

        if (breakerAmplitude > breakHeight) {
            finalz = min(finalz, depth);
            breaker = finalz / breakerAmplitude;
        } else {
            breaker = finalz / breakHeight;
        }

        // Hide the backs of waves if we're transparent
        float opacity = 1.0 - transparency;
        finalz = mix(0.0, finalz, pow(opacity, 6.0));
    }
#endif

    return finalz;
}

float applyCircularWaves(in vec3 v, float fade)
{
    int i;

    float dispZ = 0;

    vec2 slope = vec2(0.0, 0.0);
    float disp = 0.0;

    for (i = 0; i < MAX_CIRCULAR_WAVES; i++) {

        vec2 D = (v - circularWaves[i].position).xy;
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

    dispZ += disp * fade;

    wakeSlopeAndFoam.z += length(slope);
    wakeSlopeAndFoam.xy += slope * fade;

    return dispZ;
}

float applyKelvinWakes(in vec3 v, float fade)
{
    float displacementZ = 0;

#ifdef KELVIN_WAKES
    vec2 slope = vec2(0.0, 0.0);

    int i;
    for (i = 0; i < MAX_KELVIN_WAKES; i++) {

        vec3 X0 = wakes[i].position - wakes[i].shipPosition;
        vec3 T = normalize(X0);
        vec3 N = vec3(0,0,1);
        vec3 B = normalize(cross(N, T));

        vec3 P = v - wakes[i].shipPosition;
        vec3 X;
        X.x = dot(P.xy, T.xy);
        X.y = dot(P.xy, B.xy);

        float xLen = length(X0);
        vec2 tc;
        tc.x = X.x / (1.54 * xLen);
        tc.y = (X.y) / (1.54 * xLen) + 0.5;

        if (clamp(tc, 0.01, 0.99) == tc) {
#ifdef OPENGL32
            vec4 sample = texture(displacementTexture, tc);
#else
            vec4 sample = texture2D(displacementTexture, tc);
#endif
            float displacement = sample.w;

            displacement *= wakes[i].amplitude * fade;

            vec3 normal = normalize(sample.xyz * 2.0 - 1.0);
            float invmax = inversesqrt( max( dot(T,T), dot(B,B) ) );
            mat3 TBN = mat3( T * invmax, B * invmax, N );

            normal = TBN * normal;
            normal.xy *= min(1.0, wakes[i].amplitude);
            normal = normalize(normal);

            displacementZ += displacement;

            slope.x += normal.x / normal.z;
            slope.y += normal.y / normal.z;
        }
    }

    wakeSlopeAndFoam.z += min(1.0, length(slope));
    wakeSlopeAndFoam.xy += slope * fade;
#endif

    return displacementZ;
}

void applyPropWash(in vec3 v)
{
#ifdef PROPELLER_WASH

    washTexCoords = vec3(0.0, 0.0, 0.0);

    for (int i = 0; i < MAX_PROP_WASHES; i++) {

        if (washes[i].distFromSource == 0) continue;

        vec3 C = washes[i].deltaPos;
        vec3 A = v - washes[i].propPosition;
        vec3 B = v - (washes[i].propPosition + C);
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
            vec3 aCrossB = cross(A, B);
            float d = length(aCrossB) / length(C);

            // The direction of A X B indicates if we're 'left' or 'right' of the path
            float nd = d / washWidth;

            if (clamp(nd, 0.0, 1.0) == nd) {
                washTexCoords.x = nd;
                // The t0 parameter from our initial distance test to the line segment makes
                // for a handy t texture coordinate
                washTexCoords.y =  (washes[i].washLength - distFromSource) / washes[i].washWidth;

                // We stuff the blend factor into the r coordinate.

                float blend = max(0.0, 1.0 - distFromSource / (washLength));
                float distFromCenter = d / washWidth;
                blend *= max(0.0, 1.0 - distFromCenter * distFromCenter);
                washTexCoords.z = blend;
            }
        }
    }
#endif
}

void displace(in vec3 vWorld, inout vec3 vLocal)
{
    float fade = 1.0 - smoothstep(0.0, 1.0, length(vWorld - cameraPos) * invDampingDistance);

#ifdef BREAKING_WAVES
    // Fade out waves in the surge zone
    float depthFade = 1.0;

    if (surgeDepth > 0) {
        depthFade = min(surgeDepth, depth) / surgeDepth;
    }

    fade *= depthFade;
    breakerFade = depthFade;
#endif

    // Transform so z is up
    vec3 localVWorld = basis * vWorld;
    vec3 localVLocal = basis * vLocal;

    texCoords = localVWorld.xy / textureSize;

#ifdef OPENGL32
    vec3 displacement = texture(displacementMap, texCoords).xyz;
#else
    vec3 displacement = texture2D(displacementMap, texCoords).xyz;
#endif

    // Hide the backs of waves if we're transparent
    float opacity = 1.0 - transparency;
    displacement.z = mix(0.0, displacement.z, pow(opacity, 6.0));

    localVLocal.xy += displacement.xy * fade;

#if (defined(KELVIN_WAKES) || defined(PROPELLER_WASH))
    if (doWakes) {
        wakeSlopeAndFoam.xyz = vec3(0.0, 0.0, 0.0);
        localVLocal.z += applyKelvinWakes(localVWorld, fade);
        localVLocal.z += applyCircularWaves(localVWorld, fade);
        applyPropWash(localVWorld);
    } else {
#ifdef PROPELLER_WASH
        washTexCoords = vec3(0.0, 0.0, 0.0);
#endif
    }
#endif

    localVLocal.z += displacement.z * fade;

    localVLocal.z += applyBreakingWaves(localVWorld);

    foamTexCoords = localVWorld.xy / foamScale;
    noiseTexCoords = texCoords * 0.03;

    vLocal = invBasis * localVLocal;
}

bool projectToSea(in vec4 v, out vec4 vLocal, out vec4 vWorld)
{
    // Get the line this screen position projects to
    const vec2 consts = vec2(0.0, 1.0);
    vec4 p0 = v * consts.yyxy;
    vec4 p1 = v * consts.yyxy + consts.xxyx;

    // Transform into world coords
    p0 = invModelviewProj * p0;
    p1 = invModelviewProj * p1;

    // Intersect with the sea level
    vec3 up = invBasis * vec3(0, 0, 1);
    vec4 p = plane;

    float altitude = dot(cameraPos, up) - seaLevel;
    float offset = 0;

    if (clamp(altitude, 0, PRECISION_GUARD) == altitude) {
        p.w += PRECISION_GUARD;
        offset = PRECISION_GUARD;
    } else if (clamp(altitude, -PRECISION_GUARD, 0) == altitude) {
        p.w -= PRECISION_GUARD;
        offset = -PRECISION_GUARD;
    }

    vec4 dp = p1 - p0;
    float t = -dot(p0, p) / dot( dp, p);
    if (t > 0.0 && t < 1.0) {
        vLocal = dp * t + p0;
        vLocal /= vLocal.w;
        vLocal.xyz += up * offset;
        vWorld = vLocal + vec4(cameraPos, 1.0);
        return true;
    } else {
        vLocal = vec4(0.0, 0.0, 0.0, 0.0);
        vWorld = vec4(0.0, 0.0, 0.0, 0.0);
        return false;
    }
}

void main()
{
    wakeSlopeAndFoam = vec3( 0. );
    transparency = 0.0;

    vec4 worldPos, localPos;

#ifdef OPENGL32
    vec4 gridPos = gridScale * vec4(vertex.x, vertex.y, 0.0, 1.0);
#else
    vec4 gridPos = gridScale * gl_Vertex;
#endif

    if (projectToSea(gridPos, localPos, worldPos)) {
        computeTransparency(worldPos.xyz);

        // Displace
        vec3 origWorld = worldPos.xyz;
        displace(worldPos.xyz, localPos.xyz);

        V = localPos.xyz;

        // Project it back again, apply depth offset.
        vec4 v = modelview * localPos;
        v.w -= depthOffset;
        gl_Position = projection * v;
    } else {
        V = vec3(0.0, 0.0, 0.0);
        foamTexCoords = vec2(0.0, 0.0);
        texCoords = vec2(0.0, 0.0);
        noiseTexCoords = vec2(0.0, 0.0);
        wakeSlopeAndFoam = vec3(0.0, 0.0, 0.0);
#ifdef PROPELLER_WASH
        washTexCoords = vec3(0.0, 0.0, 0.0);
#endif
        fogFactor = 0.0;
        transparency = 0.0;
        gl_Position = vec4(gridPos.x, gridPos.y, 100.0, 1.0);
    }

    float fogExponent = length(V.xyz) * fogDensity;
    fogFactor = clamp(exp(-abs(fogExponent)), 0.0, 1.0);
}