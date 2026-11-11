# GPU support of the Maxine Video Effects SDK

This page says which GPUs the SDK 1.3.0.0 (Linux) supports, how to find the architecture of your GPU, and how to fetch the models for another one. It applies to the `maxine-vfx-sdk-local` package: the package contains the models of the architectures you select, so the architecture decides what you download and what you build. What applies to the AR SDK and the Audio Effects SDK is in [AR and Audio Effects SDKs](#ar-and-audio-effects-sdks).

## Requirements

- **An NVIDIA GPU with Tensor Cores: Turing (`sm_75`) or newer.**
- **Pascal and older are not supported.** A GTX 1080 (`sm_61`) and every earlier GPU cannot run the SDK's models.
- **Volta (`sm_70`) has no 1.3.0.0 Linux models.** NVIDIA publishes no model package for it in this version.
- **Driver 570.26 or newer.** The SDK bundles CUDA 12.8, cuDNN 9 and TensorRT 10.9 and takes only `libcuda.so.1` from the driver.

## Architectures with models in 1.3.0.0 Linux

| Architecture | Compute capability | Example GPUs | `install_feature.sh -g` value | NGC models tag | Model directory created by `ngc` | AI green screen file token |
|---|---|---|---|---|---|---|
| `sm_75` Turing | 7.5 | RTX 20 series, GTX 16 series, T4 | `t4` | `nvidia/maxine/<feature>:1.3.0.0_models_linux_sm75` | `<feature>_v1.3.0.0_models_linux_sm75/` | `75` |
| `sm_80` Ampere (data centre) | 8.0 | A100, A30 | `a100`, `a30` | `nvidia/maxine/<feature>:1.3.0.0_models_linux_sm80` | `<feature>_v1.3.0.0_models_linux_sm80/` | `80` |
| `sm_86` Ampere | 8.6 | RTX 30 series, A2, A10, A16, A40 | `a2`, `a10`, `a16`, `a40` | `nvidia/maxine/<feature>:1.3.0.0_models_linux_sm86` | `<feature>_v1.3.0.0_models_linux_sm86/` | `86` |
| `sm_89` Ada Lovelace | 8.9 | RTX 40 series, L4, L40 | `l4`, `l40` | `nvidia/maxine/<feature>:1.3.0.0_models_linux_sm89` | `<feature>_v1.3.0.0_models_linux_sm89/` | `89` |
| `sm_90` Hopper | 9.0 | H100 | `h100` | `nvidia/maxine/<feature>:1.3.0.0_models_linux_sm90` | `<feature>_v1.3.0.0_models_linux_sm90/` | `90` |
| `sm_100` Blackwell (data centre) | 10.0 | B100, B200 | `b200` (see the note below) | `nvidia/maxine/<feature>:1.3.0.0_models_linux_sm100` | `<feature>_v1.3.0.0_models_linux_sm100/` | `100` |
| `sm_120` Blackwell | 12.0 | RTX 50 series, RTX PRO Blackwell, B40 | `b40` | `nvidia/maxine/<feature>:1.3.0.0_models_linux_sm120` | `<feature>_v1.3.0.0_models_linux_sm120/` | `120` |

Notes on the table:

- **The example GPUs are for orientation only.** The authoritative check is the compute capability that your driver reports (next section) and NVIDIA's CUDA GPUs page.
- **The last column** is the architecture number as it appears in the AI green screen model file names: `AIGS_288x512_<N>_m{0..3}[_1_4_8].engine.trtpkg`, where `<N>` is the number without the dot and `m0` to `m3` are the four model variants. Other features name their files differently.
- **`sm_100`.** The SDK's README names `b200` as the `-g` value. The internal map of `install_feature.sh` also accepts `b100`. This page uses `b200`.
- **Models exist per feature.** In 1.3.0.0 Linux only AI green screen (`nvvfxgreenscreen`), video noise removal (`nvvfxdenoising`) and video relighting (`nvvfxrelighting`) have model packages. The tag pattern is the same for the three. The other five features (background blur, video super resolution, upscale, TrueHDR and video frame generation) are a library only.
- **In-between values.** A GPU whose compute capability is not in the table (for example 8.7 or 12.1) has no exact model package. Choosing the closest architecture is an untested combination that the loader may refuse.

## Find your architecture

Look it up once, by hand:

```bash
nvidia-smi --query-gpu=compute_cap --format=csv,noheader
```

The output has one line per GPU. `12.0` means `sm_120`, `8.6` means `sm_86`, `10.0` means `sm_100`: remove the dot. Below 7.5 the GPU is not supported. A value that is not in the table has no model package.

`maxine-vfx/download.sh` runs this query itself when you do not pass `--archs` (`--archs auto`, the default), and uses every different architecture it finds. `maxine-vfx/configure.sh --detect-gpu` runs the same query when you ask for it. The package build never queries the GPU: you select the architectures explicitly.

## Fetching models for another GPU

To use a GPU of another architecture (a second machine, a new card), fetch that architecture's models into your download directory, select it, and build again. Use the architecture from the table, here `sm_89`:

1. Download the model packages of every feature you use. The helper does this for the architecture you name, here `sm_89`, and for the features of the chosen preset (`broadcast` by default; `--preset all` adds relighting):

   ```bash
   maxine-vfx/download.sh --archs sm_89
   ```

   Or with your configured NGC CLI, for one feature:

   ```bash
   ngc registry model download-version nvidia/maxine/nvvfxgreenscreen:1.3.0.0_models_linux_sm89 --dest ~/Downloads/maxine
   ```

   Both put the new directories next to the ones you already have. Repeat for denoising and relighting if you use them. To see what NGC offers for an architecture first, run `maxine-vfx/download.sh --list --archs sm_89`.

2. Select the architectures to package. This validates against what is present in `~/Downloads/maxine` and writes `maxine-vfx/selection.conf`:

   ```bash
   maxine-vfx/configure.sh --src ~/Downloads/maxine --archs "sm_120 sm_89" --write
   ```

3. Rebuild and reinstall the package, as described in [download.md](download.md#next-step).

`configure.sh --src ~/Downloads/maxine` without other options lists what your download contains and what the SDK offers; see [download.md](download.md) and the [README](../README.md#choose-your-features-and-gpu).

### Size cost per architecture

Each architecture adds the model packages of green screen, denoising and relighting, the three features that have models. Sizes as NGC reports them for 1.3.0.0 Linux, in MiB (2^20 bytes):

| Architecture | Green screen models | Denoising models | Relighting models |
|---|---|---|---|
| `sm_75` | 99.33 | 0.80 | 75.62 |
| `sm_80` | 113.10 | 1.84 | 76.79 |
| `sm_86` | 108.34 | 1.79 | 78.61 |
| `sm_89` | 109.41 | 2.30 | 76.76 |
| `sm_90` | 113.45 | 3.60 | 77.97 |
| `sm_100` | 117.21 | 2.76 | 104.30 |
| `sm_120` | 113.14 | 3.72 | 79.46 |

The default preset (`broadcast`) needs green screen and denoising models only. Relighting models come with `--preset all` or `--features`. You can check a package before you download it:

```bash
ngc registry model info nvidia/maxine/nvvfxgreenscreen:1.3.0.0_models_linux_sm120
```

Package only the architectures of the machines you build for. The sizes of the SDK core and of the libraries are in [download.md](download.md#sizes).

## NVIDIA's `install_feature.sh`: documented only, never run

The SDK ships `features/install_feature.sh`. Given a `-g <gpu>` value from the table, it downloads a feature's library and the models for that GPU. It is described here so you can recognise what it does. **This repository does not recommend running it, and nothing in this repository runs it:**

- It installs into `/usr/local/VideoFX` and needs root.
- Its feature listing (`--list-features`) needs an NGC API key in the environment variable `NGC_CLI_API_KEY`.
- Its result is an SDK tree. A tree it installed (for example `/usr/local/VideoFX`) is a valid tree-mode source: `MAXINE_VFX_SRC=/usr/local/VideoFX` (or `configure.sh --src /usr/local/VideoFX`) builds the package from it, packaging the features and models it holds. The reasons not to use it are the root access and the files it leaves under `/usr/local`, outside the package manager.

The NGC resource names it uses, read from the script, are the same ones this repository's commands use:

| Item | Name |
|---|---|
| Organisation and team | `nvidia`, `maxine` |
| Feature library | `nvidia/maxine/<feature>` with the version `<ver>_lib_linux` |
| Feature models | `nvidia/maxine/<feature>` with the version `<ver>_models_linux_sm<N>` |
| Feature discovery | the collections `maxine_vfx_sdk` and `vfx_sdk` |
| The core SDK | the resource `nvidia/maxine/vfx_sdk_core:<ver>_linux` |

The equivalent for this package is `maxine-vfx/download.sh`, or the `ngc registry model download-version` commands in [download.md](download.md#download-by-hand), both of which create the layout the build reads.

## AR and Audio Effects SDKs

`maxine-ar-sdk-local` (AR SDK 1.2.0.0) and `maxine-afx-sdk-local` (Audio Effects SDK 3.0.0) work like the Video Effects package: the models of the architectures you select go into the package, so the architecture decides what you download and build. The architecture is the compute capability without the dot, found as in [Find your architecture](#find-your-architecture); the compute capability, example GPUs and `-g` values in the [table above](#architectures-with-models-in-1300-linux) are the same hardware facts, but its NGC tags, directory names and sizes are for Video Effects only.

| | AR SDK 1.2.0.0 | Audio Effects SDK 3.0.0 |
|---|---|---|
| GPU | Turing (`sm_75`) or newer | Turing (`sm_75`) or newer |
| Architectures with models | `sm_75`, `sm_80`, `sm_86`, `sm_89`, `sm_90`, `sm_100`, `sm_120` | `sm_75`, `sm_80`, `sm_86`, `sm_89`, `sm_90`, `sm_100`, `sm_120` |
| Where the list comes from | The architectures NVIDIA's feature installer fetches 1.2.0.0 Linux models for | The architectures NVIDIA's `download_features.sh` maps a GPU to |
| Models tag | `nvidia/maxine/<feature>:1.2.0.0_models_linux_sm<N>` | `nvidia/maxine/afx_<feature>:3.0.0-<rate>-sm<N>` |
| Model directory created by `ngc` | `<feature>_v1.2.0.0_models_linux_sm<N>/` | `afx_<feature>_v3.0.0-<rate>-sm<N>/` |
| Models | In 1.2.0.0 Linux every feature has them | Each feature has model packages per sample rate and architecture; an item NGC does not have shows as "no model package" |
| Models per sample rate | not applicable | `16k` and `48k`; `8k_to_16k` and `16k_to_48k` for audio super resolution |
| Bundled | CUDA 12.8, cuDNN 9.7 and TensorRT 10.9 | CUDA 12.8, cuDNN 9.7 and TensorRT 10.9 |
| Download helper | `maxine-ar/download.sh --archs ...` | `maxine-afx/download.sh --archs ...` |
| Select the architectures | `maxine-ar/configure.sh --archs ... --write` | `maxine-afx/configure.sh --archs ... --write` |

Notes:

- **Pascal and older are not supported.** Both helpers stop on an architecture below `sm_75` and say so. An architecture that is not in the list (for example 8.7 or 12.1) has no exact model package: the helpers warn and show "no model package" for it.
- **Driver.** Both packages depend on `nvidia-utils` for `libcuda.so.1` and bundle their own CUDA, cuDNN and TensorRT. This repository's sources state no separate minimum driver for these two SDKs; the 570.26 above is the figure given for the Video Effects SDK, which bundles the same CUDA version.
- **The helpers detect the GPU** the same way as `maxine-vfx/download.sh`: `--archs auto` (the default) asks `nvidia-smi` for the compute capability and uses every different architecture it finds. The builds never query the GPU, and `configure.sh --detect-gpu` runs the query only when you ask for it.
- **Fetching another GPU's models** follows [Fetching models for another GPU](#fetching-models-for-another-gpu), with the helper and the tags of the package you are using, for example `maxine-ar/download.sh --archs sm_89`. The manual commands are in [download.md](download.md#ar-sdk-download-by-hand) and [download.md](download.md#afx-sdk-download-by-hand).
- **Size per architecture.** For the AR SDK and `sm_120` the models are 92.5 MiB for eye contact, 48.0 MiB for landmark detection, 28.7 MiB for face box detection and 1.6 MiB for face expressions; each further architecture adds the same kind of set. For the Audio Effects SDK each architecture adds the models of every selected feature at every sample rate present. `download.sh --list --archs all` prints the size NGC reports for each item, and the build summary prints the model size per architecture. Package only the architectures of the machines you build for.
- **If the build stops** with a missing models directory, a selected feature lacks models for a selected architecture (or, for the Audio Effects SDK, for one of its sample rates): the message names the feature, the architecture and the NGC tag to download, or you can leave that architecture out of the selection.
