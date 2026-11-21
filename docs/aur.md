# The recipes on the AUR

This guide is for the maintainer who publishes the recipes on the Arch User Repository (AUR). To install a package, see [INSTALL.md](../INSTALL.md).

The five recipes are prepared for the AUR, as recipes only: `scripts/aur.sh` generates each AUR package's files from this repository. Four are published: `maxine-vfx-sdk-local`, `maxine-ar-sdk-local`, `maxine-afx-sdk-local` and `nvidia-optical-flow-sdk-local`. `nvidia-tensorrt-sdk-local` is not on the AUR.

| AUR package | Recipe | What the user supplies |
| --- | --- | --- |
| `maxine-vfx-sdk-local` | `maxine-vfx/` | the Video Effects SDK, downloaded from NVIDIA NGC (account with Maxine access, API key) |
| `maxine-ar-sdk-local` | `maxine-ar/` | the AR SDK, from NGC (same) |
| `maxine-afx-sdk-local` | `maxine-afx/` | the Audio Effects SDK, from NGC (same) |
| `nvidia-optical-flow-sdk-local` | `nvidia-optical-flow/` | `optical_flow_sdk_5.0.7.zip`, downloaded in a browser (free NVIDIA Developer Program login) |
| `nvidia-tensorrt-sdk-local` | `nvidia-tensorrt/` | nothing: `makepkg` downloads the archive from NVIDIA's public URL; a local copy can be supplied |

No NVIDIA file is in an AUR repository, in this repository or in the commit an AUR recipe fetches. Each user downloads the SDK under the licence they accept, and the package built from it stays on that user's machine ([Licences and caveats](../README.md#licences-and-caveats)).

## How the AUR copy differs

A recipe in this repository reads its helpers from the working tree, through `_repo=$(realpath -- "$startdir/..")`. The helpers are `selection.sh`, `assemble.sh`, `source.sh`, the os-release shim's source and the documents it installs. An AUR clone holds only its own files, so `scripts/aur.sh` generates a copy of the PKGBUILD that:

- fetches this repository at one pinned commit, `omarchy-nvidia-sdks::git+https://github.com/rsd/omarchy-nvidia-sdks.git#commit=<sha>`, with the SHA-256 `makepkg` computes for a git source pinned by commit (that of `git archive` of the commit), and adds `git` to `makedepends`;
- reads the helpers from `$srcdir/omarchy-nvidia-sdks`;
- replaces the header paragraph about the working tree with one that names the repository, the pinned commit's documentation, and where `configure.sh` is (`src/omarchy-nvidia-sdks/<recipe>/configure.sh` after `makepkg -o --noprepare`);
- rewrites the header's build examples to run in the AUR clone: `src/omarchy-nvidia-sdks/<recipe>/configure.sh --conf selection.conf ...`, so that `configure.sh` writes the `selection.conf` next to the PKGBUILD rather than next to itself.

Nothing else changes: the build inputs (the `MAXINE_*` and `NVIDIA_*` variables, `selection.conf` next to the PKGBUILD, the defaults) work as in this repository. The pinned source keeps one copy of each helper; an AUR reviewer reads them at the pinned commit on GitHub.

The `.SRCINFO` is `LC_ALL=C makepkg --printsrcinfo` of the generated PKGBUILD alone in an empty directory, with an empty environment apart from `PATH` and an empty `HOME`, so no build input changes it. For TensorRT it is the download case.

## Publishing a release

The pinned commit is `HEAD`, and the PKGBUILD transformed is `HEAD`'s. `scripts/aur.sh` refuses when `HEAD` is not in `origin/main` (as last fetched: it does not fetch), or when the recipe or a file it reads differs from `HEAD`. So commit and push first, then for each package:

```bash
git clone ssh://aur@aur.archlinux.org/maxine-vfx-sdk-local.git aur/maxine-vfx-sdk-local   # once; aur/ is git-ignored
scripts/aur.sh --recipe maxine-vfx --aur aur/maxine-vfx-sdk-local     # writes PKGBUILD, .SRCINFO, LICENSE
scripts/aur.sh --recipe maxine-vfx --check aur/maxine-vfx-sdk-local   # optional: fails with a diff when stale
(cd aur/maxine-vfx-sdk-local && git add PKGBUILD .SRCINFO LICENSE && git commit -m '1.3.0.0-3' && git push)
```

For a package not yet on the AUR, `git init -b master aur/<package>` and `git -C aur/<package> remote add origin ssh://aur@aur.archlinux.org/<package>.git` replace the clone: the first push creates it.

`--aur` writes into the top of a git clone only, refuses a clone that holds any other file, and commits nothing. `scripts/aur.sh --recipe DIR` prints the AUR PKGBUILD and `--srcinfo` its `.SRCINFO`. `LICENSE` is the 0BSD licence the AUR submission guidelines recommend for package sources; it covers the AUR repository's files, not NVIDIA's software.

A helper or document change reaches AUR users only through a new pinned commit. Regenerate, bump `pkgrel`, and push. A change to a document that a recipe installs (`docs/usage.md` for the three Maxine packages, the recipe's `README.md` for Optical Flow and TensorRT) needs this too. Optionally run `namcap PKGBUILD` in the AUR clone, and `namcap` on a built package (which stays local).

`scripts/tests/aur-test.sh` (run by `scripts/test.sh`) generates the five copies from a snapshot of the working tree, compares each `.SRCINFO` with a fresh one, and builds `maxine-vfx-sdk-local` from a directory holding only its generated PKGBUILD against fake SDK files.
