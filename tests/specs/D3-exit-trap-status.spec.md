## sh-eval `$?` in an EXIT trap

The EXIT trap sees, as `$?`, the status the shell is leaving with -- an
`exit N`'s N, or the last command's status when the script runs out -- and the
shell leaves with that status whatever the trap's commands answer, unless the
trap calls `exit` itself.

Expectations match `/bin/sh` and `dash`.  The second case is a pin that holds
on main too: a shell that runs out has its last status in `$?` already.

### the status an `exit` gives

```sh
(do (sh-eval "( ( trap 'echo \"trap-status=$?\"' EXIT; exit 5 ); echo \"left=$?\" ) | tr '\\n' ','; echo") ())
```
---
    trap-status=5,left=5,

### the status a subshell ends with, and one a failed command leaves

```sh
(do (sh-eval "( ( trap 'echo \"u:$?\"' EXIT; (exit 3) ); echo \"left=$?\"; ( trap 'echo \"t:$?\"' EXIT; false ); echo \"left=$?\" ) | tr '\\n' ','; echo") ())
```
---
    u:3,left=3,t:1,left=1,

### the trap's own commands do not change it, and its `exit` does

```sh
(do (sh-eval "( ( trap 'false' EXIT; exit 5 ); echo \"a=$?\"; ( trap 'echo \"in:$?\"; exit 7' EXIT; exit 5 ); echo \"b=$?\" ) | tr '\\n' ','; echo") ())
```
---
    a=5,in:5,b=7,
