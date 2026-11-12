# The Optical Flow SDK package

This page is for the person who builds `nvidia-optical-flow-sdk-local` and for programs that use it. The package is built from your own download of the NVIDIA Optical Flow SDK 5.0.7. It installs the SDK's headers, the FRUC (frame rate up-conversion) library when your download has it, and the samples and the NvOFTracker as source, under `/opt/nvidia/optical-flow`. The Optical Flow runtime itself, `libnvidia-opticalflow.so`, is not part of the SDK: it comes from the NVIDIA driver (`nvidia-utils`).

The recipe's own reference, with every build input and the rules for what is searched for, is [../nvidia-optical-flow/README.md](../nvidia-optical-flow/README.md). `scripts/setup.sh --sdk of` runs the steps below for you; see [setup.md](setup.md).

The package contains NVIDIA software and is for your own machine only; see the "Licence and personal use" section of the [README](../README.md) and [Licence notes](#licence-notes) below. NVIDIA does not support this configuration (Arch Linux, a package built by a third-party recipe).

The recipe was written and tested against NVIDIA's documented layout of the SDK (its release notes), with fake files of the documented names, not against a real archive. The API headers are searched for by name rather than by fixed path, so small differences in directory names are tolerated. If your download does not hold the API headers, `configure.sh` and the build stop with an error that says what they looked for; nothing is packaged from a layout they do not recognise.

## Download

NVIDIA publishes the SDK as one zip, behind a Developer Program login and a licence. Nothing in this repository downloads it for you.

1. Sign in to the NVIDIA Developer Program, or create an account, at <https://developer.nvidia.com/opticalflow/download>.
2. Read the NVIDIA DesignWorks SDK License and select "Accept & Download" for `optical_flow_sdk_5.0.7.zip`.
3. Save it in `~/Downloads` (where `scripts/setup.sh` looks), or anywhere else, and pass its location with `--src-of PATH` or `NVIDIA_OF_SRC`.

NVIDIA publishes no checksum for the zip. `configure.sh --write` records the SHA-256 of your download, and the build verifies the zip against it, so a file that changed in between is refused.

Then build and install, either with the guided script (it prints each command and asks before running it):

```bash
scripts/setup.sh --sdk of
```

or by hand:

```bash
cd nvidia-optical-flow
./configure.sh --src ~/Downloads/optical_flow_sdk_5.0.7.zip --write   # prints what the zip holds, saves it
makepkg -f
sudo pacman -U nvidia-optical-flow-sdk-local-5.0.7-*-x86_64.pkg.tar*
```

`configure.sh` reads the zip without network access and extracts nothing. Its first lines are machine readable (`version`, `source`, `layout`, `sha256`, `features`), followed by a report; the `features` line lists the components found, out of `api`, `fruc`, `tracker-src` and `samples`. It exits with status 0 when the API headers are found. A directory with two `optical_flow_sdk_*.zip` files is refused: name the one you mean.

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/optical-flow/include/` | The API headers (`nvOpticalFlowCommon.h`, `nvOpticalFlowCuda.h` and the others of the SDK's API header directory) |
| `/opt/nvidia/optical-flow/fruc/include/` and `fruc/lib/` | The FRUC header and library as shipped, with the CUDA runtime FRUC bundles, private to that directory. Present only when your download has FRUC |
| `/opt/nvidia/optical-flow/samples/`, `tracker/` | The sample programs and NvOFTracker as source, for reading. They are not built |
| `/opt/nvidia/optical-flow/licenses/` and the top-level files | The SDK's licence, readme and release notes |
| `/usr/share/nvidia-optical-flow/nvidia-optical-flow.env` | The environment file described below |

Nothing goes into `/usr/include`, `/usr/lib` or `/etc`, and nothing is set globally. FRUC's bundled CUDA runtime would otherwise shadow the system's for every program. The package depends on `nvidia-utils` and provides `nvidia-optical-flow-sdk`. It does not conflict with the AUR package `nvidia-opticalflow-headers`, which installs older headers in `/usr/include`: the two install disjoint paths, so a program built against one sees only that one.

## The environment file

`/usr/share/nvidia-optical-flow/nvidia-optical-flow.env` has plain `KEY=value` lines, so it works as a systemd `EnvironmentFile=` and with `set -a; . file; set +a`.

| Key | Value |
|---|---|
| `NVIDIA_OF_ROOT` | `/opt/nvidia/optical-flow` |
| `NVIDIA_OF_INCLUDE_DIR` | `/opt/nvidia/optical-flow/include` |
| `NVIDIA_OF_LIBRARY_PATH`, `LD_LIBRARY_PATH` | `/opt/nvidia/optical-flow/fruc/lib`. Both are absent when FRUC is not packaged |
| `NVIDIA_OF_FEATURES` | The packaged components, comma separated, for example `api,fruc,tracker-src,samples` |

Load it for one build or one program, never from a login profile. When FRUC is not packaged the file sets no library path at all, so loading it leaves the program's own `LD_LIBRARY_PATH` as it was.

## Using it from a program

**The Optical Flow API.** Build with `-I"$NVIDIA_OF_INCLUDE_DIR"`. The API is implemented by the driver: a program loads `libnvidia-opticalflow.so.1` at run time with `dlopen`, so there is nothing to link and nothing to add to the library path. NVIDIA documents a Turing or newer GPU and a driver of 525.85.05 or newer for SDK 5.0.

**FRUC.** Include the header from `/opt/nvidia/optical-flow/fruc/include` and link or load the library in `/opt/nvidia/optical-flow/fruc/lib`. The library needs its bundled CUDA runtime, which sits beside it, so run the program with that directory on `LD_LIBRARY_PATH`, or link with an RPATH to it. Keep it to the one program: a bundled CUDA runtime on the path of every program would shadow the system's.

```bash
(set -a; . /usr/share/nvidia-optical-flow/nvidia-optical-flow.env; set +a
 cc -I"$NVIDIA_OF_INCLUDE_DIR" -c myflow.c)
```

**Combining environment files.** A program that loads this file together with another SDK's must not rely on the `LD_LIBRARY_PATH` lines: each file sets one, and the last file loaded wins. Build the value from the `NVIDIA_OF_LIBRARY_PATH`, `NVIDIA_TRT_LIBRARY_PATH` and `MAXINE_*_LIBRARY_PATH` keys, skipping the ones a file does not set. [usage.md](usage.md#other-packages-optical-flow-and-tensorrt) shows how.

## Check the installation

```bash
pacman -Ql nvidia-optical-flow-sdk-local | head
ls /opt/nvidia/optical-flow/include
ldconfig -p | grep libnvidia-opticalflow
grep '^NVIDIA_OF_FEATURES' /usr/share/nvidia-optical-flow/nvidia-optical-flow.env
(set -a; . /usr/share/nvidia-optical-flow/nvidia-optical-flow.env; set +a
 for f in /opt/nvidia/optical-flow/fruc/lib/*.so*; do ldd "$f" | grep 'not found'; done)
```

The first two commands list the package and the headers, and `grep` shows the components that were packaged. `ldconfig -p` must show `libnvidia-opticalflow.so.1`: if it does not, the driver's utilities (`nvidia-utils`) are missing or too old. With FRUC packaged and the environment file applied, the `ldd` loop prints nothing. Without FRUC the directory does not exist and the loop has nothing to check. `scripts/setup.sh` makes the same checks after an install and prints one line for the SDK.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `configure.sh` says no API headers were found | The source is not the SDK zip, or its layout differs from the documented one. Check `bsdtar -tf optical_flow_sdk_5.0.7.zip`; the headers are `nvOpticalFlowCommon.h` and `nvOpticalFlowCuda.h` |
| The build stops on a missing or different SHA-256 | A zip needs a recorded checksum: run `configure.sh --src ZIP --write` again. If the zip changed since, download it again |
| The build stops on a version | The zip's version is not 5.0.7: the recipe packages that version only. Download `optical_flow_sdk_5.0.7.zip` |
| `configure.sh` warns that FRUC is left out | The header or the library was not found, or two libraries matched. The warning lists what the directory holds. The rest of the package is built without FRUC |
| `libnvidia-opticalflow.so.1` is not found at run time | It comes from `nvidia-utils`, not from this package. Install or update the driver packages |
| A program using FRUC fails to load the CUDA runtime | The FRUC library directory is not on its `LD_LIBRARY_PATH` or RPATH. Load the environment file for that program |
| Another program breaks after loading the environment file | The file was loaded globally, so FRUC's bundled CUDA runtime shadows the system's. Load it for one program only |

## Licence notes

- You accept the NVIDIA DesignWorks SDK License when you download the SDK, with your own account. Read it.
- The licence does not allow redistributing the SDK stand-alone. The package is for your own machine only: never upload it to a package repository, to the AUR as a binary or to a release page, and never share it.
- This repository holds only the recipe; no NVIDIA file is committed, and `scripts/check-no-nvidia.sh` refuses the zip, the SDK's headers and an unpacked SDK tree.
- This is not legal advice.
