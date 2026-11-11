# omarchy-nvidia-sdks

Personal-use recipes that turn your own NVIDIA SDK download into local Arch Linux packages, so that several projects share one install instead of each carrying its own copy.

## Licence and personal use

Read this before using anything here.

- **You accept NVIDIA's licence and you download the SDK yourself**, from NVIDIA NGC, with your own account. The recipes only automate what happens after that.
- **This repository holds only recipes**: PKGBUILDs, scripts, documentation and the source of a small compatibility shim. **Nothing from NVIDIA is committed**: no SDK files, libraries, headers, models (`*.trtpkg`), tarballs or licence PDFs. The guard `scripts/check-no-nvidia.sh` enforces this: it refuses NVIDIA's file types (libraries, models and their `*.trtpkg.*` checksum sidecars, archives, PDFs, SDK headers), an unpacked SDK tree (`VideoFX/`, `ARSDK/`, `Audio_Effects_SDK/`), an NGC download directory, an SDK's top-level names (`lib/`, `include/`, `features/`, `external/`, `share/`, `samples/`, `licenses/`, `nvafx/`, `bin/`, `docs/`, `version.h`, `Changelog.txt`) placed directly inside a recipe directory, and file content that carries an NVIDIA marker. Enable its hooks in your clone with:

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
| [`maxine-vfx/`](maxine-vfx/) | `maxine-vfx-sdk-local` | NVIDIA Maxine Video Effects SDK 1.3.0.0: the features and GPU architectures you download and select. The download helper fetches AI green screen, background blur and video noise removal by default |
| [`maxine-ar/`](maxine-ar/) | `maxine-ar-sdk-local` | NVIDIA Maxine AR SDK 1.2.0.0: eye contact (gaze redirection), face box detection, facial landmarks, face expressions and the other documented AR features. The download helper fetches eye contact with the two features it depends on by default |
| [`maxine-afx/`](maxine-afx/) | `maxine-afx-sdk-local` | NVIDIA Maxine Audio Effects SDK 3.0.0 (package version 3.0.0.12): noise removal, room echo removal, both together and Studio Voice, at the sample rates you download. The download helper fetches those four at 48 kHz by default |

The three packages follow the same pattern: you download the SDK from NGC, you choose the features and GPU architectures, and `makepkg` builds one package from your download. Each installs under its own `/opt/nvidia/maxine/` directory and its own environment file, and none sets anything globally, so they can be installed together. The sections up to [Not limited to one GPU or to today's features](#not-limited-to-one-gpu-or-to-todays-features) describe the Video Effects package; [the AR and Audio Effects packages](#the-ar-and-audio-effects-packages) follow.

## Quick start

You need an NVIDIA Developer Program account, the NGC CLI, and `ngc config set` run by yourself. [docs/download.md](docs/download.md#prerequisites) has the steps. Then:

1. Download the SDK files from NGC with one command:

   ```bash
   maxine-vfx/download.sh
   ```

   The script detects your GPU architecture, probes NGC, prints a table of what it would download and how big it is, asks for confirmation, downloads only what is missing, verifies the result and retries failures. Use `--dry-run` to look without downloading, `--preset all` for every feature, and `--yes` to skip the question. The options are in [docs/download.md](docs/download.md#download-with-one-command). The result is one directory, by default `~/Downloads/maxine`.

2. Choose your features and architectures, and build the package. The script prints these commands with your paths filled in, and `--build` runs them for you:

   ```bash
   maxine-vfx/configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
   cd maxine-vfx && makepkg -f
   ```

   `configure.sh` saves the choice in `maxine-vfx/selection.conf` (see [Choose your features and GPU](#choose-your-features-and-gpu)), and `makepkg` reads it. Without `selection.conf` you can pass the same choice in the environment: `MAXINE_VFX_SRC=~/Downloads/maxine MAXINE_VFX_ARCHS=sm_120 MAXINE_VFX_FEATURES=all makepkg -f`.

3. Install the package yourself: `sudo pacman -U maxine-vfx-sdk-local-*.pkg.tar*`. Nothing in this repository runs `sudo` or installs anything.
4. Use it from your programs, following [docs/usage.md](docs/usage.md).

The build options (`MAXINE_VFX_SRC`, `MAXINE_VFX_ARCHS`, `MAXINE_VFX_FEATURES`) are described in [maxine-vfx/README.md](maxine-vfx/README.md). If you prefer to type the `ngc` commands yourself, [docs/download.md](docs/download.md#download-by-hand) lists them in full.

## Choose your features and GPU

Run the selection helper on your download directory to see what you have and what the SDK offers:

```bash
maxine-vfx/configure.sh --src ~/Downloads/maxine
```

It reads the directory without network access and without running `ngc`, and prints:

- the features and GPU architectures **present** in your download, and the SDK version;
- the features the SDK **offers** and the GPU architectures that have models for 1.3.0.0 Linux, with the ones you already have marked;
- your current selection and the commands to change it or to fetch more.

SDK 1.3.0.0 for Linux offers eight features on NGC:

| Feature | NGC name | Preset |
|---|---|---|
| AI green screen | `nvvfxgreenscreen` | broadcast, all |
| Background blur | `nvvfxbackgroundblur` | broadcast, all |
| Video noise removal | `nvvfxdenoising` | broadcast, all |
| Video relighting | `nvvfxrelighting` | all |
| Video super resolution | `nvvfxvideosuperres` | all |
| Video upscaling | `nvvfxupscale` | all |
| SDR to HDR (TrueHDR) | `nvvfxtruehdr` | all |
| Video frame generation | `nvvfxvideoframegeneration` | all |

The `broadcast` preset is the default of `download.sh`. Model packages exist only for green screen, denoising and relighting. Artifact reduction (`nvvfxartifactreduction`) is not on NGC for 1.3.0.0. What each feature does, its closest NVIDIA Broadcast name and its download size are in [docs/download.md](docs/download.md#features). NGC hides the Maxine items from `ngc registry model list "nvidia/maxine/nvvfx*"`, which prints an empty table, so use `maxine-vfx/download.sh --list` to see what is available.

To save a selection:

```bash
maxine-vfx/configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
```

This validates the selection against what is present (a feature or architecture you have not downloaded is an error, and the message names the command that fetches it) and writes `maxine-vfx/selection.conf`. The file is git-ignored because it holds a local path. The PKGBUILD reads it when it builds; it is parsed as plain `KEY=value` lines and never executed. An environment variable overrides the file, and the file overrides the built-in default. `configure.sh --show` prints the current file.

To fetch more features or architectures, run `maxine-vfx/download.sh` again with `--features` or `--archs`, then `configure.sh` and `makepkg` again. Which GPUs are supported, how to find your architecture and how to fetch models for another GPU are in [docs/gpu-support.md](docs/gpu-support.md).

### Not limited to one GPU or to today's features

- **Features.** `MAXINE_VFX_FEATURES` is `all` (the default: every feature found in your download is packaged) or a list such as `nvvfxgreenscreen,nvvfxbackgroundblur`: exactly those are packaged, and each must be present. To add a feature, download its library and models into the same directory (`download.sh --features ...`, or your own `ngc`), then rebuild. The steps are in [docs/download.md](docs/download.md#more-features).
- **GPU architectures.** `MAXINE_VFX_ARCHS` takes a list (`"sm_120 sm_89"`) or `all`. The SDK needs a Tensor-core GPU, Turing or newer; see [docs/gpu-support.md](docs/gpu-support.md). Each architecture adds the model packages of every feature that has models: for `sm_120` that is about 113 MiB for green screen, 3.7 MiB for denoising and 79 MiB for relighting. The sizes per architecture are in [docs/gpu-support.md](docs/gpu-support.md#size-cost-per-architecture).
- **Sizes** in these documents are stated in MiB or GiB (2^20 and 2^30 bytes), or in GB (10^9 bytes), explicitly. The default download for `sm_120` is about 2.75 GiB, of which the SDK core is 2.63 GiB. The assembled SDK tree is 4.4 GiB (4,671,229,191 bytes) and the built package (`PKGEXT=.pkg.tar`) is about 4.4 GiB too. With all eight features and `sm_120` models the assembled tree is 5,054,183,158 bytes (4.71 GiB) and the package is about 4.7 GiB (`PKGEXT=.pkg.tar`); the five features outside the default add 326,922,413 bytes (about 312 MiB) to the download.

## The AR and Audio Effects packages

`maxine-ar/` and `maxine-afx/` have the same layout, options and steps as `maxine-vfx/`: `download.sh`, `configure.sh`, a PKGBUILD that reads `selection.conf` and the environment, and an environment file for consumers. Each package's README is the reference for its build inputs: [maxine-ar/README.md](maxine-ar/README.md) and [maxine-afx/README.md](maxine-afx/README.md). Each package has its own download directory, by default `~/Downloads/maxine/ar-sdk` and `~/Downloads/maxine/afx-sdk`, so that one source directory holds one SDK.

```bash
# AR SDK: eye contact, face box and landmark detection
maxine-ar/download.sh
maxine-ar/configure.sh --src ~/Downloads/maxine/ar-sdk --archs sm_120 --features all --write
cd maxine-ar && makepkg -f

# Audio Effects SDK: noise removal, room echo removal and Studio Voice at 48 kHz
maxine-afx/download.sh
maxine-afx/configure.sh --src ~/Downloads/maxine/afx-sdk --archs sm_120 --features all --write
cd maxine-afx && PKGEXT=.pkg.tar makepkg -f
```

Then install with `sudo pacman -U` yourself and use the package as described in [docs/usage.md](docs/usage.md). The build inputs are `MAXINE_AR_SRC`, `MAXINE_AR_ARCHS` and `MAXINE_AR_FEATURES`, and `MAXINE_AFX_SRC`, `MAXINE_AFX_ARCHS` and `MAXINE_AFX_FEATURES`. The Audio Effects package has no sample-rate input: every sample rate present in your download is packaged.

| Package | Features | NGC names |
|---|---|---|
| `maxine-ar-sdk-local` | Eye contact (`nvargazeredirection`), face box detection (`nvarfaceboxdetection`), facial landmarks (`nvarlandmarkdetection`), face expressions (`nvarfaceexpressions`); also offered: body detection, body pose and lip synchronisation (`nvarbodydetection`, `nvarbodyposeestimation`, `nvarlipsync`) | `nvidia/maxine/<feature>` |
| `maxine-afx-sdk-local` | Noise removal (`denoiser`), room echo removal (`dereverb`), both in one (`dereverb_denoiser`), Studio Voice (`studio_voice`); also offered: audio super resolution (`superres`), the 16 kHz variants and speaker focus (Early Access) | `nvidia/maxine/afx_<feature>` |

Eye Contact and Auto Frame in NVIDIA Broadcast belong to the AR SDK, not to the Video Effects SDK. The names, preset contents, manual `ngc` commands and sizes are in [docs/download.md](docs/download.md#maxine-ar-sdk) for the AR SDK and [docs/download.md](docs/download.md#maxine-audio-effects-sdk) for the Audio Effects SDK. The GPU architectures are in [docs/gpu-support.md](docs/gpu-support.md#ar-and-audio-effects-sdks).

## Repository layout

```
README.md
LICENSE-MIT, LICENSE-APACHE
.gitignore
.githooks/                        pre-commit, pre-merge-commit, pre-push: run the licence guard
scripts/check-no-nvidia.sh        licence guard: refuses NVIDIA files, SDK trees, NGC download directories
scripts/test.sh                   runs every check of this repository
scripts/tests/                    tests of the guard, of env.sh and of a PKGBUILD fixture build
docs/download.md                  downloading the SDKs from NGC: the one-command path, the manual steps, sizes, troubleshooting, for the three SDKs
docs/usage.md                     how a program uses each installed package: environment file, shim, models
docs/gpu-support.md               supported GPUs, architectures and how to fetch their models
maxine-vfx/PKGBUILD               the package recipe
maxine-vfx/assemble.sh            builds the SDK tree from your download
maxine-vfx/download.sh            downloads what you need with your configured ngc: probes, shows sizes, verifies
maxine-vfx/configure.sh           shows what your download holds and saves your selection
maxine-vfx/selection.sh           parses selection.conf (never executes it), for the PKGBUILD and configure.sh
maxine-vfx/README.md              build instructions for the package
maxine-vfx/tests/                 tests of assemble.sh, configure.sh and download.sh on tiny fake files
maxine-ar/                        the AR SDK package: PKGBUILD, assemble.sh, download.sh, configure.sh, selection.sh, README.md, tests/ (same roles as in maxine-vfx/)
maxine-afx/                       the Audio Effects SDK package: the same files as maxine-ar/
tools/os-release-shim/            the compatibility shim and its test
tools/maxine-probe/               a small program that checks the SDK loads
```

## Testing

```bash
scripts/test.sh
```

This runs every check in the repository, for all three packages: shellcheck over every script, the syntax and metadata of each PKGBUILD, the fixture tests of each package's `assemble.sh`, `configure.sh` and `download.sh` (the last against a fake `ngc`), a `makepkg` build of each PKGBUILD against fake SDK files, the shim test, and the licence guard and its hooks, then the guard over the whole tree. It needs `shellcheck`. A GPU is not required, it uses no network and it needs no NVIDIA download. The `makepkg` fixture builds are skipped when `makepkg`, `fakeroot` or `bsdtar` is missing.

## Licence of this repository's content

MIT OR Apache-2.0, at your option: see [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE). This covers only the content of this repository. It does not apply to any NVIDIA software you download or to a package built from it.
