# Guided setup

`scripts/setup.sh` takes you from nothing to installed local packages of the SDKs you download yourself. It checks your machine, finds and validates your NGC download of each SDK, lets you choose the optional features, runs `configure.sh` and `makepkg`, installs the package, adds Audio Effects effects after the install if you ask for them, checks the result and prints the commands that undo it.

It is a convenience over the per-package steps in [download.md](download.md) and the package READMEs, not a replacement for them. Every step it runs is printed first as a command you could type yourself, so the whole procedure can also be done by hand. The licence terms in the "Licence and personal use" section of the [README](../README.md) apply unchanged: you accept NVIDIA's licence and you download the SDK with your own account.

## Start with a dry run

```bash
scripts/setup.sh --dry-run
```

A dry run is read-only. It runs the preflight checks and the detection of your downloads, asks nothing, writes nothing, runs no `sudo`, and prints every command it would run. It takes the default selection of optional features. Run it first to see what the real run would do on your machine. `--print-commands` is an alias.

Then run the script for real:

```bash
scripts/setup.sh
```

Without `--sdk` it asks, for each SDK, whether to set it up (Video Effects, AR, Audio Effects). Every question defaults to No: an empty answer or the end of input means No.

## Options

| Option | Effect |
|---|---|
| `--sdk LIST` | The SDKs to set up: `vfx`, `ar`, `afx` (comma separated) or `all`. Without it the script asks for each one |
| `--features-KEY LIST` | The optional features of one SDK (`--features-vfx`, `--features-ar`, `--features-afx`), as names, as their numbers in the list, or `all`, comma separated. Without it the script shows the list and asks |
| `--dry-run`, `--print-commands` | Read-only: check, detect and print the commands; ask nothing, change nothing |
| `-h`, `--help` | Print the options and the full lists of optional features of each SDK |

Environment variables:

| Variable | Meaning |
|---|---|
| `MAXINE_VFX_SRC`, `MAXINE_AR_SRC`, `MAXINE_AFX_SRC` | The download directory of an SDK, as for `configure.sh` and `makepkg`. Without them the script uses the directory in the package's `selection.conf`, then the default directory (`~/Downloads/maxine`, `~/Downloads/maxine/ar-sdk`, `~/Downloads/maxine/afx-sdk`) |
| `NGC_API_KEY` | The key for NVIDIA's `download_features.sh`, used only by the Audio Effects post-install step (see [The key](#the-key)) |
| `MAXINE_SETUP_ROOT` | A prefix for `/opt` and `/usr/share`. It exists for the script's own tests; leave it empty |

The exit status is 0 when the run is done (an SDK you skipped is not a failure), 1 for a hard blocker or a failed step, and 2 for a usage error.

## The steps

Running the script again is safe. What is already done is detected and kept: a valid download, a `selection.conf`, a built package, the installed version, features already copied in.

### 1. Preflight

Read-only. The script reports what it finds and explains how to fix what is missing, but it fixes nothing.

- Arch Linux and `pacman`. Without `pacman` or without `makepkg` the script stops.
- `base-devel`, `fakeroot` and `bsdtar` (warnings, with the `pacman -S --needed` command to install them).
- The GPU, driver and compute capability from `nvidia-smi`, the resulting `sm_<N>` architecture, a warning for a GPU older than Turing (`sm_75`) or a driver older than 570.26. `nvidia-smi` is queried once, which wakes a sleeping discrete GPU.
- Free disk space for the download directory (at least 3 GiB) and for the build directory (13.2 GiB for one SDK: the assembled tree of about 4.4 GiB, `makepkg`'s copy of it and the package).
- Whether the NGC CLI is on `PATH`. It is needed only by `download.sh`.

### 2. Your download

For each SDK you chose, the script finds the download directory and validates it offline. It runs the package's `configure.sh --src DIR`, which reads the directory without network access, and checks every `.trtpkg.md5` checksum file against the model beside it. A download that `configure.sh` accepts and whose checksums match is valid.

Before the download is checked, you choose the SDK's optional features. The script shows a numbered list of every optional feature of the SDK, with the default selection marked `[x]` and Early Access features marked `[Early Access]`. The list is read from the package's `download.sh`, so it is the list of `download.sh --features`. Answer with numbers or names, `all`, or Enter for the default. `--help` prints the lists without running anything. The features are fetched together with the SDK, before the build, so the package contains them and pacman owns them.

If the download is valid but lacks a selected feature, the script prints the `download.sh --features` command for the missing ones. If there is no usable download, it prints the manual steps and waits:

1. Create or log in to your NVIDIA Developer Program account (a plain NGC account is not enough).
2. Open the SDK's catalogue page, log in, select Get Access under NVIDIA Developer Program and accept NVIDIA's licence.
3. Generate a personal API key that includes the NGC Catalog service.
4. Install the NGC CLI.
5. Run `ngc config set` yourself and paste the key there.

The details of each step are in [download.md](download.md#prerequisites). The script then offers to run `download.sh` for you (only if `ngc` is on `PATH`, and only after a y/N; `download.sh` shows the sizes and asks again before it downloads). Whether you let it or ran the command yourself, press Enter to re-check the directory, or `s` to skip the SDK. The loop repeats until the download is valid or you skip.

An SDK tree you extracted yourself (see [Alternative: an existing SDK tree](download.md#alternative-an-existing-sdk-tree)) is packaged as it is. `download.sh` cannot add features to it, so the script prints the commands to fetch a download directory of its own and to select that instead.

### 3. Selection

If the SDK has no `selection.conf`, the script prints the `configure.sh --src DIR --archs sm_<N> --features all --write` command with your detected architecture and asks before writing it. `--features all` means that everything in your download is packaged, so the selection of features happened at download time. If a `selection.conf` exists it is shown and kept unless you agree to replace it.

### 4. Build

`makepkg -f` runs in the package directory (with `PKGEXT=.pkg.tar`) after a y/N, because it takes several GiB and a while. An already built package is reused only when it is current. It is rebuilt when this run changed the download or the selection, when `selection.conf` is newer than the package, or when the download holds files newer than the package.

### 5. Install

The script prints `sudo pacman -U <package>` and runs it only after a y/N. It never runs `makepkg -i` or `makepkg -s`. If the SDK is already installed at the version the recipe builds, the download, build and install are skipped.

If you added Audio Effects effects by hand earlier (step 6 below) and the new package now contains them, `pacman -U` would stop with "exists in filesystem" because no package owns those directories. The script detects this, prints `sudo rm -r` of exactly those directories, and runs it only after a y/N, before the install. If you decline, it does not install and prints both commands for you to run.

### 6. Features added after the install (Audio Effects)

Audio Effects effects you did not fetch before the build can be added after the install with NVIDIA's own `download_features.sh`, which the package installs under `/opt/nvidia/maxine/afx/features`. The script compares your selection with what is packaged and what is already there, and handles only the effects that are in neither:

1. It asks before downloading, then takes the NGC API key (see [The key](#the-key)).
2. It runs `download_features.sh` from the installed `features/` directory, into a new directory below `~/Downloads/maxine/afx-features` that exists for this run only.
3. It checks the checksums of the download.
4. It prints `sudo cp -R --no-preserve=ownership` of only the requested feature directories into the installed `features/` directory and runs it after a y/N. `--no-preserve=ownership` makes the copy owned by root. The temporary download directory is removed after a successful copy.

Caveats of this route:

- The copied files are outside pacman's ownership. `pacman -R` does not remove them, and a later package that contains them needs the `sudo rm -r` of step 5. The undo commands at the end of the run name them.
- An effect whose feature is in the package, but at another sample rate, is not added this way, because its directory belongs to the package. The script prints the `download.sh --features` command and the rebuild instead.
- Early Access effects (speaker focus) may need NVIDIA's approval of your NGC account before they download.
- To have an effect packaged instead, fetch it with `download.sh --features` before the build.

### 7. Check

Read-only. For each SDK the script checks the installed package, the environment file, the library path, `ldd` of the core library with that path, and the models for your architecture, and prints one line per SDK with notes for anything missing. It then points to the by-hand checks in [usage.md](usage.md#check-the-installation).

### 8. Undo

Printed, never run: the `sudo rm -r` of the copied feature directories (first, because pacman does not own them) and `sudo pacman -R` of the installed packages.

## What stays manual, and why

The script never logs in to NGC, never accepts a licence and never runs `ngc config`. Accepting the licence and creating the key are acts of your own account, with your own agreement to NVIDIA's terms, so they stay with you. `ngc config set` is where the key is entered; keeping it a step you run yourself means the key goes into the NGC CLI's own configuration and nowhere else. The script never reads `~/.ngc` or any other credential. It prints each manual step with the link and waits.

## The key

The only step that handles a key is the optional Audio Effects post-install step. `download.sh` and `configure.sh` never do.

- The script takes `NGC_API_KEY` from the environment when it is set. Otherwise it asks for it with no echo after you agree to the download, and an empty answer skips the step.
- The key is held in a shell variable that is not exported. The script never prints, logs or stores it and never puts it on a command line. It hands it only to `download_features.sh`, in that one process's environment.
- The step refuses to run under `bash -x`, which would print the key.
- NVIDIA's `download_features.sh` itself passes the key to `curl` or `wget` on their command line, so it is visible in the process list while that script runs. This script cannot prevent that.

If this matters to you, fetch the effects with `download.sh --features` before the build instead: that route needs only your configured NGC CLI.

## Commands that use `sudo`

The script runs `sudo` for these commands only, each shown first, each confirmed with a y/N whose default is No, and none in a dry run:

| Command | Purpose |
|---|---|
| `sudo pacman -U <package>` | Install a package you built |
| `sudo rm -r <feature directories>` | Remove hand-copied Audio Effects feature directories that a new package contains, so that `pacman -U` can install it |
| `sudo cp -R --no-preserve=ownership <feature directories> <installed features directory>` | Copy Audio Effects effects added after the install |

It never runs `pacman -R`, `makepkg -i` or `makepkg -s`. Besides `sudo`, it runs `download.sh`, `configure.sh --write` and `makepkg -f` only after a y/N, and it queries `nvidia-smi` once.

## Adding an SDK

The script has no per-SDK code. Each SDK is a descriptor in `scripts/setup.d/`, parsed as `KEY=value` text and never sourced. To add one, add a descriptor and the package directory it names. The format is in [scripts/setup.d/README](../scripts/setup.d/README).

## Tests

`scripts/tests/setup-test.sh` tests the script with stubbed tools. It runs from `scripts/test.sh`.
