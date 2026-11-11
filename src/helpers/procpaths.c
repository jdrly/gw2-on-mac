// procpaths: every process's real executable, "<pid> <path>" lines (proc_pidpath), as SWTOR on
// Mac's hold-launcher --paths. gw2om.sh tells its own Wine processes by it: Wine rewrites argv[0],
// so ps shows C:\...\name.exe for them, while the executable is the engine's loader in wine.app.
// The path is the resolved one, however the process was started.
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    int n = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t *all = n > 0 ? malloc(n) : NULL;
    if (!all) return 1;
    n = proc_listpids(PROC_ALL_PIDS, 0, all, n) / (int)sizeof(pid_t);
    for (int i = 0; i < n; i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (all[i] > 0 && proc_pidpath(all[i], path, sizeof(path)) > 0)
            printf("%d %s\n", (int)all[i], path);
    }
    free(all);
    return 0;
}
