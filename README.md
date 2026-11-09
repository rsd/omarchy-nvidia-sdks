# omarchy-nvidia-sdks

Personal-use recipes that turn your own NVIDIA SDK download into local Arch Linux packages, so that several projects share one install instead of each carrying its own copy.

## Licence and personal use

Read this before using anything here.

- **You accept NVIDIA's licence and you download the SDK yourself**, from NVIDIA NGC, with your own account. The recipes only automate what happens after that.
- **This repository holds only recipes**: PKGBUILDs, scripts, documentation and the source of a small compatibility shim. **Nothing from NVIDIA is committed**: no SDK files, libraries, headers, models (`*.trtpkg`), tarballs or licence PDFs. The guard `scripts/check-no-nvidia.sh` enforces this. Enable its hooks in your clone with:

  ```bash
  git config core.hooksPath .githooks
  ```

  The hooks are `pre-commit`, `pre-merge-commit` and `pre-push`. `pre-push` checks the commits being pushed with the guard's `--range` mode. `git commit --no-verify` bypasses them (as does `git push --no-verify` for `pre-push`), so the guard is a safety net and not an access control. `scripts/check-no-nvidia.sh --all` checks the working tree, not the history: a file committed earlier stays in the history until you rewrite it.

- **The built package contains NVIDIA software and is for your own machine only.** Never upload it to a package repository, to the AUR as a binary, to a release page, or share it in any other way. The NVIDIA Software License Agreement (8.5) forbids redistribution, including in "publicly accessible software repositories".
- **Do not publish benchmark results** (licence 8.9), and do not reverse engineer the software.
- **NVIDIA does not support this configuration.** Arch Linux and other distributions the SDK does not list, and client-side use of an SDK documented for servers, are outside what NVIDIA supports. Expect no vendor support.
- This is not legal advice. Read the licence you accept.

The licence of this repository's own content is stated at the end of this page.

## Packages

| Directory | Package | Contents |
|---|---|---|
| [`maxine-vfx/`](maxine-vfx/) | `maxine-vfx-sdk-local` | NVIDIA Maxine Video Effects SDK 1.3.0.0: the features and GPU architectures you download and select. The download helper fetches AI green screen and background blur by default |

## Quick start

1. Download the SDK files from NGC, following [docs/download.md](docs/download.md). The result is one directory, for example `~/Downloads/maxine`. The helper `maxine-vfx/download.sh` runs the downloads with your own NGC CLI once it is configured.
2. Find your GPU architecture once, by hand. The build never probes the GPU:

   ```bash
   nvidia-smi --query-gpu=compute_cap --format=csv,noheader   # 12.0 means sm_120
   ```

3. Choose your features and architectures, and save the choice (see [Choose your features and GPU](#choose-your-features-and-gpu)):

   ```bash
   maxine-vfx/configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
   ```

4. Build the package. The choice is read from `maxine-vfx/selection.conf`:

   ```bash
   cd maxine-vfx && makepkg -f
   ```

   Without `selection.conf` you can pass the same choice in the environment instead: `MAXINE_VFX_SRC=~/Downloads/maxine MAXINE_VFX_ARCHS=sm_120 MAXINE_VFX_FEATURES=all makepkg -f`.

5. Install it yourself: `sudo pacman -U maxine-vfx-sdk-local-*.pkg.tar.zst`. Nothing in this repository runs `sudo`.
6. Use it from your programs, following [docs/usage.md](docs/usage.md).

The build options (`MAXINE_VFX_SRC`, `MAXINE_VFX_ARCHS`, `MAXINE_VFX_FEATURES`) are described in [maxine-vfx/README.md](maxine-vfx/README.md).

## Choose your features and GPU

Run the selection helper on your download directory to see what you have and what the SDK offers:

```bash
maxine-vfx/configure.sh --src ~/Downloads/maxine
```

It reads the directory without network access and without running `ngc`, and prints:

- the features and GPU architectures **present** in your download, and the SDK version;
- the features the SDK **offers** and the GPU architectures that have models for 1.3.0.0 Linux, with the ones you already have marked;
- your current selection and the commands to change it or to fetch more.

The features the SDK offers are the "Common VFX SDK Features" of its own `features/README.md`: Artifact Reduction (`nvvfxartifactreduction`; the 1.1.0.0 Changelog says it was removed, so check NGC before relying on it), Video Super Resolution (`nvvfxvideosuperres`), video denoising (`nvvfxdenoising`), video upscaling (`nvvfxupscale`), AI green screen (`nvvfxgreenscreen`) and background blur (`nvvfxbackgroundblur`). The Changelog also names Video Relighting, TrueHDR and Video Frame Generation (VFG); their NGC names are in the output of `ngc registry model list "nvidia/maxine/nvvfx*"` (or `maxine-vfx/download.sh --list`).

To save a selection:

```bash
maxine-vfx/configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
```

This validates the selection against what is present (a feature or architecture you have not downloaded is an error, and the message names the command that fetches it) and writes `maxine-vfx/selection.conf`. The file is git-ignored because it holds a local path. The PKGBUILD reads it when it builds; it is parsed as plain `KEY=value` lines and never executed. An environment variable overrides the file, and the file overrides the built-in default. `configure.sh --show` prints the current file.

To fetch more features or architectures, use `maxine-vfx/download.sh` or your own `ngc` (see [docs/download.md](docs/download.md)), run `configure.sh` again, and rebuild. Which GPUs are supported, how to find your architecture and how to fetch models for another GPU are in [docs/gpu-support.md](docs/gpu-support.md).

### Not limited to one GPU or to today's features

- **Features.** `MAXINE_VFX_FEATURES` is `all` (the default: every feature found in your download is packaged) or a list such as `nvvfxgreenscreen,nvvfxbackgroundblur`: exactly those are packaged, and each must be present. To add a feature, download its library and models with your own `ngc` into the same directory, then rebuild. Discover the names with the read-only `ngc registry model list "nvidia/maxine/nvvfx*"`. The steps are in [docs/download.md](docs/download.md#more-features).
- **GPU architectures.** `MAXINE_VFX_ARCHS` takes a list (`"sm_120 sm_89"`) or `all`. The SDK needs a Tensor-core GPU, Turing or newer; see [docs/gpu-support.md](docs/gpu-support.md). Each architecture adds the model packages of every feature that has models: in 1.3.0.0 the green screen models are about 113 MB (10^6 bytes) per architecture, and other features differ. Check a package before you download it with `ngc registry model info nvidia/maxine/<feature>:<version>_models_linux_sm<N>`.
- **Sizes** in these documents are stated in GiB (2^30 bytes) or GB (10^9 bytes) explicitly. The SDK core tarball is 2.62 GiB (2.82 GB). The assembled SDK tree is 4.4 GiB (4,671,229,191 bytes) and the built package (`PKGEXT=.pkg.tar`) is about 4.4 GiB too.

## Roadmap

- `maxine-afx/`: the Maxine Audio Effects SDK. Planned, not started.
- `maxine-ar/`: the Maxine AR SDK, which holds eye contact (it is not part of the Video Effects SDK). Planned, not started.

## Repository layout

```
README.md
LICENSE-MIT, LICENSE-APACHE
.gitignore
.githooks/                        pre-commit, pre-merge-commit, pre-push: run the licence guard
scripts/check-no-nvidia.sh        licence guard: refuses NVIDIA files
scripts/test.sh                   runs every check of this repository
scripts/tests/                    tests of the guard
docs/download.md                  the manual download steps for maxine-vfx
docs/usage.md                     how a program uses the installed package
docs/gpu-support.md               supported GPUs, architectures and how to fetch their models
maxine-vfx/PKGBUILD               the package recipe
maxine-vfx/assemble.sh            builds the SDK tree from your download
maxine-vfx/download.sh            optional helper that calls your configured ngc
maxine-vfx/configure.sh           shows what your download holds and saves your selection
maxine-vfx/selection.sh           parses selection.conf (never executes it), for the PKGBUILD and configure.sh
maxine-vfx/README.md              build instructions for the package
maxine-vfx/tests/                 tests of assemble.sh and configure.sh on tiny fake files
tools/os-release-shim/            the compatibility shim and its test
tools/maxine-probe/               a small program that checks the SDK loads
```

## Testing

```bash
scripts/test.sh
```

This runs every check in the repository. It needs `shellcheck`, a GPU is not required, and it uses no network.

## Licence of this repository's content

MIT OR Apache-2.0, at your option: see [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE). This covers only the content of this repository. It does not apply to any NVIDIA software you download or to a package built from it.
