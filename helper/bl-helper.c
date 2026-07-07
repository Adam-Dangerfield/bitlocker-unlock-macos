// bl-helper — stable privileged-helper stub for BitLockerUnlock.
//
// This binary is intentionally minimal and MUST stay byte-stable: Full Disk
// Access is granted to it (TCC keys the grant on its code-signing cdhash), and
// because a compiled ad-hoc binary's cdhash changes on any edit, keeping this
// fixed means the user only ever grants FDA once. Its sole job is to (re)launch
// the daemon as a child and stay alive as the responsible parent, so TCC keeps
// attributing the daemon's — and the `bl`/dislocker processes IT spawns — file
// access to this FDA-granted binary. The real, updatable logic lives in
// /usr/local/libexec/bl-helperd, which this never needs to change to update.
#include <unistd.h>
#include <sys/wait.h>

static const char *DAEMON = "/usr/local/libexec/bl-helperd";

int main(void) {
    for (;;) {
        pid_t p = fork();
        if (p == 0) {
            execl(DAEMON, "bl-helperd", (char *)0);
            _exit(127);            // exec failed — daemon missing
        }
        if (p < 0) return 1;
        int st;
        waitpid(p, &st, 0);        // supervise: relaunch if the daemon exits
        sleep(1);
    }
    return 0;
}
