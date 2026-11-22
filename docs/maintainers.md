# Maintaining the repository

This page is for people who change the recipes, check the packages or add an SDK. You do not need it to install or use the packages (see [INSTALL.md](../INSTALL.md)).

## Repository layout

```
README.md
INSTALL.md                        all installation directions
LICENSE-MIT, LICENSE-APACHE
.gitignore
.githooks/                        pre-commit, pre-merge-commit, pre-push: run the licence guard
scripts/check-no-nvidia.sh        licence guard: refuses NVIDIA files, SDK trees, NGC download directories
scripts/setup.sh                  guided setup: preflight, download detection, configure, build, install, check, undo
scripts/check-ngc.sh              read-only check of your NGC key and of your account's access to the Maxine models
scripts/setup.d/                  one descriptor per SDK for setup.sh (format in scripts/setup.d/README)
scripts/test.sh                   runs every check of this repository
scripts/aur.sh                    makes a recipe's AUR copy: its helpers fetched from a pinned commit of this repository (docs/aur.md)
scripts/tests/                    tests of the guard, of env.sh, of setup.sh, of check-ngc.sh and of a PKGBUILD fixture build
docs/download.md                  what is downloaded, from where and whether it needs a login, for every SDK; and downloading the Maxine SDKs from NGC: the one-command path, the manual steps, sizes, the credential check, access (HTTP 402), troubleshooting
docs/optical-flow.md              the Optical Flow SDK package: browser download, what it installs, environment file, use, check, troubleshooting
docs/tensorrt.md                  the TensorRT package: the download (automatic or in a browser), what it installs, environment file, pkg-config, CMake and RPATH, the AUR's tensorrt, CUDA versions
docs/aur.md                       the recipes on the AUR: how the AUR copies are made and published
docs/usage.md                     how a program uses each installed package: environment file, shim, models
docs/gpu-support.md               supported GPUs, architectures and how to fetch their models
docs/setup-script.md              how scripts/setup.sh works: options, stages, the key, sudo
docs/maintainers.md               this page
maxine-vfx/PKGBUILD               the package recipe
maxine-vfx/assemble.sh            builds the SDK tree from your download
maxine-vfx/download.sh            downloads what you need with your configured ngc: probes, shows sizes, verifies
maxine-vfx/configure.sh           shows what your download holds and saves your selection
maxine-vfx/selection.sh           parses selection.conf (never executes it), for the PKGBUILD and configure.sh
maxine-vfx/README.md              build instructions for the package
maxine-vfx/tests/                 tests of assemble.sh, configure.sh and download.sh on tiny fake files
maxine-ar/                        the AR SDK package: PKGBUILD, assemble.sh, download.sh, configure.sh, selection.sh, README.md, tests/ (same roles as in maxine-vfx/)
maxine-afx/                       the Audio Effects SDK package: the same files as maxine-ar/
nvidia-optical-flow/              the Optical Flow SDK package: PKGBUILD, assemble.sh, configure.sh, selection.sh, README.md, tests/ (no download.sh: the zip is downloaded in a browser)
nvidia-tensorrt/                  the TensorRT package: PKGBUILD, source.sh, configure.sh, selection.sh, README.md, tests/ (no download.sh: makepkg downloads the archive, or you supply it)
tools/os-release-shim/            the compatibility shim and its test
tools/maxine-probe/               a small program that checks the SDK loads
```

## Run the tests

```bash
scripts/test.sh
```

This runs every check in the repository, for all five packages. It needs no GPU, uses no network and needs no NVIDIA download: every check runs on fake SDK files. The checks are:

- shellcheck over every script;
- the syntax and metadata of each PKGBUILD;
- the fixture tests of each package's `assemble.sh`, `configure.sh` and `download.sh` (the last against a fake `ngc`);
- the `configure.sh` and `selection.conf` tests of the Optical Flow and TensorRT packages on tiny fake zips, archives and trees;
- a `makepkg` build of each PKGBUILD against fake SDK files;
- the AUR copies `scripts/aur.sh` makes, and a build of one from a directory holding only its PKGBUILD;
- the shim test;
- the tests of `scripts/setup.sh` and `scripts/check-ngc.sh`, with stubbed `pacman`, `sudo`, `makepkg`, `ngc`, `curl` and `nvidia-smi`, so nothing is installed and nothing reaches NGC;
- the licence guard and its hooks, then the guard over the whole tree.

It needs `shellcheck` (a tool that checks shell scripts for mistakes). If `shellcheck` is not on your `PATH`, name it:

```bash
SHELLCHECK=/path/to/shellcheck scripts/test.sh
```

The `makepkg` fixture builds, and the Optical Flow and TensorRT `configure.sh` tests where they need `bsdtar`, are skipped when `makepkg`, `fakeroot` or `bsdtar` is missing.

## The licence guard and its git hooks

The guard `scripts/check-no-nvidia.sh` keeps NVIDIA's files out of the repository. It refuses:

- NVIDIA's file types: libraries, models and their `*.trtpkg.*` checksum sidecars, archives, PDFs, and SDK headers, including those of the Optical Flow SDK and TensorRT;
- an unpacked SDK tree (`VideoFX/`, `ARSDK/`, `Audio_Effects_SDK/`, `Optical_Flow_SDK_*/`, `TensorRT-*/`);
- an NGC download directory;
- an SDK's top-level names (`lib/`, `include/`, `features/`, `external/`, `share/`, `samples/`, `licenses/`, `nvafx/`, `bin/`, `docs/`, `version.h`, `Changelog.txt`) placed directly inside a recipe directory, and the matching top-level names of the Optical Flow SDK and of the TensorRT archive inside their recipe directories;
- file content that carries an NVIDIA marker.

Enable its hooks in your clone with:

```bash
git config core.hooksPath .githooks
```

The hooks are `pre-commit`, `pre-merge-commit` and `pre-push`. `pre-push` checks the commits being pushed with the guard's `--range` mode. `git commit --no-verify` bypasses them, and `git push --no-verify` bypasses `pre-push`, so the guard is a safety net and not an access control. To check the working tree, run the command below. It does not check the history: a file committed earlier stays in the history until you rewrite it.

```bash
scripts/check-no-nvidia.sh --all
```

## Adding an SDK to the script

Add a descriptor in `scripts/setup.d/` and the package directory it names. The format is in [scripts/setup.d/README](../scripts/setup.d/README). In short, a descriptor sets:

- **How the download is obtained.** `obtain=ngc` (the default) uses the package's `download.sh` and your own NGC CLI. `obtain=browser` is for one file that you download in a browser after accepting a licence: the descriptor names the file (`download_file`, with `{version}` for the PKGBUILD's version) and the licence, and the script prints the browser steps. `obtain=auto` is for one file that the recipe's `makepkg` downloads itself (a `source=` entry). The script uses a copy at the source when there is one; otherwise it says that `makepkg` will download the file, names the licence and gives the by-hand route. TensorRT uses it.
- **What `configure.sh` takes.** `configure_select` says whether `--archs`, `--features`, both or neither is passed, so that an SDK without GPU architectures needs no detected GPU.
- **What the check looks at.** Optionally a core library for `ldd`, optional libraries, libraries that must be on the system, files that must exist, and a model directory.
- **Optional downloads and features after the install**, for an NGC SDK that has them (a catalogue read from its `download.sh`, and a script that adds features to the installed tree).
- **Placeholders.** `status=placeholder` lists an entry that is not installable yet: a request page and the steps to request access. Removing the status and adding the package keys activates it.

The contract of the package's `configure.sh` and `selection.sh` is in the same README. `scripts/tests/setup-test.sh` tests the script with stubbed tools and runs from `scripts/test.sh`. How the script behaves at run time is in [setup-script.md](setup-script.md).

## Publishing on the AUR

See [aur.md](aur.md).
