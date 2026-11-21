# omarchy-nvidia-sdks

Local Arch Linux packages for the NVIDIA Maxine, Optical Flow and TensorRT SDKs, for people who want NVIDIA Broadcast-style RTX effects on Linux. You download each SDK from NVIDIA yourself, or let `makepkg` fetch TensorRT. This repository turns it into a package for your own machine.

## What you get

SDK stands for software development kit: the libraries, headers and AI models a program uses. Five packages:

- **Maxine Video Effects** (`maxine-vfx-sdk-local`): AI green screen, background blur, video noise removal, relighting and video super resolution. Maxine is NVIDIA's family of AI video and audio effects.
- **Maxine AR** (`maxine-ar-sdk-local`): eye contact and face detection.
- **Maxine Audio Effects** (`maxine-afx-sdk-local`): noise removal, room echo removal and Studio Voice.
- **NVIDIA Optical Flow SDK** (`nvidia-optical-flow-sdk-local`): the headers, the FRUC (frame rate up-conversion) library and the samples.
- **NVIDIA TensorRT** (`nvidia-tensorrt-sdk-local`): NVIDIA's library for running AI models fast on its GPUs.

The effects need an NVIDIA RTX GPU: Turing (RTX 20 series) or newer, with Tensor cores. See [docs/gpu-support.md](docs/gpu-support.md).

## Why use these packages

NVIDIA Broadcast offers RTX effects for a webcam and a microphone: background blur, removal and replacement, video noise removal, eye contact, and microphone noise and room echo removal. NVIDIA ships no Broadcast application for Linux, but it does publish the SDKs behind these effects. They are awkward to install and share on a Linux system. These packages fix that:

- **Nothing is redistributed.** You get each SDK from NVIDIA under NVIDIA's licence, with your own account where NVIDIA asks for one. The repository holds only recipes.
- **One guided script.** `scripts/setup.sh` checks your machine, finds your download, builds the package, installs it and checks the result. It asks before every step that changes anything, and it prints each command first.
- **Isolated installs.** Each package installs under `/opt/nvidia/` with an environment file that a program loads for itself. The Maxine and Optical Flow packages set nothing globally, so you can install them together.
- **Reusable.** Any project on Arch Linux or an Arch-based distribution that needs the Maxine, Optical Flow or TensorRT headers and libraries can depend on these packages instead of carrying its own copy of an SDK. [docs/usage.md](docs/usage.md) explains how a program finds the headers, libraries and models.
- **Your choice of features and GPUs.** You pick the effects and GPU architectures, and the package holds only those.
- **Tested without a GPU.** `scripts/test.sh` runs every check on fake SDK files, with no network and no NVIDIA download.

The packages were made for [omarchy-broadcast](https://github.com/rsd/omarchy-broadcast), a virtual camera and microphone daemon for Omarchy that uses these SDKs on RTX GPUs. They do not depend on it.

## Install

```bash
git clone https://github.com/rsd/omarchy-nvidia-sdks.git && cd omarchy-nvidia-sdks && scripts/setup.sh --dry-run
```

The dry run changes nothing. It checks your machine and prints every command the real run would use. When it looks right, run `scripts/setup.sh --sdk vfx` (or `ar`, `afx`, `of`, `trt`) and follow the prompts.

[INSTALL.md](INSTALL.md) has the prerequisites, the downloads from NVIDIA, the build and install of each package, the check, troubleshooting and uninstall. Four packages are on the AUR as recipes: `maxine-vfx-sdk-local`, `maxine-ar-sdk-local`, `maxine-afx-sdk-local` and `nvidia-optical-flow-sdk-local`. `nvidia-tensorrt-sdk-local` is not ([docs/aur.md](docs/aur.md)).

## Requirements and limits

- An NVIDIA RTX GPU (Turing or newer), the NVIDIA driver 570.26 or newer, and Arch Linux or an Arch-based distribution.
- A free NVIDIA Developer Program account for the Maxine and Optical Flow SDKs. For Maxine you also need the NGC (NVIDIA GPU Cloud) command line tool and a personal API key. TensorRT needs no account.
- It is not an NVIDIA product, and NVIDIA does not support it.
- Each package is for your own machine only. Never share or upload it ([Licences and caveats](#licences-and-caveats)).
- `nvidia-tensorrt-sdk-local` conflicts with the AUR `tensorrt` package. Its package also adds a loader entry (`/etc/ld.so.conf.d/nvidia-tensorrt-sdk.conf`) and links its builder libraries into `/usr/lib`, so that every program finds TensorRT without the environment file. See [docs/tensorrt.md](docs/tensorrt.md).
- The Optical Flow recipe was written against NVIDIA's documented layout of the SDK, not a real archive. See [docs/optical-flow.md](docs/optical-flow.md).

## What is included

| Directory | Package | Contents |
|---|---|---|
| [`maxine-vfx/`](maxine-vfx/) | `maxine-vfx-sdk-local` | NVIDIA Maxine Video Effects SDK 1.3.0.0: the features and GPU architectures you download and select. The download helper fetches AI green screen, background blur and video noise removal by default |
| [`maxine-ar/`](maxine-ar/) | `maxine-ar-sdk-local` | NVIDIA Maxine AR SDK 1.2.0.0: eye contact (gaze redirection), face box detection, facial landmarks, face expressions and the other documented AR features. The download helper fetches eye contact with the two features it depends on by default |
| [`maxine-afx/`](maxine-afx/) | `maxine-afx-sdk-local` | NVIDIA Maxine Audio Effects SDK 3.0.0 (package version 3.0.0.12): noise removal, room echo removal, both together and Studio Voice, at the sample rates you download. The download helper fetches those four at 48 kHz by default |
| [`nvidia-optical-flow/`](nvidia-optical-flow/) | `nvidia-optical-flow-sdk-local` | NVIDIA Optical Flow SDK 5.0.7 from your own `optical_flow_sdk_5.0.7.zip`: the headers, the FRUC library when your download has it, and the samples and NvOFTracker as source, under `/opt/nvidia/optical-flow`. The runtime library comes from the NVIDIA driver. Guide: [docs/optical-flow.md](docs/optical-flow.md) |
| [`nvidia-tensorrt/`](nvidia-tensorrt/) | `nvidia-tensorrt-sdk-local` | NVIDIA TensorRT 11.4.0.106 for Linux x86_64 and CUDA 13.4, from the archive that `makepkg` downloads from NVIDIA or that you supply (the ARM build is refused), installed as shipped under `/opt/nvidia/tensorrt`, with a pkg-config file, an environment file and links in `/usr/lib` for the builder-resource libraries that TensorRT opens by file name. It sits beside the AUR's `tensorrt`, which installs into `/usr`, and it provides `tensorrt` too: a package that depends on `tensorrt` finds TensorRT through the environment file or pkg-config, not under `/usr`. Guide: [docs/tensorrt.md](docs/tensorrt.md) |

The three Maxine packages follow the same pattern. You download the SDK from NGC, you choose the features and GPU architectures, and `makepkg` builds one package from your download. Each installs under its own `/opt/nvidia/maxine/` directory with its own environment file.

The Optical Flow SDK and TensorRT packages are simpler. Each is one file, obtained after you accept NVIDIA's licence, and there are no features or architectures to choose. You download the Optical Flow file in a browser. For TensorRT, `makepkg` can download the file from NVIDIA, or you can download it in a browser.

`scripts/setup.sh` also lists a Maxine Early Access entry. It is a placeholder that only prints how to request access.

## Documentation

| Page | Contents |
|---|---|
| [INSTALL.md](INSTALL.md) | Prerequisites, downloads, the guided script, install by hand, check, troubleshooting, uninstall |
| [docs/download.md](docs/download.md) | What is downloaded and from where; downloading the Maxine SDKs from NGC; the credential check; HTTP 402; troubleshooting |
| [docs/usage.md](docs/usage.md) | How a program uses each installed package: environment file, shim, models |
| [docs/gpu-support.md](docs/gpu-support.md) | Supported GPUs, architectures and how to fetch their models |
| [docs/optical-flow.md](docs/optical-flow.md) | The Optical Flow SDK package |
| [docs/tensorrt.md](docs/tensorrt.md) | The TensorRT package |
| [docs/aur.md](docs/aur.md) | The recipes on the AUR: how the AUR copies are made and published |

Each package directory has its own README with the build inputs.

## Repository layout

```
README.md
INSTALL.md                        all installation directions
LICENSE-MIT, LICENSE-APACHE
.gitignore
.githooks/                        pre-commit, pre-merge-commit, pre-push: run the licence guard
scripts/check-no-nvidia.sh        licence guard: refuses NVIDIA files, SDK trees, NGC download directories
scripts/setup.sh                  guided setup: preflight, download detection, configure, build, install, check, undo
scripts/check-ngc.sh              read-only check of your NGC key and of your account's access to the Maxine models
scripts/setup.d/                  one descriptor per SDK for setup.sh (format in scripts/setup.d/README)
scripts/test.sh                   runs every check of this repository
scripts/aur.sh                    makes a recipe's AUR copy: its helpers fetched from a pinned commit of this repository (docs/aur.md)
scripts/tests/                    tests of the guard, of env.sh, of setup.sh, of check-ngc.sh and of a PKGBUILD fixture build
docs/download.md                  what is downloaded, from where and whether it needs a login, for every SDK; and downloading the Maxine SDKs from NGC: the one-command path, the manual steps, sizes, the credential check, access (HTTP 402), troubleshooting
docs/optical-flow.md              the Optical Flow SDK package: browser download, what it installs, environment file, use, check, troubleshooting
docs/tensorrt.md                  the TensorRT package: the download (automatic or in a browser), what it installs, environment file, pkg-config, CMake and RPATH, the AUR's tensorrt, CUDA versions
docs/aur.md                       the recipes on the AUR: how the AUR copies are made and published
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
nvidia-optical-flow/              the Optical Flow SDK package: PKGBUILD, assemble.sh, configure.sh, selection.sh, README.md, tests/ (no download.sh: the zip is downloaded in a browser)
nvidia-tensorrt/                  the TensorRT package: PKGBUILD, source.sh, configure.sh, selection.sh, README.md, tests/ (no download.sh: makepkg downloads the archive, or you supply it)
tools/os-release-shim/            the compatibility shim and its test
tools/maxine-probe/               a small program that checks the SDK loads
```

## Testing

```bash
scripts/test.sh
```

This runs every check in the repository, for all five packages:

- shellcheck over every script;
- the syntax and metadata of each PKGBUILD;
- the fixture tests of each package's `assemble.sh`, `configure.sh` and `download.sh` (the last against a fake `ngc`);
- the `configure.sh` and `selection.conf` tests of the Optical Flow and TensorRT packages on tiny fake zips, archives and trees;
- a `makepkg` build of each PKGBUILD against fake SDK files;
- the AUR copies `scripts/aur.sh` makes, and a build of one from a directory holding only its PKGBUILD;
- the shim test;
- the tests of `scripts/setup.sh` and `scripts/check-ngc.sh`, with stubbed `pacman`, `sudo`, `makepkg`, `ngc`, `curl` and `nvidia-smi`, so nothing is installed and nothing reaches NGC;
- the licence guard and its hooks, then the guard over the whole tree.

It needs `shellcheck` (a tool that checks shell scripts for mistakes). A GPU is not required, it uses no network and it needs no NVIDIA download. The `makepkg` fixture builds, and the Optical Flow and TensorRT `configure.sh` tests where they need `bsdtar`, are skipped when `makepkg`, `fakeroot` or `bsdtar` is missing.

To add an SDK to `scripts/setup.sh`, see [Adding an SDK to the script](INSTALL.md#adding-an-sdk-to-the-script).

## Licences and caveats

### Licence and personal use

Read this before using anything here.

- **You accept NVIDIA's licence, and you download the SDK yourself**, with your own account where NVIDIA asks for one: from NVIDIA NGC for the Maxine SDKs, and in a browser from NVIDIA's developer site for the Optical Flow SDK. TensorRT is also served by NVIDIA without a login, and `makepkg` can download it for you under NVIDIA's TensorRT Software License Agreement, or you can download it in a browser. Apart from that download, the recipes only automate what happens after your download.
- **This repository holds only recipes**: PKGBUILDs, scripts, documentation and the source of a small compatibility shim. **Nothing from NVIDIA is committed**: no SDK files, libraries, headers, models (`*.trtpkg`), tarballs or licence PDFs. It does not redistribute anything from NVIDIA. The guard `scripts/check-no-nvidia.sh` enforces this: it refuses NVIDIA's file types (libraries, models and their `*.trtpkg.*` checksum sidecars, archives, PDFs, SDK headers, including those of the Optical Flow SDK and TensorRT), an unpacked SDK tree (`VideoFX/`, `ARSDK/`, `Audio_Effects_SDK/`, `Optical_Flow_SDK_*/`, `TensorRT-*/`), an NGC download directory, an SDK's top-level names (`lib/`, `include/`, `features/`, `external/`, `share/`, `samples/`, `licenses/`, `nvafx/`, `bin/`, `docs/`, `version.h`, `Changelog.txt`) placed directly inside a recipe directory (and the matching top-level names of the Optical Flow SDK and of the TensorRT archive inside their recipe directories), and file content that carries an NVIDIA marker. Enable its hooks in your clone with:

  ```bash
  git config core.hooksPath .githooks
  ```

  The hooks are `pre-commit`, `pre-merge-commit` and `pre-push`. `pre-push` checks the commits being pushed with the guard's `--range` mode. `git commit --no-verify` bypasses them (as does `git push --no-verify` for `pre-push`), so the guard is a safety net and not an access control. `scripts/check-no-nvidia.sh --all` checks the working tree, not the history: a file committed earlier stays in the history until you rewrite it.

- **The built package contains NVIDIA software and is for your own machine only.** Never upload it to a package repository, to the AUR as a binary, to a release page, or share it in any other way. The NVIDIA Software License Agreement for the Maxine SDKs (8.5) forbids redistribution, including in "publicly accessible software repositories". The Optical Flow SDK is under the NVIDIA DesignWorks SDK License, which does not allow redistributing the SDK stand-alone, and TensorRT is under the TensorRT Software License Agreement, which allows installing and using it internally and does not allow redistributing it, except its runtime libraries inside an application that adds material functionality. The TensorRT package is not that, and it ships a short note on these terms in `/usr/share/licenses/nvidia-tensorrt-sdk-local/TERMS.txt`. Nothing built here is that: read the licence you accept for each SDK.
- **Do not publish benchmark results** (the Maxine licence, 8.9), and do not reverse engineer the software.
- **NVIDIA does not support this configuration.** Arch Linux and other distributions the SDK does not list, packages built by a third-party recipe, and client-side use of an SDK documented for servers, are outside what NVIDIA supports. Expect no vendor support.
- This is not legal advice. Read the licence you accept.

### Licence of this repository's content

MIT OR Apache-2.0, at your option: see [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE). This covers only the content of this repository. It does not apply to any NVIDIA software you download or to a package built from it.
