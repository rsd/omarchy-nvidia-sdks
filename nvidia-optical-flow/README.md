# nvidia-optical-flow: the NVIDIA Optical Flow SDK as a local package

This recipe builds `nvidia-optical-flow-sdk-local`, a local Arch package of the NVIDIA Optical Flow SDK 5.0.7, from your own download. Several projects on the machine can share the package. You need this page to build the package by hand. [`scripts/setup.sh --sdk of`](https://github.com/rsd/omarchy-nvidia-sdks/blob/main/scripts/setup.sh) does the same steps with questions ([INSTALL.md](https://github.com/rsd/omarchy-nvidia-sdks/blob/main/INSTALL.md)).

You download the SDK yourself, after accepting NVIDIA's licence. This directory holds only the recipe ([`PKGBUILD`](https://github.com/rsd/omarchy-nvidia-sdks/blob/main/nvidia-optical-flow/PKGBUILD)). The built package contains NVIDIA software: keep it on your own machine and never share or upload it.

The recipe is validated against NVIDIA's documented package contents (the SDK's release notes) using fake fixtures. The zip's exact layout is found by searching rather than by fixed paths, so small differences in directory names are tolerated. `./configure.sh` shows what it found before you build.

## Licence and personal use

- The SDK is distributed under the NVIDIA DesignWorks SDK License. You accept it yourself when you download the SDK. Read it.
- The SDK may not be redistributed stand-alone. The package built here is for **your own machine only**: never upload it to a package repository, to the AUR as a binary or to a release page, and never share it.
- Nothing from NVIDIA is committed to this repository: no zip, headers, libraries or licence documents. The guard `scripts/check-no-nvidia.sh` refuses the zip, the SDK's headers, an unpacked `Optical_Flow_SDK_*/` tree anywhere, and the SDK's top-level names (`NvOFInterface/`, `NvOFBasicSamples/`, `NvOFTracker/`, `NvOFFRUC/`, `Common/`) and the installed tree's (`include/`, `fruc/`, `samples/`, `tracker/`, `licenses/`) placed directly in this directory.
- NVIDIA does not support this configuration (Arch Linux, a package built by a third-party recipe). This is not legal advice.

## Before you start

- **The zip.** Sign in to the NVIDIA Developer Program at <https://developer.nvidia.com/opticalflow/download>, accept the licence and download `optical_flow_sdk_5.0.7.zip`. Nothing here downloads the SDK for you. NVIDIA publishes no checksum for the zip, so `configure.sh --write` records the SHA-256 of your download and the build verifies the zip against it.
- **A GPU and driver.** The Optical Flow API is implemented by the NVIDIA driver, as `libnvidia-opticalflow.so` in `nvidia-utils`. An application loads it at run time with `dlopen`. NVIDIA documents a Turing or newer GPU and driver 525.85.05 or newer for SDK 5.0.
- **What the SDK provides.** The headers, the samples, NvOFTracker and the prebuilt FRUC (frame rate up-conversion) library.
- `makepkg`, `fakeroot` and `bsdtar` ([INSTALL.md](https://github.com/rsd/omarchy-nvidia-sdks/blob/main/INSTALL.md#before-you-start)).

## Build and install

From this directory:

```sh
./configure.sh --src ~/Downloads/optical_flow_sdk_5.0.7.zip --write
makepkg -f
# or without selection.conf, from an extracted tree:
NVIDIA_OF_SRC=$HOME/Downloads/Optical_Flow_SDK_5.0.7 makepkg -f
```

Install the package yourself:

```sh
sudo pacman -U nvidia-optical-flow-sdk-local-5.0.7-*-x86_64.pkg.tar*
```

## Check that it works

```sh
pacman -Ql nvidia-optical-flow-sdk-local | head
ls /opt/nvidia/optical-flow/include
ldconfig -p | grep libnvidia-opticalflow
grep '^NVIDIA_OF_FEATURES' /usr/share/nvidia-optical-flow/nvidia-optical-flow.env
```

`ldconfig -p` must show `libnvidia-opticalflow.so.1`. If it does not, the driver's utilities (`nvidia-utils`) are missing or too old. Further checks, and troubleshooting, are in [docs/optical-flow.md](https://github.com/rsd/omarchy-nvidia-sdks/blob/main/docs/optical-flow.md#check-the-installation).

## Uninstall

```sh
sudo pacman -R nvidia-optical-flow-sdk-local
```

## Build inputs

| Variable | Default | Meaning |
|---|---|---|
| `NVIDIA_OF_SRC` | this directory | the zip, a directory holding exactly one `optical_flow_sdk_*.zip`, or an extracted SDK tree; an absolute path |
| `NVIDIA_OF_SHA256` | the `SHA256` of `selection.conf` | the SHA-256 the zip must have |

`NVIDIA_OF_SRC` comes from the environment variable when it is set and not empty, else from `selection.conf` in this directory, else the default. The checksum belongs to the zip it was recorded for:

1. `NVIDIA_OF_SHA256` from the environment wins.
2. Otherwise the `SHA256` of `selection.conf` applies, while the source is that file's `NVIDIA_OF_SRC`.
3. Otherwise there is none.

`prepare()` prints both values and where they came from.

- **A zip** must have a checksum, and it must match. The build stops otherwise, naming the command that records it. The build first copies the zip into makepkg's `src/` and then hashes, lists and extracts only that copy, so a file replaced during the build cannot pass the checksum and be extracted in its place. It is extracted with `bsdtar` into `src/`, never next to the zip or into the source. Member names that are absolute or contain `..`, symbolic links whose target is absolute or leads out of the zip, and devices, fifos and sockets are refused before anything is extracted.
- **An extracted tree** has no checksum and is packaged as it is. A checksum given for a tree stops the build. A symbolic link whose target is absolute or resolves outside the tree, and a device, fifo or socket, stop the build.
- Whatever the source, the assembled tree is checked again before it is packaged: no symbolic link may be absolute or resolve outside it, and no device, fifo or socket may be in it. `configure.sh` applies the same refusals as the build, so a tree that changed after `configure.sh --write` is still checked when you build.
- A directory holding two or more `optical_flow_sdk_*.zip` files stops the build: keep one, or name the one you mean. A directory holding one is read as that zip, even if an extracted tree sits beside it.

The SDK version comes from the zip's name (`optical_flow_sdk_5.0.7.zip`), else from its top-level directory (`Optical_Flow_SDK_5.0.7`, in any letter case), else from the API header's major and minor version. A version other than the PKGBUILD's `pkgver` stops the build, naming both.

### Choosing with configure.sh

[`configure.sh`](https://github.com/rsd/omarchy-nvidia-sdks/blob/main/nvidia-optical-flow/configure.sh) reads the source without network access and extracts nothing (a zip's member names are listed with `bsdtar -t`):

```sh
./configure.sh --src ~/Downloads/optical_flow_sdk_5.0.7.zip           # what it holds
./configure.sh --src ~/Downloads/optical_flow_sdk_5.0.7.zip --write   # save it, with its SHA-256
./configure.sh --show                                                 # print the current selection.conf
```

`--src` defaults to `$NVIDIA_OF_SRC`, else the `NVIDIA_OF_SRC` of the current `selection.conf`, else this directory. Without `--write` the output starts with five machine-readable lines, then a report:

```
version 5.0.7
source /home/you/Downloads/optical_flow_sdk_5.0.7.zip
layout zip
sha256 <64 hexadecimal digits>
features api fruc tracker-src samples
```

- `source` is the zip itself, or the tree's directory.
- `layout` is `zip` or `tree`.
- `sha256` is `none` for a tree.
- `features` lists the components present, in the order `api`, `fruc`, `tracker-src`, `samples`.
- `version` has only the major and minor parts when the API header is the only source of it.

The exit status is 0 when the API headers are found, and non-zero, with the reason and the download instructions, otherwise.

`--write` validates the source the same way and replaces `selection.conf` atomically. Given a directory holding the zip, it records the zip itself.

### selection.conf

`selection.conf` is git-ignored: it holds a path on your machine.

```
NVIDIA_OF_SRC=/home/you/Downloads/optical_flow_sdk_5.0.7.zip
SHA256=<64 hexadecimal digits>
```

The PKGBUILD reads it in `prepare()` only, so `makepkg --printsrcinfo` does not depend on it. [`selection.sh`](https://github.com/rsd/omarchy-nvidia-sdks/blob/main/nvidia-optical-flow/selection.sh) parses it as `KEY=value` lines and never sources or executes it. These stop the build with the line number:

- an unknown key, or a line that is not `KEY=value`;
- a key given twice, or an empty value;
- a value containing `$`, a backtick, a quote or a control character;
- a relative `NVIDIA_OF_SRC`;
- a `SHA256` that is not 64 hexadecimal digits.

### What is searched for

[`assemble.sh`](https://github.com/rsd/omarchy-nvidia-sdks/blob/main/nvidia-optical-flow/assemble.sh) finds the components, for `configure.sh` (`--scan`) and for the build alike:

| Component | Found as | Required |
|---|---|---|
| `api` | `nvOpticalFlowCommon.h` and `nvOpticalFlowCuda.h` side by side; the copy in a directory named `NvOFInterface` wins when there are several | yes |
| `fruc` | the header `NvFRUC.h` or `NvOFFRUC.h`, and the library `libNvFRUC.so`, `NvFRUC.so`, `libNvOFFRUC.so` or `NvOFFRUC.so` (a path naming `linux` or `ubuntu` wins, then the shallowest), with the `libcudart.so*` files NVIDIA bundles next to it | no |
| `tracker-src` | `NvOFTracker/` beside the API header directory | no |
| `samples` | `NvOFBasicSamples/` beside the API header directory | no |

FRUC is left out with a warning in these cases:

- a FRUC header without the library, or the reverse;
- two candidate libraries at the same depth;
- an `NvOFFRUC/` directory in which no header and library of these names are found. The warning lists the headers and libraries that directory holds, so that a renamed FRUC is noticed rather than silently left out.

The build still succeeds. The samples' shared `Common/` directory is not installed. Its licence files are (below).

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/optical-flow/include/` | the API headers (every `*.h` of the SDK's API header directory) |
| `/opt/nvidia/optical-flow/fruc/include/` | the FRUC header, under its shipped name (`NvFRUC.h` or `NvOFFRUC.h`) |
| `/opt/nvidia/optical-flow/fruc/lib/` | the FRUC library as shipped, a link under its other name (with or without the `lib` prefix: `libNvFRUC.so` and `NvFRUC.so`, or `libNvOFFRUC.so` and `NvOFFRUC.so`), and the CUDA runtime FRUC bundles, private to this directory |
| `/opt/nvidia/optical-flow/samples/` | `NvOFBasicSamples/`, as source (documentation; not built) |
| `/opt/nvidia/optical-flow/tracker/` | `NvOFTracker/`, as source (documentation; not built: it needs CUDA 11.8, cuDNN 8.6, TensorRT 8.5 and OpenCV) |
| `/opt/nvidia/optical-flow/` | the SDK's top-level files (readme, licence, release notes), as shipped |
| `/opt/nvidia/optical-flow/licenses/` | the SDK's other licence files, for example FreeImage's, named after their path with `/` as `_` |
| `/usr/share/nvidia-optical-flow/nvidia-optical-flow.env` | the environment file a consumer loads |
| `/usr/share/licenses/nvidia-optical-flow-sdk-local/` | links to the SDK's licence files, and this repository's licence (the documentation) |
| `/usr/share/doc/nvidia-optical-flow-sdk-local/README.md` | this page |

Nothing goes into `/usr/include`, `/usr/lib` or `/etc`, there is no `profile.d` script, and nothing sets `LD_LIBRARY_PATH` globally: FRUC's bundled CUDA runtime would otherwise shadow the system's for every program. The package does not include the os-release shim the Maxine packages use, because the Optical Flow SDK is not documented to check the distribution.

The package depends on `nvidia-utils` and provides `nvidia-optical-flow-sdk=5.0.7`. It does not conflict with the AUR package `nvidia-opticalflow-headers`, which installs the 3.0 headers in `/usr/include`: the two install disjoint paths.

### The environment file

Plain `KEY=value` lines, no quotes and no expansion, so it works as a systemd `EnvironmentFile=` and with `set -a; . file; set +a`. Load it for one program only, never from a login profile.

| Key | Value |
|---|---|
| `NVIDIA_OF_ROOT` | `/opt/nvidia/optical-flow` |
| `NVIDIA_OF_INCLUDE_DIR` | `/opt/nvidia/optical-flow/include` |
| `NVIDIA_OF_LIBRARY_PATH`, `LD_LIBRARY_PATH` | `/opt/nvidia/optical-flow/fruc/lib`; both lines are absent when FRUC is not packaged |
| `NVIDIA_OF_FEATURES` | the packaged components, comma-separated, for example `api,fruc,tracker-src,samples` |

A program that uses only the Optical Flow API needs `NVIDIA_OF_INCLUDE_DIR` to build and nothing at run time (the driver's library is on the system's search path). A program that uses FRUC also needs the library path, for the FRUC library and its bundled CUDA runtime.

When FRUC is not packaged there is no library directory, and the file sets neither `NVIDIA_OF_LIBRARY_PATH` nor `LD_LIBRARY_PATH`. Loading it leaves the program's `LD_LIBRARY_PATH` as it was. (An empty `LD_LIBRARY_PATH=` would clear it, and a later `$LD_LIBRARY_PATH:/x` would then put the current directory on the search path.)

A program that loads more than one environment file, for example this one and a Maxine SDK's or TensorRT's, must not rely on their `LD_LIBRARY_PATH` lines: each file sets `LD_LIBRARY_PATH`, so the last file loaded wins. Build `LD_LIBRARY_PATH` yourself from the `NVIDIA_*_LIBRARY_PATH` and `MAXINE_*_LIBRARY_PATH` keys, which carry the same values under names that do not collide, skipping the keys that are absent. Set it explicitly after loading the files. In a systemd unit, use an `Environment=LD_LIBRARY_PATH=...` line after the `EnvironmentFile=` lines, since a unit file cannot expand a variable that comes from an environment file.

## Tests

The tests use fake files with the SDK's documented names. They need no GPU, no network and no NVIDIA download, and write only under `mktemp`:

```sh
tests/configure-test.sh   # configure.sh, selection.sh and the scan: zips, trees, versions, FRUC, --write
tests/pkgbuild-test.sh    # makepkg builds of the PKGBUILD (needs makepkg, fakeroot, bsdtar)
```
