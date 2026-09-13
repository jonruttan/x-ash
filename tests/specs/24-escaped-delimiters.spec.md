## sh-eval a backslash protects a word delimiter

Outside quotes a backslash protects the character after it, including the
characters that would otherwise end the word, so `a\ b` is one word. Checked
against `/bin/sh` with `printf` rather than `echo`, since dash's `echo`
interprets escapes of its own.

    echo a\ b

tokenized as `a\` and `b` -- two words, the first ending in a backslash that
protects nothing.  The expander then met that trailing backslash, found no
character for it to protect, and fell through to a run of length zero: the
walk recursed on the same index forever and allocated until the process was
killed.  It was a HANG, not a wrong answer, which is why it is worth its own
change.

### an escaped space is part of the word

```sh
(do (sh-eval "printf '[%s]\\n' a\\ b") ())
```
---
    [a b]

### and in an assignment's value

```sh
(do (sh-eval "v=a\\ b; printf '[%s]\\n' \"$v\"") ())
```
---
    [a b]

### several of them in one word

```sh
(do (sh-eval "printf '[%s]\\n' pre\\ mid\\ post") ())
```
---
    [pre mid post]

### an escaped semicolon does not end the command

```sh
(do (sh-eval "printf '[%s]\\n' a\;b") ())
```
---
    [a;b]

### an escaped pipe is not a pipeline

```sh
(do (sh-eval "printf '[%s]\\n' a\\|b") ())
```
---
    [a|b]

### an escaped backslash is one backslash

```sh
(do (sh-eval "printf '[%s]\\n' a\\\\b") ())
```
---
    [a\b]

### inside double quotes a backslash-space is literal, as POSIX says

```sh
(do (sh-eval "printf '[%s]\\n' \"a\\ b\"") ())
```
---
    [a\ b]

### the word still reaches a function as ONE argument

```sh
(do (sh-eval "f() { printf '[%s][%s]\\n' \"$1\" \"$2\"; }; f a\\ b c") ())
```
---
    [a b][c]
