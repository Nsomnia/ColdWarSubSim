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

#define MAX_WAVES 5

uniform mat4 modelview;
uniform mat4 projection;
uniform mat4 invModelviewProj;
uniform mat3 basis;
uniform mat3 invBasis;
uniform vec3 radii;
uniform vec3 oneOverRadii;
uniform vec3 north;
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

void computeTransparency(in vec3 worldPos, in vec3 up)
{
    // Compute depth at this position
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

void applyCircularWaves(inout vec3 v, in vec3 localPos, out vec3 normal)
{
    int i;

    vec3 slope = vec3(0.0, 0.0, 0.0);
    float disp = 0.0;

    for (i = 0; i < MAX_CIRCULAR_WAVES; i++) {

        vec3 D = (localPos - circularWaves[i].position);
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
}

void applyKelvinWakes(inout vec3 v, in vec3 up, in vec3 localPos)
{
    int i;
#ifdef KELVIN_WAKES
    vec3 accumNormal = vec3(0,0,0);
    float disp = 0.0;

    for (i = 0; i < MAX_KELVIN_WAKES; i++) {

        vec3 X0 = wakes[i].position - wakes[i].shipPosition;
        vec3 T = normalize(X0);
        vec3 N = up;
        vec3 B = normalize(cross(N, T));

        vec3 P = localPos - wakes[i].shipPosition;
        vec3 X;
        X.x = dot(P, T);
        X.y = dot(P, B);
//      X.z = dot(P, N);

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

            disp += displacement;
        }
    }

    v.z += disp;
#endif
}

void applyPropWash(in vec3 v, in vec3 localPos, in vec3 up)
{
#ifdef PROPELLER_WASH

    washTexCoords = vec3(0.0, 0.0, 0.0);

    for (int i = 0; i < MAX_PROP_WASHES; i++) {

        if (washes[i].distFromSource == 0) continue;

        vec3 C = washes[i].deltaPos;
        vec3 A = localPos - washes[i].propPosition;
        vec3 B = localPos - (washes[i].propPosition + C);
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
    P = pt;
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

            P += vec3(QAC * waves[i].direction.x,
                      QAC * waves[i].direction.y,
                      waves[i].amplitude * S);

            normal += vec3(waves[i].direction.x * WAC,
                           waves[i].direction.y * WAC,
                           waves[i].steepness * WA * S);
        }
    }

    normal = vec3(normal.x * -1.0, normal.y * -1.0, 1.0 - normal.z);
}

// Intersect a ray of origin P0 and direction v against a unit sphere centered at the origin
bool raySphereIntersect(in vec3 p0, in vec3 v, out vec3 intersection)
{
    float twop0v = 2.0 * dot(p0, v);
    float p02 = dot(p0, p0);
    float v2 = dot(v, v);

    float disc = twop0v * twop0v - (4.0 * v2)*(p02 - 1.0);
    if (disc > 0.0) {
        float discSqrt = sqrt(disc);
        float den = 2.0 * v2;
        float t = (-twop0v - discSqrt) / den;
        if (t < 0.0) {
            t = (-twop0v + discSqrt) / den;
        }
        intersection = p0 + t * v;
        return true;
    } else {
        return false;
    }
}

// Intersect a ray against an ellipsoid centered at the origin
bool rayEllipsoidIntersect(in vec3 R0, in vec3 Rd, out vec3 intersection)
{
    // Distort the ray so it aims toward a unit sphere, do a sphere intersection
    // and scale it back to the ellpsoid's space.

    vec3 scaledR0 = R0 * oneOverRadii;
    vec3 scaledRd = Rd * oneOverRadii;

    vec3 sphereIntersection;
    if (raySphereIntersect(scaledR0, scaledRd, sphereIntersection)) {
        intersection = sphereIntersection * radii;
        return true;
    } else {
        return false;
    }
}

// Alternate, faster method - but it can't handle viewpoints inside the ellipsoid.
// If you don't need underwater views, this may be better for you.
bool rayEllipsoidIntersectFast(in vec3 R0, in vec3 Rd, out vec3 intersection)
{
    vec3 q = R0 * oneOverRadii;
    vec3 bUnit = normalize(Rd * oneOverRadii);
    float wMagnitudeSquared = dot(q, q) - 1.0;

    float t = -dot(bUnit, q);
    float tSquared = t * t;

    if ((t >= 0.0) && (tSquared >= wMagnitudeSquared)) {
        float temp = t - sqrt(tSquared - wMagnitudeSquared);
        vec3 r = (q + temp * bUnit);
        intersection = r * radii;

        return true;
    } else {
        return false;
    }
}

bool projectToSea(in vec4 v, out vec4 worldPos, out float cellSize)
{
    // Get the line this screen position projects to
    vec4 p0 = v;
    p0.z = -1.0;
    vec4 p1 = v;
    p1.z = 1.0;

    // Transform into world coords
    p0 = invModelviewProj * p0;
    p1 = invModelviewProj * p1;

    vec3 p03 = p0.xyz / p0.w;
    vec3 p13 = p1.xyz / p1.w;

    // Intersect with the sea level
    vec3 intersect;

    if (rayEllipsoidIntersect(p03 + cameraPos, p13 - p03, intersect)) {
        worldPos = vec4(intersect.x, intersect.y, intersect.z, 1.0);

        // Compute projected grid cell size while we're at it
        // Project back to clip space
        vec4 worldPosCamera4 = vec4(0.0, 0.0, 0.0, 1.0);
        worldPosCamera4.xyz = worldPos.xyz - cameraPos;
        vec4 p2 = modelview * projection * worldPosCamera4;
        p2 /= p2.w;

        // Displace it by one grid cell
        p2.xy += vec2(2.0 / gridSize, 2.0 / gridSize);

        // Back to world space
        vec4 p21 = p2;
        vec4 p22 = p2;
        p21.z = 0.0;
        p22.z = 1.0;

        p21 = invModelviewProj * p21;
        p21 /= p21.w;
        p22 = invModelviewProj * p22;
        p22 /= p22.w;

        if (rayEllipsoidIntersect(p21.xyz + cameraPos, (p22.xyz - p21.xyz), intersect)) {
            // Get the projected world distance
            cellSize = length(intersect - worldPos.xyz);

            return true;
        }
    }

    return false;
}

vec3 computeArcLengths(in vec3 worldPos, in vec3 northDir, in vec3 eastDir)
{
    vec3 pt = worldPos - cameraPos;
    return vec3(dot(pt, eastDir), dot(pt, northDir), 0.0);
}

void main()
{
    // To avoid precision issues, the translation component of the modelview matrix
    // is zeroed out, and the camera position passed in via cameraPos

    vec4 worldPos;
    float cellSize;

    transparency = 0.0;
#ifdef PROPELLER_WASH
    washTexCoords = vec3(0.0, 0.0, 0.0);
#endif

#ifdef OPENGL32
    vec4 gridPos = gridScale * vec4(vertex.x, vertex.y, 0.0, 1.0);
#else
    vec4 gridPos = gridScale * gl_Vertex;
#endif

    bool above = true;

    if (projectToSea(gridPos, worldPos, cellSize)) {
        // Here, worldPos is relative to the center of the Earth, since
        // projectToSea added the camera position back in after transforming

        above = length(cameraPos.xyz) > length(worldPos.xyz);
        vec3 up = normalize(worldPos.xyz);
        vec3 east = normalize(cross(north, up));
        vec3 nnorth = normalize(cross(up, east));

        // Transform position on the ellipsoid into a planar reference,
        // x east, y north, z up
        vec3 planar = computeArcLengths(worldPos.xyz, nnorth, east);

        // Compute displacement and surface normal from Gerstner waves
        vec3 P, normal;
        gerstner(planar, P, normal, (2.0 * 3.14159265) / cellSize);

        // Add in ship wakes
        vec3 wakeNormal = vec3(0.,0.,1.);
        if (doWakes) {
            vec3 localPos = worldPos.xyz - cameraPos.xyz;
            applyCircularWaves(P, localPos.xyz, wakeNormal);
            applyKelvinWakes(P, up, localPos.xyz);
            applyPropWash(P, localPos.xyz, up);
        }

        vec3 disp = P - planar;

        foam = 0.0; // max(0.0, disp.z - foamHeight);
        foamTexCoords = planar.xy / foamScale;

        // Transform back into geocentric coords
        worldPos.xyz = worldPos.xyz + disp.x * east + disp.y * nnorth + disp.z * up;

        computeTransparency(worldPos.xyz, up);

        V = normalize(worldPos.xyz - cameraPos);
        N = normalize(normal.x * east + normal.y * nnorth + normal.z * up);
        N = normalize(N + wakeNormal - vec3(0.0,0.0,1.0));

        // Make relative to the camera, and project it back again
        worldPos.xyz -= cameraPos;
        // Project it back again, apply depth offset.
        vec4 v = modelview * worldPos;
        v.w -= depthOffset;
        gl_Position = projection * v;
    } else {
        // No intersection, move the vert out of clip space
        gl_Position = vec4(gridPos.x, gridPos.y, 2.0, 1.0);
    }

    float fogExponent = length(V.xyz) * fogDensity;
    fogFactor = clamp(exp(-abs(fogExponent)), 0.0, 1.0);
}