// Maxine VFX SDK 1.3.0.0 probe: AIGS load+run timing, BackgroundBlur run timing.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <cuda.h>
#include "nvVideoEffects.h"
#include "nvCVImage.h"

#define CHK(call) do { NvCV_Status s_ = (call); if (s_ != NVCV_SUCCESS) { \
  printf("FAIL %s:%d %s -> %d (%s)\n", __FILE__, __LINE__, #call, (int)s_, NvCV_GetErrorStringFromCode(s_)); return 1; } \
  else printf("ok   %s\n", #call); } while (0)

static double now_ms(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec*1e3+t.tv_nsec/1e6; }

int main(int argc, char **argv) {
  const char *modeldir = argc > 1 ? argv[1] : "models";
  unsigned W = 1920, H = 1080, mode = argc > 2 ? atoi(argv[2]) : 0;
  unsigned ver = 0;
  if (getenv("VFX_LOG")) NvVFX_ConfigureLogger(3, "stderr", NULL, NULL);
  CHK(NvVFX_GetVersion(&ver));
  printf("NvVFX_GetVersion = 0x%08x  (major %u minor %u build %u)\n", ver, ver>>24, (ver>>16)&0xff, (ver>>8)&0xff);

  // application-owned CUDA context (primary ctx, shared with the SDK's cudart) + stream
  CUdevice dev; CUcontext ctx; char name[128];
  if (cuInit(0) || cuDeviceGet(&dev,0) || cuDevicePrimaryCtxRetain(&ctx,dev) || cuCtxSetCurrent(ctx)) { printf("FAIL cuda init\n"); return 1; }
  cuDeviceGetName(name, sizeof name, dev); printf("CUDA device: %s\n", name);
  CUstream stream; CHK(NvVFX_CudaStreamCreate(&stream));

  NvVFX_Handle aigs;
  CHK(NvVFX_CreateEffect("GreenScreen", &aigs));
  CHK(NvVFX_SetString(aigs, NVVFX_MODEL_DIRECTORY, modeldir));
  CHK(NvVFX_SetCudaStream(aigs, NVVFX_CUDA_STREAM, stream));
  CHK(NvVFX_SetU32(aigs, NVVFX_MODE, mode));
  CHK(NvVFX_SetU32(aigs, NVVFX_CUDA_GRAPH, 1));
  CHK(NvVFX_SetU32(aigs, NVVFX_MAX_INPUT_WIDTH, W));
  CHK(NvVFX_SetU32(aigs, NVVFX_MAX_INPUT_HEIGHT, H));
  CHK(NvVFX_SetU32(aigs, NVVFX_MAX_NUMBER_STREAMS, 1));

  // Path A: SDK-allocated GPU images
  NvCVImage src={0}, dst={0};
  CHK(NvCVImage_Alloc(&src, W, H, NVCV_BGR, NVCV_U8, NVCV_CHUNKY, NVCV_GPU, 1));
  CHK(NvCVImage_Alloc(&dst, W, H, NVCV_A,   NVCV_U8, NVCV_CHUNKY, NVCV_GPU, 1));
  cuMemsetD8Async((CUdeviceptr)src.pixels, 0x80, (size_t)src.pitch * H, stream);
  CHK(NvVFX_SetImage(aigs, NVVFX_INPUT_IMAGE, &src));
  CHK(NvVFX_SetImage(aigs, NVVFX_OUTPUT_IMAGE, &dst));

  NvVFX_StateObjectHandle state; 
  CHK(NvVFX_AllocateState(aigs, &state));
  CHK(NvVFX_SetStateObjectHandleArray(aigs, NVVFX_STATE, &state));

  double t0 = now_ms();
  NvCV_Status ls = NvVFX_Load(aigs);
  double t1 = now_ms();
  printf("NvVFX_Load -> %d (%s)  took %.1f ms\n", (int)ls, NvCV_GetErrorStringFromCode(ls), t1-t0);
  if (ls != NVCV_SUCCESS) return 2;

  double r0 = now_ms();
  NvCV_Status rs = NvVFX_Run(aigs, 0);
  double r1 = now_ms();
  printf("first NvVFX_Run(sync) -> %d (%s)  took %.2f ms\n", (int)rs, NvCV_GetErrorStringFromCode(rs), r1-r0);
  if (rs != NVCV_SUCCESS) return 3;
  for (int i=0;i<10;i++) NvVFX_Run(aigs,0);
  int N=200; double a=now_ms();
  for (int i=0;i<N;i++) NvVFX_Run(aigs,0);
  double b=now_ms();
  printf("AIGS mode %u 1920x1080 BGR u8 GPU -> A u8 GPU: avg %.3f ms/frame over %d (sync Run)\n", mode, (b-a)/N, N);

  // Path B: caller-owned device memory wrapped with NvCVImage_Init (no SDK alloc)
  CUdeviceptr pin, pout; size_t pitchIn = W*3, pitchOut = W;
  cuMemAlloc(&pin, pitchIn*H); cuMemAlloc(&pout, pitchOut*H); cuMemsetD8(pin, 0x40, pitchIn*H);
  NvCVImage ein, eout;
  CHK(NvCVImage_Init(&ein,  W, H, (int)pitchIn,  (void*)pin,  NVCV_BGR, NVCV_U8, NVCV_CHUNKY, NVCV_GPU));
  CHK(NvCVImage_Init(&eout, W, H, (int)pitchOut, (void*)pout, NVCV_A,   NVCV_U8, NVCV_CHUNKY, NVCV_GPU));
  CHK(NvVFX_SetImage(aigs, NVVFX_INPUT_IMAGE, &ein));
  CHK(NvVFX_SetImage(aigs, NVVFX_OUTPUT_IMAGE, &eout));
  CHK(NvVFX_Load(aigs));
  a=now_ms(); for (int i=0;i<N;i++) { NvCV_Status e = NvVFX_Run(aigs,0); if(e){printf("Run(ext) err %d\n",e);break;} } b=now_ms();
  printf("AIGS with caller-owned cuMemAlloc buffers: avg %.3f ms/frame\n", (b-a)/N);
  // async path: Run(1) then stream sync
  a=now_ms(); for (int i=0;i<N;i++) NvVFX_Run(aigs,1); NvVFX_CudaStreamSynchronize(stream); b=now_ms();
  printf("AIGS async Run(1)+1 stream sync: avg %.3f ms/frame\n", (b-a)/N);

  // Background blur: src BGR + mask A -> BGR
  NvVFX_Handle blur; NvCVImage bout={0};
  CHK(NvCVImage_Alloc(&bout, W, H, NVCV_BGR, NVCV_U8, NVCV_CHUNKY, NVCV_GPU, 1));
  CHK(NvVFX_CreateEffect("BackgroundBlur", &blur));
  CHK(NvVFX_SetCudaStream(blur, NVVFX_CUDA_STREAM, stream));
  CHK(NvVFX_SetImage(blur, NVVFX_INPUT_IMAGE_0, &ein));
  CHK(NvVFX_SetImage(blur, NVVFX_INPUT_IMAGE_1, &eout));
  CHK(NvVFX_SetImage(blur, NVVFX_OUTPUT_IMAGE, &bout));
  CHK(NvVFX_SetF32(blur, NVVFX_STRENGTH, 0.5f));
  t0=now_ms(); NvCV_Status bl = NvVFX_Load(blur); t1=now_ms();
  printf("Blur NvVFX_Load -> %d (%s) took %.1f ms\n", (int)bl, NvCV_GetErrorStringFromCode(bl), t1-t0);
  if (bl==NVCV_SUCCESS) {
    for (int i=0;i<10;i++) NvVFX_Run(blur,0);
    a=now_ms(); for (int i=0;i<N;i++) NvVFX_Run(blur,0); b=now_ms();
    printf("BackgroundBlur 1920x1080: avg %.3f ms/frame\n", (b-a)/N);
  }
  NvVFX_DestroyEffect(blur);
  NvVFX_DeallocateState(aigs, state);
  NvVFX_DestroyEffect(aigs);
  NvVFX_CudaStreamDestroy(stream);
  printf("DONE\n");
  return 0;
}
