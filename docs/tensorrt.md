# The TensorRT package

TensorRT is NVIDIA's library for running AI models fast on its GPUs. This page is for the person who builds `nvidia-tensorrt-sdk-local` and for programs that use it. You build the package from NVIDIA TensorRT 11.4.0.106 for CUDA 13.4 (CUDA is NVIDIA's GPU computing platform). The build downloads the archive from NVIDIA, or uses a copy you already have. It installs TensorRT, as shipped, under `/opt/nvidia/tensorrt`, isolated from the system: for example so that an ONNX Runtime build can use the TensorRT execution provider. Arch's `cuda` package provides the CUDA 13 runtime it runs on.

The recipe's own reference, with every build input, is [../nvidia-tensorrt/README.md](../nvidia-tensorrt/README.md). `scripts/setup.sh --sdk trt` runs the steps below for you. It uses the archive in `~/Downloads` when there is one; when there is none, `makepkg` downloads it from NVIDIA during the build (see [Download](#download)). See [setup.md](setup.md).

The package contains NVIDIA software and is for your own machine only; see the "Licence and personal use" section of the [README](../README.md) and [Licence notes](#licence-notes) below. NVIDIA does not support this configuration (Arch Linux, a package built by a third-party recipe).

## Quick start

You need an NVIDIA RTX GPU, an Arch-based distribution, the NVIDIA driver, the `cuda` package (version 13.4 or newer, below 14) and, for the browser download, a free NVIDIA Developer Program account. TensorRT needs no NGC account and no API key, and the automatic download needs no login.

1. **Optional: put the file in `~/Downloads`.** If you do not, the script has `makepkg` download it from NVIDIA during the build (see [Download](#download)), after it names the licence: read the TensorRT Software License Agreement before you build, because by building you accept it. To download it in a browser instead, which needs your NVIDIA login and your acceptance of the licence, open <https://developer.nvidia.com/tensorrt/download>, log in, accept the licence and download `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst` into `~/Downloads`. Take the Linux x86_64 build for CUDA 13.4, not the ARM build and not the `cuda-12.9` build.
2. **Optional: install `cuda` first.** It is a large download, and `pacman -U` also pulls it in from Arch's repositories when it is missing:

   ```bash
   sudo pacman -S --needed cuda
   ```

3. **Look first.** This is read-only:

   ```bash
   scripts/setup.sh --sdk trt --dry-run
   ```

   *Success:* the output ends with `Dry run: nothing was asked, run or written.` If it finds no archive, it says that `makepkg` will download it from NVIDIA, and names the licence.
4. **Build and install.** The script asks before each step and runs `sudo pacman -U` only after you answer `y`:

   ```bash
   scripts/setup.sh --sdk trt
   ```

   *Success:* section `7. Check` shows `ok` for `trt`, and the exit status is 0.
5. **Check by hand** (see [Check the installation](#check-the-installation)): both version lines must read `11.4.0.106`.

If it fails, see [Troubleshooting](#troubleshooting). The two usual causes are the wrong archive (ARM, or `cuda-12.9`) and a source that is named but missing: a `selection.conf` left by an earlier run, or `--src-trt PATH` or `NVIDIA_TRT_SRC` pointing at a file that is gone. The script then stops for TensorRT and deletes nothing. Fix the path or remove the `selection.conf`, and the script can let `makepkg` download the archive.

## Download

There are two ways to get the archive. Both give the same file, and the recipe checks it against the same SHA-256.

- **Automatic.** `makepkg` in `nvidia-tensorrt/` downloads the file from NVIDIA when there is no copy to use, and `scripts/setup.sh --sdk trt` does the same when it finds none in `~/Downloads`. NVIDIA serves it publicly, without a login, under its TensorRT Software License Agreement. The download is about 3.7 GB (3,725,547,403 bytes). makepkg keeps the copy in the recipe directory, or in `SRCDEST` if you set it, and reuses it on the next build. The archive is not stored in this repository, which is why the recipe downloads it from NVIDIA instead.
- **Yourself.** NVIDIA's download page needs a Developer Program login and your acceptance of the licence. Use it when you want the file before the build, or when the build machine has no internet access.

The guided script, `scripts/setup.sh --sdk trt`, looks for the file in `~/Downloads` (or the place you give with `--src-trt`). When it is missing, the script does not stop: it prints that `makepkg` will download the file from NVIDIA when it builds, names the licence and points to the steps below. In that case it writes no `selection.conf`, and `makepkg` runs without a source.

To download it yourself:

1. Sign in to the NVIDIA Developer Program, or create an account, at <https://developer.nvidia.com/tensorrt/download>.
2. Read and accept the TensorRT Software License Agreement (<https://docs.nvidia.com/deeplearning/tensorrt/latest/reference/sla.html>), then select "Accept & Download".
3. Choose TensorRT 11.4.0.106, Linux x86_64, the TAR package for CUDA 13.4. The file is `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst`, with SHA-256 `c67c87674cbe7b2337d1c30cb16d48686ab79ecb11bf08cb764b71f4f2bb711b` (the checksum published in the AUR's `tensorrt` recipe).
4. Save it in `~/Downloads` (where `scripts/setup.sh` looks), or anywhere else, and pass its location with `--src-trt PATH` or `NVIDIA_TRT_SRC`. Keep only one `TensorRT-*.tar.*` archive in the directory you name. When the build looks in `~/Downloads` on its own, it uses only the file with the exact name above, so another TensorRT archive there cannot be used by mistake.

Download the right file:

- **The `cuda-13.4` file, not the `cuda-12.9` build of the same version.** The package depends on CUDA 13.4. A `cuda-12.9` archive is refused with "not the archive this recipe packages".
- **The Linux x86_64 file, not the ARM (aarch64) one.** NVIDIA has so far published TensorRT 11.4.1 for ARM only, so a newer version number on the download page is not necessarily an x86_64 build. This recipe packages 11.4.0.106. The recipe and `setup.sh` refuse an ARM archive by its file name, by its contents (aarch64 Python wheels, or a `targets/aarch64-linux-gnu` or `targets/sbsa-linux` directory) and, for an extracted tree, by the machine type of `libnvinfer`.
- If the directory you name holds one x86_64 archive and also ARM ones, the x86_64 one is used and the ARM ones are reported as skipped. If it holds two x86_64 archives, name the one you mean.

The recipe pins that SHA-256 and refuses another file, so a damaged or different download stops the build with a message naming both hashes. Then build and install. Either use the guided script, which prints each command and asks before running it (it uses the file in `~/Downloads`, or the place you give with `--src-trt`, and otherwise lets `makepkg` download it):

```bash
scripts/setup.sh --sdk trt
```

or do it by hand:

```bash
cd nvidia-tensorrt
./configure.sh --src ~/Downloads --write   # optional: checks the archive offline, saves the choice
PKGEXT=.pkg.tar makepkg -f                 # downloads the archive when no source is found
sudo pacman -U nvidia-tensorrt-sdk-local-11.4.0.106-2-x86_64.pkg.tar
```

The build takes the archive from the first of these that applies:

1. `NVIDIA_TRT_SRC` in the environment;
2. `NVIDIA_TRT_SRC` in `selection.conf`, which `configure.sh --write` saves;
3. the file `~/Downloads/TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst`, if it exists;
4. otherwise, the download. `SRCDEST=~/Downloads makepkg -f` saves the download in `~/Downloads`, or reuses a copy already there.

The package is several GiB (a GiB is about a billion bytes), so `PKGEXT=.pkg.tar` skips a slow compression. The build needs free space for the archive (about 3.7 GB when downloaded), its copy in `src/`, the extracted tree, the copy in `pkg/` and the package. The source can also be an extracted tree, which has no checksum and only has its version checked.

**A future release without a published checksum.** The `_trt_sha256=` line of the PKGBUILD can be left empty when a release's checksum is not published anywhere you can verify it. The archive must then carry the recipe's `_trt_archive` name, and nothing pins its content: `configure.sh --write` records the SHA-256 of the archive it saw, the PKGBUILD verifies the archive it builds from against that recorded sum, and otherwise prints the sum as "not pinned" for you to compare with NVIDIA's download page. The release in this recipe is pinned.

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/tensorrt/` | The TensorRT tree as shipped: `include/`, `lib/`, `bin/` (`trtexec`), `python/` (the wheels), `samples/`, `data/`, `doc/`, and `targets/x86_64-linux-gnu/` when the archive has it |
| `/opt/nvidia/tensorrt/lib/pkgconfig/nvidia-tensorrt.pc` | A pkg-config file generated by the build |
| `/etc/ld.so.conf.d/nvidia-tensorrt-sdk.conf` | Puts the library directory on the system library path, for the libraries found by soname |
| `/usr/lib/libnvinfer_builder_resource_*.so.11.4.0` | Symbolic links, one for each library in the TensorRT library directory whose soname starts with `do_not_link_against_` (16 in this release, the `_win_` variants included), each to the same file there. `libnvinfer` opens these by file name |
| `/usr/share/nvidia-tensorrt/nvidia-tensorrt.env` | The environment file described below: `TENSORRT_HOME`, the pkg-config directory and the root and include paths, for tooling and builds |
| `/usr/share/licenses/nvidia-tensorrt-sdk-local/TERMS.txt` | A short note on the licence terms, next to links to TensorRT's own licence files |

One file goes into `/etc`: `/etc/ld.so.conf.d/nvidia-tensorrt-sdk.conf`, which adds `/opt/nvidia/tensorrt/lib` (`targets/x86_64-linux-gnu/lib` when the tree has no `lib/`) to the system library path. That entry makes the libraries that are found by soname visible to every program, `libnvinfer.so.11`, the plugins and the parsers among them. It does not reach the builder-resource libraries. NVIDIA gives each of them a deliberate soname of the form `do_not_link_against_` followed by its file name, so `ldconfig` caches it only under that name. `libnvinfer` has no RUNPATH and opens these libraries with `dlopen()` by file name, and the loader finds a file name only through `LD_LIBRARY_PATH`, a RUNPATH of the library that calls `dlopen()`, or the default directories such as `/usr/lib`. The package therefore also links them into `/usr/lib`. At package time it finds, with `readelf`, every library in the TensorRT library directory whose soname starts with `do_not_link_against_`, and creates a symbolic link to each one in `/usr/lib` under its own name. The list is read from the files rather than written into the recipe, so a later release with a different set of builder resources needs no change to it. The `_win_` variants are linked as well, because `libnvinfer` refers to the same name prefix and the package does not try to decide which of them Linux loads. NVIDIA's files are not changed: the links leave the shipped libraries as they are, where editing their soname or adding a RUNPATH would have modified them. A program that finds `libnvinfer.so.11` without an RPATH or RUNPATH needs the entry, or `LD_LIBRARY_PATH`, to load it. pacman runs `ldconfig` for the file on install, upgrade and removal through glibc's own hook, so the package needs no install script. Nothing goes into `/usr/include`, the only files under `/usr/lib` are these links, and there is no `profile.d` script. `trtexec` is not on `PATH` (run `/opt/nvidia/tensorrt/bin/trtexec`), and the Python wheels are not installed into `site-packages`: install the wheel of your Python version into a virtual environment yourself, with `pip install /opt/nvidia/tensorrt/python/tensorrt-<version>-cp<NN>-...whl`.

The package depends on `cuda>=13.4`, `cuda<14` and `nvidia-utils`. It does not depend on cuDNN, which TensorRT has not required since version 10; install Arch's `cudnn` yourself if something you run needs it.

## The environment file

`/usr/share/nvidia-tensorrt/nvidia-tensorrt.env` has plain `KEY=value` lines, so it works as a systemd `EnvironmentFile=` and with `set -a; . file; set +a`.

| Key | Value |
|---|---|
| `NVIDIA_TRT_ROOT`, `TENSORRT_HOME` | `/opt/nvidia/tensorrt` |
| `NVIDIA_TRT_INCLUDE_DIR` | `/opt/nvidia/tensorrt/include` |
| `NVIDIA_TRT_LIBRARY_PATH`, `LD_LIBRARY_PATH` | `/opt/nvidia/tensorrt/lib` |
| `NVIDIA_TRT_PKG_CONFIG_PATH` | `/opt/nvidia/tensorrt/lib/pkgconfig`, the directory to add to `PKG_CONFIG_PATH` |
| `NVIDIA_TRT_VERSION` | `11.4.0.106` |

When the archive has no `lib/`, the library and pkg-config paths are under `targets/x86_64-linux-gnu/lib`. Load the file for one build or one program, never from a login profile.

A program that loads this file together with another SDK's must not rely on the `LD_LIBRARY_PATH` lines: each file sets one, and the last file loaded wins. Build the value from the `NVIDIA_*_LIBRARY_PATH` and `MAXINE_*_LIBRARY_PATH` keys instead. [usage.md](usage.md#other-packages-optical-flow-and-tensorrt) shows how.

## Using it from a program

**pkg-config.**

```bash
PKG_CONFIG_PATH=/opt/nvidia/tensorrt/lib/pkgconfig pkg-config --cflags --libs nvidia-tensorrt
```

prints the include paths, the library path with an RPATH, `-lnvinfer -lnvinfer_plugin -lnvonnxparser` and the CUDA runtime. TensorRT's headers include the CUDA runtime's, so the file has `Requires: cudart`, which Arch's `cuda` package provides.

**CMake and ONNX Runtime.** Point the build at the root. ONNX Runtime's build script takes `--use_tensorrt --tensorrt_home /opt/nvidia/tensorrt`, or the CMake option `-Donnxruntime_TENSORRT_HOME=/opt/nvidia/tensorrt`. A CMake project that searches for TensorRT finds it with `-DCMAKE_PREFIX_PATH=/opt/nvidia/tensorrt`, or from `TENSORRT_HOME` for the projects that read it. A package that builds against it declares `depends=('nvidia-tensorrt-sdk')`.

**RPATH rather than LD_LIBRARY_PATH.** Link a program or library with an RPATH (or RUNPATH) of `/opt/nvidia/tensorrt/lib` so that it finds TensorRT on its own: with CMake, `-DCMAKE_INSTALL_RPATH=/opt/nvidia/tensorrt/lib` or `-DCMAKE_BUILD_RPATH=...`; the pkg-config file adds `-Wl,-rpath` itself. The system loader entry already makes the libraries visible to every program, so `LD_LIBRARY_PATH` from the environment file is not needed to run one. Setting `LD_LIBRARY_PATH` globally would put these libraries in front of those of every program, including programs that bundle another TensorRT (the Maxine SDKs bundle TensorRT 10). Keep it to the one program that needs it.

## Relation to the AUR's tensorrt package

The AUR `tensorrt` package installs the same NVIDIA archive into `/usr` (`/usr/include`, `/usr/lib`). This package installs it into `/opt/nvidia/tensorrt` and conflicts with it. The two would otherwise both be on the system library path: `ldconfig` resolves each soname (`libnvinfer.so.11`, and so on) to one copy, in directory order, and `libnvinfer` then loads its sibling libraries by exact versioned name from that cache, so with two different TensorRT 11 releases installed a process could mix the libraries of both. Both packages also put files with the same names in `/usr/lib` (the AUR's own builder-resource libraries and this package's links to them), so pacman offers to replace one package with the other; install only one of them. This package provides `nvidia-tensorrt-sdk` for the packages that want the isolated copy, and `tensorrt` (version 11.4.0.106), so a package that depends on `tensorrt` can be satisfied by it. Such a package expects the `/usr` paths, which this package does not provide apart from the links in `/usr/lib`, so it must find TensorRT through the environment file or pkg-config. A program built against one finds only that one. This package does not provide `python-tensorrt`, because it installs no Python module.

## Versions and CUDA

TensorRT is built for one CUDA major version. This recipe packages TensorRT 11.4.0.106 for CUDA 13.4, and the package depends on `cuda>=13.4` and `cuda<14`: the CUDA 13 runtime it loads. The version in `include/NvInferVersion.h` must be exactly `11.4.0.106`, or `configure.sh` and the build stop and name both versions.

When Arch's `cuda` moves to a new major version, the `cuda<14` bound makes the upgrade conflict with this package, as intended: a TensorRT built for CUDA 13 does not run on CUDA 14. Do not relax the bound. Instead, once NVIDIA publishes a TensorRT for the new CUDA, download it, update the recipe (the `pkgver`, `_cudaver`, `_trt_archive` and `_trt_sha256` of the PKGBUILD, a check that `_trt_url` still points at NVIDIA's file, and the `download_file` of `scripts/setup.d/50-trt.conf`) to match, and rebuild; until then, either hold `cuda` back or remove this package before the upgrade. Within CUDA 13, a newer minor release of Arch's `cuda` than 13.4 satisfies the bounds.

## Check the installation

```bash
pacman -Ql nvidia-tensorrt-sdk-local | head
grep '^NVIDIA_TRT_VERSION' /usr/share/nvidia-tensorrt/nvidia-tensorrt.env
PKG_CONFIG_PATH=/opt/nvidia/tensorrt/lib/pkgconfig pkg-config --modversion nvidia-tensorrt
(set -a; . /usr/share/nvidia-tensorrt/nvidia-tensorrt.env; set +a
 ldd /opt/nvidia/tensorrt/lib/libnvinfer.so | grep 'not found')
```

The version lines must read `11.4.0.106`. With the environment file applied, the `ldd` command prints nothing; a missing CUDA library means Arch's `cuda` is not installed or is not a CUDA 13 release. `scripts/setup.sh` makes the same checks after an install and prints one line for the SDK.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| The build stops on a SHA-256 mismatch | The file is incomplete, damaged or another archive. If makepkg downloaded it, delete the copy in the recipe directory or in `SRCDEST` and build again. If it is your own file, download it again from the page above |
| makepkg stops while it downloads TensorRT | The network failed, or NVIDIA's server did not answer. Build again later, or download the file in a browser and put it in `~/Downloads` |
| `scripts/setup.sh --sdk trt` stops with `makepkg would stop on it instead of downloading`, or with `selection.conf is not valid` | A source is named but missing, or the `selection.conf` is not valid. Fix the path, or remove `selection.conf` (the script never deletes it) so that `makepkg` downloads the archive. See [setup.md](setup.md#2-your-download) |
| The build stops on another TensorRT version | The source holds a version other than 11.4.0.106. Download the archive named above |
| `configure.sh` finds no archive and no tree | The directory holds no `TensorRT-*.tar.*` and no tree with `include/NvInferVersion.h`. Pass the file with `--src` |
| `configure.sh` finds two archives | Name the one you mean, or move the other away |
| `this is the ARM (aarch64) build of TensorRT; download the Linux x86_64 one: <file> from https://developer.nvidia.com/tensorrt/download` | The archive (or tree) is the ARM build: its name says `aarch64` or `sbsa`, its contents hold aarch64 wheels or a `targets/aarch64-linux-gnu` or `targets/sbsa-linux` directory, or its `libnvinfer` is an aarch64 ELF file. Download the x86_64 file the message names. When the ARM version is newer than the recipe's, the message adds that NVIDIA publishes it for ARM only and which x86_64 version to take |
| `<file> is not the archive this recipe packages: expected TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-...` | A different x86_64 archive, for example the `cuda-12.9` build of the same version. The package depends on CUDA 13.4: download the `cuda-13.4` file |
| `pacman -U` stops on `cuda` | The installed CUDA is outside `13.4` to `14`. See [Versions and CUDA](#versions-and-cuda) |
| A program cannot find `libnvinfer.so` | It was not linked with an RPATH and the environment file is not loaded for it. Link with the RPATH, or load the file for that program only |
| `pkg-config` does not find `nvidia-tensorrt` | `PKG_CONFIG_PATH` lacks `/opt/nvidia/tensorrt/lib/pkgconfig` (`NVIDIA_TRT_PKG_CONFIG_PATH`) |
| A program loads the Maxine SDK's TensorRT instead | `LD_LIBRARY_PATH` was set globally or by the wrong file. Use RPATH, and build the path explicitly |
| `createInferBuilder: Unable to load library: libnvinfer_builder_resource_sm120.so.11.4.0: cannot open shared object file` (for example from ONNX Runtime's TensorRT provider, which then aborts; the architecture in the name depends on your GPU) | The builder-resource library is not reachable by its file name: this package links those libraries into `/usr/lib`, and the links are missing in an earlier build of the package. Rebuild and reinstall the package. Check with `ls -l /usr/lib/libnvinfer_builder_resource_*`, which should list links to `/opt/nvidia/tensorrt/lib`. If pacman refuses the install because of a file in `/usr/lib`, see [Relation to the AUR's tensorrt package](#relation-to-the-aurs-tensorrt-package) |

## Licence notes

- NVIDIA serves the TensorRT archive to you under its TensorRT Software License Agreement, whether makepkg downloads it or you do. Read it.
- The agreement allows installing and using TensorRT internally and does not allow redistributing it, except its runtime libraries (the `.so` files), and only inside an application that adds material functionality (supplement sections 2 and 1.2). This package is not that: it is for your own machine only. Never upload it to a package repository, to the AUR as a binary or to a release page, and never share it. The package ships `/usr/share/licenses/nvidia-tensorrt-sdk-local/TERMS.txt` with this summary.
- This repository holds only the recipe; no NVIDIA file is committed, the archive is not redistributed, and `scripts/check-no-nvidia.sh` refuses the archive, TensorRT's headers and an unpacked TensorRT tree.
- This is not legal advice.
