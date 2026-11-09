// os-release-shim: an LD_PRELOAD library that shows one process a
// replacement /etc/os-release.
//
// The NVIDIA Maxine Video Effects SDK's model loader reads /etc/os-release
// and refuses distributions it does not list (docs/setup/maxine.md,
// section 7). This library redirects read-only opens of exactly
// "/etc/os-release" to the file named by $MAXINE_OS_RELEASE, in the
// process that preloads it and nowhere else. Every other call passes
// through unchanged. See README.md next to this file.
//
// Rules:
//   - Only the exact absolute path "/etc/os-release" is redirected. A
//     relative path (with or without a directory descriptor), a different
//     spelling ("/etc//os-release", "/usr/lib/os-release") or a symlink to
//     the file is not.
//   - Only read-only opens are redirected (O_RDONLY without O_CREAT or
//     O_TRUNC; fopen modes "r", "rb", "re", ... without '+'). A write goes
//     to the real path, never to the replacement file.
//   - $MAXINE_OS_RELEASE must be an absolute path. If it is unset,
//     empty, relative or too long, nothing is redirected (a warning goes to
//     stderr when it is set but unusable).
//   - If the replacement file cannot be opened, the real file is opened
//     instead, so the process behaves as it would without the shim.
//   - At load time the library removes LD_PRELOAD from the environment, so
//     child processes do not inherit it (the whole variable: other preloads
//     listed in it are not passed on either). $MAXINE_OS_RELEASE is kept.
//     The configuration is read once, at that point.
//   - $MAXINE_OS_RELEASE_DEBUG=1 logs each redirect to stderr.
//   - Deprecated: $OMA_BROADCAST_OS_RELEASE and
//     $OMA_BROADCAST_OS_RELEASE_DEBUG, the names from the omarchy-broadcast
//     project, are still read, each only when its new name is not set (a
//     new name set to the empty string still wins), with one note on stderr
//     per process. The consumer sets them until it moves to the new names;
//     they will be removed in a later release. Neither name is removed from
//     the environment.
//
// Real symbols are resolved with dlsym(RTLD_NEXT, ...) on first use. If a
// lookup would recurse (dlsym itself opening a file on the same thread) or
// fails, the open family falls back to the raw openat system call, which
// has the same semantics; fopen and fopen64 then fail with ENOSYS. With
// glibc neither case occurs in practice: dlsym does not open files and libc
// always exports these symbols.
//
// openat2(2) has no glibc wrapper in common use and is not intercepted.

#undef _FORTIFY_SOURCE
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#define EXPORT __attribute__((visibility("default")))

static const char kTarget[] = "/etc/os-release";
static const char kEnvPath[] = "MAXINE_OS_RELEASE";
static const char kEnvDebug[] = "MAXINE_OS_RELEASE_DEBUG";
// Deprecated fallbacks for the two names above (see the rules at the top).
static const char kOldEnvPath[] = "OMA_BROADCAST_OS_RELEASE";
static const char kOldEnvDebug[] = "OMA_BROADCAST_OS_RELEASE_DEBUG";

// ---------------------------------------------------------------------------
// Configuration, read once.

static pthread_once_t config_once = PTHREAD_ONCE_INIT;
static char fake_path[PATH_MAX];  // empty: redirect disabled
static int debug;

static void log_line(const char *a, const char *b, const char *c) {
    // write(2) only: no stdio, no allocation, no file opens.
    const char *parts[] = {"os-release-shim: ", a, b, c, "\n"};
    for (size_t i = 0; i < sizeof parts / sizeof parts[0]; i++) {
        if (parts[i] == NULL) continue;
        size_t len = strlen(parts[i]);
        while (len > 0) {
            ssize_t n = write(STDERR_FILENO, parts[i], len);
            if (n <= 0) return;
            parts[i] += n;
            len -= (size_t)n;
        }
    }
}

// The environment is read and edited through `environ` directly, not with
// getenv/unsetenv: a program may define its own (bash does, for its shell
// variables), and the shim's calls would bind to those.
extern char **environ;

static const char *env_get(const char *name) {
    size_t len = strlen(name);
    for (char **e = environ; e != NULL && *e != NULL; e++) {
        if (strncmp(*e, name, len) == 0 && (*e)[len] == '=') return *e + len + 1;
    }
    return NULL;
}

// Removes every NAME=... entry in place, as glibc's unsetenv does.
static void env_remove(const char *name) {
    size_t len = strlen(name);
    if (environ == NULL) return;
    char **w = environ;
    for (char **r = environ; *r != NULL; r++) {
        if (strncmp(*r, name, len) == 0 && (*r)[len] == '=') continue;
        *w++ = *r;
    }
    *w = NULL;
}

// Returns the value of `name` if it is set (even empty); otherwise the value
// of its deprecated name `old`, with a note on stderr, if that is set; else
// NULL. *used receives the name the value came from, for later messages.
// Called only from config_init, so each note appears at most once per
// process.
static const char *env_get_compat(const char *name, const char *old, const char **used) {
    *used = name;
    const char *v = env_get(name);
    if (v != NULL) return v;
    v = env_get(old);
    if (v != NULL) {
        *used = old;
        log_line(old, " is deprecated, use ", name);
    }
    return v;
}

static void config_init(void) {
    const char *name;
    const char *d = env_get_compat(kEnvDebug, kOldEnvDebug, &name);
    debug = d != NULL && strcmp(d, "1") == 0;

    const char *p = env_get_compat(kEnvPath, kOldEnvPath, &name);
    if (p != NULL && p[0] != '\0') {
        size_t len = strlen(p);
        if (p[0] != '/') {
            log_line(name, " is not an absolute path; not redirecting: ", p);
        } else if (len >= sizeof fake_path) {
            log_line(name, " is too long; not redirecting", NULL);
        } else {
            memcpy(fake_path, p, len + 1);
        }
    }

    // Children must not inherit the preload. Editing the environment is
    // safe here: this runs in the library's constructor (or, at the latest,
    // on the first intercepted call), before the program reads its
    // environment or starts threads.
    env_remove("LD_PRELOAD");
}

__attribute__((constructor)) static void shim_init(void) {
    pthread_once(&config_once, config_init);
}

// Returns the replacement path if `path` is the target, else NULL.
static const char *redirect_for(const char *path, int read_only) {
    if (path == NULL || !read_only) return NULL;
    if (strcmp(path, kTarget) != 0) return NULL;
    pthread_once(&config_once, config_init);
    return fake_path[0] != '\0' ? fake_path : NULL;
}

static int flags_read_only(int flags) {
    return (flags & O_ACCMODE) == O_RDONLY &&
           (flags & (O_CREAT | O_TRUNC)) == 0 &&
           (flags & O_TMPFILE) != O_TMPFILE;
}

static int fopen_mode_read_only(const char *mode) {
    return mode != NULL && mode[0] == 'r' && strchr(mode, '+') == NULL;
}

static int needs_mode(int flags) {
    return (flags & O_CREAT) != 0 || (flags & O_TMPFILE) == O_TMPFILE;
}

// ---------------------------------------------------------------------------
// Real symbols.

static __thread int resolving __attribute__((tls_model("initial-exec")));

static void *resolve(void **slot, const char *name) {
    void *fn = __atomic_load_n(slot, __ATOMIC_ACQUIRE);
    if (fn != NULL || resolving) return fn;
    resolving = 1;
    fn = dlsym(RTLD_NEXT, name);
    resolving = 0;
    if (fn != NULL) __atomic_store_n(slot, fn, __ATOMIC_RELEASE);
    return fn;
}

typedef int (*openat_fn)(int, const char *, int, ...);
typedef FILE *(*fopen_fn)(const char *, const char *);

static void *real_openat_sym, *real_openat64_sym;
static void *real_fopen_sym, *real_fopen64_sym;

// All open-family entry points funnel through here: open(p) is
// openat(AT_FDCWD, p), and an absolute path ignores dirfd. The 64-bit
// variant is used for the *64 entry points; on LP64 both are identical.
static int do_openat(int large, int dirfd, const char *path, int flags, mode_t mode) {
    openat_fn fn = (openat_fn)resolve(large ? &real_openat64_sym : &real_openat_sym,
                                      large ? "openat64" : "openat");
    if (fn != NULL) return fn(dirfd, path, flags, mode);
    if (large) flags |= O_LARGEFILE;
    return (int)syscall(SYS_openat, dirfd, path, flags, mode);
}

static int open_common(int large, int dirfd, const char *path, int flags, mode_t mode) {
    const char *fake = redirect_for(path, flags_read_only(flags));
    if (fake != NULL) {
        int fd = do_openat(large, AT_FDCWD, fake, flags, mode);
        if (fd >= 0) {
            if (debug) log_line("redirected open of ", kTarget, NULL);
            return fd;
        }
        if (debug) log_line("cannot open the replacement, using the real file: ", fake, NULL);
    }
    return do_openat(large, dirfd, path, flags, mode);
}

static FILE *fopen_common(int large, const char *path, const char *mode) {
    fopen_fn fn = (fopen_fn)resolve(large ? &real_fopen64_sym : &real_fopen_sym,
                                    large ? "fopen64" : "fopen");
    if (fn == NULL) {
        errno = ENOSYS;
        return NULL;
    }
    const char *fake = redirect_for(path, fopen_mode_read_only(mode));
    if (fake != NULL) {
        FILE *f = fn(fake, mode);
        if (f != NULL) {
            if (debug) log_line("redirected fopen of ", kTarget, NULL);
            return f;
        }
        if (debug) log_line("cannot open the replacement, using the real file: ", fake, NULL);
    }
    return fn(path, mode);
}

// ---------------------------------------------------------------------------
// Interposed entry points. The mode argument is read only when the flags
// require it (O_CREAT or O_TMPFILE), as the libc wrappers do.

#define READ_MODE(flags, last)                    \
    mode_t mode = 0;                              \
    if (needs_mode(flags)) {                      \
        va_list ap;                               \
        va_start(ap, last);                       \
        mode = (mode_t)va_arg(ap, int);           \
        va_end(ap);                               \
    }

EXPORT int open(const char *path, int flags, ...) {
    READ_MODE(flags, flags);
    return open_common(0, AT_FDCWD, path, flags, mode);
}

EXPORT int open64(const char *path, int flags, ...) {
    READ_MODE(flags, flags);
    return open_common(1, AT_FDCWD, path, flags, mode);
}

EXPORT int openat(int dirfd, const char *path, int flags, ...) {
    READ_MODE(flags, flags);
    return open_common(0, dirfd, path, flags, mode);
}

EXPORT int openat64(int dirfd, const char *path, int flags, ...) {
    READ_MODE(flags, flags);
    return open_common(1, dirfd, path, flags, mode);
}

// Fortified variants (_FORTIFY_SOURCE): called only without O_CREAT or
// O_TMPFILE, so there is no mode argument. The real ones would abort on
// those flags; passing them on with mode 0 matches the kernel's view.
int __open_2(const char *path, int flags);
int __open64_2(const char *path, int flags);
int __openat_2(int dirfd, const char *path, int flags);
int __openat64_2(int dirfd, const char *path, int flags);

EXPORT int __open_2(const char *path, int flags) {
    return open_common(0, AT_FDCWD, path, flags, 0);
}

EXPORT int __open64_2(const char *path, int flags) {
    return open_common(1, AT_FDCWD, path, flags, 0);
}

EXPORT int __openat_2(int dirfd, const char *path, int flags) {
    return open_common(0, dirfd, path, flags, 0);
}

EXPORT int __openat64_2(int dirfd, const char *path, int flags) {
    return open_common(1, dirfd, path, flags, 0);
}

EXPORT FILE *fopen(const char *path, const char *mode) {
    return fopen_common(0, path, mode);
}

EXPORT FILE *fopen64(const char *path, const char *mode) {
    return fopen_common(1, path, mode);
}
