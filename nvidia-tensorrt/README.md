# nvidia-tensorrt: TensorRT as a local package

[`PKGBUILD`](PKGBUILD) turns your own download of NVIDIA TensorRT 11.4 for CUDA 13.4 into a local Arch package, `nvidia-tensorrt-sdk-local`, installed under `/opt/nvidia/tensorrt`, that several projects on the machine can share: for example an ONNX Runtime build with the TensorRT execution provider. Download TensorRT yourself, after accepting NVIDIA's licence; this directory holds only the recipe. The built package contains NVIDIA software: keep it on your own machine and never share or upload it.

The package version is TensorRT's full version, `11.4.0.106`, read from `include/NvInferVersion.h`. Arch's `cuda` package provides the CUDA 13 runtime it runs on.

## Downloading

TensorRT is downloaded by hand; nothing in this repository downloads it.

1. Open <https://developer.nvidia.com/tensorrt/download> and sign in with an NVIDIA Developer Program account.
2. Read and accept the TensorRT Software License Agreement (<https://docs.nvidia.com/deeplearning/tensorrt/latest/reference/sla.html>). It allows internal use and does not allow redistributing TensorRT, except its runtime libraries as part of an application.
3. Choose TensorRT 11.4, Linux x86_64, the TAR package for CUDA 13.4. The file is

   ```
   TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst
   ```

   with SHA-256 `c67c87674cbe7b2337d1c30cb16d48686ab79ecb11bf08cb764b71f4f2bb711b`.
4. Save it in `~/Downloads` (the default source) or anywhere else, and point the build at it (below). Keep only one `TensorRT-*.tar.*` archive in the directory you name.

## Build inputs

One input, `NVIDIA_TRT_SRC`, from the environment, else from `selection.conf` in this directory (written by `configure.sh`), else the default `~/Downloads`. It is an absolute path to one of:

| Source | Example | Checked |
|---|---|---|
| the archive | `~/Downloads/TensorRT-Enterprise-11.4.0.106-...-Release-external.tar.zst` | SHA-256 against the value pinned in the PKGBUILD, then the version |
| a directory holding exactly one `TensorRT-*.tar.*` | `~/Downloads` | the same; two archives are an error |
| an extracted tree | `~/Downloads/TensorRT-11.4.0.106` (its `include/` holds `NvInferVersion.h`), or a directory holding one such tree | the version only: a tree has no checksum |

A directory that holds both the archive and an extracted tree is read as the archive, which can be verified. In every case the version in `include/NvInferVersion.h` must be `11.4.0.106`, and the tree must hold `include/NvInfer.h`, `include/NvOnnxParser.h`, `include/NvInferVersion.h` and the libraries `libnvinfer`, `libnvinfer_plugin` and `libnvonnxparser` in `lib/`, or in `targets/x86_64-linux-gnu/lib/` when the archive ships its files there (with or without a `lib` link to it). `trtexec` (`bin/`), the Python wheels (`python/`) and `samples/` are packaged when present. Every other header in `include/`, such as `NvOnnxConfig.h` where a release ships it, is packaged as shipped but not required.

A source holding a device, a fifo or a socket, or a symbolic link whose target is absolute (`lib/libnvinfer.so -> /etc/shadow`) or leads out of the TensorRT tree (`-> ../../../../etc`), is refused, by `configure.sh` and by the build alike. In an archive this is judged from `bsdtar`'s listing of the member types and link targets, before anything is extracted; the tree the build packages is checked again, with the links resolved, so a tree changed after `configure.sh --write` is still caught.

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

`layout` is `archive` or `tree`, `sha256` is `none` for a tree, and `features` lists `headers libs` followed by whichever of `trtexec python samples` are present. It exits 0 for a valid source and 1 with the reason otherwise: no or several archives, a SHA-256 mismatch (it names both hashes; download the file again), another TensorRT version (it names both versions), or missing headers or libraries.

## Building and installing

```sh
cd nvidia-tensorrt
./configure.sh --src ~/Downloads --write
PKGEXT=.pkg.tar makepkg -f
sudo pacman -U nvidia-tensorrt-sdk-local-11.4.0.106-1-x86_64.pkg.tar
```

`prepare()` prints the source and where it came from, copies the archive into makepkg's `src/` directory, and from then on reads only that copy: it verifies its SHA-256 again, checks its members and extracts it with `bsdtar` into `src/`, never next to your download. A download replaced while the build runs therefore cannot pass the checksum and be extracted in its place. An extracted tree is copied, and the copy is what is checked and packaged. The package is several GiB; `PKGEXT=.pkg.tar` skips a slow compression. Installing is your step: the recipe never runs `pacman` or `sudo`.

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/tensorrt/` | the TensorRT tree as shipped: `include/`, `lib/`, `bin/` (`trtexec`), `python/` (the wheels), `samples/`, `data/`, `doc/`, and `targets/x86_64-linux-gnu/` when the archive has it |
| `/opt/nvidia/tensorrt/lib/pkgconfig/nvidia-tensorrt.pc` | a pkg-config file, generated by the build (in `targets/x86_64-linux-gnu/lib/pkgconfig/` when the tree has no `lib/`) |
| `/usr/share/nvidia-tensorrt/nvidia-tensorrt.env` | the environment file a consumer loads |
| `/usr/share/licenses/nvidia-tensorrt-sdk-local/` | links to TensorRT's licence and notice files in `/opt/nvidia/tensorrt` |
| `/usr/share/doc/nvidia-tensorrt-sdk-local/README.md` | this page |

Nothing goes into `/usr/include`, `/usr/lib` or `/etc`: no `ld.so.conf.d` entry, no `profile.d` script, `trtexec` is not on `PATH` (run `/opt/nvidia/tensorrt/bin/trtexec`) and the Python wheels are not installed into `site-packages` (install one into a virtual environment yourself, with `pip install /opt/nvidia/tensorrt/python/tensorrt-<version>-cp<NN>-...whl`, picking the wheel of your Python version). The package depends on `cuda>=13.4` and `cuda<14` (the CUDA 13 runtime this TensorRT is built for, and the `cudart.pc` the pkg-config file requires) and `nvidia-utils` (the driver). It does not depend on cuDNN, which TensorRT no longer requires since version 10 (only optional, deprecated cuDNN-based plugins and tactic sources use it); install Arch's `cudnn` yourself if something you run needs it.

## Using it from another project

### The environment file

| Key | Value |
|---|---|
| `NVIDIA_TRT_ROOT`, `TENSORRT_HOME` | `/opt/nvidia/tensorrt` |
| `NVIDIA_TRT_INCLUDE_DIR` | `/opt/nvidia/tensorrt/include` |
| `NVIDIA_TRT_LIBRARY_PATH`, `LD_LIBRARY_PATH` | `/opt/nvidia/tensorrt/lib` |
| `NVIDIA_TRT_PKG_CONFIG_PATH` | `/opt/nvidia/tensorrt/lib/pkgconfig`, the directory to add to `PKG_CONFIG_PATH` |
| `NVIDIA_TRT_VERSION` | `11.4.0.106` |

(For a tree with no `lib/`, the library and pkg-config paths are under `targets/x86_64-linux-gnu/lib`.)

Plain `KEY=value` lines, so it works as a systemd `EnvironmentFile=` and in a script:

```sh
set -a; . /usr/share/nvidia-tensorrt/nvidia-tensorrt.env; set +a
```

Load it for one build or one program, never from a login profile.

A program that loads more than one environment file, for example this one and a Maxine SDK's or the Optical Flow SDK's, must not rely on their `LD_LIBRARY_PATH` lines: each file sets `LD_LIBRARY_PATH`, so the last file loaded wins. Build `LD_LIBRARY_PATH` yourself from the `NVIDIA_*_LIBRARY_PATH` and `MAXINE_*_LIBRARY_PATH` keys, which carry the same values under names that do not collide, skipping the keys a file does not set, and set it explicitly after loading the files (in a systemd unit, an `Environment=LD_LIBRARY_PATH=...` line after the `EnvironmentFile=` lines, since a unit file cannot expand a variable that comes from an environment file).

### pkg-config

```sh
PKG_CONFIG_PATH=/opt/nvidia/tensorrt/lib/pkgconfig pkg-config --cflags --libs nvidia-tensorrt
# -I/opt/nvidia/tensorrt/include -I/opt/cuda/include -L/opt/nvidia/tensorrt/lib -Wl,-rpath,/opt/nvidia/tensorrt/lib -lnvinfer -lnvinfer_plugin -lnvonnxparser -L/opt/cuda/lib -lcudart
```

TensorRT's headers include the CUDA runtime headers, so the file has `Requires: cudart`: Arch's `cuda` ships `/usr/lib/pkgconfig/cudart.pc`, which adds `/opt/cuda/include` and `-lcudart` (the exact order of the flags may differ). The directory is also in the environment file, as `NVIDIA_TRT_PKG_CONFIG_PATH`.

### CMake and ONNX Runtime

Point the build at the root: ONNX Runtime's build script takes `--use_tensorrt --tensorrt_home /opt/nvidia/tensorrt` (or the CMake option `-Donnxruntime_TENSORRT_HOME=/opt/nvidia/tensorrt`), and a CMake project that searches for TensorRT finds it with `-DCMAKE_PREFIX_PATH=/opt/nvidia/tensorrt` (or `TENSORRT_HOME` from the environment file, for the projects that read it). A package that builds against it declares `depends=('nvidia-tensorrt-sdk')`.

### RPATH rather than LD_LIBRARY_PATH

Link a program or library with an RPATH (or RUNPATH) of `/opt/nvidia/tensorrt/lib` (CMake: `-DCMAKE_INSTALL_RPATH=/opt/nvidia/tensorrt/lib` or `-DCMAKE_BUILD_RPATH=...`; the pkg-config file adds `-Wl,-rpath`) so that it finds TensorRT on its own. Setting `LD_LIBRARY_PATH` globally would put these libraries in front of every program's, including programs that bundle another TensorRT (the Maxine SDKs bundle TensorRT 10); keep it to the one program that needs it.

## Relation to the AUR's tensorrt package

The Arch User Repository's `tensorrt` package installs the same NVIDIA archive into `/usr` (`/usr/include`, `/usr/lib`). This package installs it into `/opt/nvidia/tensorrt` and does not `provides` or `conflicts` with `tensorrt`: the two share no file and can be installed together, and a package that depends on `tensorrt` expects the `/usr` paths, which this package does not provide. A program built against one finds only that one. This package's checksum is the one that recipe publishes for the same archive.

## Licence notes

- You accept NVIDIA's TensorRT Software License Agreement and download TensorRT yourself, with your own account. This repository holds only the recipe; no NVIDIA file is committed (the guard `scripts/check-no-nvidia.sh` enforces it).
- The built package contains NVIDIA software and is for your own machine only. Never upload it to a package repository, to the AUR as a binary or to a release page, and never share it. The agreement permits distributing only TensorRT's runtime libraries as part of your own application, under its terms; this package is not that.
- NVIDIA does not support this packaging. This is not legal advice: read the agreement you accept.

## Testing

```sh
tests/configure-test.sh   # configure.sh, source.sh and selection.sh on tiny fake archives and trees
tests/pkgbuild-test.sh    # a makepkg build of a fake archive in a temporary copy (exit 77 without makepkg, fakeroot or bsdtar)
```

Both work on fake files under `mktemp`; neither needs a GPU, the network or a TensorRT download, and neither writes into this directory. The checksum tests pin the fake archive's SHA-256 in a temporary copy of the PKGBUILD, the file `configure.sh` reads `_trt_archive` and `_trt_sha256` from.
