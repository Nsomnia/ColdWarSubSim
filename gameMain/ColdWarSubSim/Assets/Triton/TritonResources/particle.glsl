#ifdef OPENGL32
in vec3 initialPosition;
in vec3 initialVelocity;
in float size;
in float startTime;
in float offsetX;
in float offsetY;
in float texCoordX;
in float texCoordY;
out float elapsed;
out vec2 texCoord;
out vec3 vEye;
out vec3 vWorld;
#else
attribute vec3 initialPosition;
attribute vec3 initialVelocity;
attribute float size;
attribute float startTime;
attribute float offsetX;
attribute float offsetY;
attribute float texCoordX;
attribute float texCoordY;
varying float elapsed;
varying vec2 texCoord;
varying vec3 vEye;
varying vec3 vWorld;
#endif

uniform mat4 mvProj;
uniform mat4 modelView;
uniform float time;
uniform vec3 g;
uniform vec3 cameraPos;
uniform vec3 refOffset;

uniform bool hasHeightMap;
uniform mat4 heightMapMatrix;
uniform sampler2D heightMap;
uniform float invSizeFactor;

void main()
{
    elapsed = time - startTime;

    // p(t) = p0 + v0t + 0.5gt^2
    vec3 relPos = 0.5 * g * elapsed * elapsed + initialVelocity * elapsed + initialPosition;
    vec2 offset = vec2(offsetX, offsetY);

    vec3 worldPos = relPos + cameraPos - refOffset;

    float depthFade = 1.0;

    if (hasHeightMap) {
#ifdef OPENGL32
        float height = texture(heightMap, (heightMapMatrix * vec4(worldPos, 1.0)).xy).x;
#else
        float height = texture2D(heightMap, (heightMapMatrix * vec4(worldPos, 1.0)).xy).x;
#endif

        if (height > -(size * invSizeFactor)) {
            gl_PointSize = 0;
            gl_Position = vec4(0.0,0.0,100.0,0.0);
            return;
        }
    }

    vec4 wPos = vec4(relPos - refOffset, 1.0);

    vec4 eyeSpacePos = modelView * wPos;

#ifdef POINT_SPRITES
    float dist = length(eyeSpacePos.xyz);
    gl_PointSize = max(1.0, size / dist);
#endif

    eyeSpacePos.xy += offset;

    wPos = eyeSpacePos * modelView;

    texCoord = vec2(texCoordX, texCoordY);

    gl_Position = mvProj * wPos;

    vEye = eyeSpacePos.xyz / eyeSpacePos.w;
    vWorld = worldPos;
}
