#ifdef OPENGL32
in vec4 position;
#else
attribute vec4 position;
#endif

uniform mat4 mvProj;

void main()
{
    vec4 clipPos = mvProj * position;
    gl_Position = clipPos;
}
