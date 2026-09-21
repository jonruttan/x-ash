## sh-eval a descriptor opened by number

`n<file`, `n>file` and `n>>file` open the file as descriptor n.  With `exec`
it stays open for the commands that follow; on a compound command it is open
for the whole of it.  An open answers the lowest descriptor free, which can be
n itself, as it is for `exec 3<file` when 3 is free.  The pipe a
here-document arrives on is placed the same way, and so is a pipeline's or a
command substitution's when the shell has closed its stdin or stdout.

Expectations match `/bin/sh` and `dash`.

### exec opens a file for reading, and reads take its lines in turn

```sh
(do (sh-eval "( f=$(mktemp); printf 'a\\nb\\n' > \"$f\"; exec 3<\"$f\"; read -r x <&3; read -r y <&3; exec 3<&-; rm -f \"$f\"; echo \"$x$y\" )") ())
```
---
    ab

### a command reads from it

```sh
(do (sh-eval "( f=$(mktemp); printf 'a\\nb\\n' > \"$f\"; exec 3<\"$f\"; cat <&3; rm -f \"$f\" )") ())
```
---
    b

### a loop reads its lines from 3 and leaves stdin alone

```sh
(do (sh-eval "( f=$(mktemp); printf 'a\\nb\\n' > \"$f\"; while read -r l <&3; do printf '%s' \"$l\"; done 3<\"$f\"; echo; rm -f \"$f\" )") ())
```
---
    ab

### exec opens a file for writing

```sh
(do (sh-eval "( f=$(mktemp); exec 3>\"$f\"; echo logged >&3; exec 3>&-; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    logged

### and for appending

```sh
(do (sh-eval "( f=$(mktemp); echo one > \"$f\"; exec 3>>\"$f\"; echo two >&3; exec 3>&-; tail -1 \"$f\"; rm -f \"$f\" )") ())
```
---
    two

### a group writes through it

```sh
(do (sh-eval "( f=$(mktemp); exec 3>\"$f\"; { echo a; echo b; } >&3; exec 3>&-; wc -l < \"$f\" | tr -d ' '; rm -f \"$f\" )") ())
```
---
    2

### a here-document on 3

```sh
(do (sh-eval "( cat 3<<EOF <&3\non three\nEOF\n)") ())
```
---
    on three

### a pipeline when stdin is closed

```sh
(do (sh-eval "( exec <&-; echo hi | cat )") ())
```
---
    hi

### a command substitution when stdin and stdout are closed

```sh
(do (sh-eval "( exec <&- >&-; x=$(echo sub); echo \"$x\" >&2 ) 2>&1") ())
```
---
    sub
