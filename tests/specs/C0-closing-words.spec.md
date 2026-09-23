## sh-eval a closing word where a command starts

`then`, `elif`, `else`, `fi`, `do`, `done`, `esac` and `}` are reserved where
a command could start, and there each closes a construct or is a syntax
error.  That holds at the top level as inside a construct: the text of an
`eval`, a dot script and the script itself refuse one that closes nothing, and
stop there.  Where a command cannot start the word is an argument, and quoted
or produced by an expansion it is a command's name.

Expectations match `/bin/sh` and `dash`, except where noted.  Ash reads and
runs a line's commands in turn, so a command in front of the stray word on
the same line has run by the time it is refused; the cases put the word on a
line of its own.  The loop's `done`, the dot script, the look-alike words and
the function's `echo done` are pins that hold on main too.

### every closing word is refused where a command starts

```sh
(do (sh-eval "( for w in fi done '}' then else elif do esac; do ( eval \"echo $w-before\n$w\necho $w-after\" ) 2>/dev/null || echo \"$w-refused\"; done ) | tr '\\n' ','; echo") ())
```
---
    fi-before,fi-refused,done-before,done-refused,}-before,}-refused,then-before,then-refused,else-before,else-refused,elif-before,elif-refused,do-before,do-refused,esac-before,esac-refused,

### and after a construct that is already closed

```sh
(do (sh-eval "( ( eval 'if true; then echo in; fi\nfi\necho after' ) 2>/dev/null || echo refused ) | tr '\\n' ','; echo") ())
```
---
    in,refused,

### a loop's `done` twice over

```sh
(do (sh-eval "( eval 'while false; do :; done\ndone' ) 2>/dev/null || echo refused") ())
```
---
    refused

### the script's own top level stops at one

```sh
(write (guard (e (lit raised)) (sh-eval "printf a\nfi\nprintf b")))
```
---
    araised

### a dot script's

```sh
(do (sh-eval "( d=$(mktemp -d); printf 'echo a\\nfi\\necho b\\n' > \"$d/f\"; ( . \"$d/f\" ) 2>/dev/null || echo failed; rm -rf \"$d\" ) | tr '\\n' ','; echo") ())
```
---
    a,failed,

### an `eval` inside a construct closes nothing outside it

A syntax error in the text of `eval` ends a shell that is not interactive, as
POSIX has a special built-in's error do, and as `dash` does; bash 3.2 goes on
to the next command.

```sh
(do (sh-eval "( if true; then eval fi; echo still; fi ) 2>/dev/null || echo refused") ())
```
---
    refused

### words that only look like closing words

```sh
(do (sh-eval "( echo fi done then; x=fi; $x 2>/dev/null || echo \"expanded:$?\"; \"done\" 2>/dev/null || echo \"quoted:$?\" ) | tr '\\n' ','; echo") ())
```
---
    fi done then,expanded:127,quoted:127,

### a function's `echo done`, called inside an `if`

```sh
(do (sh-eval "( f() { echo done; }; if true; then f; fi; echo done; echo end ) | tr '\\n' ','; echo") ())
```
---
    done,done,end,
