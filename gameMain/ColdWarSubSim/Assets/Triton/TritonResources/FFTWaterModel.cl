//#pragma OPENCL EXTENSION cl_khr_gl_sharing : enable

__kernel void CreateTextures(__global const float *inputs, __write_only image2d_t displacement, __write_only image2d_t slopeFoam, uint2 dim, float2 twoCellsSize,
                             float chopScale, float dt, __global float *foamBuffer)
{
    __global const float *H = inputs;
    __global const float *chopX = inputs + (dim.x * dim.y);
    __global const float *chopZ = chopX + (dim.x * dim.y);

    int2 gridPos;
    gridPos.x = get_global_id(0);
    gridPos.y = get_global_id(1);

    int idx = gridPos.y * dim.x + gridPos.x;

    int prevX = gridPos.x > 0 ? gridPos.x-1 : dim.x-1;
    int nextX = gridPos.x < dim.x-1 ? gridPos.x + 1 : 0;
    int prevY = gridPos.y > 0 ? gridPos.y - 1 : dim.y-1;
    int nextY = gridPos.y < dim.y - 1 ? gridPos.y + 1 : 0;

    float thisChopX = chopX[idx] * chopScale;
    float nextChopX = chopX[gridPos.y * dim.x + nextX];
    float prevChopX = chopX[gridPos.y * dim.x + prevX];
    float thisChopZ = chopZ[idx] * chopScale;
    float nextChopZ = chopZ[nextY * dim.x + gridPos.x];
    float prevChopZ = chopZ[prevY * dim.x + gridPos.x];

    float4 color;
    color.x = thisChopX;
    color.y = thisChopZ;
    color.z = H[idx];
    color.w = 1.0f;
    write_imagef(displacement, gridPos, color);

    float xWidth = twoCellsSize.x + nextChopX - prevChopX;
    float yDepth = twoCellsSize.y + nextChopZ - prevChopZ;

    float xDelta = (H[gridPos.y * dim.x + nextX] - H[gridPos.y * dim.x + prevX]);
    float yDelta = (H[nextY * dim.x + gridPos.x] - H[prevY * dim.x + gridPos.x]);
    float dx = xDelta / xWidth;
    float dy = yDelta / yDepth;

    // Rate at which x displacement changes if x is constant
    float sxx = (chopX[nextY * dim.x + gridPos.x] - chopX[prevY * dim.x + gridPos.x]) / yDepth;
    // Rate at which y displacement changes if x is constant
    float syx = (chopZ[nextY * dim.x + gridPos.x] - chopZ[prevY * dim.x + gridPos.x]) / yDepth;
    // Rate at which y displacement changes if y is constant
    float syy = (chopZ[gridPos.y * dim.x + nextX] - chopZ[gridPos.y * dim.x + prevX]) / xWidth;
    // Rate at which x displacement changes if y is constant
    float sxy = (chopX[gridPos.y * dim.x + nextX] - chopX[gridPos.y * dim.x + prevX]) / xWidth;

    color.x = dx;
    color.y = dy;

    float Jxx = 1.0 + chopScale * sxx;
    float Jyy = 1.0 + chopScale * syy;
    float Jxy = chopScale * sxy;
    float Jyx = chopScale * syx;
    float J = Jxx * Jyy - Jxy * Jyx;

    float foam = 1.0f - J;

    color.z = foam;

    write_imagef(slopeFoam, gridPos, color);
    foamBuffer[gridPos.y * dim.x + gridPos.x] = foam;
}

__kernel void ProcessWater(__global const float *H0, __global const float *omega, __global float *fftIn, float t, uint2 dim, float2 size)
{
    __global float *H = fftIn;
    __global float *chopX = fftIn + (dim.x * dim.y * 2);
    __global float *chopZ = chopX + (dim.x * dim.y * 2);

    int2 gridPos;
    gridPos.x = get_global_id(0);
    gridPos.y = get_global_id(1);

    int h0idx = gridPos.y*(dim.x + 1)*2 + gridPos.x * 2;
    float2 h0;
    h0.x = H0[h0idx];
    h0.y = H0[h0idx + 1];

    int h0NegKIdx = (dim.y - gridPos.y) * (dim.x + 1) * 2 + (dim.x - gridPos.x) * 2;
    float2 h0NegKConj;
    h0NegKConj.x = H0[h0NegKIdx];
    h0NegKConj.y = H0[h0NegKIdx+1] * -1;

    uint2 half = dim / 2;
    float2 kPos;
    kPos.x = (float)gridPos.x - (float)half.x;
    kPos.y = (float)gridPos.y - (float)half.y;

    const float TWOPI = 3.14159265f * 2.0f;
    float2 K = (TWOPI * kPos) / size;

    float wk = omega[dim.x * gridPos.y + gridPos.x];
    float wkt = wk * t;
    float cwkt = native_cos(wkt);
    float swkt = native_sin(wkt);

    float2 term1, term2;
    term1.x = h0.x * cwkt - h0.y * swkt;
    term1.y = h0.x * swkt + h0.y * cwkt;
    term2.x = h0NegKConj.x * cwkt - h0NegKConj.y * -swkt;
    term2.y = h0NegKConj.x * -swkt + h0NegKConj.y * cwkt;

    float2 Htilde = term1 + term2;

    int outIdx = gridPos.y * dim.x * 2 + gridPos.x * 2;
    H[outIdx] = Htilde.x;
    H[outIdx+1] = Htilde.y;

    if (dot(K, K) > 0) {
        float2 chopImg = fast_normalize(K);
        float2 cX, cZ;
        cX.x = -(chopImg.x * Htilde.y);
        cX.y = (chopImg.x * Htilde.x);
        cZ.x = -(chopImg.y * Htilde.y);
        cZ.y = (chopImg.y * Htilde.x);

        chopX[outIdx] = cX.x;
        chopX[outIdx+1] = cX.y;
        chopZ[outIdx] = cZ.x;
        chopZ[outIdx+1] = cZ.y;
    } else {
        chopX[outIdx] = chopX[outIdx+1] = chopZ[outIdx] = chopZ[outIdx+1] = 0.0f;
    }
}