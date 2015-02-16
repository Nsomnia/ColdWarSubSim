#define PRECISION_GUARD 2.0

#ifdef OPENGL32
in vec2 vertex;
out vec3 V;
out vec2 foamTexCoords;
out vec2 texCoords;
out vec2 noiseTexCoords;
out vec3 up;
out vec4 wakeNormalsAndFoam;
out float fogFactor;
out float transparency;
#ifdef PROPELLER_WASH
out vec3 washTexCoords;
#endif
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
varying vec3 up;
varying vec4 wakeNormalsAndFoam;
varying float fogFactor;
varying float transparency;
#ifdef PROPELLER_WASH
varying vec3 washTexCoords;
#endif
varying float depth;
#ifdef BREAKING_WAVES
varying float breaker;
varying float breakerFade;
#endif
#endif

uniform mat4 modelview;
uniform mat4 projection;
uniform mat4 invModelviewProj;
uniform vec3 radii;
uniform vec3 oneOverRadii;
uniform vec3 north;
uniform vec3 east;
uniform vec3 cameraPos;
uniform mat3 basis;
uniform mat4 gridScale;
uniform float antiAliasing;
uniform float foamScale;
uniform float gridSize;
uniform vec2 textureSize;
uniform sampler2D displacementMap;
uniform vec3 fogColor;
uniform float fogDensity;
uniform float fogDensityBelow;
uniform float invDampingDistance;
uniform bool doWakes;
uniform vec3 floorPlanePoint;
uniform vec3 floorPlaneNormal;
uniform float washLength;
uniform vec4 plane;
uniform float planarHeight;
uniform float planarAdjust;
uniform vec3 referenceLocation;
uniform float depthOffset;

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

void applyBreakingWaves(inout vec3 v)
{
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
        float opacity = 1.0 - transparency;
        finalz = mix(0.0, finalz, pow(opacity, 6.0));

        v.z += finalz;
    }
#endif
}

void applyCircularWaves(inout vec3 v, in vec3 localPos, float fade, out vec2 slope, out float foam)
{
    int i;

    vec3 slope3 = vec3(0.0, 0.0, 0.0);
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
            slope3 +=  D * (derivative / dist);
        }
    }

    v.z += disp * fade;

    slope = (basis * slope3).xy * fade;

    foam = length(slope);
}

void applyKelvinWakes(inout vec3 v, in vec3 localPos, float fade, inout vec2 slope, inout float foam)
{
    int i;
#ifdef KELVIN_WAKES
    vec2 accumSlope = vec2(0,0);
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

            vec3 normal = normalize(sample.xyz * 2.0 - 1.0);
            float invmax = inversesqrt( max( dot(T,T), dot(B,B) ) );
            mat3 TBN = mat3( T * invmax, B * invmax, N );

            normal = TBN * normal;

            // Convert to z-up
            normal = basis * normal;

            normal.xy *= min(1.0, wakes[i].amplitude);
            normal = normalize(normal);

            disp += displacement;

            accumSlope += vec2(normal.x / normal.z, normal.y / normal.z);
        }
    }

    v.z += disp * fade;

    foam += length(accumSlope);
    slope += accumSlope * fade;

#endif
}

void applyPropWash(in vec3 v, in vec3 localPos)
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
        intersection = vec3(0.0, 0.0, 0.0);
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
        intersection = vec3(0.0, 0.0, 0.0);
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
        intersection = vec3(0.0, 0.0, 0.0);
        return false;
    }
}

bool rayPlaneIntersect(in vec4 p0, in vec4 p1, out vec4 intersection)
{
    float offset = 0;
    vec4 p = plane;
    if (plane.w < PRECISION_GUARD && plane.w >= 0) {
        p.w = PRECISION_GUARD;
        offset = PRECISION_GUARD - plane.w;
    } else if (plane.w < 0 && plane.w >= -PRECISION_GUARD) {
        p.w = -PRECISION_GUARD;
        offset = -PRECISION_GUARD - plane.w;
    }

    // Intersect with the sea level
    vec4 dp = p1 - p0;
    float t = -dot(p0, p) / dot( dp, p);
    if (t > 0.0 && t < 1.0) {
        intersection = dp * t + p0;
        intersection /= intersection.w;
        vec3 up = normalize(cameraPos);
        intersection.xyz += up * offset;
        return true;
    } else {
        intersection = vec4(0.0, 0.0, 0.0, 0.0);
        return false;
    }
}

bool projectToSea(in vec4 v, out vec4 worldPos, out vec4 localPos)
{
    // Get the line this screen position projects to
    vec4 p0 = v;
    p0.z = -1.0;
    vec4 p1 = v;
    p1.z = 1.0;

    // Transform into world coords
    p0 = invModelviewProj * p0;
    p1 = invModelviewProj * p1;

    if (plane.w < planarHeight) {
        vec4 intersect;
        // Intersect with the sea level
        if (rayPlaneIntersect(p0, p1, localPos)) {
            worldPos = localPos + vec4(cameraPos, 1.0);
            // Account for error from plane approximation
            float dist = length(localPos.xyz + (plane.xyz * plane.w));
            vec2 v = vec2(radii.x, dist);
            float error = planarAdjust + (length(v) - radii.x);
            vec3 errorv = plane.xyz * error;
            worldPos.xyz -= errorv;
            localPos.xyz -= errorv;
            return true;
        } else {
            localPos = vec4(0.0);
            worldPos = vec4(0.0);
            return false;
        }
    } else {
        vec3 intersect = vec3(0.0);
        vec3 p03 = p0.xyz / p0.w;
        vec3 p13 = p1.xyz / p1.w;
        if (rayEllipsoidIntersect(p03 + cameraPos, p13 - p03, intersect)) {
            localPos = vec4(intersect - cameraPos, 1.0);
            worldPos = vec4(intersect, 1.0);
            return true;
        } else {
            localPos = vec4(0.0);
            worldPos = vec4(0.0);
            return false;
        }
    }

}

vec3 computeArcLengths(in vec3 localPos, in vec3 northDir, in vec3 eastDir)
{
    vec3 pt = referenceLocation + localPos;
    return vec3(dot(pt, eastDir), dot(pt, northDir), 0.0);
}

void main()
{
    wakeNormalsAndFoam = vec4( 0., 0., 1., 0 );
    transparency = 0.0;
#ifdef PROPELLER_WASH
    washTexCoords = vec3(0., 0., 0.);
#endif
    // To avoid precision issues, the translation component of the modelview matrix
    // is zeroed out, and the camera position passed in via cameraPos
    vec4 worldPos = vec4(0.0);

#ifdef OPENGL32
    vec4 gridPos = gridScale * vec4(vertex.x, vertex.y, 0.0, 1.0);
#else
    vec4 gridPos = gridScale * gl_Vertex;
#endif

    vec4 localPos = vec4(0.0);
    if (projectToSea(gridPos, worldPos, localPos)) {
        // Here, worldPos is relative to the center of the Earth, since
        // projectToSea added the camera position back in after transforming

        float fogExponent = length(localPos.xyz) * fogDensity;
        fogFactor = clamp(exp(-abs(fogExponent)), 0.0, 1.0);

        up = normalize(worldPos.xyz);

        // Transform position on the ellipsoid into a planar reference,
        // x east, y north, z up
        vec3 planar = computeArcLengths(localPos.xyz, north, east);

        // Compute water depth and transparency
        computeTransparency(worldPos.xyz);

        float fade = 1.0 - smoothstep(0.0, 1.0, length(localPos.xyz) * invDampingDistance);

#ifdef BREAKING_WAVES
        // Fade out waves in the surge zone
        float depthFade = 1.0;

        if (surgeDepth > 0) {
            depthFade = min(surgeDepth, depth) / surgeDepth;
        }

        fade *= depthFade;
        breakerFade = depthFade;
#endif

        // Compute displacement
        texCoords = planar.xy / textureSize;
#ifdef OPENGL32
        vec3 disp = texture(displacementMap, texCoords).xyz;
#else
        vec3 disp = texture2D(displacementMap, texCoords).xyz;
#endif
        // Hide the backs of waves if we're transparent
        float opacity = 1.0 - transparency;
        disp.z = mix(0.0, disp.z, pow(opacity, 6.0));

        disp = disp * fade;

        localPos.xyz += disp.x * east + disp.y * north;

        foamTexCoords = (planar.xy + disp.xy) / foamScale;
        noiseTexCoords = texCoords * 0.03;

        if (doWakes) {
            vec2 slope;
            float foam;

            applyCircularWaves(planar, localPos.xyz, fade, slope, foam);
            applyKelvinWakes(planar, localPos.xyz, fade, slope, foam);
            applyPropWash(planar, localPos.xyz);

            vec3 sx = vec3(1.0, 0.0, slope.x);
            vec3 sy = vec3(0.0, 1.0, slope.y);
            wakeNormalsAndFoam.xyz = normalize(cross(sx, sy));
            wakeNormalsAndFoam.w = min(1.0, foam);

        } else {
            fade = 0;
        }

        applyBreakingWaves(planar);

        // Transform back into geocentric coords
        localPos.xyz += (disp.z + planar.z) * up;

        V = localPos.xyz;

        // Project it back again, apply depth offset.
        vec4 v = modelview * localPos;
        v.w -= depthOffset;
        gl_Position = projection * v;

    } else {
        // No intersection, move the vert out of clip space
        gl_Position = vec4(gridPos.x, gridPos.y, 100.0, 1.0);
        V = vec3(0.0);
        foamTexCoords = vec2(0.0);
        texCoords = vec2(0.0);
        noiseTexCoords = vec2(0.0);
        up = vec3(0.0);
        fogFactor = 0.0;
#ifdef PROPELLER_WASH
        washTexCoords = vec3(0.0);
#endif
    }
}