# maxine-probe

A small standalone C program that checks an installed Maxine Video Effects SDK (software development kit), such as the tree the `maxine-vfx` package installs under `/opt/nvidia/maxine/videofx`. Run it after you install the package to confirm that the effects load and run. It is a verification aid, not part of the package.

It uses the GPU. It creates a CUDA context and runs the effects on frames in GPU memory. Run it when nothing else depends on the GPU being idle.

## What it checks

1. `NvVFX_GetVersion` reports the SDK version (expected `0x01030000` for 1.3.0.0).
2. A CUDA device and stream can be created (primary context shared with the SDK's runtime).
3. The AI green screen (AIGS) effect loads its model package (`NvVFX_Load`), then runs 200 frames at 1920x1080 BGR u8 on the GPU. Load time, first-run time and average time per frame are printed. Two image-allocation paths are tried: SDK-allocated GPU images, and images wrapping application-owned device memory.
4. The background blur effect loads and runs with an external mask.

A run passes when the version is correct, `NvVFX_Load -> 0` is printed, the output ends with `DONE` and there is no `FAIL` line.

The timings it prints are for verifying your own installation only. Do not publish them: NVIDIA's licence forbids publishing benchmarks of the SDK (SLA 8.9).

## Build and run against the package

From the repository root, with the package installed. The CUDA headers are bundled with the SDK, so no system CUDA toolkit is needed.

```sh
set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
gcc -O2 -o /tmp/probe tools/maxine-probe/probe.c \
  -I"$MAXINE_VFX_ROOT/include" -I"$MAXINE_VFX_ROOT/external/cuda/include" \
  -L"$MAXINE_VFX_ROOT/lib" -lVideoFX -lNVCVImage -lcuda
env LD_PRELOAD=/usr/lib/maxine-vfx/os-release-shim.so /tmp/probe "$MAXINE_VFX_MODEL_DIR"
```

The environment file sets `LD_LIBRARY_PATH` to the SDK's bundled libraries and `MAXINE_OS_RELEASE` to the packaged replacement `os-release`; do this in a throwaway shell, not in your login shell. The os-release shim is needed on a distribution the SDK does not list ([../os-release-shim/README.md](../os-release-shim/README.md)); set `LD_PRELOAD` on the probe itself, never on a wrapper in front of it.

Arguments: `probe [model_dir] [aigs_mode]`. `model_dir` defaults to `./models`, which usually does not exist; pass `$MAXINE_VFX_MODEL_DIR`. `aigs_mode` defaults to 0.

To probe another SDK tree (for example a user-prefix install), point `MAXINE_VFX_ROOT` at it and source `env.sh` instead of the environment file:

```sh
export MAXINE_VFX_ROOT=~/.local/opt/maxine/VideoFX
source tools/maxine-probe/env.sh
export MAXINE_OS_RELEASE=$PWD/tools/maxine-probe/fake-os-release
```

## Files

| File | Purpose |
|---|---|
| `probe.c` | The probe |
| `env.sh` | Sets `LD_LIBRARY_PATH` for the SDK's bundled libraries; honours `$MAXINE_VFX_ROOT` (default `/opt/nvidia/maxine/videofx`) |
| `fake-os-release` | An `os-release` file naming a listed distribution (Ubuntu 24.04), read through the os-release shim; the package installs it as `/usr/lib/maxine-vfx/fake-os-release` |

## Environment variables

| Variable | Effect |
|---|---|
| `MAXINE_VFX_ROOT` | SDK root; used by `env.sh` and the build command |
| `MAXINE_VFX_MODEL_DIR` | The model directory, set by the package's environment file |
| `VFX_LOG` | If set, enables the SDK's own logging on stderr |
