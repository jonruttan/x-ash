## sh-eval diagnostics go to stderr

A shell reports on standard error so that a caller can silence it, redirect
it, or capture the command's real output without it.  Two of ash's own
diagnostics went to standard OUTPUT instead -- a missing command and a failed
`cd` -- which made `2>/dev/null` useless against them and, worse, put them
inside `x=$(...)` as if they were the command's answer.

These cases fail on the old code by capturing the message; they are not
merely a status check, which would have passed either way.  Each expectation
was taken from `/bin/sh` first.

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
