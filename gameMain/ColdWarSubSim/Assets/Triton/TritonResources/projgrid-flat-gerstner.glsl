#define MAX_WAVES 5

#ifdef OPENGL32
in vec2 vertex;
out vec3 V;
out vec3 N;
out float foam;
out vec2 foamTexCoords;
out float fogFactor;
out float transparency;
#ifdef PROPELLER_WASH
out vec3 washTexCoords;
#endif
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


uniform mat4 modelview;
uniform mat4 projection;
uniform mat4 invModelviewProj;
uniform vec4 plane;
uniform mat3 basis;
uniform mat3 invBasis;
uniform vec3 cameraPos;
uniform mat4 gridScale;
uniform float antiAliasing;
uniform float foamScale;
uniform vec3 fogColor;
uniform float fogDensity;
uniform float fogDensityBelow;
uniform bool doWakes;
uniform vec3 floorPlanePoint;
uniform vec3 floorPlaneNormal;
uniform float washLength;
uniform float depthOffset;

struct GerstnerWave {
    float steepness;
    float amplitude;
    float frequency;
    vec2  direction;
    float phaseSpeed;
};

uniform GerstnerWave waves[MAX_WAVES];
uniform int numWaves;
uniform float time;
uniform float gridSize;


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
    // Compute depth at this position
    vec3 up = invBasis * vec3(0.0, 0.0, 1.0);
    vec3 l = -up;
    vec3 l0 = worldPos;
    vec3 n = floorPlaneNormal;
    vec3 p0 = floorPlanePoint;
    float numerator = dot((p0 - l0), n);
    float denominator = dot(l, n);
    if (denominator != 0.0) {
        float depth = numerator / denominator;

        // Compute fog at this distance underwater
        float fogExponent = abs(depth) * fogDensityBelow;
        transparency = clamp(exp(-abs(fogExponent)), 0.0, 1.0);
    }
}


void applyCircularWaves(inout vec3 v,  out vec3 normal, out float foam)
{
    int i;

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

    v.z += disp;

    vec3 sx = vec3(1.0, 0.0, slope.x * 0.1);
    vec3 sy = vec3(0.0, 1.0, slope.y * 0.1);
    normal = normalize(cross(sx, sy));

    foam = clamp(length(slope), 0.0, 1.0);
}

void applyKelvinWakes(inout vec3 v, inout vec3 normal, inout float foam)
{
    int i;
#ifdef KELVIN_WAKES
    vec2 slope = vec2(0.0, 0.0);
    float disp = 0.0;

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

            displacement *= wakes[i].amplitude;

            vec3 normal = normalize(sample.xyz * 2.0 - 1.0);
            float invmax = inversesqrt( max( dot(T,T), dot(B,B) ) );
            mat3 TBN = mat3( T * invmax, B * invmax, N );

            normal = TBN * normal;
            normal.xy *= wakes[i].amplitude;
            normal = normalize(normal);

            disp += displacement;
            slope.x += normal.x / normal.z;
            slope.y += normal.y / normal.z;
        }
    }

    v.z += disp;

    vec3 sx = vec3(1.0, 0.0, slope.x * 0.1);
    vec3 sy = vec3(0.0, 1.0, slope.y * 0.1);
    normal = (normal + normalize(cross(sx, sy))) * 0.5;

    foam += clamp(length(slope), 0.0, 1.0);
#endif
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
            vec3 x1 = washes[i].propPosition;
            vec3 x2 = x1 + washes[i].deltaPos;

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
                //if (washes[i].number == 0) blend *= 1.0 - clamp(t0 * t0, 0.0, 1.0);
                //blend *= smoothstep(0, 0.1, nd);
                washTexCoords.z = blend;
            }
        }
    }
#endif
}

void gerstner(in vec3 pt, out vec3 P, out vec3 normal, in float sampleFreq)
{
    vec3 disp = vec3(0.0, 0.0, 0.0);
    normal = vec3(0.0, 0.0, 0.0);

    int i;
    for (i = 0; i < numWaves; i++) {
        float nyquistLimit = waves[i].frequency * 2.0;
        if (sampleFreq > nyquistLimit) {
            float nyquistFade = min((sampleFreq - nyquistLimit) / (nyquistLimit * antiAliasing), 1.0);
            float A = waves[i].amplitude * nyquistFade;
            float WA = waves[i].frequency * A;
            float tmp = waves[i].frequency * dot(waves[i].direction, pt.xy) + waves[i].phaseSpeed * time;
            float S = sin(tmp);
            float C = cos(tmp);
            float WAC = WA * C;
            float QAC = waves[i].steepness * A * C;

            disp += vec3(QAC * waves[i].direction.x,
                         QAC * waves[i].direction.y,
                         waves[i].amplitude * S);

            normal += vec3(waves[i].direction.x * WAC,
                           waves[i].direction.y * WAC,
                           waves[i].steepness * WA * S);
        }
    }

    P = pt + disp;
    normal = vec3(normal.x * -1.0, normal.y * -1.0, 1.0 - normal.z);

    foam = 0;
    vec3 wakeNormal = vec3( 0.0 );
    if (doWakes) {
        applyCircularWaves(P, wakeNormal, foam);
        applyKelvinWakes(P, wakeNormal, foam);
        applyPropWash(P);
    }
    normal = normalize(normal + wakeNormal);

    foamTexCoords = P.xy / foamScale;
}

void adjustHeight(inout vec3 v, out vec3 normal, in float cellSize)
{
    // Transform so z is up
    vec3 localV = basis * v;

    float sampleFreq = (2.0 * 3.14159265) / cellSize;

    gerstner(localV.xyz, v, normal, sampleFreq);

    v = invBasis * v;
    normal = invBasis * normal;
}

bool projectToSea(in vec4 v, out vec4 vWorld, out float cellSize)
{
    // Get the line this screen position projects to
    vec4 p0 = v;
    vec4 p1 = v;
    p0.z = 0.0;
    p1.z = 1.0;

    // Transform into world coords
    p0 = invModelviewProj * p0;
    p1 = invModelviewProj * p1;

    // Intersect with the sea level
    vec4 dp = p1 - p0;
    float t = -dot(p0, plane) / dot( dp, plane);
    if (t > 0.0 && t < 1.0) {
        vec4 vLocal;
        vLocal = p0 + dp * t;
        vLocal /= vLocal.w;
        vWorld = vLocal + vec4(cameraPos, 0.0);

        // Compute projected grid cell size while we're at it
        // Project back to clip space
        mat4 modelviewProj = modelview * projection;
        vec4 p2 = modelviewProj * vLocal;
        p2 /= p2.w;

        // Displace it by one grid cell
        float cellSizeScreen = 2.0 / gridSize;
        p2.xy += vec2(cellSizeScreen, cellSizeScreen);

        // Back to world space
        vec4 p21 = p2;
        p21.z = 0.0;
        vec4 p22 = p2;
        p22.z = 1.0;
        p21 = invModelviewProj * p21;
        p22 = invModelviewProj * p22;

        vec4 dp2 = p22 - p21;
        t = -dot(p21, plane) / dot(dp2, plane);
        if (t > 0.0) {
            p2 = p21 += dp2 * t;
            p2 /= p2.w;

            // Get the projected world distance
            cellSize = length(p2 - vLocal);

            return true;
        } else {
            cellSize = 0.0;
            return false;
        }
    } else {
        vWorld = vec4(0.0, 0.0, 0.0, 0.0);
        cellSize = 0.0;
        return false;
    }
}

void main()
{
    vec4 worldPos = vec4(0.0, 0.0, 0.0, 0.0);
    float cellSize = 0.0;
    transparency = 0.0;
#ifdef PROPELLER_WASH
    washTexCoords = vec3(0.0, 0.0, 0.0);
#endif

#ifdef OPENGL32
    vec4 gridPos = gridScale * vec4(vertex.x, vertex.y, 0.0, 1.0);
#else
    vec4 gridPos = gridScale * gl_Vertex;
#endif

    if (projectToSea(gridPos, worldPos, cellSize)) {
        // Displace
        vec3 normal;
        adjustHeight(worldPos.xyz, normal, cellSize);

        N = normalize(normal);
        V = (worldPos.xyz - cameraPos);

        computeTransparency(worldPos.xyz);

        // Project it back again, apply depth offset.
        vec4 v = modelview * vec4(V, 1.0);
        v.w -= depthOffset;
        gl_Position = projection * v;
    } else {
        N = V = vec3(0.0, 0.0, 0.0);
        foamTexCoords = vec2(0.0, 0.0);
#ifdef PROPELLER_WASH
        washTexCoords = vec3(0.0, 0.0, 0.0);
#endif
        fogFactor = 0;
        foam = 0;
        gl_Position = vec4(gridPos.x, gridPos.y, 2.0, 1.0);
    }

    float fogExponent = length(V.xyz) * fogDensity;
    fogFactor = clamp(exp(-abs(fogExponent)), 0.0, 1.0);

}