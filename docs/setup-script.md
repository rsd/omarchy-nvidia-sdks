# How the guided script works

This page is the reference for `scripts/setup.sh`: its options, its variables, what each stage does, how it handles an NGC key and which commands use `sudo`. You do not need it to install a package: [INSTALL.md](../INSTALL.md) has the steps. To add an SDK to the script, see [Adding an SDK to the script](maintainers.md#adding-an-sdk-to-the-script).

The script knows five SDKs and one placeholder:

- The Maxine Video Effects, AR and Audio Effects SDKs, downloaded from NGC (NVIDIA GPU Cloud).
- The Optical Flow SDK and TensorRT, each one file. You download the Optical Flow SDK in a browser. For TensorRT, the script uses the file in `~/Downloads` if there is one. If there is none, `makepkg` downloads it from NVIDIA when the build runs.
- A Maxine Early Access entry that is not installable yet.

The script is a convenience over the per-package steps in [download.md](download.md) and the package READMEs. It does not replace them. It prints every step first as a command you could type yourself.

It has no per-SDK code: each SDK is a descriptor in `scripts/setup.d/`, and `--sdk LIST` picks from them. A dry run takes the default selection of optional features and runs no `sudo`.

## Options

| Option | Effect |
|---|---|
| `--sdk LIST` | The SDKs to set up, comma separated: `vfx`, `ar`, `afx`, `of`, `trt`, `maxineea`, or `all`. Without it the script asks about each one (default answer: No). `maxineea` is a placeholder that only prints how to request Early Access (see [The Maxine Early Access entry](#the-maxine-early-access-entry)); `all` skips it |
| `--features-KEY LIST` | The optional downloads of one SDK that has any (`--features-vfx`, `--features-ar`, `--features-afx`; KEY as in `--sdk`), comma separated: names from the SDK's list, their numbers, or `all`. `all` is every effect except those marked "access required" (see [Effects that need access](#effects-that-need-access)), which you choose by name or number. Without the option the script shows the list and asks: numbers or names, `all`, or Enter for the default (marked `[x]`). A dry run takes the default. The Optical Flow SDK and TensorRT have no optional features. `scripts/setup.sh --help` prints every SDK's feature list |
| `--src-KEY PATH` | Where the download of one SDK is (`--src-vfx`, `--src-ar`, `--src-afx`, `--src-of`, `--src-trt`). For an NGC SDK, its download directory. For an SDK downloaded as one file, that file, the directory that holds it or its extracted tree. It comes before the `*_SRC` variable, the package's `selection.conf` and the default location |
| `--dry-run`, `--print-commands` | Read-only: check, detect and print the commands; ask nothing, change nothing |
| `-h`, `--help` | Print the options, where each SDK comes from and the lists of optional features of each SDK |

Examples:

```bash
# look first: every SDK, the default selection
scripts/setup.sh --dry-run

# Audio Effects, every effect that is not "access required"
scripts/setup.sh --sdk afx --features-afx all

# TensorRT only
scripts/setup.sh --sdk trt

# one named effect instead of the default
scripts/setup.sh --sdk afx --features-afx superres-16k_to_48k

# look at two SDKs
scripts/setup.sh --sdk vfx,afx --dry-run

# by number; 11 needs access (see below)
scripts/setup.sh --sdk afx --features-afx 2,4,11
```

Without `--sdk` the script asks, for each SDK, whether to set it up (Video Effects, AR, Audio Effects, Optical Flow, TensorRT and the Early Access entry). An empty answer or the end of input means No.

The exit status is 0 when the run is done (an SDK you skipped is not a failure), 1 for a hard blocker or a failed step, and 2 for a usage error.

### Feature names

`scripts/setup.sh --help` is the reference. The names are those of the SDK's `download.sh --features`. For the Video Effects and AR SDKs they are the NGC names of the features (`nvvfxgreenscreen`, `nvargazeredirection`, and so on; see [download.md](download.md#features) and [download.md](download.md#ar-sdk-features)). For the Audio Effects SDK each effect is `<feature>-<rate>`:

| Name | Effect | Default |
|---|---|---|
| `denoiser-16k`, `denoiser-48k` | Noise removal | 48k |
| `dereverb-16k`, `dereverb-48k` | Room echo removal | 48k |
| `dereverb_denoiser-16k`, `dereverb_denoiser-48k` | Noise and room echo removal in one effect | 48k |
| `superres-8k_to_16k`, `superres-16k_to_48k` | Audio super resolution | none |
| `studio_voice-16k`, `studio_voice-48k` | Studio Voice | 48k |
| `speaker_focus-16k`, `speaker_focus-48k` | Speaker focus (access required: Maxine Early Access) | none |

### Environment variables

| Variable | Meaning |
|---|---|
| `MAXINE_VFX_SRC`, `MAXINE_AR_SRC`, `MAXINE_AFX_SRC`, `NVIDIA_OF_SRC`, `NVIDIA_TRT_SRC` | The download of an SDK, as for `configure.sh` and `makepkg`. Without them the script uses the location in the package's `selection.conf`, then the default (`~/Downloads/maxine`, `~/Downloads/maxine/ar-sdk`, `~/Downloads/maxine/afx-sdk`, and `~/Downloads` for the Optical Flow SDK and TensorRT) |
| `NGC_API_KEY` | The key for NVIDIA's `download_features.sh`, used only by the Audio Effects post-install step (see [The key](#the-key)) |
| `MAXINE_SETUP_ROOT` | A prefix for `/opt` and `/usr/share`. It exists for the script's own tests; leave it empty |

## Stage 1: preflight

Read-only. The script reports what it finds and explains how to fix what is missing. It fixes nothing itself.

- Arch Linux and `pacman`. Without `pacman` or without `makepkg` the script stops.
- `base-devel` (the group that holds `makepkg` and the build tools), `fakeroot` and `bsdtar` (warnings, with the `pacman -S --needed` command to install them).
- The GPU, driver and compute capability from `nvidia-smi`, the resulting `sm_<N>` architecture, a warning for a GPU older than Turing (`sm_75`) or a driver older than 570.26. `nvidia-smi` is queried once, which wakes a sleeping discrete GPU.
- Free disk space for the download directory (at least 3 GiB) and for the build directory (13.2 GiB for one SDK: the assembled tree of about 4.4 GiB, `makepkg`'s copy of it and the package). Both figures are sized for the Video Effects SDK; the TensorRT package is several GiB as well, and the Optical Flow SDK is much smaller.
- Whether the NGC CLI (the `ngc` command line tool) is on `PATH`. Only `download.sh` needs it, so only the NGC SDKs.

## Stage 2: your download

For each SDK you chose, the script finds the download directory and validates it offline. It runs the package's `configure.sh --src DIR`, which reads the directory without network access, and checks every `.trtpkg.md5` checksum file against the model beside it. A download that `configure.sh` accepts and whose checksums match is valid.

Before the download is checked, you choose the SDK's optional features. The script shows a numbered list of every optional feature of the SDK:

- the default selection is marked `[x]`;
- the features that need NVIDIA's approval are marked `[access required: Maxine Early Access]`, followed by the page where to request it.

The list is read from the package's `download.sh`, so it is the list of `download.sh --features`. Answer with numbers or names, `all`, or Enter for the default. The features are fetched together with the SDK, before the build, so the package contains them and pacman owns them.

If the download is valid but lacks a selected feature, the script prints the `download.sh --features` command for the missing ones. If there is no usable download, it prints the manual steps and waits (for TensorRT it does not wait; see below). For an NGC SDK these steps are yours. They are the five steps of step 3 in [INSTALL.md](../INSTALL.md#install-with-the-guided-script), and [download.md](download.md#prerequisites) has the details of each.

The script then offers to run `download.sh` for you. It does so only if `ngc` is on `PATH`, and only after a y/N. `download.sh` shows the sizes and asks again before it downloads. Whether you let it or ran the command yourself, press Enter to re-check the directory, or `s` to skip the SDK. The loop repeats until the download is valid or you skip.

### The Optical Flow SDK and TensorRT

These are one file each, so there is no NGC step, no `download.sh` and no optional feature. A missing Optical Flow download prints these steps, naming the SDK's licence, and never mentions NGC:

1. Join the NVIDIA Developer Program, or log in to your account.
2. Open the SDK's download page (`https://developer.nvidia.com/opticalflow/download` or `https://developer.nvidia.com/tensorrt/download`).
3. Read the licence (the NVIDIA DesignWorks SDK License, or the NVIDIA TensorRT Software License Agreement) and select "Accept & Download" for the file the script names: `optical_flow_sdk_5.0.7.zip`, or `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst`.
4. Save it in `~/Downloads` (where the script looks), or give its location with `--src-of PATH` or `--src-trt PATH`: the file, the directory holding it or its extracted tree.

Then press Enter to re-check, or `s` to skip the SDK. The script validates the download with the package's `configure.sh --src`, which reads the zip or archive without extracting it and checks its version.

- Later `configure.sh --write` records the choice, with the SHA-256 of a zip or archive.
- The by-hand steps are in [optical-flow.md](optical-flow.md#download) and [tensorrt.md](tensorrt.md#download).
- The script then runs `makepkg` with the file it has checked, passed in `NVIDIA_TRT_SRC`, so the TensorRT build downloads nothing.
- The Optical Flow recipe was written against NVIDIA's documented layout of the SDK, not a real archive: if your zip differs, `configure.sh` stops with an error that names what it did not find.

### TensorRT without a file

The script does not stop at a missing download. It prints that `makepkg` will download `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst` from NVIDIA when it builds and checks it against the SHA-256 the recipe pins. It names NVIDIA's TensorRT Software License Agreement: read it before you build, because by building you accept it. It gives the by-hand route for a copy you download yourself, in [tensorrt.md](tensorrt.md#download).

- It writes no `selection.conf` (stage 3 prints `Selection: none`) and runs `makepkg` without `NVIDIA_TRT_SRC`.
- A source that is named but missing, or a `selection.conf` that is not valid, stops TensorRT with a message and deletes nothing. Fix the source, or remove `selection.conf`, so that `makepkg` downloads the file.

### An SDK tree you extracted yourself

An SDK tree you extracted yourself (see [Alternative: an existing SDK tree](download.md#alternative-an-existing-sdk-tree)) is packaged as it is. `download.sh` cannot add features to it, so the script prints the commands to fetch a download directory of its own and to select that instead.

## Stage 3: selection

If the SDK has no `selection.conf`, the script prints the `configure.sh --src DIR --archs sm_<N> --features all --write` command with your detected architecture and asks before writing it. `--features all` means that everything in your download is packaged, so the selection of features happened at download time. If a `selection.conf` exists it is shown and kept unless you agree to replace it. For TensorRT with no file found, it prints `Selection: none` and writes nothing: `makepkg` downloads the file and the build needs no `selection.conf`.

## Stage 4: build

`makepkg -f` runs in the package directory (with `PKGEXT=.pkg.tar`) after a y/N, because it takes several GiB and a while. An already built package is reused only when it is current. It is rebuilt in these cases:

- this run changed the download or the selection;
- `selection.conf` is newer than the package;
- the download holds files newer than the package.

## Stage 5: install

The script prints `sudo pacman -U <package>` and runs it only after a y/N. It never runs `makepkg -i` or `makepkg -s`. If the SDK is already installed at the version the recipe builds, the download, build and install are skipped.

If you added Audio Effects effects by hand earlier (stage 6) and the new package now contains them, `pacman -U` would stop with "exists in filesystem" because no package owns those directories. The script detects this, prints `sudo rm -r` of exactly those directories, and runs it only after a y/N, before the install. If you decline, it does not install and prints both commands for you to run.

## Stage 6: features added after the install (Audio Effects)

Audio Effects effects you did not fetch before the build can be added after the install with NVIDIA's own `download_features.sh`, which the package installs under `/opt/nvidia/maxine/afx/features`. The script compares your selection with what is packaged and what is already there, and handles only the effects that are in neither:

1. It asks before downloading, then takes the NGC API key (see [The key](#the-key)).
2. It runs `download_features.sh` from the installed `features/` directory, once per feature, into a new directory below `~/Downloads/maxine/afx-features` that exists for this run only. One run per feature means that an answer of HTTP 402 for one feature skips only that feature: the script says that your key works but the account has no access to that model, names the model's NGC page, and carries on with the others. A skipped feature is not a failed setup.
3. It checks the checksums of the download.
4. It prints `sudo cp -R --no-preserve=ownership` of only the requested feature directories into the installed `features/` directory and runs it after a y/N. `--no-preserve=ownership` makes the copy owned by root. The temporary download directory is removed after a successful copy.

Caveats of this route:

- The copied files are outside pacman's ownership. `pacman -R` does not remove them, and a later package that contains them needs the `sudo rm -r` of stage 5. The undo commands at the end of the run name them.
- An effect whose feature is in the package, but at another sample rate, is not added this way, because its directory belongs to the package. The script prints the `download.sh --features` command and the rebuild instead.
- Effects that need access (speaker focus) are skipped when your account has none: see [Effects that need access](#effects-that-need-access).
- To have an effect packaged instead, fetch it with `download.sh --features` before the build.

## Stage 7: check

Read-only. See [Check that it works](../INSTALL.md#check-that-it-works) in INSTALL.md. For each SDK the script checks the installed package, the environment file, the library path, `ldd` of the core library with that path, and the models for your architecture, and it prints one line per SDK with notes for anything missing. The checks differ by SDK:

- **Maxine SDKs:** package, environment file, `ldd`, models for your architecture.
- **Optical Flow:** the driver's `libnvidia-opticalflow.so.1` on the system, the headers, and the FRUC libraries when packaged. No models.
- **TensorRT:** `libnvinfer.so`, the headers and the pkg-config file. No models.

## Stage 8: undo

Printed, never run: the `sudo rm -r` of the copied feature directories (first, because pacman does not own them) and `sudo pacman -R` of the installed packages.

## Effects that need access

Of the Audio Effects SDK's effects, `speaker_focus` (16k and 48k) is part of NVIDIA Maxine Early Access: NGC lists it as "available by request only", and an account without that approval is not entitled to download it. The other effects are generally available. Request access at <https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/models/afx_speaker_focus>. The status of every Audio Effects model is in [download.md](download.md#afx-sdk-model-status).

- `setup.sh` labels such effects `[access required: Maxine Early Access]` in its list, with that page.
- `--features-afx all` leaves them out, so `all` works for an account without access.
- Naming or numbering one still selects it, with a note that NGC answers HTTP 402 without approval.
- When NGC answers HTTP 402, the key is valid but the account is not entitled to the model. The download of that effect is skipped, with a message that names the model's NGC page, and the setup goes on with the rest. That holds before the build (`maxine-afx/download.sh` skips the effect and still exits 0 when other effects were fetched; see [download.md](download.md#http-402-the-key-works-the-account-has-no-access)) and after the install (stage 6).
- `scripts/check-ngc.sh` tells you beforehand whether your account has the access: see [download.md](download.md#check-your-ngc-credentials).

## The key

The only step that handles a key is the optional Audio Effects post-install step. `download.sh` and `configure.sh` never do.

- The script takes `NGC_API_KEY` from the environment when it is set. Otherwise it asks for it with no echo after you agree to the download, and an empty answer skips the step.
- The key is held in a shell variable that is not exported. The script never prints, logs or stores it and never puts it on a command line. It hands it only to `download_features.sh`, in that one process's environment.
- The step refuses to run under `bash -x`, which would print the key.
- Each `download_features.sh` run gets a private `TMPDIR` (mode 700) that is removed afterwards, also after an error or an interrupt. NVIDIA's script writes the NGC token it obtains to a file in `TMPDIR` and never deletes it, so a private directory leaves nothing behind. Its fixed paths `/tmp/temp_list` and `/tmp/temp_lib.tar.gz` (file lists and libraries, no key) cannot be redirected.
- NVIDIA's `download_features.sh` itself passes the key to `curl` or `wget` on their command line, so it is visible in the process list while that script runs. This script cannot prevent that.

If this matters to you, fetch the effects with `download.sh --features` before the build instead: that route needs only your configured NGC CLI.

To check a key before you use it, run the command below. It reads a key at a prompt without echo and checks it against NGC, without printing, logging or storing it. See [Check your NGC credentials](download.md#check-your-ngc-credentials).

```bash
scripts/check-ngc.sh --key
```

## Commands that use `sudo`

The script runs `sudo` for these commands only, each shown first, each confirmed with a y/N whose default is No, and none in a dry run:

| Command | Purpose |
|---|---|
| `sudo pacman -U <package>` | Install a package you built |
| `sudo rm -r <feature directories>` | Remove hand-copied Audio Effects feature directories that a new package contains, so that `pacman -U` can install it |
| `sudo cp -R --no-preserve=ownership <feature directories> <installed features directory>` | Copy Audio Effects effects added after the install |

It never runs `pacman -R`, `makepkg -i` or `makepkg -s`. Besides `sudo`, it runs `download.sh`, `configure.sh --write` and `makepkg -f` only after a y/N, and it queries `nvidia-smi` once.

## The Maxine Early Access entry

`--sdk maxineea` is a placeholder for the Maxine Early Access collection on NGC, which is private and available by request only. It is listed as "access required". Choosing it (with `--sdk maxineea`, or by answering yes to its question) only prints how to request access, with the collection's page and the licence it is under. It is never downloaded, configured, built, installed or verified, it needs no package directory, and `--sdk all` skips it with one line. It becomes installable once a maintainer adds the item names (visible only after access is granted) and a package directory.
