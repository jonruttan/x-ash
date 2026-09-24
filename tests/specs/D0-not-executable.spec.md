## sh-eval a command that is there but cannot run

When a command's exec comes back, the shell tells two failures apart, as
POSIX has it and dash and bash do.  Something is there that cannot run -- a
file with no execute bit, found by its path or in a directory of PATH, or a
directory -- and the status is 126, with `Permission denied`.  Nothing is
there, and the status is 127, with `command not found`.

Expectations match `/bin/sh` and `dash`.

### the statuses

A file with no execute bit found through PATH and by its path, a directory,
a path to nothing, a name found nowhere, and the same file once it may run.

```sh
(do (sh-eval "( d=$(mktemp -d); printf 'echo hi\\n' > \"$d/noexec\"; chmod 644 \"$d/noexec\"; PATH=\"$d:$PATH\"; ( noexec ) 2>/dev/null; printf '%s,' $?; ( \"$d/noexec\" ) 2>/dev/null; printf '%s,' $?; ( \"$d\" ) 2>/dev/null; printf '%s,' $?; ( \"$d/missing\" ) 2>/dev/null; printf '%s,' $?; ( nosuch_notexec ) 2>/dev/null; printf '%s,' $?; chmod 755 \"$d/noexec\"; noexec; rm -rf \"$d\" )") ())
```
---
    126,126,126,127,127,hi

### the message says why

```sh
(do (sh-eval "( d=$(mktemp -d); : > \"$d/f\"; ( \"$d/f\" ) 2>&1 | grep -c 'Permission denied'; rm -rf \"$d\" )") ())
```
---
    1
