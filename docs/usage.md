# Using the maxine-vfx-sdk-local package

This page is for programs and projects that load the Maxine Video Effects SDK installed by `maxine-vfx-sdk-local`. For building the package, see [download.md](download.md) and [../maxine-vfx/README.md](../maxine-vfx/README.md). For supported GPUs and architectures, see [gpu-support.md](gpu-support.md).

The package contains NVIDIA software and is for your own machine only; see the "Licence and personal use" section of the [README](../README.md). NVIDIA does not support this configuration (Arch, distributions the SDK does not list, client-side use).

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/maxine/videofx/` | The SDK tree: `lib/`, `lib/models/`, `features/`, `include/`, `external/cuda`, `external/tensorrt`, `share/` |
| `/usr/lib/maxine-vfx/os-release-shim.so` | The compatibility shim (built from `tools/os-release-shim`) |
| `/usr/lib/maxine-vfx/fake-os-release` | The replacement `os-release` (Ubuntu 24.04) |
| `/usr/share/maxine-vfx/maxine-vfx.env` | The environment file described below |
| `/usr/share/licenses/maxine-vfx-sdk-local/` | Symlinks to the SDK's licence files under `/opt/nvidia/maxine/videofx/share`, and copies of `LICENSE-MIT` and `LICENSE-APACHE` (they cover the shim) |
| `/usr/share/doc/maxine-vfx-sdk-local/` | This page (`usage.md`) |

The package is isolated on purpose. It installs no `/etc/ld.so.conf.d` entry and no `/etc/profile.d` file, and it sets neither `LD_LIBRARY_PATH` nor `LD_PRELOAD` globally. The SDK bundles CUDA 12.8 and TensorRT 10.9, and putting them on the global library path would shadow Arch's CUDA 13 for every program. A program opts in explicitly, as described below.

## The environment file

`/usr/share/maxine-vfx/maxine-vfx.env` holds plain `KEY=value` lines without quotes or variable expansion, and comments only on their own lines. That makes it usable both as a systemd `EnvironmentFile=` and in a shell with `set -a`. The file also starts with comment lines, omitted here. Its keys, in file order, shown for two features (green screen and background blur) and architecture `sm_120`:

```
MAXINE_VFX_ROOT=/opt/nvidia/maxine/videofx
MAXINE_VFX_MODEL_DIR=/opt/nvidia/maxine/videofx/lib/models
MAXINE_VFX_LIBRARY_PATH=/opt/nvidia/maxine/videofx/lib:/opt/nvidia/maxine/videofx/features/nvvfxbackgroundblur/lib:/opt/nvidia/maxine/videofx/features/nvvfxgreenscreen/lib:/opt/nvidia/maxine/videofx/external/cuda/lib:/opt/nvidia/maxine/videofx/external/tensorrt/lib
LD_LIBRARY_PATH=<same value as MAXINE_VFX_LIBRARY_PATH>
MAXINE_VFX_OS_RELEASE_SHIM=/usr/lib/maxine-vfx/os-release-shim.so
MAXINE_OS_RELEASE=/usr/lib/maxine-vfx/fake-os-release
MAXINE_VFX_FEATURES=nvvfxbackgroundblur,nvvfxgreenscreen
MAXINE_VFX_ARCHS=sm_120
```

`MAXINE_VFX_FEATURES` and `MAXINE_VFX_ARCHS` are informational: comma-separated lists, without spaces, of the features and architectures that were packaged. The library path has one `features/<feature>/lib` entry for every packaged feature, sorted by name, between `lib` and the bundled CUDA and TensorRT directories. The example grows with what you download: a package built with more features lists more entries, and more architectures lengthen `MAXINE_VFX_ARCHS`. The file never sets `LD_PRELOAD`.

The package is one package, not one per feature, because the feature set is only known after reading your download; the reasons are in [../maxine-vfx/README.md](../maxine-vfx/README.md).

Two uses:

- In a systemd unit: `EnvironmentFile=/usr/share/maxine-vfx/maxine-vfx.env`.
- In a shell, for one command or one session:

  ```bash
  set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
  ```

Never source the file from a login profile, `~/.bashrc` or `~/.profile`. The bundled CUDA 12 and TensorRT 10 libraries would then shadow the system libraries for every program you start. The bundled directories must be on `LD_LIBRARY_PATH` for the SDK, because Arch ships CUDA 13 and none of the `.so.12`, `.so.9` or `.so.10` sonames the SDK needs exist system-wide, and because the feature libraries are found by a plain `dlopen("libnvVFXGreenScreen.so")`.

## The compatibility shim

The SDK's model loader reads `/etc/os-release` and refuses distributions that are not on NVIDIA's list. The error it returns, `-1209` ("no kernel image is available for execution on the device"), is misleading: no CUDA error occurs, and only the `ID` and `VERSION_ID` fields are read.

`os-release-shim.so` is a compatibility shim for distributions the SDK does not list. It is an `LD_PRELOAD` library: inside a process that preloads it, a read-only open of exactly `/etc/os-release` opens the file named by the environment variable `MAXINE_OS_RELEASE` instead, and every other call passes through unchanged. Only that process is affected, the real file is untouched and no root is needed. The shim does not modify the SDK, the models or their encryption. NVIDIA does not support this configuration.

Set `MAXINE_OS_RELEASE_DEBUG=1` to make the shim log each redirect on stderr, which shows whether it is active. The package's environment file sets only `MAXINE_OS_RELEASE`.

### Deprecated names

The shim used to read `OMA_BROADCAST_OS_RELEASE` and `OMA_BROADCAST_OS_RELEASE_DEBUG`. Those names are deprecated but still read, for programs that have not been updated yet. They apply per variable, as follows:

- If the new name is set in the environment, even to an empty string, it is used and the old name is ignored.
- If only the old name is set, it is used, and the shim prints one note per process on stderr: `os-release-shim: OMA_BROADCAST_OS_RELEASE is deprecated, use MAXINE_OS_RELEASE` (and the same for `_DEBUG`).

The old names will be removed in a later release. Use the new names in anything you write.

The replacement file `/usr/lib/maxine-vfx/fake-os-release` reads:

```
NAME="Ubuntu"
VERSION_ID="24.04"
ID=ubuntu
ID_LIKE=debian
VERSION_CODENAME=noble
PRETTY_NAME="Ubuntu 24.04 LTS"
```

**Preload it on the final program only.** The shim removes `LD_PRELOAD` from the environment of the process that loads it, so that children do not inherit it. A wrapper such as `timeout`, `sh -c` or `cargo` that carries `LD_PRELOAD` loads the shim itself, drops the variable and starts the program without it, which then fails with `-1209`. Write `timeout 60 env LD_PRELOAD=... program`, not `LD_PRELOAD=... timeout 60 program`.

## Running a program

Manual run:

```bash
set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
env LD_PRELOAD=$MAXINE_VFX_OS_RELEASE_SHIM <program> [args]
```

### systemd user unit

Generic drop-in, for any user service that loads the SDK, at `~/.config/systemd/user/<service>.service.d/maxine.conf`:

```ini
[Service]
EnvironmentFile=/usr/share/maxine-vfx/maxine-vfx.env
Environment=LD_PRELOAD=/usr/lib/maxine-vfx/os-release-shim.so
```

Example for omarchy-broadcast, `~/.config/systemd/user/omarchy-broadcastd.service.d/maxine.conf`, with the same content:

```ini
[Service]
EnvironmentFile=/usr/share/maxine-vfx/maxine-vfx.env
Environment=LD_PRELOAD=/usr/lib/maxine-vfx/os-release-shim.so
```

Then:

```bash
systemctl --user daemon-reload
systemctl --user restart omarchy-broadcastd.service
```

Remove the file, reload and restart to go back to the unit without the SDK.

## The model directory

`MAXINE_VFX_MODEL_DIR` (`/opt/nvidia/maxine/videofx/lib/models`) holds the `.engine.trtpkg` model packages of every feature that has them, for the architectures you built the package with (`MAXINE_VFX_ARCHS`). A program passes it to the SDK as the effect parameter `NVVFX_MODEL_DIRECTORY`. If it is not set, the SDK looks in `./models`, which usually does not exist and gives `-13`.

## Engine cache

The SDK has an optional per-effect parameter `NVVFX_MODEL_CACHE_DIRECTORY` ("ModelCacheDir", a TRT-RTX cache directory; the default is `ModelDir/cache`) and `NVVFX_MODEL_CACHE_MODE` ("ModelCacheMode": 0 Auto, 1 Disabled, 2 ForceRegenerate). The application sets them with `NvVFX_SetString` and `NvVFX_SetU32`; there is no environment variable for them.

The 1.3.0.0 Linux models are prebuilt TensorRT engines for each architecture. After a successful SDK run on the reference machine, no `lib/models/cache` directory appeared in a user-writable install, so on Linux no cache appears to be written. This supports leaving `/opt` read-only. It was observed in a user-writable install, not on the packaged read-only tree.

The package therefore creates no shared cache directory: a world-writable engine cache would be a tampering risk. The default `ModelDir/cache` under `/opt` is owned by root and read-only.

Convention for a program that wants a cache: use a per-user directory, `${XDG_CACHE_HOME:-$HOME/.cache}/maxine-vfx`, and pass it as `ModelCacheDir`. In a systemd user unit, `CacheDirectory=maxine-vfx` provides it as `%C/maxine-vfx`. Every project of the same user then shares that directory.

## Referencing the package from another package

The SDK is a separate personal download, so a consumer's PKGBUILD should declare it as an optional dependency, not a hard one:

```bash
optdepends=('maxine-vfx-sdk-local: NVIDIA Maxine video effects')
```

The package also provides `maxine-vfx-sdk=1.3.0.0`. A consumer that needs particular features can check `MAXINE_VFX_FEATURES` in the environment file at run time; it lists the features that were packaged.

When you build the package for a consumer, name the features it needs with `MAXINE_VFX_FEATURES=<list>`: the build fails when one of them is missing from your download. omarchy-broadcast, for example, needs green screen and background blur, so build with `MAXINE_VFX_FEATURES=nvvfxgreenscreen,nvvfxbackgroundblur`, or with `MAXINE_VFX_FEATURES=all` to package everything you downloaded. `maxine-vfx/configure.sh --src <dir>` shows what your download holds and `--write` saves the choice in the git-ignored `maxine-vfx/selection.conf` (an environment variable overrides it). The GPU architectures you can package are in [gpu-support.md](gpu-support.md).

## Check the installation

```bash
pacman -Ql maxine-vfx-sdk-local | head
(set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
 ldd /opt/nvidia/maxine/videofx/lib/libVideoFXLocal.so | grep 'not found')
```

With the environment file applied, the `ldd` command prints nothing.

## Bundled cuDNN headers

NVIDIA's own tarball ships 8 dangling symlinks in `external/cuda`: 7 headers, `external/cuda/include/cudnn*.h -> /etc/alternatives/libcudnn*` (Debian's alternatives system, absent on Arch), and `external/cuda/lib/libcudnn.so -> libcudnn9.so.9`, whose target the SDK does not ship. The package keeps all 8 as shipped. Using the Video Effects API does not need them. A program that compiles against the bundled cuDNN headers, or links with `-lcudnn`, needs the real cuDNN from elsewhere.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `NvVFX_Load` returns `-1209`, "no kernel image is available" | `/etc/os-release` is not an accepted distribution. Not a real CUDA error | Preload the shim on the program itself (not on a wrapper), check that `MAXINE_OS_RELEASE` is an absolute path to a file with both `ID=` and `VERSION_ID=`, and run with `MAXINE_OS_RELEASE_DEBUG=1` to see the redirect. The deprecated old names still work, with a note on stderr: see [Deprecated names](#deprecated-names) |
| `NvVFX_CreateEffect` returns `-2` (unimplemented) | The feature libraries (for example `libnvVFXGreenScreen.so` and `libnvVFXBackgroundBlur.so`) are not found by `dlopen` | Apply the environment file, which puts `features/<feature>/lib` on `LD_LIBRARY_PATH`; check that the feature was in the package |
| `NvVFX_Load` returns `-13` ("file could not be found") | The model directory is wrong or the models are missing | Pass `MAXINE_VFX_MODEL_DIR` as `NVVFX_MODEL_DIRECTORY`; check that `ls /opt/nvidia/maxine/videofx/lib/models` shows `.trtpkg` files for your architecture |
| `libcudart.so.12`, `libnpp*.so.12`, `libcudnn.so.9` or `libnvinfer.so.10` not found | The bundled `external/cuda/lib` and `external/tensorrt/lib` are not on `LD_LIBRARY_PATH` | Apply the environment file and repeat the `ldd` check above |
| `ld.so: object '...os-release-shim.so' from LD_PRELOAD cannot be preloaded` | The shim is not at the path in `LD_PRELOAD`; the program runs without it | Check the path in the drop-in or command; the package installs it at `/usr/lib/maxine-vfx/os-release-shim.so` |
| `Cannot load libVideoFXTriton.so` in the SDK log | The Triton client library needs `libgrpcclient.so`, which is not used here | Harmless; ignore it |
