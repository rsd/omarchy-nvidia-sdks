# Using the Maxine SDK packages

This page is for programs and projects that load a Maxine SDK after one of three packages installed it: `maxine-vfx-sdk-local` (Video Effects), `maxine-ar-sdk-local` (AR) or `maxine-afx-sdk-local` (Audio Effects). Maxine is NVIDIA's family of AI video and audio effects. Each package installs this page as `/usr/share/doc/<package>/usage.md`.

The sections from "What the package installs" to "Troubleshooting" describe the Video Effects package. The [Maxine AR SDK](#maxine-ar-sdk) and [Maxine Audio Effects SDK](#maxine-audio-effects-sdk) sections describe the other two, which follow the same pattern:

- an environment file (a text file of `KEY=value` settings) that you load for one program;
- a shim (a small library that makes the SDK accept your distribution) that you preload on that program;
- no global setting.

[Why nothing is global](#why-nothing-is-global) says why.

For the Optical Flow SDK and TensorRT packages, see [Other packages](#other-packages-optical-flow-and-tensorrt). For building the packages, see [download.md](download.md), [../maxine-vfx/README.md](../maxine-vfx/README.md), [../maxine-ar/README.md](../maxine-ar/README.md) and [../maxine-afx/README.md](../maxine-afx/README.md). For supported GPUs and architectures, see [gpu-support.md](gpu-support.md).

The package contains NVIDIA software and is for your own machine only; see the "Licence and personal use" section of the [README](../README.md). NVIDIA does not support this configuration (Arch, distributions the SDK does not list, client-side use).

## Quick start

Install the package first (see the [README](../README.md#quick-start)). Then, for the Video Effects package, run any program that uses it like this. Replace `<program>` with the program's command. For the AR and Audio Effects packages, use the commands in their sections below.

1. Load the environment file in your shell. This sets the library paths for this shell only:

   ```bash
   set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
   ```

2. Start the program with the shim preloaded:

   ```bash
   env LD_PRELOAD=$MAXINE_VFX_OS_RELEASE_SHIM <program> [args]
   ```

3. Check the installation. With the environment file loaded, the `ldd` command prints nothing when every library is found:

   ```bash
   pacman -Ql maxine-vfx-sdk-local | head
   (set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
    ldd /opt/nvidia/maxine/videofx/lib/libVideoFXLocal.so | grep 'not found')
   ```

If a call fails, find its error code in [Troubleshooting](#troubleshooting). The most common is `-1209` ("no kernel image is available"), which means the shim is not preloaded on the program itself.

Do not put the `set -a` line in `~/.bashrc` or another login file. The bundled libraries would then replace the system's for every program you start.

## What the package installs

This and the following sections up to "Troubleshooting" are about `maxine-vfx-sdk-local`.

| Path | Content |
|---|---|
| `/opt/nvidia/maxine/videofx/` | The SDK tree: `lib/`, `lib/models/`, `features/`, `include/`, `external/cuda`, `external/tensorrt`, `share/` |
| `/usr/lib/maxine-vfx/os-release-shim.so` | The compatibility shim (built from `tools/os-release-shim`) |
| `/usr/lib/maxine-vfx/fake-os-release` | The replacement `os-release` (Ubuntu 24.04) |
| `/usr/share/maxine-vfx/maxine-vfx.env` | The environment file described below |
| `/usr/share/licenses/maxine-vfx-sdk-local/` | Symlinks to the SDK's licence files under `/opt/nvidia/maxine/videofx/share`, and copies of `LICENSE-MIT` and `LICENSE-APACHE` (they cover the shim) |
| `/usr/share/doc/maxine-vfx-sdk-local/` | This page (`usage.md`) |

The package is isolated on purpose. It installs no `/etc/ld.so.conf.d` entry and no `/etc/profile.d` file, and it sets neither `LD_LIBRARY_PATH` nor `LD_PRELOAD` globally. The SDK bundles CUDA 12.8 and TensorRT 10.9, and putting them on the global library path would shadow Arch's CUDA 13 for every program. A program opts in explicitly, as described below.

## The environment file

`/usr/share/maxine-vfx/maxine-vfx.env` holds plain `KEY=value` lines without quotes or variable expansion, and comments only on their own lines. That makes it usable both as a systemd `EnvironmentFile=` and in a shell with `set -a`. The file also starts with comment lines, omitted here. Its keys, in file order, shown for two features (green screen and background blur) and architecture `sm_120`:

```
MAXINE_VFX_ROOT=/opt/nvidia/maxine/videofx
MAXINE_VFX_MODEL_DIR=/opt/nvidia/maxine/videofx/lib/models
MAXINE_VFX_LIBRARY_PATH=/opt/nvidia/maxine/videofx/lib:/opt/nvidia/maxine/videofx/features/nvvfxbackgroundblur/lib:/opt/nvidia/maxine/videofx/features/nvvfxgreenscreen/lib:/opt/nvidia/maxine/videofx/external/cuda/lib:/opt/nvidia/maxine/videofx/external/tensorrt/lib
LD_LIBRARY_PATH=<same value as MAXINE_VFX_LIBRARY_PATH>
MAXINE_VFX_OS_RELEASE_SHIM=/usr/lib/maxine-vfx/os-release-shim.so
MAXINE_OS_RELEASE=/usr/lib/maxine-vfx/fake-os-release
MAXINE_VFX_FEATURES=nvvfxbackgroundblur,nvvfxgreenscreen
MAXINE_VFX_ARCHS=sm_120
```

`MAXINE_VFX_FEATURES` and `MAXINE_VFX_ARCHS` are informational: comma-separated lists, without spaces, of the features and architectures that were packaged. The library path has one `features/<feature>/lib` entry for every packaged feature, sorted by name, between `lib` and the bundled CUDA and TensorRT directories. The example grows with what you download: a package built with more features lists more entries, and more architectures lengthen `MAXINE_VFX_ARCHS`. The file never sets `LD_PRELOAD`.

The package is one package, not one per feature, because the feature set is only known after reading your download; the reasons are in [../maxine-vfx/README.md](../maxine-vfx/README.md).

Two uses:

- In a systemd unit: `EnvironmentFile=/usr/share/maxine-vfx/maxine-vfx.env`.
- In a shell, for one command or one session:

  ```bash
  set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
  ```

Never source the file from a login profile, `~/.bashrc` or `~/.profile`. The bundled CUDA 12 and TensorRT 10 libraries would then shadow the system libraries for every program you start. The bundled directories must be on `LD_LIBRARY_PATH` for the SDK, because Arch ships CUDA 13 and none of the `.so.12`, `.so.9` or `.so.10` sonames the SDK needs exist system-wide, and because the feature libraries are found by a plain `dlopen("libnvVFXGreenScreen.so")`.

## The compatibility shim

The SDK's model loader reads `/etc/os-release` and refuses distributions that are not on NVIDIA's list. The error it returns, `-1209` ("no kernel image is available for execution on the device"), is misleading: no CUDA error occurs, and only the `ID` and `VERSION_ID` fields are read.

`os-release-shim.so` is a compatibility shim for distributions the SDK does not list. It is an `LD_PRELOAD` library: inside a process that preloads it, a read-only open of exactly `/etc/os-release` opens the file named by the environment variable `MAXINE_OS_RELEASE` instead, and every other call passes through unchanged. Only that process is affected, the real file is untouched and no root is needed. The shim does not modify the SDK, the models or their encryption. NVIDIA does not support this configuration.

Set `MAXINE_OS_RELEASE_DEBUG=1` to make the shim log each redirect on stderr, which shows whether it is active. The package's environment file sets only `MAXINE_OS_RELEASE`.

### Deprecated names

The shim used to read `OMA_BROADCAST_OS_RELEASE` and `OMA_BROADCAST_OS_RELEASE_DEBUG`. Those names are deprecated but still read, for programs that have not been updated yet. They apply per variable, as follows:

- If the new name is set in the environment, even to an empty string, it is used and the old name is ignored.
- If only the old name is set, it is used, and the shim prints one note per process on stderr: `os-release-shim: OMA_BROADCAST_OS_RELEASE is deprecated, use MAXINE_OS_RELEASE` (and the same for `_DEBUG`).

The old names will be removed in a later release. Use the new names in anything you write.

The replacement file `/usr/lib/maxine-vfx/fake-os-release` reads:

```
NAME="Ubuntu"
VERSION_ID="24.04"
ID=ubuntu
ID_LIKE=debian
VERSION_CODENAME=noble
PRETTY_NAME="Ubuntu 24.04 LTS"
```

**Preload it on the final program only.** The shim removes `LD_PRELOAD` from the environment of the process that loads it, so that children do not inherit it. A wrapper such as `timeout`, `sh -c` or `cargo` that carries `LD_PRELOAD` loads the shim itself, drops the variable and starts the program without it, which then fails with `-1209`. Write `timeout 60 env LD_PRELOAD=... program`, not `LD_PRELOAD=... timeout 60 program`.

## Running a program

Manual run:

```bash
set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
env LD_PRELOAD=$MAXINE_VFX_OS_RELEASE_SHIM <program> [args]
```

### systemd user unit

Generic drop-in, for any user service that loads the SDK, at `~/.config/systemd/user/<service>.service.d/maxine.conf`:

```ini
[Service]
EnvironmentFile=/usr/share/maxine-vfx/maxine-vfx.env
Environment=LD_PRELOAD=/usr/lib/maxine-vfx/os-release-shim.so
```

Example for omarchy-broadcast, `~/.config/systemd/user/omarchy-broadcastd.service.d/maxine.conf`, with the same content:

```ini
[Service]
EnvironmentFile=/usr/share/maxine-vfx/maxine-vfx.env
Environment=LD_PRELOAD=/usr/lib/maxine-vfx/os-release-shim.so
```

Then:

```bash
systemctl --user daemon-reload
systemctl --user restart omarchy-broadcastd.service
```

Remove the file, reload and restart to go back to the unit without the SDK.

## The model directory

`MAXINE_VFX_MODEL_DIR` (`/opt/nvidia/maxine/videofx/lib/models`) holds the `.engine.trtpkg` model packages of every feature that has them, for the architectures you built the package with (`MAXINE_VFX_ARCHS`). A program passes it to the SDK as the effect parameter `NVVFX_MODEL_DIRECTORY`. If it is not set, the SDK looks in `./models`, which usually does not exist and gives `-13`.

## Engine cache

The SDK has an optional per-effect parameter `NVVFX_MODEL_CACHE_DIRECTORY` ("ModelCacheDir", a TRT-RTX cache directory; the default is `ModelDir/cache`) and `NVVFX_MODEL_CACHE_MODE` ("ModelCacheMode": 0 Auto, 1 Disabled, 2 ForceRegenerate). The application sets them with `NvVFX_SetString` and `NvVFX_SetU32`; there is no environment variable for them.

The 1.3.0.0 Linux models are prebuilt TensorRT engines for each architecture. After a successful SDK run on the reference machine, no `lib/models/cache` directory appeared in a user-writable install, so on Linux no cache appears to be written. This supports leaving `/opt` read-only. It was observed in a user-writable install, not on the packaged read-only tree.

The package therefore creates no shared cache directory: a world-writable engine cache would be a tampering risk. The default `ModelDir/cache` under `/opt` is owned by root and read-only.

Convention for a program that wants a cache: use a per-user directory, `${XDG_CACHE_HOME:-$HOME/.cache}/maxine-vfx`, and pass it as `ModelCacheDir`. In a systemd user unit, `CacheDirectory=maxine-vfx` provides it as `%C/maxine-vfx`. Every project of the same user then shares that directory.

## Referencing the package from another package

The SDK is a separate personal download, so a consumer's PKGBUILD should declare it as an optional dependency, not a hard one:

```bash
optdepends=('maxine-vfx-sdk-local: NVIDIA Maxine video effects')
```

The package also provides `maxine-vfx-sdk=1.3.0.0`. A consumer that needs particular features can check `MAXINE_VFX_FEATURES` in the environment file at run time; it lists the features that were packaged.

When you build the package for a consumer, name the features it needs with `MAXINE_VFX_FEATURES=<list>`: the build fails when one of them is missing from your download. omarchy-broadcast, for example, needs green screen and background blur, so build with `MAXINE_VFX_FEATURES=nvvfxgreenscreen,nvvfxbackgroundblur`, or with `MAXINE_VFX_FEATURES=all` to package everything you downloaded. `maxine-vfx/configure.sh --src <dir>` shows what your download holds and `--write` saves the choice in the git-ignored `maxine-vfx/selection.conf` (an environment variable overrides it). The GPU architectures you can package are in [gpu-support.md](gpu-support.md).

## Check the installation

```bash
pacman -Ql maxine-vfx-sdk-local | head
(set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
 ldd /opt/nvidia/maxine/videofx/lib/libVideoFXLocal.so | grep 'not found')
```

With the environment file applied, the `ldd` command prints nothing.

## Features: effect selectors and headers

A program creates an effect with `NvVFX_CreateEffect(selector, &handle)`. The selector string, the header macro and the header for each feature, under `/opt/nvidia/maxine/videofx`:

| Feature | Selector | Header macro | Header | Image formats |
|---|---|---|---|---|
| `nvvfxgreenscreen` | `"GreenScreen"` | `NVVFX_FX_GREEN_SCREEN` | `features/nvvfxgreenscreen/include/nvVFXGreenScreen.h` | in BGR U8 chunky, out A U8 mask |
| `nvvfxbackgroundblur` | `"BackgroundBlur"` | `NVVFX_FX_BGBLUR` | `features/nvvfxbackgroundblur/include/nvVFXBackgroundBlur.h` | in BGR U8 plus an optional A or Y U8 mask, out BGR U8 |
| `nvvfxdenoising` | `"Denoising"` | `NVVFX_FX_DENOISING` | `features/nvvfxdenoising/include/nvVFXDenoising.h` | BGR U8 chunky, or normalized BGR F32 planar; needs a state array (`NVVFX_STATE`) before `Run` |
| `nvvfxrelighting` | `"Relighting"` | `NVVFX_FX_RELIGHTING` | `features/nvvfxrelighting/include/nvVFXRelighting.h` | in0 BGR or RGB U8; in1 A U8 matte (from green screen); HDRI RGB or BGR F32, 2:1, on `NVVFX_INPUT_HDR_RELIGHTING_IMAGE`; out BGR or RGB U8 foreground (background pixels are invalid, composite it) |
| `nvvfxvideosuperres` | `"VideoSuperRes"` | `NVVFX_FX_VIDEO_SUPER_RES` | `features/nvvfxvideosuperres/include/nvVFXVideoSuperRes.h` | RGBA or BGRA U8, or RGB10A2 P32 via `ImageEncodingMode`; modes 8-15 (denoise, deblur) keep the size; needs driver 570.190+, 580.82+ or 590.44+ |
| `nvvfxupscale` | `"Upscale"` | `NVVFX_FX_SR_UPSCALE` | `features/nvvfxupscale/include/nvVFXUpscale.h` | RGBA U8 in and out; 1.33x, 1.5x, 2x, 3x, 4x |
| `nvvfxtruehdr` | `"TrueHDR"` | `NVVFX_FX_TRUE_HDR` | `features/nvvfxtruehdr/include/nvVFXTrueHDR.h` | in RGBA U8, out RGB10A2 P32 (HDR10 PQ) |
| `nvvfxvideoframegeneration` | `"VideoFrameGeneration"` | `NVVFX_FX_VIDEO_FRAME_GENERATION` | `features/nvvfxvideoframegeneration/include/nvVFXVideoFrameGeneration.h` | `SrcImage0` previous and `SrcImage1` current frame, RGBA or BGRA U8, or RGB10A2 P32; `InputWidth` and `InputHeight` must be set before `NvVFX_Load` |

The core headers are `include/nvVideoEffects.h`, `include/nvCVImage.h` and `include/nvCVStatus.h`. `NvVFX_GetString(effect, NVVFX_INFO, ...)` returns each effect's parameter list.

All eight features were checked to create and load their effect on an `sm_120` GPU with driver 615.78. This was a load check, not a benchmark.

## Bundled cuDNN headers

NVIDIA's own tarball ships 8 dangling symlinks in `external/cuda`: 7 headers, `external/cuda/include/cudnn*.h -> /etc/alternatives/libcudnn*` (Debian's alternatives system, absent on Arch), and `external/cuda/lib/libcudnn.so -> libcudnn9.so.9`, whose target the SDK does not ship. The package keeps all 8 as shipped. Using the Video Effects API does not need them. A program that compiles against the bundled cuDNN headers, or links with `-lcudnn`, needs the real cuDNN from elsewhere.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `NvVFX_Load` returns `-1209`, "no kernel image is available" | `/etc/os-release` is not an accepted distribution. Not a real CUDA error | Preload the shim on the program itself (not on a wrapper), check that `MAXINE_OS_RELEASE` is an absolute path to a file with both `ID=` and `VERSION_ID=`, and run with `MAXINE_OS_RELEASE_DEBUG=1` to see the redirect. The deprecated old names still work, with a note on stderr: see [Deprecated names](#deprecated-names) |
| `NvVFX_CreateEffect` returns `-2` (unimplemented) | The feature libraries (for example `libnvVFXGreenScreen.so` and `libnvVFXBackgroundBlur.so`) are not found by `dlopen` | Apply the environment file, which puts `features/<feature>/lib` on `LD_LIBRARY_PATH`; check that the feature was in the package |
| `NvVFX_Load` returns `-13` ("file could not be found") | The model directory is wrong or the models are missing | Pass `MAXINE_VFX_MODEL_DIR` as `NVVFX_MODEL_DIRECTORY`; check that `ls /opt/nvidia/maxine/videofx/lib/models` shows `.trtpkg` files for your architecture |
| `libcudart.so.12`, `libnpp*.so.12`, `libcudnn.so.9` or `libnvinfer.so.10` not found | The bundled `external/cuda/lib` and `external/tensorrt/lib` are not on `LD_LIBRARY_PATH` | Apply the environment file and repeat the `ldd` check above |
| `ld.so: object '...os-release-shim.so' from LD_PRELOAD cannot be preloaded` | The shim is not at the path in `LD_PRELOAD`; the program runs without it | Check the path in the drop-in or command; the package installs it at `/usr/lib/maxine-vfx/os-release-shim.so` |
| `Cannot load libVideoFXTriton.so` in the SDK log | The Triton client library needs `libgrpcclient.so`, which is not used here | Harmless; ignore it |

## Maxine AR SDK

`maxine-ar-sdk-local` installs the AR SDK 1.2.0.0 (eye contact, face box detection, facial landmarks and the other features you packaged). It works like the Video Effects package above; this section lists what differs.

### What the AR package installs

| Path | Content |
|---|---|
| `/opt/nvidia/maxine/arsdk/` | The SDK tree: `lib/`, `lib/models/`, `features/`, `include/`, `external/cuda`, `external/tensorrt`, `share/` |
| `/usr/lib/maxine-ar/os-release-shim.so` | The compatibility shim (the same one as in the other packages) |
| `/usr/lib/maxine-ar/fake-os-release` | The replacement `os-release` (Ubuntu 24.04), the same content as shown in [The compatibility shim](#the-compatibility-shim) |
| `/usr/share/maxine-ar/maxine-ar.env` | The environment file |
| `/usr/share/licenses/maxine-ar-sdk-local/` | Links to the SDK's licence files, including the models' licence of each feature, and copies of `LICENSE-MIT` and `LICENSE-APACHE` (they cover the shim) |
| `/usr/share/doc/maxine-ar-sdk-local/` | This page (`usage.md`) |

The package also provides `maxine-ar-sdk=1.2.0.0`. A consumer's PKGBUILD should declare it as an optional dependency, for example `optdepends=('maxine-ar-sdk-local: NVIDIA Maxine AR effects')`.

### The AR environment file

`/usr/share/maxine-ar/maxine-ar.env` has the same format as the Video Effects one: plain `KEY=value` lines, no quotes or expansion, comments only on their own lines, usable as a systemd `EnvironmentFile=` and with `set -a`. Its keys, in file order, shown for three features and `sm_120`:

```
MAXINE_AR_ROOT=/opt/nvidia/maxine/arsdk
MAXINE_AR_MODEL_DIR=/opt/nvidia/maxine/arsdk/lib/models
MAXINE_AR_LIBRARY_PATH=/opt/nvidia/maxine/arsdk/lib:/opt/nvidia/maxine/arsdk/features/nvarfaceboxdetection/lib:/opt/nvidia/maxine/arsdk/features/nvargazeredirection/lib:/opt/nvidia/maxine/arsdk/features/nvarlandmarkdetection/lib:/opt/nvidia/maxine/arsdk/external/cuda/lib:/opt/nvidia/maxine/arsdk/external/tensorrt/lib
LD_LIBRARY_PATH=<same value as MAXINE_AR_LIBRARY_PATH>
MAXINE_AR_OS_RELEASE_SHIM=/usr/lib/maxine-ar/os-release-shim.so
MAXINE_OS_RELEASE=/usr/lib/maxine-ar/fake-os-release
MAXINE_AR_FEATURES=nvarfaceboxdetection,nvargazeredirection,nvarlandmarkdetection
MAXINE_AR_ARCHS=sm_120
```

`MAXINE_AR_FEATURES` and `MAXINE_AR_ARCHS` are informational: comma-separated lists of what was packaged. The library path has one `features/<feature>/lib` entry per packaged feature, sorted by name, between `lib` and the bundled CUDA and TensorRT directories. The file never sets `LD_PRELOAD`.

Load it for one program only: as `EnvironmentFile=/usr/share/maxine-ar/maxine-ar.env` in a systemd unit, or for one command or session with:

```bash
set -a; . /usr/share/maxine-ar/maxine-ar.env; set +a
```

Never source it from a login profile, `~/.bashrc` or `~/.profile`. The bundled directories must be on `LD_LIBRARY_PATH` for the SDK, because none of the CUDA 12 or TensorRT 10 sonames it needs exist system-wide on Arch, and the feature libraries are found by `dlopen`.

### The shim and running a program (AR)

The AR feature libraries read `/etc/os-release`, like the Video Effects model loader, so on a distribution the SDK does not list they need the shim: see [The compatibility shim](#the-compatibility-shim) for what it does and for `MAXINE_OS_RELEASE_DEBUG=1`. The package's environment file sets `MAXINE_OS_RELEASE` and `MAXINE_AR_OS_RELEASE_SHIM`, and the program has to preload the shim. Preload it on the final program only, as explained there: a wrapper that carries `LD_PRELOAD` loads the shim itself, drops the variable and starts the program without it.

```bash
set -a; . /usr/share/maxine-ar/maxine-ar.env; set +a
env LD_PRELOAD=$MAXINE_AR_OS_RELEASE_SHIM <program> [args]
```

A systemd user unit, at `~/.config/systemd/user/<service>.service.d/maxine-ar.conf`:

```ini
[Service]
EnvironmentFile=/usr/share/maxine-ar/maxine-ar.env
Environment=LD_PRELOAD=/usr/lib/maxine-ar/os-release-shim.so
```

Then `systemctl --user daemon-reload` and restart the service. Remove the file, reload and restart to go back to the unit without the SDK.

### Models (AR)

`MAXINE_AR_MODEL_DIR` (`/opt/nvidia/maxine/arsdk/lib/models`) holds the model files of the packaged features for the architectures you built the package with (`MAXINE_AR_ARCHS`), together with the files the core ships there. Models are not found by searching: a program passes this directory to the SDK as the model directory of the feature it creates. The models of all packaged features share this one directory. The package creates no engine cache directory.

### Check the AR installation

```bash
pacman -Ql maxine-ar-sdk-local | head
ls /opt/nvidia/maxine/arsdk/lib/models
(set -a; . /usr/share/maxine-ar/maxine-ar.env; set +a
 ldd /opt/nvidia/maxine/arsdk/lib/libnvARPose.so | grep 'not found')
```

With the environment file applied, the `ldd` command prints nothing, and the model directory lists files for your architecture. If a feature fails to load, check the same causes as in [Troubleshooting](#troubleshooting): the shim is not preloaded on the program itself (`MAXINE_OS_RELEASE_DEBUG=1` shows whether it is active), the feature libraries are not on `LD_LIBRARY_PATH`, or the model directory is wrong.

## Maxine Audio Effects SDK

`maxine-afx-sdk-local` installs the Audio Effects SDK 3.0.0, package version 3.0.0.12 (noise removal, room echo removal, both together, Studio Voice and the other effects you packaged).

### What the AFX package installs

| Path | Content |
|---|---|
| `/opt/nvidia/maxine/afx/` | The SDK tree as NVIDIA lays it out: `nvafx/lib`, `nvafx/include`, `features/<feature>/{lib,include,licenses,models}`, `external/cuda/lib` (CUDA 12.8, cuDNN 9.7.1 and TensorRT 10.9), `licenses/`, `samples/`, `version.h` |
| `/usr/lib/maxine-afx/os-release-shim.so` | The compatibility shim |
| `/usr/lib/maxine-afx/fake-os-release` | The replacement `os-release` (Ubuntu 24.04) |
| `/usr/share/maxine-afx/maxine-afx.env` | The environment file |
| `/usr/share/licenses/maxine-afx-sdk-local/` | Links to the SDK's licence files (its agreements, the models' licence, the third-party notices), and copies of `LICENSE-MIT` and `LICENSE-APACHE` |
| `/usr/share/doc/maxine-afx-sdk-local/` | This page (`usage.md`) |

The package also provides `maxine-afx-sdk=3.0.0.12`. Declare it as an optional dependency, for example `optdepends=('maxine-afx-sdk-local: NVIDIA Maxine audio effects')`.

### The AFX environment file

`/usr/share/maxine-afx/maxine-afx.env` has the same format as the others. Its keys, in file order, shown for two features at 48 kHz and `sm_120`:

```
MAXINE_AFX_ROOT=/opt/nvidia/maxine/afx
MAXINE_AFX_FEATURES_DIR=/opt/nvidia/maxine/afx/features
MAXINE_AFX_LIBRARY_PATH=/opt/nvidia/maxine/afx/nvafx/lib:/opt/nvidia/maxine/afx/features/denoiser/lib:/opt/nvidia/maxine/afx/features/studio_voice/lib:/opt/nvidia/maxine/afx/features/speaker_focus/lib:/opt/nvidia/maxine/afx/features/superres/lib:/opt/nvidia/maxine/afx/external/cuda/lib
LD_LIBRARY_PATH=<same value as MAXINE_AFX_LIBRARY_PATH>
MAXINE_AFX_OS_RELEASE_SHIM=/usr/lib/maxine-afx/os-release-shim.so
MAXINE_OS_RELEASE=/usr/lib/maxine-afx/fake-os-release
MAXINE_AFX_FEATURES=denoiser,studio_voice
MAXINE_AFX_ARCHS=sm_120
MAXINE_AFX_RATES=48k
```

`MAXINE_AFX_FEATURES`, `MAXINE_AFX_ARCHS` and `MAXINE_AFX_RATES` are informational: comma-separated lists of what was packaged. The library path is `nvafx/lib`, one `features/<feature>/lib` per packaged feature (sorted by name), then `features/speaker_focus/lib` and `features/superres/lib` (optional features NVIDIA distributes separately; listed even when not packaged, so adding them under the same root later needs no change, and a missing directory on the path is harmless; not repeated when packaged), then `external/cuda/lib`; there is no separate TensorRT directory, it is in `external/cuda/lib`. The path is needed because the feature libraries are loaded by `libnv_audiofx.so`, and their own search path does not reach `external/cuda/lib`. The file never sets `LD_PRELOAD`.

Load it for one program only, in the same two ways as the other packages (`EnvironmentFile=/usr/share/maxine-afx/maxine-afx.env`, or `set -a; . /usr/share/maxine-afx/maxine-afx.env; set +a`), and never from a login profile.

### The shim and running a program (AFX)

The feature libraries read `/etc/os-release`, so the shim is installed alongside and stays inactive until the program preloads it. Read [The compatibility shim](#the-compatibility-shim) for what it does; the rule about preloading on the final program applies unchanged.

```bash
set -a; . /usr/share/maxine-afx/maxine-afx.env; set +a
env LD_PRELOAD=$MAXINE_AFX_OS_RELEASE_SHIM <program> [args]
```

A systemd user unit, at `~/.config/systemd/user/<service>.service.d/maxine-afx.conf`:

```ini
[Service]
EnvironmentFile=/usr/share/maxine-afx/maxine-afx.env
Environment=LD_PRELOAD=/usr/lib/maxine-afx/os-release-shim.so
```

### Models (AFX)

The Audio Effects SDK does not search for models: an application passes the path of a model to the effect, as its `model_path` parameter. Each feature's models are in `features/<feature>/models/sm_<N>/`, the models of every sample rate of that architecture side by side. The environment file therefore gives the directory to build the path from, not a single model directory:

```
$MAXINE_AFX_FEATURES_DIR/<feature>/models/sm_<N>/<model>.trtpkg
```

For example `/opt/nvidia/maxine/afx/features/denoiser/models/sm_120/denoiser_48k.trtpkg`. A model can be named without its build number: like NVIDIA's `download_features.sh`, the build adds a relative link without the trailing number to each model, so `denoiser_48k.trtpkg` points at `denoiser_48k_<build>.trtpkg`. Use the architecture and sample rate your package holds (`MAXINE_AFX_ARCHS` and `MAXINE_AFX_RATES`; a package may hold several of each). The models' `.md5` files are checked during the build and are not installed.

### Check the AFX installation

```bash
pacman -Ql maxine-afx-sdk-local | head
ls /opt/nvidia/maxine/afx/features/denoiser/models/sm_120
(set -a; . /usr/share/maxine-afx/maxine-afx.env; set +a
 ldd /opt/nvidia/maxine/afx/nvafx/lib/libnv_audiofx.so | grep 'not found')
```

With the environment file applied, the `ldd` command prints nothing. Use a feature and architecture your package holds in the second command.

## Other packages: Optical Flow and TensorRT

Two further packages are not Maxine SDKs and have their own pages: `nvidia-optical-flow-sdk-local` (the NVIDIA Optical Flow SDK, [optical-flow.md](optical-flow.md)) and `nvidia-tensorrt-sdk-local` (TensorRT, [tensorrt.md](tensorrt.md)). They follow the same rules as the three above: each installs under its own directory in `/opt/nvidia/`, has an environment file you load for one program or one build, and sets no environment variable globally (the TensorRT package does add a system library path entry, described below). They need no shim.

| Package | Directory | Environment file | Library path key |
|---|---|---|---|
| `nvidia-optical-flow-sdk-local` | `/opt/nvidia/optical-flow` | `/usr/share/nvidia-optical-flow/nvidia-optical-flow.env` | `NVIDIA_OF_LIBRARY_PATH` (absent when FRUC is not packaged) |
| `nvidia-tensorrt-sdk-local` | `/opt/nvidia/tensorrt` | `/usr/share/nvidia-tensorrt/nvidia-tensorrt.env` | `NVIDIA_TRT_LIBRARY_PATH` |

A program that combines these with a Maxine SDK loads several environment files, and each sets `LD_LIBRARY_PATH`, so the last one wins. Build `LD_LIBRARY_PATH` yourself from the `*_LIBRARY_PATH` keys (`MAXINE_VFX_LIBRARY_PATH`, `MAXINE_AR_LIBRARY_PATH`, `MAXINE_AFX_LIBRARY_PATH`, `NVIDIA_OF_LIBRARY_PATH`, `NVIDIA_TRT_LIBRARY_PATH`), skipping the keys that a file does not set, and set it after loading the files. In a systemd unit, write the joined value in an `Environment=LD_LIBRARY_PATH=...` line after the `EnvironmentFile=` lines. The TensorRT package is the exception to the rule that a program must opt in: it installs an `/etc/ld.so.conf.d` entry, so its TensorRT 11 is on the system loader path. It does not shadow the TensorRT 10 that the Maxine SDKs bundle: the sonames differ (`libnvinfer.so.11` against `libnvinfer.so.10`), and the `LD_LIBRARY_PATH` from a Maxine SDK's environment file is searched before the loader cache. A program that combines them therefore no longer needs `NVIDIA_TRT_LIBRARY_PATH` in its `LD_LIBRARY_PATH`.

## Why nothing is global

None of the three Maxine packages installs an `/etc/ld.so.conf.d` entry or an `/etc/profile.d` file, or sets `LD_LIBRARY_PATH` or `LD_PRELOAD` globally, and none writes under `/etc`:

- Each SDK bundles its own CUDA 12.8, cuDNN and TensorRT 10.9. On Arch, which ships CUDA 13, putting them on the global library path would shadow the system libraries for every program. The bundled directories are on the path only for the program that loads the environment file.
- `LD_PRELOAD` is per process by design. The shim redirects one file, `/etc/os-release`, for the process that preloads it, so that only that process sees the replacement and the real file stays untouched.
- The packages can be installed side by side because each has its own directory under `/opt/nvidia/maxine/`, its own `/usr/lib/maxine-*` and its own environment file. A program that uses more than one SDK must combine them itself. The environment files all set `LD_LIBRARY_PATH`, so with two files loaded the later one wins: build the value from the `MAXINE_VFX_LIBRARY_PATH`, `MAXINE_AR_LIBRARY_PATH` and `MAXINE_AFX_LIBRARY_PATH` keys, which are the same values under names that do not collide, and set `LD_LIBRARY_PATH` explicitly. In a systemd unit, write the joined value out in an `Environment=LD_LIBRARY_PATH=...` line after the `EnvironmentFile=` lines, since the unit file cannot expand a variable that comes from an environment file.
- A package whose SDK you do not use costs nothing at run time: nothing loads it until a program opts in.
