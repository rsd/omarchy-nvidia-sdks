# GPU support of the Maxine Video Effects SDK

This page says which GPUs the SDK 1.3.0.0 (Linux) supports, how to find the architecture of your GPU, and how to fetch the models for another one. It applies to the `maxine-vfx-sdk-local` package: the package contains the models of the architectures you select, so the architecture decides what you download and what you build.

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
- **Models exist per feature.** The tag is the same for every feature that has models; background blur has none.
- **In-between values.** A GPU whose compute capability is not in the table (for example 8.7 or 12.1) has no exact model package. Choosing the closest architecture is an untested combination that the loader may refuse.

## Find your architecture

Look it up once, by hand:

```bash
nvidia-smi --query-gpu=compute_cap --format=csv,noheader
```

The output `12.0` means `sm_120`, `8.9` means `sm_89`. Remove the dot to get the number.

Neither the package build nor the helper scripts run `nvidia-smi` for you: querying the GPU wakes a sleeping discrete GPU. `maxine-vfx/configure.sh --detect-gpu` runs the same query, but only when you ask for it.

## Fetching models for another GPU

To use a GPU of another architecture (a second machine, a new card), fetch that architecture's models into your download directory, select it, and build again. Use the architecture from the table, here `sm_89`:

1. Download the model packages of every feature you use. With your configured NGC CLI, for one feature:

   ```bash
   ngc registry model download-version "nvidia/maxine/nvvfxgreenscreen:1.3.0.0_models_linux_sm89" --dest "$DIR"
   ```

   or, for every feature in the helper's list at once:

   ```bash
   maxine-vfx/download.sh --dest "$DIR" --archs sm_89
   ```

2. Select the architectures to package. This validates against what is present in `$DIR` and writes `maxine-vfx/selection.conf`:

   ```bash
   maxine-vfx/configure.sh --src "$DIR" --archs "sm_120 sm_89" --write
   ```

3. Rebuild and reinstall the package, as described in [download.md](download.md#next-step).

`configure.sh --src "$DIR"` without other options lists what your download contains and what the SDK offers; see [download.md](download.md) and the [README](../README.md#choose-your-features-and-gpu).

### Size cost per architecture

Each architecture adds the model packages of every feature that has models. In 1.3.0.0 the AI green screen is 8 `.engine.trtpkg` files, about 113 MB (10^6 bytes) per architecture. Other features differ. Check a package before you download it:

```bash
ngc registry model info "nvidia/maxine/<feature>:1.3.0.0_models_linux_sm<N>"
```

Package only the architectures of the machines you build for.

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

The equivalent for this package is the `ngc registry model download-version` command above, or `maxine-vfx/download.sh`, both of which create the layout the build reads.
