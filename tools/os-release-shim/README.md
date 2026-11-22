# os-release-shim

A small `LD_PRELOAD` library that shows one process a replacement `/etc/os-release`. You need it to run the Maxine SDKs (software development kits) on a distribution that NVIDIA does not list. The Maxine packages build and install it for you.

The model loader of the NVIDIA Maxine Video Effects SDK reads `/etc/os-release` and refuses distributions it does not list. On such a distribution `NvVFX_Load` fails with `-1209`. With the shim preloaded, the program that loads the SDK reads a replacement file naming a listed distribution instead. This is a compatibility shim. NVIDIA does not support this configuration.

The `maxine-vfx` package ([`../../maxine-vfx/`](../../maxine-vfx/)) builds it and installs it inactive. The `maxine-ar` and `maxine-afx` packages do the same under their own `/usr/lib/maxine-ar/` and `/usr/lib/maxine-afx/` directories.

| Path | Content |
|---|---|
| `/usr/lib/maxine-vfx/os-release-shim.so` | the library |
| `/usr/lib/maxine-vfx/fake-os-release` | the replacement `os-release` (Ubuntu 24.04), from [`../maxine-probe/fake-os-release`](../maxine-probe/fake-os-release) |

Nothing activates it. A consumer preloads it on its own program ([docs/usage.md](../../docs/usage.md)).

It was first written for the omarchy-broadcast project. Its environment variables are `MAXINE_OS_RELEASE` and `MAXINE_OS_RELEASE_DEBUG`; the deprecated names from that project are still read (see below).

## What it does

- It interposes `open`, `open64`, `openat`, `openat64`, `__open_2`, `__open64_2`, `__openat_2`, `__openat64_2`, `fopen` and `fopen64`. The SDK reads the file with `fopen`.
- A read-only open of exactly the absolute path `/etc/os-release` opens the file named by `$MAXINE_OS_RELEASE` instead. Nothing else is redirected:
  - not a relative path, with or without a directory descriptor (`openat(fd_of_etc, "os-release")`), nor another spelling of the path (`/etc//os-release`, `/usr/lib/os-release`);
  - not an open for writing (`O_WRONLY`, `O_RDWR`, `O_CREAT`, `O_TRUNC`, `O_TMPFILE`, or an `fopen` mode other than `r...` without `+`): those go to the real path, so the replacement file is never written;
  - not `stat`, `access` or `readlink`: the SDK only reads the contents.
- An `O_PATH` open of the exact path counts as read-only and is redirected too, so `open("/etc/os-release", O_PATH | O_NOFOLLOW)` returns a descriptor for the replacement file, not for the symbolic link that `/etc/os-release` usually is.
- Every other call passes through unchanged to the next definition (`dlsym(RTLD_NEXT, ...)`), with the mode argument passed on when `O_CREAT` or `O_TMPFILE` is set. The fortified `__open_2` variants take no mode argument; where `O_CREAT` or `O_TMPFILE` is set they pass mode 0 on, which glibc's own fortified callers never do (they abort on those flags).
- `$MAXINE_OS_RELEASE` must be an absolute path. If it is unset, empty, relative or longer than `PATH_MAX`, nothing is redirected; a set but unusable value prints a warning on stderr. If the replacement file cannot be opened, the real file is opened instead, so the process behaves as it would without the shim.
- When it is loaded, it removes `LD_PRELOAD` from the process environment, so no child process inherits it (the whole variable, including any other library listed in it). `$MAXINE_OS_RELEASE` stays.
- `MAXINE_OS_RELEASE_DEBUG=1` logs each redirect on stderr.

### Deprecated names

`OMA_BROADCAST_OS_RELEASE` and `OMA_BROADCAST_OS_RELEASE_DEBUG`, the names used by omarchy-broadcast, are still read, because that project still sets them until it moves to the new names. They will be removed in a later release. For each variable separately:

- if the new name is set, even to the empty string, it is used and the old name is ignored;
- otherwise, if the old name is set, it is used, and the shim prints one note per process on stderr, for example `os-release-shim: OMA_BROADCAST_OS_RELEASE is deprecated, use MAXINE_OS_RELEASE`.

Neither name is removed from the environment.

No namespace is involved: the process keeps the user's uid and the user's own user and mount namespaces.

## Build and test

From the repository root:

```sh
make -C tools/os-release-shim            # -> target/os-release-shim/os-release-shim.so
make -C tools/os-release-shim test       # builds and runs test.sh
make -C tools/os-release-shim OUT=/dir   # -> /dir/os-release-shim.so
```

The build needs only a C compiler and glibc. The test uses `cat`, `grep` and `python3` when present (the Python checks are skipped without it). Run it with no shim environment of your own:

```sh
env -u LD_PRELOAD -u MAXINE_OS_RELEASE -u MAXINE_OS_RELEASE_DEBUG \
    -u OMA_BROADCAST_OS_RELEASE -u OMA_BROADCAST_OS_RELEASE_DEBUG \
    make -C tools/os-release-shim test
```

## Running a program with it

With the package installed:

```sh
env LD_PRELOAD=/usr/lib/maxine-vfx/os-release-shim.so \
    MAXINE_OS_RELEASE=/usr/lib/maxine-vfx/fake-os-release \
    <program> [args]
```

The package's environment file sets `MAXINE_OS_RELEASE` (and names the shim in `MAXINE_VFX_OS_RELEASE_SHIM`), but never `LD_PRELOAD`: preloading is the consumer's explicit choice.

Put `LD_PRELOAD` on the final program, the one that loads the SDK, not on a wrapper in front of it: a wrapper such as `timeout`, `sh -c` or `cargo` would load the shim itself, remove `LD_PRELOAD`, and start the program without it. Write `timeout 60 env LD_PRELOAD=... program`, not `LD_PRELOAD=... timeout 60 program`. For `cargo test`, set it through a runner so that only the test binary is preloaded:

```sh
CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUNNER="env LD_PRELOAD=/usr/lib/maxine-vfx/os-release-shim.so" \
    cargo test ...
```

Never set it globally (a login profile, `/etc/ld.so.preload`): every program would then read the replacement file.

If the library file is missing, the dynamic loader prints `ERROR: ld.so: object '...' from LD_PRELOAD cannot be preloaded (cannot open shared object file): ignored.` and the program runs without it.

## Files

| File | Purpose |
|---|---|
| `os-release-shim.c` | The library |
| `Makefile` | Builds the library into `target/os-release-shim/` (or `$OUT`), and runs the test |
| `shim-test.c` | Calls every interposed entry point and checks what it reads or creates |
| `test.sh` | Runs `shim-test` with and without the shim, and checks ordinary programs (`cat`, `grep`, `python3`), child processes, the deprecated names, debug logging and namespaces |

## Support note

This is a compatibility shim for distributions the SDK does not list; NVIDIA does not support this configuration. It changes only what the process that preloads it reads as `/etc/os-release`; it does not modify `/etc/os-release` on disk, the SDK or the models. Read the licence you accepted from NVIDIA; this note is not legal advice.
