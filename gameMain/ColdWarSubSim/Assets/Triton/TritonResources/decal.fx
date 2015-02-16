uniform float4x4 mvProj;

uniform float4x4 inverseView;
uniform float4x4 decalMatrix;
uniform float2 inverseViewport;
uniform float4x4 projMatrix;
uniform float4 viewport;
uniform float4x4 inverseProjection;
uniform float depthOffset;
uniform float alpha;
uniform float4 lightColor;

struct VSInput {
float4 position :
    POSITION;
};

#ifdef DX9

struct VSOutput {
float4 position :
    POSITION;
};

struct PSSceneIn {
float4 pos :
    POSITION0;
};

struct PSSceneOut {
float4 color:
    COLOR;
float depth :
    DEPTH;
};

TEXTURE depthTexture;
TEXTURE decalTexture;

sampler2D gDepthTextureSampler = sampler_state {
    Texture = (depthTexture);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

sampler2D gDecalTextureSampler = sampler_state {
    Texture = (decalTexture);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

#else

struct VSOutput {
float4 position :
    SV_Position;
};

struct PSSceneIn {
float4 pos :
    SV_Position;
};

struct PSSceneOut {
float4 color :
    SV_Target;
float depth :
    SV_Depth;
};

Texture2D depthTexture;
Texture2D decalTexture;

SamplerState gTriLinearSamClamp {
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = WRAP;
    AddressV = WRAP;
};

SamplerState gBiLinearSamClamp {
    Filter = MIN_MAG_LINEAR_MIP_POINT;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

#endif

VSOutput VS(VSInput Input)
{
    VSOutput Out;

    float4 clipPos = mul(Input.position, mvProj);
    Out.position = clipPos;

    return Out;
}

// Function for converting depth to view-space position
// in deferred pixel shader pass.  vTexCoord is a texture
// coordinate for a full-screen quad, such that x=0 is the
// left of the screen, and y=0 is the top of the screen.
float4 CalcEyeFromWindow(float3 windowSpace)
{
    // Get x/w and y/w from the viewport position
    float x = windowSpace.x * 2 - 1;
    float y = (1 - windowSpace.y) * 2 - 1;
    float4 vProjectedPos = float4(x, y, windowSpace.z, 1.0f);
    // Transform by the inverse projection matrix
    float4 vPositionVS = mul(vProjectedPos, inverseProjection);
    vPositionVS /= vPositionVS.w;
    return vPositionVS;
}

#ifdef DX9
PSSceneOut PS(float2 pos : VPOS)
{
    float2 fragPos = pos;
#else
PSSceneOut PS(PSSceneIn input)
{
    float4 fragPos = input.pos;
#endif

    float2 depthUV = (fragPos.xy - viewport.xy) * inverseViewport;

#ifdef DX9
    float depth = tex2D(gDepthTextureSampler, depthUV).x;
#else
    float depth = depthTexture.Sample(gBiLinearSamClamp, depthUV).x;
#endif

    float fragDepth = depth + depthOffset;

    float4 eyeSpace = CalcEyeFromWindow(float3(depthUV, depth));

    float4 worldRelative = mul(eyeSpace, inverseView);

    float4 clip = mul(worldRelative, decalMatrix);

    float4 ndc = clip / clip.w;

    float2 tc = (ndc.xy * 0.5) + 0.5;

    if (tc.x < 0 || tc.x > 1 || tc.y < 0 || tc.y > 1) {
        discard;
    }

#ifdef DX9
    float4 texcolor = tex2D(gDecalTextureSampler, tc);
#else
    float4 texcolor = decalTexture.Sample(gTriLinearSamClamp, tc);
#endif

    float4 color = texcolor;
    color *= lightColor;
    color.a *= alpha;

    PSSceneOut output;
    output.color = color;
    output.depth = fragDepth;
    return output;
}

#ifdef DX11
technique11 ColorTech {
    pass P0
    {
        SetVertexShader(CompileShader(vs_5_0, VS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_5_0, PS()));
    }
}
#endif

#ifdef DX10
technique10 ColorTech {
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0, VS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0, PS()));
    }
}
#endif

#ifdef DX10LEVEL9
technique10 ColorTech {
    pass P0
    {
        SetVertexShader(CompileShader(vs_4_0_level_9_1, VS()));
        SetGeometryShader(NULL);
        SetPixelShader(CompileShader(ps_4_0_level_9_1, PS()));
    }
}
#endif

#ifdef DX9
technique {
    pass P0
    {
        SetVertexShader(CompileShader(vs_3_0, VS()));
#ifdef PS30
        SetPixelShader(CompileShader(ps_3_0, PS()));
#else
        SetPixelShader(CompileShader(ps_2_0, PS()));
#endif
    }
}
#endif
