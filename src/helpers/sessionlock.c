// sessionlock: the kernel lock (flock) that keeps one watcher per game session (gw2om.sh
// watch-session), for a shell that has no flock of its own. A flock belongs to the open file, not
// to the process that took it: the shell opens the lock file on a descriptor, this helper takes the
// lock on that inherited descriptor and exits, and the shell keeps holding it. A child that
// inherits the descriptor (the watcher) holds it too; the kernel releases it when the last holder
// has closed it, so no lock ever goes stale.
//
//   sessionlock take <fd>            take the lock on the open descriptor <fd>, without waiting:
//                                    0 taken (or already held by this open file), 1 another holds
//                                    it, 2 error (no such descriptor)
//   sessionlock held <file>          0 another holds the lock on <file>, 1 free (or no file),
//                                    2 error
//   sessionlock hold <file> <secs>   take it (waiting for it) and hold it for <secs> seconds (for
//                                    tests)
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

static int usage(void)
{
    fprintf(stderr, "usage: sessionlock take <fd> | held <file> | hold <file> <seconds>\n");
    return 2;
}

int main(int argc, char **argv)
{
    if (argc == 3 && strcmp(argv[1], "take") == 0) {
        char *end;
        long fd = strtol(argv[2], &end, 10);
        if (*argv[2] == '\0' || *end != '\0' || fd < 0 || fd > 255) return usage();
        if (flock((int)fd, LOCK_EX | LOCK_NB) == 0) return 0;
        return errno == EWOULDBLOCK ? 1 : 2;
    }
    if (argc == 3 && strcmp(argv[1], "held") == 0) {
        int fd = open(argv[2], O_RDONLY | O_CLOEXEC);
        if (fd < 0) return errno == ENOENT ? 1 : 2;
        if (flock(fd, LOCK_EX | LOCK_NB) == 0) { close(fd); return 1; }
        int held = errno == EWOULDBLOCK;
        close(fd);
        return held ? 0 : 2;
    }
    if (argc == 4 && strcmp(argv[1], "hold") == 0) {
        int fd = open(argv[2], O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
        if (fd < 0 || flock(fd, LOCK_EX) != 0) return 2;
        sleep((unsigned)atoi(argv[3]));
        return 0;
    }
    return usage();
}
