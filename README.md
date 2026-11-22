# omarchy-nvidia-sdks

Use NVIDIA's RTX webcam and microphone effects on Linux. These are Arch Linux recipes that turn the NVIDIA Maxine, Optical Flow and TensorRT SDKs, which you download from NVIDIA yourself, into local pacman packages for your own machine. They are for Arch Linux and Omarchy users with an NVIDIA GPU who want these SDKs as pacman packages.

SDK stands for software development kit: the libraries, headers and AI models a program uses. Maxine is NVIDIA's family of AI video and audio effects. The packages were made for [omarchy-broadcast](https://github.com/rsd/omarchy-broadcast), a camera and microphone daemon for Linux that uses these SDKs on RTX GPUs. They do not depend on it.

## What you get

Five packages, one for each SDK:

- **Maxine Video Effects** (VFX, `maxine-vfx-sdk-local`, SDK 1.3.0.0): AI green screen, background blur, video noise removal, relighting and video super resolution. You choose the features and GPU architectures.
- **Maxine AR** (`maxine-ar-sdk-local`, SDK 1.2.0.0): eye contact and face detection. AR stands for augmented reality.
- **Maxine Audio Effects** (AFX, `maxine-afx-sdk-local`, SDK 3.0.0, package version 3.0.0.12): noise removal, room echo removal and Studio Voice, at the sample rates you download.
- **NVIDIA Optical Flow SDK** (`nvidia-optical-flow-sdk-local`, SDK 5.0.7): the headers, the FRUC (frame rate up-conversion) library when your download has it, and the samples and the tracker as source.
- **NVIDIA TensorRT** (`nvidia-tensorrt-sdk-local`, 11.4.0.106 for CUDA 13.4): NVIDIA's library for running AI models fast on its GPUs. CUDA is NVIDIA's GPU computing platform.

The Maxine packages also install an os-release shim, a small library that lets the SDK accept a distribution NVIDIA does not list. It stays inactive until a program preloads it. See [tools/os-release-shim/README.md](tools/os-release-shim/README.md).

The effects need an NVIDIA RTX GPU: Turing (RTX 20 series) or newer, with Tensor cores (the AI hardware of RTX cards). See [docs/gpu-support.md](docs/gpu-support.md).

To use the effects in a webcam or microphone, see the omarchy-broadcast guides for [Maxine video effects](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/maxine.md) and the [microphone](https://github.com/rsd/omarchy-broadcast/blob/main/docs/setup/microphone.md). Its Maxine modules depend on these packages: the `omarchy-broadcast-maxine-vfx`, `-ar` and `-afx` packages depend on `maxine-vfx-sdk-local`, `maxine-ar-sdk-local` and `maxine-afx-sdk-local`. [omarchy-onnxruntime](https://github.com/rsd/omarchy-onnxruntime) uses `nvidia-tensorrt-sdk-local` for its TensorRT engine.

## Why use these packages

NVIDIA Broadcast offers RTX effects for a webcam and a microphone: background blur, removal and replacement, video noise removal, eye contact, and microphone noise and room echo removal. NVIDIA ships no Broadcast application for Linux, but it does publish the SDKs behind these effects. They are awkward to install and share on a Linux system. These packages fix that:

- **Nothing is redistributed.** You get each SDK from NVIDIA under NVIDIA's licence, with your own account where NVIDIA asks for one. The repository holds only recipes.
- **One guided script.** `scripts/setup.sh` checks your machine, finds your download, builds the package, installs it and checks the result. It asks before every step that changes anything, and it prints each command first.
- **Isolated installs.** Each package installs under `/opt/nvidia/` with an environment file that a program loads for itself. The Maxine and Optical Flow packages set nothing globally, so you can install them together.
- **Reusable.** Any project on Arch Linux or an Arch-based distribution that needs the Maxine, Optical Flow or TensorRT headers and libraries can depend on these packages instead of carrying its own copy of an SDK. [docs/usage.md](docs/usage.md) explains how a program finds the headers, libraries and models.
- **Your choice of features and GPUs.** You pick the effects and GPU architectures, and the package holds only those.

## Install

Clone the repository and look first. The dry run changes nothing. It checks your machine and prints every command the real run would use:

```bash
git clone https://github.com/rsd/omarchy-nvidia-sdks.git
cd omarchy-nvidia-sdks
scripts/setup.sh --dry-run
```

Then run the setup for one SDK and follow the prompts. Pick the key from this table:

| SDK | Key | You download it from |
|---|---|---|
| Maxine Video Effects | `vfx` | NVIDIA NGC (NVIDIA GPU Cloud) |
| Maxine AR | `ar` | NGC |
| Maxine Audio Effects | `afx` | NGC |
| Optical Flow | `of` | NVIDIA's developer site, in a browser |
| TensorRT | `trt` | NVIDIA, automatically |

```bash
scripts/setup.sh --sdk vfx
```

For a Maxine or Optical Flow SDK, the script tells you what to download first. It builds the package, asks before it runs `sudo pacman -U` and checks the result. Check it yourself with the package of the SDK you chose, for example:

```bash
pacman -Q maxine-vfx-sdk-local
```

[INSTALL.md](INSTALL.md) has the prerequisites, the downloads from NVIDIA, the check, troubleshooting and uninstall. Four packages are also on the AUR (the Arch User Repository) as recipes: `maxine-vfx-sdk-local`, `maxine-ar-sdk-local`, `maxine-afx-sdk-local` and `nvidia-optical-flow-sdk-local`. `nvidia-tensorrt-sdk-local` is not ([docs/aur.md](docs/aur.md)).

## Limits

- **Arch Linux and Arch-based distributions only, on x86_64.** The recipes build pacman packages, and TensorRT for ARM is refused. On another distribution, install the SDKs with NVIDIA's own instructions: NGC for Maxine, developer.nvidia.com for Optical Flow and TensorRT.
- **NVIDIA RTX GPU, Turing (RTX 20) or newer.** Pascal and older, Volta, AMD and Intel GPUs are out ([docs/gpu-support.md](docs/gpu-support.md)).
- **You download each SDK from NVIDIA.** Each package is for your own machine only. Never share or upload it ([Licences and caveats](#licences-and-caveats)).
- **NVIDIA does not support this setup:** Arch, the os-release shim and client-side use of an SDK ([Licences and caveats](#licences-and-caveats)).
- **The Optical Flow recipe was written against NVIDIA's documented layout of the SDK, not a real archive.** See [docs/optical-flow.md](docs/optical-flow.md).
- **`nvidia-tensorrt-sdk-local` conflicts with the AUR `tensorrt` package.** Its package also adds a loader entry (`/etc/ld.so.conf.d/nvidia-tensorrt-sdk.conf`) and links its builder libraries into `/usr/lib`, so that every program finds TensorRT without the environment file. See [docs/tensorrt.md](docs/tensorrt.md).

The requirements (GPU, driver, accounts, disk space) are in [INSTALL.md](INSTALL.md#before-you-start).

## Documentation

| Page | Contents |
|---|---|
| [INSTALL.md](INSTALL.md) | Prerequisites, downloads, the guided script, check, troubleshooting, uninstall |
| [docs/download.md](docs/download.md) | What is downloaded and from where; downloading the Maxine SDKs from NGC; the credential check; HTTP 402; troubleshooting |
| [docs/usage.md](docs/usage.md) | How a program uses each installed package: environment file, shim, models |
| [docs/gpu-support.md](docs/gpu-support.md) | Supported GPUs, architectures and how to fetch their models |
| [docs/optical-flow.md](docs/optical-flow.md) | The Optical Flow SDK package |
| [docs/tensorrt.md](docs/tensorrt.md) | The TensorRT package |
| [docs/setup-script.md](docs/setup-script.md) | How `scripts/setup.sh` works, its options and variables, the key handling, and how to add an SDK to it |
| [docs/aur.md](docs/aur.md) | The recipes on the AUR: how the AUR copies are made and published |
| [tools/os-release-shim/README.md](tools/os-release-shim/README.md) | The os-release shim |
| [tools/maxine-probe/README.md](tools/maxine-probe/README.md) | A small program that checks that an installed Maxine SDK loads |

Each package directory has its own README with the build inputs.

## Maintainers

The repository layout, the tests and the licence guard with its git hooks are in [docs/maintainers.md](docs/maintainers.md).

## Licences and caveats

### Licence and personal use

Read this before using anything here.

- **You accept NVIDIA's licence, and you download the SDK yourself**, with your own account where NVIDIA asks for one: from NVIDIA NGC for the Maxine SDKs, and in a browser from NVIDIA's developer site for the Optical Flow SDK. TensorRT is also served by NVIDIA without a login, and `makepkg` can download it for you under NVIDIA's TensorRT Software License Agreement, or you can download it in a browser. Apart from that download, the recipes only automate what happens after your download.
- **This repository holds only recipes**: PKGBUILDs, scripts, documentation and the source of a small compatibility shim. **Nothing from NVIDIA is committed**: no SDK files, libraries, headers, models (`*.trtpkg`), tarballs or licence PDFs. It does not redistribute anything from NVIDIA. The guard `scripts/check-no-nvidia.sh` enforces this. What it refuses, and how to enable its git hooks, is in [docs/maintainers.md](docs/maintainers.md#the-licence-guard-and-its-git-hooks).
- **The built package contains NVIDIA software and is for your own machine only.** Never upload it to a package repository, to the AUR as a binary, to a release page, or share it in any other way. The NVIDIA Software License Agreement for the Maxine SDKs (8.5) forbids redistribution, including in "publicly accessible software repositories". The Optical Flow SDK is under the NVIDIA DesignWorks SDK License, which does not allow redistributing the SDK stand-alone, and TensorRT is under the TensorRT Software License Agreement, which allows installing and using it internally and does not allow redistributing it, except its runtime libraries inside an application that adds material functionality. The TensorRT package is not that, and it ships a short note on these terms in `/usr/share/licenses/nvidia-tensorrt-sdk-local/TERMS.txt`. Nothing built here is that: read the licence you accept for each SDK.
- **Do not publish benchmark results** (the Maxine licence, 8.9), and do not reverse engineer the software.
- **NVIDIA does not support this configuration.** Arch Linux and other distributions the SDK does not list, packages built by a third-party recipe, and client-side use of an SDK documented for servers, are outside what NVIDIA supports. Expect no vendor support.
- This is not legal advice. Read the licence you accept.

### Licence of this repository's content

MIT OR Apache-2.0, at your option: see [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE). This covers only the content of this repository. It does not apply to any NVIDIA software you download or to a package built from it.

### Trademarks

This project is not affiliated with or endorsed by NVIDIA. NVIDIA, Maxine, TensorRT, CUDA, NGC, RTX and NVIDIA Broadcast are trademarks and/or registered trademarks of NVIDIA Corporation.
