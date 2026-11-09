// Test program for os-release-shim, run by test.sh under LD_PRELOAD.
//
//   shim-test redirect <tmpdir>      /etc/os-release must read as the file
//                                    named by $OMA_BROADCAST_OS_RELEASE
//   shim-test passthrough <tmpdir>   /etc/os-release must read as the real file
//
// Every interposed entry point is called directly. Reference contents are
// read with the raw openat system call, which the shim cannot see.

#undef _FORTIFY_SOURCE
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

int __open_2(const char *path, int flags);
int __open64_2(const char *path, int flags);
int __openat_2(int dirfd, const char *path, int flags);
int __openat64_2(int dirfd, const char *path, int flags);

static int failures;

#define CHECK(cond, ...)                              \
    do {                                              \
        if (cond) {                                   \
            printf("ok   ");                          \
        } else {                                      \
            printf("FAIL ");                          \
            failures++;                               \
        }                                             \
        printf(__VA_ARGS__);                          \
        printf("\n");                                 \
    } while (0)

static char *read_fd(int fd) {
    static char buf[3][8192];
    static int slot;
    char *b = buf[slot++ % 3];
    size_t n = 0;
    ssize_t r;
    while (n < sizeof buf[0] - 1 && (r = read(fd, b + n, sizeof buf[0] - 1 - n)) > 0) n += (size_t)r;
    b[n] = '\0';
    close(fd);
    return b;
}

static char *read_raw(const char *path) {
    int fd = (int)syscall(SYS_openat, AT_FDCWD, path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "cannot read %s: %s\n", path, strerror(errno));
        exit(2);
    }
    return strdup(read_fd(fd));
}

static char *read_file(FILE *f) {
    static char b[8192];
    if (f == NULL) return NULL;
    size_t n = fread(b, 1, sizeof b - 1, f);
    b[n] = '\0';
    fclose(f);
    return b;
}

static int same(int fd, const char *want) {
    return fd >= 0 && strcmp(read_fd(fd), want) == 0;
}

static int same_file(FILE *f, const char *want) {
    char *got = read_file(f);
    return got != NULL && strcmp(got, want) == 0;
}

static int created_mode(int fd, const char *path, mode_t want) {
    struct stat st;
    int ok = fd >= 0 && fstat(fd, &st) == 0 && (st.st_mode & 07777) == want;
    if (fd >= 0) close(fd);
    if (path != NULL) unlink(path);
    return ok;
}

int main(int argc, char **argv) {
    if (argc != 3 || (strcmp(argv[1], "redirect") != 0 && strcmp(argv[1], "passthrough") != 0)) {
        fprintf(stderr, "usage: %s redirect|passthrough <tmpdir>\n", argv[0]);
        return 2;
    }
    int redirect = strcmp(argv[1], "redirect") == 0;
    const char *tmp = argv[2];
    const char *T = "/etc/os-release";

    char *real = read_raw(T);
    char *want = real;
    if (redirect) {
        const char *fake = getenv("OMA_BROADCAST_OS_RELEASE");
        if (fake == NULL) {
            fprintf(stderr, "redirect mode needs OMA_BROADCAST_OS_RELEASE\n");
            return 2;
        }
        want = read_raw(fake);
        if (strcmp(want, real) == 0) {
            fprintf(stderr, "the replacement must differ from the real file\n");
            return 2;
        }
    }
    const char *what = redirect ? "replacement" : "real file";

    // Every entry point, absolute exact path.
    CHECK(same(open(T, O_RDONLY), want), "open reads the %s", what);
    CHECK(same(open64(T, O_RDONLY | O_CLOEXEC), want), "open64 reads the %s", what);
    CHECK(same(openat(AT_FDCWD, T, O_RDONLY), want), "openat(AT_FDCWD) reads the %s", what);
    CHECK(same(openat64(AT_FDCWD, T, O_RDONLY), want), "openat64(AT_FDCWD) reads the %s", what);
    CHECK(same(__open_2(T, O_RDONLY), want), "__open_2 reads the %s", what);
    CHECK(same(__open64_2(T, O_RDONLY), want), "__open64_2 reads the %s", what);
    CHECK(same(__openat_2(AT_FDCWD, T, O_RDONLY), want), "__openat_2 reads the %s", what);
    CHECK(same(__openat64_2(AT_FDCWD, T, O_RDONLY), want), "__openat64_2 reads the %s", what);
    CHECK(same_file(fopen(T, "r"), want), "fopen(\"r\") reads the %s", what);
    CHECK(same_file(fopen64(T, "re"), want), "fopen64(\"re\") reads the %s", what);

    // An absolute path ignores dirfd, so it is redirected too.
    int tmpfd = open(tmp, O_RDONLY | O_DIRECTORY);
    CHECK(same(openat(tmpfd, T, O_RDONLY), want), "openat(dirfd, absolute) reads the %s", what);

    // Never redirected: relative paths, other spellings, other files, writes.
    int etc = open("/etc", O_RDONLY | O_DIRECTORY);
    CHECK(same(openat(etc, "os-release", O_RDONLY), real), "openat(/etc fd, \"os-release\") reads the real file");
    CHECK(same(__openat_2(etc, "os-release", O_RDONLY), real), "__openat_2(/etc fd, relative) reads the real file");
    close(etc);
    if (chdir("/etc") == 0) {
        CHECK(same(open("os-release", O_RDONLY), real), "open(\"os-release\") in /etc reads the real file");
        CHECK(same(open("./../etc/os-release", O_RDONLY), real), "open(\"./../etc/os-release\") reads the real file");
    }
    CHECK(same(open("/etc//os-release", O_RDONLY), real), "open(\"/etc//os-release\") reads the real file");

    char other[4096];
    snprintf(other, sizeof other, "%s/other", tmp);
    int ofd = (int)syscall(SYS_openat, AT_FDCWD, other, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (ofd < 0 || write(ofd, "other\n", 6) != 6) return 2;
    close(ofd);
    CHECK(same(open(other, O_RDONLY), "other\n"), "an unrelated file is untouched (open)");
    CHECK(same_file(fopen(other, "r"), "other\n"), "an unrelated file is untouched (fopen)");
    unlink(other);

    // A write never reaches the replacement: the real, root-owned file is
    // opened, which fails for an ordinary user (and succeeds for root).
    errno = 0;
    int w = open(T, O_RDWR);
    CHECK(w < 0 ? errno == EACCES || errno == EROFS : geteuid() == 0, "open(O_RDWR) goes to the real file");
    if (w >= 0) close(w);
    errno = 0;
    FILE *wf = fopen(T, "r+");
    CHECK(wf == NULL ? errno == EACCES || errno == EROFS : geteuid() == 0, "fopen(\"r+\") goes to the real file");
    if (wf != NULL) fclose(wf);

    // The variadic mode is passed on for O_CREAT and O_TMPFILE.
    umask(0);
    char path[4096];
    snprintf(path, sizeof path, "%s/created-open", tmp);
    CHECK(created_mode(open(path, O_WRONLY | O_CREAT | O_EXCL, 0640), path, 0640), "open(O_CREAT, 0640) creates mode 0640");
    snprintf(path, sizeof path, "%s/created-open64", tmp);
    CHECK(created_mode(open64(path, O_WRONLY | O_CREAT | O_EXCL, 0604), path, 0604), "open64(O_CREAT, 0604) creates mode 0604");
    CHECK(created_mode(openat(tmpfd, "created-openat", O_WRONLY | O_CREAT | O_EXCL, 0620), NULL, 0620),
          "openat(dirfd, O_CREAT, 0620) creates mode 0620");
    unlinkat(tmpfd, "created-openat", 0);
    CHECK(created_mode(openat64(tmpfd, "created-openat64", O_WRONLY | O_CREAT | O_EXCL, 0602), NULL, 0602),
          "openat64(dirfd, O_CREAT, 0602) creates mode 0602");
    unlinkat(tmpfd, "created-openat64", 0);
    int tf = open(tmp, O_TMPFILE | O_RDWR, 0610);
    if (tf < 0 && (errno == EOPNOTSUPP || errno == EISDIR)) {
        printf("skip O_TMPFILE not supported in %s\n", tmp);
    } else {
        CHECK(created_mode(tf, NULL, 0610), "open(O_TMPFILE, 0610) creates mode 0610");
    }
    snprintf(path, sizeof path, "%s/created-fopen", tmp);
    FILE *cf = fopen(path, "w");
    CHECK(cf != NULL, "fopen(\"w\") creates a file");
    if (cf != NULL) fclose(cf);
    unlink(path);
    close(tmpfd);

    printf("%s: %d failure(s)\n", argv[1], failures);
    return failures == 0 ? 0 : 1;
}
