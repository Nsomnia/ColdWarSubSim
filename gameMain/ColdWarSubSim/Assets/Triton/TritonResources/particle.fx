uniform float4x4 mvProj;
uniform float4x4 modelView;
uniform float time;
uniform float3 g;
uniform float4 lightColor;
uniform float transparency;
uniform float3 cameraPos;
uniform float3 refOffset;

uniform bool hasHeightMap;
uniform float4x4 heightMapMatrix;

#ifdef DX9
uniform float invSizeFactor;
#endif

struct VSInput {
float4 position :
    POSITION;
float4 velocity :
    NORMAL;
};

#ifdef DX9

struct VSOutput {
float4 position :
    POSITION;
float pointSize :
    PSIZE;
float2 texCoord :
    TEXCOORD0;
float elapsed:
    TEXCOORD1;
};

struct PSSceneIn {
float4 pos :
    POSITION0;
float2 tex :
    TEXTURE0;
float elapsed :
    TEXTURE1;
};

TEXTURE sprayTexture;
TEXTURE heightMap;

sampler2D gSpraySampler = sampler_state {
    Texture = (sprayTexture);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

sampler2D gHeightSampler = sampler_state {
    Texture = (heightMap);
    MipFilter = LINEAR;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

#else

struct VSOutput {
float4 position :
    POSITION;
float pointSize :
    PSIZE;
float elapsed:
    FOG;
};

struct PSSceneIn {
float4 pos :
    SV_Position;
float2 tex :
    TEXTURE0;
float elapsed :
    FOG;
};

Texture2D sprayTexture;
Texture2D heightMap;

uniform float4x4 invModelView;

SamplerState gTriLinearSamClamp {
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

SamplerState gBiLinearSamClamp {
    Filter = MIN_MAG_LINEAR_MIP_POINT;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

cbuffer cbImmutable {
    float3 g_positions[4] =
    {
        float3( -1.0f, 1.0f, 0.0f ),
        float3( 1.0f, 1.0f, 0.0f ),
        float3( -1.0f, -1.0f, 0.0f ),
        float3( 1.0f, -1.0f, 0.0f ),
    };
    float2 g_texcoords[4] =
    {
        float2(0.0f,1.0f),
        float2(1.0f,1.0f),
        float2(0.0f,0.0f),
        float2(1.0f,0.0f),
    };
};

[maxvertexcount(4)]
void GS(point VSOutput input[1], inout TriangleStream<PSSceneIn> SpriteStream)
{
    PSSceneIn output;

    //
    // Emit two new triangles
    //
    for(int i=0; i<4; i++) {
        float3 position = g_positions[i] * input[0].pointSize;
        position = mul( position.xyz, (float3x3)invModelView ) + input[0].position.xyz;
        output.pos = mul( float4(position,1.0f), mvProj );

        output.tex = g_texcoords[i];
        output.elapsed = input[0].elapsed;

        SpriteStream.Append(output);
    }
    SpriteStream.RestartStrip();
}

#endif

VSOutput VS(VSInput Input)
{
    VSOutput Out;

    float elapsed = time - Input.position.w;

    // p(t) = p0 + v0t + 0.5gt^2
    float3 relPos = 0.5f * g * elapsed * elapsed + Input.velocity.xyz * elapsed + (Input.position.xyz);
    float3 worldPos = relPos + cameraPos - refOffset;

    if (hasHeightMap) {
        float particleSize;
        float4 texCoords = mul(float4(worldPos, 1.0), heightMapMatrix);
        float4 tc4 = float4(texCoords.x, texCoords.y, 0.0f, 0.0f);

#ifdef DX9
        float height = tex2Dlod(gHeightSampler, tc4).x;
        particleSize = Input.velocity.w * invSizeFactor;
        Out.texCoord = float2(0,0);
#else
        float height = heightMap.SampleLevel(gBiLinearSamClamp, texCoords, 0).x;
        particleSize = Input.velocity.w;
#endif
        if (height > -particleSize) {
            Out.pointSize = 0.0f;
            Out.position = float4(0.0f, 0.0f, 2.0f, 1.0f);
            Out.elapsed = elapsed;
            return Out;
        }
    }

    float4 wPos = float4(relPos - refOffset, 1.0f);

    float4 eyeSpacePos = mul(wPos, modelView);
    float dist = length(eyeSpacePos.xyz);

#ifdef DX9
    Out.pointSize = max(1.0f, Input.velocity.w / dist);
    Out.position = mul(wPos, mvProj);
#else
    Out.pointSize = Input.velocity.w;
    Out.position = wPos;
#endif

    Out.elapsed = elapsed;

    return Out;
}

#ifdef DX9
float4 PS(float3 texCoords : TEXCOORD0, float elapsed : TEXCOORD1) : COLOR {

    float decay = clamp(exp(-2.0f * elapsed) * 5.0f * sin(elapsed), 0.0f, 1.0f);
    float3 spray = tex2D(gSpraySampler, texCoords.xy).xyz * lightColor.xyz * decay * transparency;

    if (length(spray) < 0.05f) {
        discard;
    }

    return float4(spray.xyz, clamp(spray.x, 0.0f, 1.0f));
}
#else
float4 PS(PSSceneIn input) : SV_TARGET {

    float decay = clamp(exp(-2.0f * input.elapsed) * 2.0f * sin(3.0f * input.elapsed), 0.0, 1.0);

    float3 spray = sprayTexture.Sample(gTriLinearSamClamp, input.tex).xyz * lightColor.xyz * decay * transparency;

    if (length(spray) < 0.05f) {
        discard;
    }

    return float4(spray.xyz, clamp(spray.x, 0.0f, 1.0f));
}
#endif

#ifdef DX11
technique11 ColorTech {
    pass P0
    {
        SetVertexShader( CompileShader( vs_5_0, VS() ) );
        SetGeometryShader( CompileShader( gs_5_0, GS() ) );
        SetPixelShader( CompileShader( ps_5_0, PS() ) );
    }
}
#endif

#ifdef DX10
technique10 ColorTech {
    pass P0
    {
        SetVertexShader( CompileShader( vs_4_0, VS() ) );
        SetGeometryShader( CompileShader( gs_4_0, GS() ) );
        SetPixelShader( CompileShader( ps_4_0, PS() ) );
    }
}
#endif

#ifdef DX10LEVEL9
technique10 ColorTech {
    pass P0
    {
        SetVertexShader( CompileShader( vs_4_0_level_9_1, VS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader( ps_4_0_level_9_1, PS() ) );
    }
}
#endif

#ifdef DX9
technique {
    pass P0
    {
        SetVertexShader( CompileShader( vs_3_0, VS() ) );
#ifdef PS30
        SetPixelShader( CompileShader( ps_3_0, PS() ) );
#else
        SetPixelShader( CompileShader( ps_2_0, PS() ) );
#endif
    }
}
#endif
