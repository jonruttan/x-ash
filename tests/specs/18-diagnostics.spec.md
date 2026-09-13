## sh-eval diagnostics go to stderr

A shell reports on standard error so a caller can silence or redirect it
without losing the command's real output. These check that ash's diagnostics --
a missing command, a failed `cd` -- go to stderr, so `2>/dev/null` silences
them and `x=$(...)` does not capture them.

### a command substitution does not capture the not-found message

```sh
(do (sh-eval "x=$(nosuchcmd_zz); echo \"[$x]\"") ())
```
---
    []

### nor does it when the caller silenced stderr

```sh
(do (sh-eval "x=$(nosuchcmd_zz 2>/dev/null); echo \"[$x]\"") ())
```
---
    []

### a failed cd reports without joining the output

```sh
(do (sh-eval "y=$(cd /nosuchdir_zz; echo done); echo \"[$y]\"") ())
```
---
    [done]

### 2>/dev/null silences a missing command, and the status stands

```sh
(do (sh-eval "nosuchcmd_zz 2>/dev/null; echo $?") ())
```
---
    127

### and silences a failed cd, whose status also stands

```sh
(do (sh-eval "cd /nosuchdir_zz 2>/dev/null; echo $?") ())
```
---
    1
