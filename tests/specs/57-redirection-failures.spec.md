## sh-eval a redirection that cannot be made

A redirection the shell cannot make is reported, and the command it belongs to
does not run: its status is not 0 and the shell goes on.  A special builtin is
the exception POSIX names -- a redirection error on one ends a shell that is
not interactive.

The status itself is the shell's to choose: dash answers 2 and bash 1, so the
cases ask only that it is not 0.  Expectations match `/bin/sh` and `dash`.

### a file that cannot be created fails the command

```sh
(do (sh-eval "echo hi > /nonexistent/dir/x 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; printf \"[after]\"; echo") ())
```
---
    [failed][after]

### and is reported

```sh
(do (sh-eval "x=$( { echo hi > /nonexistent/dir/x; } 2>&1 ); [ -n \"$x\" ] && printf \"[reported]\"; printf \"[end]\"; echo") ())
```
---
    [reported][end]

### a file that cannot be opened for reading fails it too

```sh
(do (sh-eval "cat < /nonexistent/file 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; printf \"[after]\"; echo") ())
```
---
    [failed][after]

### as does a descriptor nothing is open on

```sh
(do (sh-eval "echo hi >&9 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; printf \"[after]\"; echo") ())
```
---
    [failed][after]

### the command does not run

```sh
(do (sh-eval "out=$( ls /dev/null > /nonexistent/dir/x 2>/dev/null ); printf \"[out:%s]\" \"$out\"; echo") ())
```
---
    [out:]

### nor does a compound command

```sh
(do (sh-eval "out=$( for i in 1; do printf \"[ran]\"; done > /nonexistent/dir/x 2>/dev/null ); printf \"[out:%s]\" \"$out\"; echo") ())
```
---
    [out:]

### nor a function

```sh
(do (sh-eval "f() { printf \"[ran]\"; }; out=$( f > /nonexistent/dir/x 2>/dev/null ); printf \"[out:%s]\" \"$out\"; echo") ())
```
---
    [out:]

### on a special builtin it ends the shell

```sh
(do (sh-eval "( : > /nonexistent/dir/x 2>/dev/null; printf \"[continued]\" ); [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [failed]

### a redirection that can be made still is

```sh
(do (sh-eval "out=$( echo one > /dev/null; echo two ); printf \"[%s:%s]\" \"$out\" \"$?\"; echo") ())
```
---
    [two:0]
