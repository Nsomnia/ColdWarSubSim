// Buffers for ProcessWater
StructuredBuffer<float2>    g_H0            :
register(t0);
StructuredBuffer<float>     g_omega         :
register(t1);
RWByteAddressBuffer         g_bufOut1       :
register(u0);

// Buffers for FlipSigns
ByteAddressBuffer           g_flipIn1       :
register(t0);
RWStructuredBuffer<float>   g_flipOut1      :
register(u0);

// Buffers for ComputeTextures
StructuredBuffer<float>     g_Real          :
register(t0);
RWTexture2D<float4>         g_displacement  :
register(u0);
RWTexture2D<float4>         g_slopeFoam     :
register(u1);
RWStructuredBuffer<float>   g_foamBuffer    :
register(u2);

#define BLOCK_SIZE_X 16
#define BLOCK_SIZE_Y 16

cbuffer cbparams :
register(b0)
{
    float t;
    uint2 dim;
    float depth;
    float2 size;
    float2 twoCellsSize;
    float chopScale;
    float dt;
    float pad1, pad2;
};

[numthreads(BLOCK_SIZE_X, BLOCK_SIZE_Y, 1)]
void FlipSigns(uint3 DTid : SV_DispatchThreadID)
{
    float signs[2] = {1, -1};
    float mul = signs[DTid.x + DTid.y & 1];

    unsigned int stride = dim.x * 8;
    unsigned int i = DTid.y * stride + DTid.x * 8;
    unsigned int bufSizeIn = stride * dim.y;

    unsigned int o = DTid.y * dim.x + DTid.x;
    unsigned int bufSizeOut = dim.x * dim.y;

    float realValue = asfloat(g_flipIn1.Load(i));
    realValue *= mul;
    g_flipOut1[o] = realValue;
    i += bufSizeIn;
    o += bufSizeOut;

    realValue = asfloat(g_flipIn1.Load(i));
    realValue *= mul;
    g_flipOut1[o] = realValue;
    i += bufSizeIn;
    o += bufSizeOut;

    realValue = asfloat(g_flipIn1.Load(i));
    realValue *= mul;
    g_flipOut1[o] = realValue;
}

[numthreads(BLOCK_SIZE_X, BLOCK_SIZE_Y, 1)]
void ComputeTextures(uint3 DTid : SV_DispatchThreadID)
{
    int2 gridPos;
    gridPos.x = DTid.x;
    gridPos.y = DTid.y;

    int bufSize = dim.x * dim.y;
    int hIdx = gridPos.y * dim.x + gridPos.x;
    int chopXIdx = hIdx + bufSize;
    int chopZIdx = chopXIdx + bufSize;

    float4 color;
    color.x = g_Real[chopXIdx] * chopScale;
    color.y = g_Real[chopZIdx] * chopScale;
    color.z = g_Real[hIdx];
    color.w = 1.0f;
    g_displacement[gridPos] = color;

    int prevX = gridPos.x > 0 ? gridPos.x-1 : (int)dim.x - 1;
    int nextX = gridPos.x < (int)dim.x - 1 ? gridPos.x + 1 : 0;
    int prevY = gridPos.y > 0 ? gridPos.y - 1 : (int)dim.y - 1;
    int nextY = gridPos.y < (int)dim.y - 1 ? gridPos.y + 1 : 0;

    float xWidth = twoCellsSize.x + g_Real[gridPos.y * dim.x + nextX + bufSize] - g_Real[gridPos.y * dim.x + prevX + bufSize];
    float yDepth = twoCellsSize.y + g_Real[nextY * dim.x + gridPos.x + bufSize * 2] - g_Real[prevY * dim.x + gridPos.x + bufSize * 2];
    float xDelta = (g_Real[gridPos.y * dim.x + nextX] - g_Real[gridPos.y * dim.x + prevX]);
    float yDelta = (g_Real[nextY * dim.x + gridPos.x] - g_Real[prevY * dim.x + gridPos.x]);
	float dx = xDelta / xWidth;
	float dy = yDelta / yDepth;

	// Rate at which x displacement changes if x is constant
	float sxx = (g_Real[nextY * dim.x + gridPos.x + bufSize] - g_Real[prevY * dim.x + gridPos.x + bufSize]) / yDepth;
	// Rate at which y displacement changes if x is constant
	float syx = (g_Real[nextY * dim.x + gridPos.x + bufSize * 2] - g_Real[prevY * dim.x + gridPos.x + bufSize * 2]) / yDepth;
	// Rate at which y displacement changes if y is constant
	float syy = (g_Real[gridPos.y * dim.x + nextX + bufSize * 2] - g_Real[gridPos.y * dim.x + prevX + bufSize * 2]) / xWidth;
	// Rate at which x displacement changes if y is constant
	float sxy = (g_Real[gridPos.y * dim.x + nextX + bufSize] - g_Real[gridPos.y * dim.x + prevX + bufSize]) / xWidth;
	
    color.x = dx;
    color.y = dy;

    float Jxx = 1.0 + chopScale * sxx;
    float Jyy = 1.0 + chopScale * syy;
    float Jxy = chopScale * sxy;
    float Jyx = chopScale * syx;
    float J = Jxx * Jyy - Jxy * Jyx;
    
    float foam = 1.0f - J;

    color.z = foam;

    g_slopeFoam[gridPos] = color;
    g_foamBuffer[gridPos.y * dim.x + gridPos.x] = foam;
}

[numthreads(BLOCK_SIZE_X, BLOCK_SIZE_Y, 1)]
void ProcessWater(uint3 DTid : SV_DispatchThreadID)
{
    int h0idx = DTid.y*(dim.x + 1) + DTid.x;
    float2 h0 = g_H0[h0idx];

    int h0NegKIdx = (dim.y - DTid.y) * (dim.x + 1) + (dim.x - DTid.x);
    float2 h0NegKConj = g_H0[h0NegKIdx];
    h0NegKConj.y *= -1;

    uint2 half = dim / 2;
    float2 kPos;
    kPos.x = (float)DTid.x - (float)half.x;
    kPos.y = (float)DTid.y - (float)half.y;

    const float TWOPI = 3.14159265f * 2.0f;
    float2 K = (TWOPI * kPos) / size;

    float dotKK = dot(K, K);

    float wk = g_omega[DTid.y * dim.x + DTid.x];
    float wkt = wk * t;
    float cwkt, swkt;
    sincos(wkt, swkt, cwkt);

    float2 term1, term2;
    term1.x = h0.x * cwkt - h0.y * swkt;
    term1.y = h0.x * swkt + h0.y * cwkt;
    term2.x = h0NegKConj.x * cwkt - h0NegKConj.y * -swkt;
    term2.y = h0NegKConj.x * -swkt + h0NegKConj.y * cwkt;

    float2 Htilde = term1 + term2;

    int outIdx1 = DTid.y * 8 * dim.x + DTid.x * 8;
    int outIdx2 = outIdx1 + (dim.x * dim.y * 8);
    int outIdx3 = outIdx2 + (dim.x * dim.y * 8);

    g_bufOut1.Store(outIdx1, asuint(Htilde.x));
    g_bufOut1.Store(outIdx1 + 4, asuint(Htilde.y));

    if (dotKK > 0) {
        float2 chopImg = normalize(K);
        float2 cX, cZ;
        cX.x = -(chopImg.x * Htilde.y);
        cX.y = (chopImg.x * Htilde.x);
        cZ.x = -(chopImg.y * Htilde.y);
        cZ.y = (chopImg.y * Htilde.x);

        g_bufOut1.Store(outIdx2, asuint(cX.x));
        g_bufOut1.Store(outIdx2 + 4, asuint(cX.y));
        g_bufOut1.Store(outIdx3, asuint(cZ.x));
        g_bufOut1.Store(outIdx3 + 4, asuint(cZ.y));
    } else {
        g_bufOut1.Store(outIdx2, asuint(0.0f));
        g_bufOut1.Store(outIdx2 + 4, asuint(0.0f));
        g_bufOut1.Store(outIdx3, asuint(0.0f));
        g_bufOut1.Store(outIdx3 + 4, asuint(0.0f));
    }
}