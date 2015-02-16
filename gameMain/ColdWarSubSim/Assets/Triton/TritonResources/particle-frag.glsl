#ifdef OPENGL32
in float elapsed;
in vec2 texCoord;
in vec3 vEye;
in vec3 vWorld;
out vec4 fragColor;
#else
varying float elapsed;
varying vec2 texCoord;
varying vec3 vEye;
varying vec3 vWorld;
#endif

uniform sampler2D particleTexture;
uniform vec4 lightColor;
uniform float time;
uniform float transparency;

void user_particle_color(in vec3 vEye, in vec3 vWorld, in vec4 texColor,
                         in vec4 lightColor, in float transparency, in float decay,
                         inout vec4 additiveColor);

void main()
{
    float decay = clamp(exp(-2.0 * elapsed) * 5.0 * sin(elapsed), 0.0, 1.0);

#ifdef POINT_SPRITES
    vec2 tex = gl_PointCoord;
#else
    vec2 tex = texCoord;
#endif

#ifdef OPENGL32
    vec4 texColor = texture(particleTexture, tex);
#else
    vec4 texColor = texture2D(particleTexture, tex);
#endif

    vec4 color = texColor * lightColor * decay * transparency;

    user_particle_color(vEye, vWorld, texColor, lightColor, transparency, decay, color);

    if (length(color.xyz) < 0.05) {
        discard;
    } else {
#ifdef OPENGL32
        fragColor = color;
#else
        gl_FragColor = color;
#endif
    }
}
