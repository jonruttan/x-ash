## sh-eval dot scripts

`.` reads a file and runs it in the shell that named it.  A `return` in the file
ends the file, with its status, and the shell goes on after the `.` -- inside a
function too, which then carries on.  `break` and `continue` in the file act on
the loop the `.` runs in.  An error in the file is that error, and ends the
shell the way the same error anywhere else would; a file that cannot be read is
an error of the `.` itself, which ends a shell that is not interactive.

Each case writes the files it sources into a directory of its own.  Expectations
match `/bin/sh` and `dash`.

### return ends the file with its status

```sh
(do (sh-eval "d=$(mktemp -d); printf 'printf \"[in]\"\\nreturn 3\\nprintf \"[not]\"\\n' > \"$d/f.sh\"; ( . \"$d/f.sh\"; printf \"[st:%s]\" $? ); rm -rf \"$d\"; echo") ())
```
---
    [in][st:3]

### inside a function, which carries on

```sh
(do (sh-eval "d=$(mktemp -d); printf 'printf \"[in]\"\\nreturn 3\\n' > \"$d/f.sh\"; ( g() { . \"$d/f.sh\"; printf \"[after:%s]\" $?; return 7; }; g; printf \"[g:%s]\" $? ); rm -rf \"$d\"; echo") ())
```
---
    [in][after:3][g:7]

### break in the file acts on the loop around the dot

```sh
(do (sh-eval "d=$(mktemp -d); printf 'break\\n' > \"$d/f.sh\"; ( for i in 1 2 3; do . \"$d/f.sh\"; printf \"[%s]\" $i; done; printf \"[end]\" ); rm -rf \"$d\"; echo") ())
```
---
    [end]

### and a loop inside the file keeps its own break

```sh
(do (sh-eval "d=$(mktemp -d); printf 'for i in 1 2; do break; done\\nprintf \"[b]\"\\n' > \"$d/f.sh\"; ( . \"$d/f.sh\"; printf \"[st:%s]\" $? ); rm -rf \"$d\"; echo") ())
```
---
    [b][st:0]

### an error in the file ends the shell that ran it

```sh
(do (sh-eval "d=$(mktemp -d); printf 'printf \"[x]\"; : $((1/0))\\nprintf \"[y]\"\\n' > \"$d/f.sh\"; ( . \"$d/f.sh\"; printf \"[continued]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; rm -rf \"$d\"; echo") ())
```
---
    [x][failed]

### so does a file that cannot be read

```sh
(do (sh-eval "( . /nonexistent/dir/f.sh; printf \"[continued]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [failed]

### what the file sets stays set

```sh
(do (sh-eval "d=$(mktemp -d); printf 'dot_value=set\\n' > \"$d/f.sh\"; ( . \"$d/f.sh\"; printf \"[%s]\" \"$dot_value\" ); rm -rf \"$d\"; echo") ())
```
---
    [set]
