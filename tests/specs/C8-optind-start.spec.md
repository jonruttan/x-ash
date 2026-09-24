## sh-eval OPTIND when the shell starts

`OPTIND` is 1 when a shell starts, before any `getopts` has set it and
whatever the environment held: POSIX has the shell set it, and dash and bash
do.

Expectations match `/bin/sh` and `dash`.  The second case is a pin that holds
on main too.

### before any getopts

The shell running these specs set it when it started; the specs that call
getopts do so in a subshell, so its value here is still that one.

```sh
(do (sh-eval "( echo \"[$OPTIND]\" )") ())
```
---
    [1]

### getopts moves it on, and a subshell inherits it

```sh
(do (sh-eval "( set -- -a -b; getopts ab o; echo \"$o $OPTIND\"; ( echo \"[$OPTIND]\" ) ) | tr '\\n' ','; echo") ())
```
---
    a 2,[2],
