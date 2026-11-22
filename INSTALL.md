# Install the NVIDIA SDK packages

This guide builds and installs the local Arch Linux packages for the NVIDIA SDKs (software development kits: libraries, headers and AI models). You download each SDK from NVIDIA yourself, except TensorRT, which `makepkg` can download for you. The guided script `scripts/setup.sh` does the rest and asks before every step that changes anything. The licence terms are in [Licence and what you download](#licence-and-what-you-download).

| Package | SDK | AUR |
|---|---|---|
| `maxine-vfx-sdk-local` | Maxine Video Effects (VFX) 1.3.0.0 | `maxine-vfx-sdk-local` |
| `maxine-ar-sdk-local` | Maxine AR 1.2.0.0 | `maxine-ar-sdk-local` |
| `maxine-afx-sdk-local` | Maxine Audio Effects (AFX) 3.0.0 (package version 3.0.0.12) | `maxine-afx-sdk-local` |
| `nvidia-optical-flow-sdk-local` | Optical Flow 5.0.7 | `nvidia-optical-flow-sdk-local` |
| `nvidia-tensorrt-sdk-local` | TensorRT 11.4.0.106 | not on the AUR |

The AUR (Arch User Repository) packages are recipes only. Each builds from files that you download from NVIDIA. See [docs/aur.md](docs/aur.md). A package's full version is its SDK version, a dash and its release number (`pkgrel`). The recipe's `PKGBUILD` has both (`pkgver=` and `pkgrel=`), and the examples below write `<pkgrel>` for it.

## Before you start

You need:

- **An NVIDIA RTX GPU**, Turing (RTX 20 series) or newer. See [docs/gpu-support.md](docs/gpu-support.md).
- **Arch Linux or an Arch-based distribution** (for example Omarchy). It needs `pacman` (the package manager), `makepkg` (builds a package from a `PKGBUILD` recipe), and `fakeroot` and `bsdtar` (helper tools `makepkg` uses). This command installs them:

  ```bash
  sudo pacman -S --needed base-devel fakeroot libarchive
  ```

- **The NVIDIA driver**, version 570.26 or newer, so that `nvidia-smi` works. Check it with:

  ```bash
  nvidia-smi
  ```

- **Free disk space**: about 3 GiB for a download and about 13 GiB for one build. Sizes in these documents are in MiB or GiB (2^20 and 2^30 bytes), or in GB (10^9 bytes), as stated.
- **A free NVIDIA Developer Program account.** You log in with it to download the Maxine and Optical Flow SDKs. TensorRT needs no login.
- **For the three Maxine SDKs only:** the NGC command line tool and a personal API key. NGC (NVIDIA GPU Cloud) is NVIDIA's online catalogue where it publishes the Maxine SDKs. The API key is the password the tool uses. Step 3 below explains how to get both.
- **For TensorRT only:** Arch's `cuda` package, version 13.4 or newer and below 14. `pacman -U` pulls it in when it is missing.

The Optical Flow SDK and TensorRT need no NGC. The Optical Flow SDK is one file that you download in a browser. TensorRT is one file that `scripts/setup.sh` or `makepkg` downloads from NVIDIA, or that you download in a browser.

## Install with the guided script

Every command runs from the root of this repository.

1. **Get this repository.**

   ```bash
   git clone https://github.com/rsd/omarchy-nvidia-sdks.git
   cd omarchy-nvidia-sdks
   ```

2. **Look first.** A dry run checks your machine and prints every command it would run. It changes nothing and asks nothing.

   ```bash
   scripts/setup.sh --dry-run
   ```

   *Success:* the output ends with `Dry run: nothing was asked, run or written.` A line with `WARNING` names something missing and how to fix it (for example a missing `base-devel`). Fix those, then run it again.

3. **Download the SDK. This step is yours.** Pick the SDK or SDKs first:

   | You want | `--sdk` key | How you get it |
   |---|---|---|
   | AI green screen, background blur, video noise removal | `vfx` | NGC |
   | Eye contact, face detection | `ar` | NGC |
   | Microphone noise and room echo removal, Studio Voice | `afx` | NGC |
   | Optical Flow | `of` | Browser |
   | TensorRT | `trt` | Automatic (or a browser download you save in `~/Downloads`) |

   - **Maxine SDKs (`vfx`, `ar`, `afx`):** set up NGC once.
     1. Log in to your NVIDIA Developer Program account.
     2. On the SDK's NGC catalogue page, select **Get Access** and accept NVIDIA's licence.
     3. Create a personal API key that includes the **NGC Catalog** service.
     4. Install the NGC command line tool, `ngc`.
     5. Run this yourself and paste the key at its prompt:

        ```bash
        ngc config set
        ```

     [docs/download.md](docs/download.md#prerequisites) has the exact links and commands. The download itself (`download.sh`) runs later, in step 5.
   - **Optical Flow (`of`):** open the download page in a browser, log in, accept the licence and save `optical_flow_sdk_5.0.7.zip` in `~/Downloads`. See [docs/optical-flow.md](docs/optical-flow.md#download).
   - **TensorRT (`trt`):** nothing to do if you have no copy. When `scripts/setup.sh` finds none in `~/Downloads`, `makepkg` downloads it from NVIDIA with no login, during the build. Read NVIDIA's TensorRT licence first: the script names it, and by building you accept it. To use your own copy, download `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst` in a browser and save it in `~/Downloads`. Take the Linux x86_64 build, not ARM. See [docs/tensorrt.md](docs/tensorrt.md#download).

   *Success:* for NGC, `scripts/check-ngc.sh` (next step) accepts your key. For a browser download, the file is in `~/Downloads`.

4. **Check your NGC key (Maxine SDKs only).** This is read-only. It never prints, logs or stores a key.

   ```bash
   scripts/check-ngc.sh
   ```

   *Success:* every line says `OK` and the exit status is 0. After each `FAIL` it prints a hint. One `FAIL` is harmless if you do not need that effect: HTTP 402 for the Early Access model `afx_speaker_focus` means your key works but your account lacks that approval. The options and the meaning of each result are in [docs/download.md](docs/download.md#check-your-ngc-credentials). To check a key that is not in the NGC tool, run the command below and type the key at the prompt, which does not echo it. Never write `NGC_API_KEY=... scripts/check-ngc.sh`: your shell keeps that line in its history.

   ```bash
   scripts/check-ngc.sh --key --no-cli
   ```

5. **Run the guided setup.** Name the SDKs you chose. The script asks before every step that changes anything (the default answer is No) and prints each command it runs. It finds your download, offers to run `download.sh` for a Maxine SDK, builds the package with `makepkg`, installs it with `sudo pacman -U`, and checks the result.

   ```bash
   scripts/setup.sh --sdk vfx
   ```

   Replace `vfx` with `ar`, `afx`, `of`, `trt`, or a comma separated list such as `vfx,afx`. The build takes several minutes, and the installed package is several GiB.

   *Success:* the `== 7. Check` section shows `ok` in every column for your SDK and the script exits with status 0. Check the status with `echo $?`, which prints `0`. Section `== 8. Undo` then prints the commands that remove what it installed.

6. **Use it.** A program loads the package's environment file and, for Maxine, preloads a small shim. [docs/usage.md](docs/usage.md) shows how.

The script is safe to run again. It detects and keeps what is done: a valid download, a `selection.conf`, a built package, the installed version, features already copied in.

### Script options

| Option | Effect |
|---|---|
| `--sdk LIST` | The SDKs to set up, comma separated: `vfx`, `ar`, `afx`, `of`, `trt`, or `all`. Without it the script asks about each one. `maxineea` is a placeholder that only prints how to request Early Access; `all` skips it |
| `--features-KEY LIST` | The optional downloads of one SDK (`--features-vfx`, `--features-ar`, `--features-afx`): names, numbers or `all`. `all` leaves out the effects marked "access required" |
| `--src-KEY PATH` | Where the download of one SDK is (`--src-vfx`, `--src-ar`, `--src-afx`, `--src-of`, `--src-trt`) |
| `--dry-run` | Read-only: check, detect and print the commands; ask nothing, change nothing |
| `-h`, `--help` | Print the options, where each SDK comes from and every SDK's feature list |

The exit status is 0 when the run is done, 1 for a hard blocker or a failed step, and 2 for a usage error. The full reference, with the environment variables and what each stage does, is in [docs/setup-script.md](docs/setup-script.md#options).

## Install one package by hand

The guided script runs these commands for you, and prints each one before it runs it. Run them yourself if you prefer. Only `scripts/setup.sh` runs `sudo` or installs anything on its own, and it asks first. `download.sh`, `configure.sh` and the PKGBUILDs never do. This example is the Video Effects SDK. `download.sh` asks NGC what exists, shows what it would download and how big it is, asks for confirmation and downloads only what is missing, by default into `~/Downloads/maxine`. `sm_120` names a GPU architecture: SM (streaming multiprocessor) plus the GPU's compute capability (CC) without the dot, here `12.0` for an RTX 50 series card. Replace it with your own, from the first command's output:

```bash
nvidia-smi --query-gpu=compute_cap --format=csv,noheader
maxine-vfx/download.sh
maxine-vfx/configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
cd maxine-vfx && makepkg -f
sudo pacman -U maxine-vfx-sdk-local-*.pkg.tar*
```

`configure.sh` saves the choice in `maxine-vfx/selection.conf`, and `makepkg` reads it. Run the last command in `maxine-vfx/`, where `makepkg` left the package. For the other SDKs, the build inputs, the features and the GPU architectures, see:

- [maxine-vfx/README.md](maxine-vfx/README.md), [maxine-ar/README.md](maxine-ar/README.md) and [maxine-afx/README.md](maxine-afx/README.md): build inputs and commands for each Maxine SDK;
- [docs/download.md](docs/download.md#download-with-one-command): the options of `download.sh` (`--dry-run` to look without downloading, `--preset all` for every feature, `--yes` to skip the question), the [features](docs/download.md#features) with their NGC names and sizes, the [manual `ngc` commands](docs/download.md#download-by-hand), and the [next step](docs/download.md#next-step) after a download;
- [docs/gpu-support.md](docs/gpu-support.md): which GPUs are supported and how to find your architecture;
- [docs/optical-flow.md](docs/optical-flow.md) and [docs/tensorrt.md](docs/tensorrt.md): the steps for Optical Flow and TensorRT.

## Check that it works

The guided script checks every install it makes: its `== 7. Check` section is read-only and prints one line per SDK, like this for the Video Effects SDK:

```
  SDK    package                          env    libpath  ldd    files
  vfx    maxine-vfx-sdk-local 1.3.0.0-<pkgrel> ok     ok       ok     ok
```

To check by hand, run these commands for the Video Effects package:

```bash
pacman -Q maxine-vfx-sdk-local
(set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
 ldd /opt/nvidia/maxine/videofx/lib/libVideoFXLocal.so | grep 'not found')
```

Expect `maxine-vfx-sdk-local 1.3.0.0-<pkgrel>` from the first command and nothing from the second: nothing printed means that every library is found. For TensorRT, both of these must print `11.4.0.106`:

```bash
grep '^NVIDIA_TRT_VERSION' /usr/share/nvidia-tensorrt/nvidia-tensorrt.env
PKG_CONFIG_PATH=/opt/nvidia/tensorrt/lib/pkgconfig pkg-config --modversion nvidia-tensorrt
```

The checks for each SDK are in [docs/usage.md](docs/usage.md#check-the-installation), [docs/optical-flow.md](docs/optical-flow.md#check-the-installation) and [docs/tensorrt.md](docs/tensorrt.md#check-the-installation).

## Troubleshooting

| What you see | What it means and what to do |
|---|---|
| `HTTP 402`, or an effect is skipped | Your key works, but your account has no access to that one model (for example the Early Access effect `speaker_focus`). The script skips it and goes on. Request access on the model's NGC page, or leave the effect out. `--features-afx all` already leaves it out. See [HTTP 402](docs/download.md#http-402-the-key-works-the-account-has-no-access) |
| `403`, `could not be found`, or `check-ngc.sh` prints `FAIL` | Run `scripts/check-ngc.sh`. It tells a missing key, an expired key, missing Maxine access and a missing entitlement apart. Most often you skipped **Get Access** or ran `ngc config set` with the wrong organisation. See [Troubleshooting](docs/download.md#troubleshooting) |
| `ngc` not found | The NGC tool is not installed, or `~/.local/bin` is not on your `PATH`. See [step 3 of the NGC setup](docs/download.md#3-install-the-ngc-cli) |
| The script cannot find your download | It prints the manual steps and waits. Save or download the file, then press Enter to check again, or give its place with `--src-vfx PATH` (or `--src-ar`, `--src-afx`, `--src-of`, `--src-trt`). For TensorRT it does not wait: `makepkg` downloads the file instead |
| TensorRT: `this is the ARM (aarch64) build` or `is not the archive this recipe packages` | You have the wrong file: the ARM build, or a `cuda-12.9` build instead of `cuda-13.4`. Download the Linux x86_64 `cuda-13.4` file. See [docs/tensorrt.md](docs/tensorrt.md#download) |
| TensorRT: `makepkg would stop on it instead of downloading`, or `selection.conf is not valid` | A source is named but missing (a stale `selection.conf`, or `--src-trt` or `NVIDIA_TRT_SRC` pointing at nothing), or the `selection.conf` is not valid. The script stops for TensorRT and deletes nothing. Fix the path, or remove `selection.conf`, so that `makepkg` downloads the archive |
| `WARNING` about disk space, `base-devel`, `fakeroot` or `bsdtar` | Free the space, or run the `pacman -S --needed` command from the warning (the command in [Before you start](#before-you-start)) |
| `WARNING` that the GPU or driver is too old | The SDKs need Turing (`sm_75`) or newer and driver 570.26 or newer. Update the driver, or this GPU cannot run them |
| `pacman -U` stops on files that "exist in filesystem" | You copied Audio Effects effects in by hand earlier. The script prints the `sudo rm -r` command that clears them and asks first. See [Stage 5: install](docs/setup-script.md#stage-5-install) |
| `pacman -U` stops on `cuda` (TensorRT) | The installed CUDA is outside 13.4 to 14. See [docs/tensorrt.md](docs/tensorrt.md#versions-and-cuda) |

For problems after the install, see the troubleshooting tables in [docs/usage.md](docs/usage.md#troubleshooting), [docs/optical-flow.md](docs/optical-flow.md#troubleshooting) and [docs/tensorrt.md](docs/tensorrt.md#troubleshooting).

## Uninstall

The script prints the removal commands in section `== 8. Undo` and never runs them. Run the `sudo pacman -R` command it printed. For one package:

```bash
sudo pacman -R maxine-vfx-sdk-local
sudo pacman -R maxine-ar-sdk-local
sudo pacman -R maxine-afx-sdk-local
sudo pacman -R nvidia-optical-flow-sdk-local
sudo pacman -R nvidia-tensorrt-sdk-local
```

If you added Audio Effects effects by hand after the install ([stage 6](docs/setup-script.md#stage-6-features-added-after-the-install-audio-effects)), `pacman` does not own them. Remove those feature directories first. The undo section names them:

```bash
sudo rm -r <feature directories>
```

## Details

### Licence and what you download

- **Nothing from NVIDIA is redistributed.** This repository holds only the build recipes: PKGBUILDs, scripts, documentation and the source of a small compatibility shim.
- **You accept NVIDIA's licence, and you download the SDK yourself**, with your own account where NVIDIA asks for one: from NVIDIA NGC for the Maxine SDKs, and in a browser from NVIDIA's developer site for the Optical Flow SDK. TensorRT is also served by NVIDIA without a login, and `makepkg` can download it for you under NVIDIA's TensorRT Software License Agreement, or you can download it in a browser. Apart from that download, the recipes only automate what happens after your download.
- **The built package contains NVIDIA software and is for your own machine only.** Never upload it to a package repository, to the AUR as a binary, to a release page, or share it in any other way.
- NVIDIA does not support this configuration.
- This is not legal advice. Read the licence you accept.

The full terms are in [Licences and caveats](README.md#licences-and-caveats).

### What you do yourself

The script never logs in to NGC, never accepts a licence and never runs `ngc config`. Accepting the licence and creating the key are acts of your own account, with your own agreement to NVIDIA's terms. These steps stay with you:

- Log in to NVIDIA, accept the licence and download a file in a browser.
- Create the NGC API key and enter it with `ngc config set`. Never paste a key into a chat or a shared document.
- Answer `y` to a `sudo` command.

The script reads a key only from the `NGC_API_KEY` environment variable or from a hidden prompt, and it never prints, logs or stores it.

### The key and `sudo`

Only the optional Audio Effects post-install step handles a key: it hands the key to NVIDIA's `download_features.sh`, which itself puts it on a command line. To avoid that, fetch the effects with `download.sh --features` before the build. The rules are in [docs/setup-script.md](docs/setup-script.md#the-key).

The script runs `sudo` for these commands only, each shown first, each confirmed with a y/N whose default is No, and none in a dry run:

| Command | Purpose |
|---|---|
| `sudo pacman -U <package>` | Install a package you built |
| `sudo rm -r <feature directories>` | Remove hand-copied Audio Effects feature directories that a new package contains, so that `pacman -U` can install it |
| `sudo cp -R --no-preserve=ownership <feature directories> <installed features directory>` | Copy Audio Effects effects added after the install |

It never runs `pacman -R`, `makepkg -i` or `makepkg -s`.
