#ifdef OPENGL32
out vec4 fragColor;
#endif

uniform sampler2D depthTexture;
uniform sampler2D decalTexture;
uniform mat4 inverseView;
uniform mat4 decalMatrix;
uniform vec2 inverseViewport;
uniform mat4 projMatrix;
uniform vec4 viewport;
uniform mat4 inverseProjection;
uniform vec2 depthRange;
uniform float depthOffset;
uniform float alpha;
uniform vec4 lightColor;

void user_decal_color(in vec4 textureColor, in float alpha, in vec4 lightColor, inout vec4 finalColor);

vec4 CalcEyeFromWindow(vec3 windowSpace)
{
    vec3 ndcPos;
    ndcPos.xy = ((2.0 * windowSpace.xy) - (2.0 * viewport.xy)) / (viewport.zw) - 1;
    ndcPos.z = (2.0 * windowSpace.z - depthRange.x - depthRange.y) / (depthRange.y - depthRange.x);

    vec4 clipPos;
    clipPos.w = projMatrix[3][2] / (ndcPos.z - (projMatrix[2][2] / projMatrix[2][3]));
    clipPos.xyz = ndcPos * clipPos.w;

    vec4 eyePos = inverseProjection * clipPos;

    return eyePos;
}

void main()
{
    vec2 depthUV = (gl_FragCoord.xy - viewport.xy) * inverseViewport;

#ifdef OPENGL32
    float depth = texture(depthTexture, depthUV).x;
#else
    float depth = texture2D(depthTexture, depthUV).x;
#endif

    gl_FragDepth = depth + depthOffset;

    vec4 eyeSpace = CalcEyeFromWindow(vec3(gl_FragCoord.xy, depth));

    vec4 worldRelative = inverseView * eyeSpace;

    vec4 clip = decalMatrix * worldRelative;

    vec4 ndc = clip / clip.w;

    vec2 tc = (ndc.xy * 0.5) + 0.5;

    if (clamp(tc, 0, 1) != tc) {
        discard;
        return;
    }

#ifdef OPENGL32
    vec4 texcolor = texture(decalTexture, tc);
#else
    vec4 texcolor = texture2D(decalTexture, tc);
#endif

    vec4 color = texcolor;
    color *= lightColor;
    color.a *= alpha;

    user_decal_color(texcolor, alpha, lightColor, color);

#ifdef OPENGL32
    fragColor = color;
#else
    gl_FragColor = color;
#endif
}
