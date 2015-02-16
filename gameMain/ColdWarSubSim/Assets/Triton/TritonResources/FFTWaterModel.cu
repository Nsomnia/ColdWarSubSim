#include <cufft.h>
#include <math_constants.h>

__global__ void CreateTextures(const float *H, const float *chopX, const float *chopZ, float * displacement, float * slopeFoam, float *foam,
                               uint2 dim, float2 twoCellsSize, float chopScale, float dt)
{
    int2 gridPos;
    gridPos.x = blockIdx.x*blockDim.x + threadIdx.x;
    gridPos.y =  blockIdx.y*blockDim.y + threadIdx.y;

    int idx = gridPos.y * dim.x + gridPos.x;
    int imageIdx = gridPos.y * dim.x * 4 + gridPos.x * 4;

    displacement[imageIdx] = chopX[idx] * chopScale;
    displacement[imageIdx+1] = chopZ[idx] * chopScale;
    displacement[imageIdx+2] = H[idx];
    displacement[imageIdx+3] = 1.0f;

    int prevX = gridPos.x > 0 ? gridPos.x-1 : dim.x-1;
    int nextX = gridPos.x < dim.x-1 ? gridPos.x + 1 : 0;
    int prevY = gridPos.y > 0 ? gridPos.y - 1 : dim.y-1;
    int nextY = gridPos.y < dim.y - 1 ? gridPos.y + 1 : 0;

    float xWidth = twoCellsSize.x + chopX[gridPos.y * dim.x + nextX] - chopX[gridPos.y * dim.x + prevX];
    float yDepth = twoCellsSize.y + chopZ[nextY * dim.x + gridPos.x] - chopZ[prevY * dim.x + gridPos.x];
    float xDelta = (H[gridPos.y * dim.x + nextX] - H[gridPos.y * dim.x + prevX]);
    float yDelta = (H[nextY * dim.x + gridPos.x] - H[prevY * dim.x + gridPos.x]);
    float dx = xDelta / xWidth;
    float dy = yDelta / yDepth;

    slopeFoam[imageIdx] = dx;
    slopeFoam[imageIdx+1] = dy;

    // Rate at which x displacement changes if x is constant
    float sxx = (chopX[nextY * dim.x + gridPos.x] - chopX[prevY * dim.x + gridPos.x]) / yDepth;
    // Rate at which y displacement changes if x is constant
    float syx = (chopZ[nextY * dim.x + gridPos.x] - chopZ[prevY * dim.x + gridPos.x]) / yDepth;
    // Rate at which y displacement changes if y is constant
    float syy = (chopZ[gridPos.y * dim.x + nextX] - chopZ[gridPos.y * dim.x + prevX]) / xWidth;
    // Rate at which x displacement changes if y is constant
    float sxy = (chopX[gridPos.y * dim.x + nextX] - chopX[gridPos.y * dim.x + prevX]) / xWidth;

    float Jxx = 1.0 + chopScale * sxx;
    float Jyy = 1.0 + chopScale * syy;
    float Jxy = chopScale * sxy;
    float Jyx = chopScale * syx;

    float J = Jxx * Jyy - Jxy * Jyx;

    float spray = 1.0f - J;

    slopeFoam[imageIdx+2] = spray;
    slopeFoam[imageIdx+3] = 1.0f;

    foam[idx] = spray;
}

__global__ void ProcessWater(const float *H0, const float *omega, float *H, float *chopX, float *chopZ, float time, uint2 inDim, uint2 outDim, float2 size)
{
    int2 gridPos;
    gridPos.x = blockIdx.x * blockDim.x + threadIdx.x;
    gridPos.y = blockIdx.y * blockDim.y + threadIdx.y;

    if (gridPos.x >= outDim.x) return;
    if (gridPos.y >= outDim.y) return;

    int h0idx = gridPos.y*(inDim.x + 1)*2 + gridPos.x * 2;
    float2 h0;
    h0.x = H0[h0idx];
    h0.y = H0[h0idx + 1];

    int h0NegKIdx = (inDim.y - gridPos.y) * (inDim.x + 1) * 2 + (inDim.x - gridPos.x) * 2;
    float2 h0NegKConj;
    h0NegKConj.x = H0[h0NegKIdx];
    h0NegKConj.y = H0[h0NegKIdx+1] * -1;

    uint2 half = make_uint2(inDim.x / 2, inDim.y / 2);
    float2 kPos;
    kPos.x = (float)gridPos.x - (float)half.x;
    kPos.y = (float)gridPos.y - (float)half.y;

    const float TWOPI = 3.14159265f * 2.0f;
    float2 K = make_float2((TWOPI * kPos.x) / size.x , (TWOPI * kPos.y) / size.y);

    float wk = omega[inDim.x * gridPos.y + gridPos.x];
    float wkt = wk * time;
    float cwkt = cosf(wkt);
    float swkt = sinf(wkt);

    float2 term1, term2;
    term1.x = h0.x * cwkt - h0.y * swkt;
    term1.y = h0.x * swkt + h0.y * cwkt;
    term2.x = h0NegKConj.x * cwkt - h0NegKConj.y * -swkt;
    term2.y = h0NegKConj.x * -swkt + h0NegKConj.y * cwkt;

    float2 Htilde = make_float2(term1.x + term2.x, term1.y + term2.y);

    int outIdx = gridPos.y * outDim.x * 2 + gridPos.x * 2;
    H[outIdx] = Htilde.x;
    H[outIdx+1] = Htilde.y;

    if (  (K.x * K.x + K.y * K.y) > 0) {
        float invLen = 1.0f / sqrtf(K.x*K.x + K.y*K.y);
        float2 chopImg = make_float2(K.x * invLen, K.y * invLen);
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

//Round a / b to nearest higher integer value
int cuda_iDivUp(int a, int b)
{
    return (a + (b - 1)) / b;
}

__global__ void flipSignsKernel(float* h, unsigned int width, unsigned int height)
{
    unsigned int x = blockIdx.x*blockDim.x + threadIdx.x;
    unsigned int y = blockIdx.y*blockDim.y + threadIdx.y;
    unsigned int i = y*width+x;

    float signs[2] = {1, -1};
    h[i] *= signs[x+y & 1];
}

extern "C" void cudaFlipSignsKernel(  float* hptr,
                                      unsigned int width, unsigned int height)
{
    dim3 block(16, 16, 1);
    dim3 grid2(cuda_iDivUp(width, block.x), cuda_iDivUp(height, block.y), 1);
    flipSignsKernel<<<grid2, block>>>(hptr, width, height);
}

extern "C" void cudaCreateTextures(const float *H, const float *chopX, const float *chopZ, unsigned int width, unsigned int height, float *displacement, float *slopeFoam, float *foam, uint2 dim, float2 twoCellsSize,
                                   float chopScale, float dt)
{
    dim3 block(16, 16, 1);
    dim3 grid2(cuda_iDivUp(width, block.x), cuda_iDivUp(height, block.y), 1);
    CreateTextures<<<grid2, block>>>(H, chopX, chopZ, displacement, slopeFoam, foam, dim, twoCellsSize, chopScale, dt);
}

extern "C" void cudaProcessWater(const float *H0, const float *omega, float *H, float *chopX, float *chopZ, float t, uint2 inDim, uint2 outDim, float2 size)
{
    dim3 block(16, 16, 1);
    dim3 grid2(cuda_iDivUp(outDim.x, block.x), cuda_iDivUp(outDim.y, block.y), 1);
    ProcessWater<<<grid2, block>>>(H0, omega, H, chopX, chopZ, t, inDim, outDim, size);
}
