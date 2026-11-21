# nvidia-tensorrt: TensorRT as a local package

This recipe builds `nvidia-tensorrt-sdk-local`, a local Arch package of NVIDIA TensorRT 11.4 for CUDA 13.4, installed under `/opt/nvidia/tensorrt`. Several projects on the machine can share it: for example an ONNX Runtime build with the TensorRT execution provider. You need this page to build the package by hand. [`scripts/setup.sh --sdk trt`](../scripts/setup.sh) does the same steps with questions ([../INSTALL.md](../INSTALL.md)).

When you build, makepkg downloads TensorRT from NVIDIA under NVIDIA's licence, unless a copy is already on your machine ([Downloading](#downloading)). This directory holds only the recipe ([`PKGBUILD`](PKGBUILD)). The built package contains NVIDIA software: keep it on your own machine and never share or upload it.

The package version is TensorRT's full version, `11.4.0.106`, read from `include/NvInferVersion.h`. Arch's `cuda` package provides the CUDA 13 runtime it runs on.

## Before you start

- An NVIDIA driver and Arch's `cuda` package, version 13.4 or newer and below 14. `pacman -U` pulls `cuda` in when it is missing.
- Free disk space: the download is about 3.7 GB. The build also needs room for the archive's copy in `src/`, the extracted tree, the copy in `pkg/` and the package. The package is several GiB.
- `makepkg`, `fakeroot` and `bsdtar` ([../INSTALL.md](../INSTALL.md#before-you-start)).
- Optional: your own copy of the archive ([Downloading](#downloading)).

## Build and install

```sh
cd nvidia-tensorrt
./configure.sh --src ~/Downloads --write   # optional: checks your file and saves it
PKGEXT=.pkg.tar makepkg -f                 # downloads the archive when no source is found
sudo pacman -U nvidia-tensorrt-sdk-local-11.4.0.106-2-x86_64.pkg.tar
```

For a download, makepkg checks the file against the pinned SHA-256 before it is used. The same checks then apply as to a file you supplied. To keep the download in `~/Downloads`, run `SRCDEST=~/Downloads makepkg -f`: a copy already there is reused. `PKGEXT=.pkg.tar` skips a slow compression.

`prepare()` prints the source and where it came from, and copies the archive into makepkg's `src/` directory. From then on it reads only that copy:

1. It verifies the SHA-256 again, against the pinned value and against the one `configure.sh --write` recorded.
2. It checks the archive's members.
3. It extracts the archive with `bsdtar` into `src/`, never next to your download.

A download replaced while the build runs therefore cannot pass the checksum and be extracted in its place. An extracted tree is copied, and the copy is what is checked and packaged. Installing is your step: the recipe never runs `pacman` or `sudo`.

## Check that it works

```sh
pacman -Ql nvidia-tensorrt-sdk-local | head
grep '^NVIDIA_TRT_VERSION' /usr/share/nvidia-tensorrt/nvidia-tensorrt.env
PKG_CONFIG_PATH=/opt/nvidia/tensorrt/lib/pkgconfig pkg-config --modversion nvidia-tensorrt
(set -a; . /usr/share/nvidia-tensorrt/nvidia-tensorrt.env; set +a
 ldd /opt/nvidia/tensorrt/lib/libnvinfer.so | grep 'not found')
```

Both version lines must read `11.4.0.106`, and the `ldd` command prints nothing. More checks and troubleshooting are in [../docs/tensorrt.md](../docs/tensorrt.md#check-the-installation).

## Uninstall

```sh
sudo pacman -R nvidia-tensorrt-sdk-local
```

## Downloading

`makepkg` can download TensorRT itself. NVIDIA serves the exact archive that this recipe pins publicly, without a login, under its TensorRT Software License Agreement. It is a normal makepkg source entry. makepkg fetches it into the recipe directory (or into `SRCDEST`, if you set it), checks it against the pinned SHA-256 and keeps it, so a second build does not download it again. The file is about 3.7 GB (3,725,547,403 bytes). This repository does not contain the archive and does not redistribute it.

To download it yourself instead, for example to build on a machine without internet access, or because you already have the file:

1. Open <https://developer.nvidia.com/tensorrt/download> and sign in with an NVIDIA Developer Program account. The automatic download does not need this page.
2. Read and accept the TensorRT Software License Agreement (<https://docs.nvidia.com/deeplearning/tensorrt/latest/reference/sla.html>). It allows internal use and does not allow redistributing TensorRT, except its runtime libraries as part of an application.
3. Choose TensorRT 11.4, Linux x86_64, the TAR package for CUDA 13.4. The file is

   ```
   TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst
   ```

   with SHA-256 `c67c87674cbe7b2337d1c30cb16d48686ab79ecb11bf08cb764b71f4f2bb711b`.

   Not the ARM build, `TensorRT-Enterprise-...-Linux-aarch64-...` (or `-Linux-sbsa-...`). The recipe packages the x86_64 one and refuses the ARM archive or tree, by its file name or by its contents (an `aarch64` Python wheel or `targets/` directory, or, in a tree, an aarch64 `lib/libnvinfer.so`), and names the file to download instead. NVIDIA publishes some releases for ARM only (TensorRT 11.4.1.31, for one, has no x86_64 build). The refusal then says so and names the x86_64 version to download, `11.4.0.106`.

   The `PKGBUILD` pins that SHA-256 in `_trt_sha256`. The line may be left empty for a future release whose checksum nobody publishes. The archive must then carry the name `_trt_archive`, and `configure.sh` and the build print its SHA-256 for you to compare with your download (`not pinned: NVIDIA publishes no checksum for this release`) and check it against the one `configure.sh --write` recorded.
4. Save it in `~/Downloads` under its own name, or anywhere else, and point the build at it (below). In `~/Downloads` the build uses only the file of that exact name, so another TensorRT archive there does not get in the way. In a directory you name, keep only one `TensorRT-*.tar.*` archive (archives named for the ARM build are set aside when exactly one other is there).

## Build inputs

One input, `NVIDIA_TRT_SRC`, is taken from the first of these that applies:

1. the environment variable `NVIDIA_TRT_SRC`;
2. `NVIDIA_TRT_SRC` in `selection.conf` in this directory (written by `configure.sh`);
3. the file `~/Downloads/TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst`, if it exists (another TensorRT archive there is ignored);
4. otherwise, the download (see [Downloading](#downloading)).

The choice between a file and a download is fixed when makepkg reads the recipe, so that makepkg knows whether it has anything to download. If that choice would change while the build runs (for example, a file appears in `~/Downloads` in the meantime), the build stops and asks you to run makepkg again. Because the outcome depends on them, `makepkg --printsrcinfo` depends on the environment, `selection.conf` and `~/Downloads` too, so this repository publishes no `.SRCINFO`.

When the source is set, it is an absolute path to one of:

| Source | Example | Checked |
|---|---|---|
| the archive | `~/Downloads/TensorRT-Enterprise-11.4.0.106-...-Release-external.tar.zst` | SHA-256 against the value pinned in the PKGBUILD, then the version |
| a directory holding exactly one `TensorRT-*.tar.*` | `~/Downloads` | the same; two archives are an error, unless all but one are named for the ARM build |
| an extracted tree | `~/Downloads/TensorRT-11.4.0.106` (its `include/` holds `NvInferVersion.h`), or a directory holding one such tree | the version only: a tree has no checksum |

A directory that holds both the archive and an extracted tree is read as the archive, which can be verified. In every case:

- the version in `include/NvInferVersion.h` must be `11.4.0.106`;
- the tree must hold `include/NvInfer.h`, `include/NvOnnxParser.h` and `include/NvInferVersion.h`;
- the tree must hold the libraries `libnvinfer`, `libnvinfer_plugin` and `libnvonnxparser` in `lib/`, or in `targets/x86_64-linux-gnu/lib/` when the archive ships its files there (with or without a `lib` link to it).

`trtexec` (`bin/`), the Python wheels (`python/`) and `samples/` are packaged when present. Every other header in `include/`, such as `NvOnnxConfig.h` where a release ships it, is packaged as shipped but not required.

A source holding a device, a fifo or a socket, or a symbolic link whose target is absolute (`lib/libnvinfer.so -> /etc/shadow`) or leads out of the TensorRT tree (`-> ../../../../etc`), is refused, by `configure.sh` and by the build alike. In an archive this is judged from `bsdtar`'s listing of the member types and link targets, before anything is extracted. The tree the build packages is checked again, with the links resolved, so a tree changed after `configure.sh --write` is still caught.

`selection.conf` holds `NVIDIA_TRT_SRC=<absolute path>` and, for an archive, `NVIDIA_TRT_SHA256=<hex>` as `configure.sh` computed it. It is parsed as `KEY=value` lines, never executed, and git-ignored (it holds a local path). The recorded SHA-256 applies only when the source comes from the file: if the archive changed since, the build stops and asks you to run `configure.sh --write` again.

## Checking and saving the source

```sh
./configure.sh --src ~/Downloads          # check and report; writes nothing
./configure.sh --src ~/Downloads --write  # check and save in selection.conf
./configure.sh --show                     # print the current selection.conf
```

`configure.sh` is offline and read-only: it lists the archive and reads its version header with `bsdtar`, without extracting it. A valid source prints these lines first, then a report:

```
version 11.4.0.106
source /home/you/Downloads/TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst
layout archive
sha256 c67c87674cbe7b2337d1c30cb16d48686ab79ecb11bf08cb764b71f4f2bb711b
features headers libs trtexec python samples
```

`layout` is `archive` or `tree`, `sha256` is `none` for a tree, and `features` lists `headers libs` followed by whichever of `trtexec python samples` are present. The report's `checksum` line says whether the SHA-256 matches the pinned one, and a `skipped` line names an ARM archive set aside in the directory.

It exits 0 for a valid source and 1 with the reason otherwise:

- no archive, or several archives;
- the ARM (aarch64) build (it names the x86_64 file to download);
- a SHA-256 mismatch (it names both hashes; download the file again);
- another TensorRT version (it names both versions);
- missing headers or libraries.

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/tensorrt/` | the TensorRT tree as shipped: `include/`, `lib/`, `bin/` (`trtexec`), `python/` (the wheels), `samples/`, `data/`, `doc/`, and `targets/x86_64-linux-gnu/` when the archive has it |
| `/opt/nvidia/tensorrt/lib/pkgconfig/nvidia-tensorrt.pc` | a pkg-config file, generated by the build (in `targets/x86_64-linux-gnu/lib/pkgconfig/` when the tree has no `lib/`) |
| `/etc/ld.so.conf.d/nvidia-tensorrt-sdk.conf` | puts the library directory on the system library path, for the libraries found by soname (see below) |
| `/usr/lib/libnvinfer_builder_resource_*.so.11.4.0` | symbolic links, one for each library in the TensorRT library directory whose soname starts with `do_not_link_against_` (16 in this release, the `_win_` variants included), each to the same file there; `libnvinfer` opens these by file name (see below) |
| `/usr/share/nvidia-tensorrt/nvidia-tensorrt.env` | the environment file a consumer loads (`TENSORRT_HOME`, the pkg-config directory, the root and include paths) |
| `/usr/share/licenses/nvidia-tensorrt-sdk-local/` | `TERMS.txt`, a short note on the licence terms, and links to TensorRT's licence and notice files in `/opt/nvidia/tensorrt` |
| `/usr/share/doc/nvidia-tensorrt-sdk-local/README.md` | this page |

The package puts one file into `/etc`: `/etc/ld.so.conf.d/nvidia-tensorrt-sdk.conf`. It adds `/opt/nvidia/tensorrt/lib` (`targets/x86_64-linux-gnu/lib` when the tree has no `lib/`) to the system library path. That entry makes the libraries that are found by soname visible to every program: `libnvinfer.so.11`, the plugins and the parsers among them. pacman runs `ldconfig` for the file on install, upgrade and removal through glibc's own hook, so the package needs no install script. A program that finds `libnvinfer.so.11` without an RPATH or RUNPATH needs the entry, or `LD_LIBRARY_PATH`, to load it.

**Why the package links builder-resource libraries into `/usr/lib`.** The entry does not reach the builder-resource libraries.

- NVIDIA gives each of them a deliberate soname of the form `do_not_link_against_` followed by its file name, so `ldconfig` caches it only under that name.
- `libnvinfer` has no RUNPATH and opens these libraries with `dlopen()` by file name. The loader finds a file name only through `LD_LIBRARY_PATH`, a RUNPATH of the library that calls `dlopen()`, or the default directories such as `/usr/lib`.
- The package therefore links them into `/usr/lib`. At package time it finds, with `readelf`, every library in the TensorRT library directory whose soname starts with `do_not_link_against_`, and creates a symbolic link to each one in `/usr/lib` under its own name.
- The list is read from the files rather than written into the recipe, so a later release with a different set of builder resources needs no change to it.
- The `_win_` variants are linked as well, because `libnvinfer` refers to the same name prefix and the package does not try to decide which of them Linux loads.
- NVIDIA's files are not changed. The links leave the shipped libraries as they are, where editing their soname or adding a RUNPATH would have modified them.

**What the package does not install.** Nothing goes into `/usr/include`. The only files under `/usr/lib` are these links, and there is no `profile.d` script. `trtexec` is not on `PATH` (run `/opt/nvidia/tensorrt/bin/trtexec`). The Python wheels are not installed into `site-packages`: install the wheel of your Python version into a virtual environment yourself, with `pip install /opt/nvidia/tensorrt/python/tensorrt-<version>-cp<NN>-...whl`.

**Dependencies.** The package depends on `cuda>=13.4` and `cuda<14` (the CUDA 13 runtime this TensorRT is built for, and the `cudart.pc` the pkg-config file requires) and on `nvidia-utils` (the driver). It does not depend on cuDNN, which TensorRT no longer requires since version 10 (only optional, deprecated cuDNN-based plugins and tactic sources use it). Install Arch's `cudnn` yourself if something you run needs it.

## Using it from another project

### The environment file

| Key | Value |
|---|---|
| `NVIDIA_TRT_ROOT`, `TENSORRT_HOME` | `/opt/nvidia/tensorrt` |
| `NVIDIA_TRT_INCLUDE_DIR` | `/opt/nvidia/tensorrt/include` |
| `NVIDIA_TRT_LIBRARY_PATH`, `LD_LIBRARY_PATH` | `/opt/nvidia/tensorrt/lib` |
| `NVIDIA_TRT_PKG_CONFIG_PATH` | `/opt/nvidia/tensorrt/lib/pkgconfig`, the directory to add to `PKG_CONFIG_PATH` |
| `NVIDIA_TRT_VERSION` | `11.4.0.106` |

For a tree with no `lib/`, the library and pkg-config paths are under `targets/x86_64-linux-gnu/lib`.

The file has plain `KEY=value` lines, so it works as a systemd `EnvironmentFile=` and in a script:

```sh
set -a; . /usr/share/nvidia-tensorrt/nvidia-tensorrt.env; set +a
```

Load it for one build or one program, never from a login profile.

A program that loads more than one environment file, for example this one and a Maxine SDK's or the Optical Flow SDK's, must not rely on their `LD_LIBRARY_PATH` lines: each file sets `LD_LIBRARY_PATH`, so the last file loaded wins. Build `LD_LIBRARY_PATH` yourself from the `NVIDIA_*_LIBRARY_PATH` and `MAXINE_*_LIBRARY_PATH` keys, which carry the same values under names that do not collide, skipping the keys a file does not set. Set it explicitly after loading the files. In a systemd unit, use an `Environment=LD_LIBRARY_PATH=...` line after the `EnvironmentFile=` lines, since a unit file cannot expand a variable that comes from an environment file.

### pkg-config

```sh
PKG_CONFIG_PATH=/opt/nvidia/tensorrt/lib/pkgconfig pkg-config --cflags --libs nvidia-tensorrt
# -I/opt/nvidia/tensorrt/include -I/opt/cuda/include -L/opt/nvidia/tensorrt/lib -Wl,-rpath,/opt/nvidia/tensorrt/lib -lnvinfer -lnvinfer_plugin -lnvonnxparser -L/opt/cuda/lib -lcudart
```

TensorRT's headers include the CUDA runtime headers, so the file has `Requires: cudart`. Arch's `cuda` ships `/usr/lib/pkgconfig/cudart.pc`, which adds `/opt/cuda/include` and `-lcudart` (the exact order of the flags may differ). The directory is also in the environment file, as `NVIDIA_TRT_PKG_CONFIG_PATH`.

### CMake and ONNX Runtime

Point the build at the root. ONNX Runtime's build script takes `--use_tensorrt --tensorrt_home /opt/nvidia/tensorrt` (or the CMake option `-Donnxruntime_TENSORRT_HOME=/opt/nvidia/tensorrt`). A CMake project that searches for TensorRT finds it with `-DCMAKE_PREFIX_PATH=/opt/nvidia/tensorrt` (or `TENSORRT_HOME` from the environment file, for the projects that read it). A package that builds against it declares `depends=('nvidia-tensorrt-sdk')`.

### RPATH rather than LD_LIBRARY_PATH

Link a program or library with an RPATH (or RUNPATH) of `/opt/nvidia/tensorrt/lib` so that it finds TensorRT on its own. With CMake, use `-DCMAKE_INSTALL_RPATH=/opt/nvidia/tensorrt/lib` or `-DCMAKE_BUILD_RPATH=...`. The pkg-config file adds `-Wl,-rpath`. The system loader entry already makes the libraries visible to every program, so `LD_LIBRARY_PATH` from the environment file is not needed to run one. Setting `LD_LIBRARY_PATH` globally would put these libraries in front of every program's, including programs that bundle another TensorRT (the Maxine SDKs bundle TensorRT 10). Keep it to the one program that needs it.

## Relation to the AUR's tensorrt package

The Arch User Repository's `tensorrt` package installs the same NVIDIA archive into `/usr` (`/usr/include`, `/usr/lib`). This package installs it into `/opt/nvidia/tensorrt` and conflicts with it. The two would otherwise both be on the system library path: `ldconfig` resolves each soname (`libnvinfer.so.11`, and so on) to one copy, in directory order, and `libnvinfer` then loads its sibling libraries by exact versioned name from that cache. With two different TensorRT 11 releases installed, a process could mix the libraries of both. Both packages also put files with the same names in `/usr/lib` (the AUR's own builder-resource libraries and this package's links to them), so pacman offers to replace one package with the other. Install only one of them.

This package provides `nvidia-tensorrt-sdk` and `tensorrt` (version 11.4.0.106). So a package that depends on `tensorrt` can be satisfied by this one (providing the name it also conflicts with is what lets pacman replace the AUR package cleanly). Such a package expects the `/usr` paths, which this package does not provide apart from the links in `/usr/lib`, so it must find TensorRT through the environment file or pkg-config instead. A program built against one finds only that one. This package does not provide `python-tensorrt`, because it installs no Python module: it ships the wheels but does not install them. This package's checksum is the one that recipe publishes for the same archive.

## Licence notes

- NVIDIA serves the TensorRT archive to you under its TensorRT Software License Agreement, whether makepkg downloads it or you do (see [Downloading](#downloading)). Read the agreement. This repository holds only the recipe; no NVIDIA file is committed (the guard `scripts/check-no-nvidia.sh` enforces it).
- The built package contains NVIDIA software and is for your own machine only. Never upload it to a package repository, to the AUR as a binary or to a release page, and never share it. The agreement permits distributing only TensorRT's runtime libraries (the `.so` files), and only inside an application that adds material functionality (supplement sections 2 and 1.2). This package is not that. The package ships `/usr/share/licenses/nvidia-tensorrt-sdk-local/TERMS.txt` with this summary.
- NVIDIA does not support this packaging. This is not legal advice: read the agreement you accept.

## Testing

```sh
tests/configure-test.sh   # configure.sh, source.sh and selection.sh on tiny fake archives and trees
tests/pkgbuild-test.sh    # a makepkg build of a fake archive in a temporary copy (exit 77 without makepkg, fakeroot or bsdtar)
```

Both work on fake files under `mktemp`. Neither needs a GPU, the network or a TensorRT download, and neither writes into this directory.

- The checksum tests pin the fake archive's SHA-256 in a temporary copy of the PKGBUILD, the file `configure.sh` reads `_trt_archive` and `_trt_sha256` from, and run the copy unpinned too.
- The ARM tests use fake aarch64 archives and trees: an `aarch64` wheel name, an `aarch64` or `sbsa` `targets/` directory, and a 20-byte ELF header for aarch64 in place of `libnvinfer`.
- The download tests in `pkgbuild-test.sh` replace makepkg's downloader with a stub that records the URL it is asked for and copies a local file, or fails. They check the exact URL, the reuse of a copy in `SRCDEST`, that a wrong file is refused by the checksum, and that `~/Downloads` and `NVIDIA_TRT_SRC` take precedence without any download. No test reaches the network.
