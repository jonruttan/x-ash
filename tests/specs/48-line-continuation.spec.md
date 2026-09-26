## sh-eval a backslash before a newline

A backslash before a newline joins the two lines: the pair is removed before
the text is read as tokens, so a command, a word or an operator may go on on
the next line.  That holds outside quotes, inside double quotes and in the
lines of a here-document whose delimiter is unquoted.  Inside single quotes, in
a comment and in a here-document with a quoted delimiter, both characters stay.

Expectations match `/bin/sh` and `dash`.

### a command goes on on the next line

```sh
(do (def nl (make-string 1 (integer->char 10))) (sh-eval (Str8 join nl (list "printf \"[%s]\" a \\" "b; echo"))) ())
```
---
    [a][b]

### so does a word

```sh
(do (sh-eval (Str8 join nl (list "printf \"[%s]\" a\\" "b; echo"))) ())
```
---
    [ab]

### and a command name

```sh
(do (sh-eval (Str8 join nl (list "prin\\" "tf \"[%s]\" joined; echo"))) ())
```
---
    [joined]

### and an operator

```sh
(do (sh-eval (Str8 join nl (list "true &\\" "& printf \"[and]\"; echo"))) ())
```
---
    [and]

### a reserved word after a continuation is still one

```sh
(do (sh-eval (Str8 join nl (list "if true; \\" "then printf \"[then]\"; fi; echo"))) ())
```
---
    [then]

### one continuation may follow another

```sh
(do (sh-eval (Str8 join nl (list "printf \"[%s]\" a\\" "\\" "b; echo"))) ())
```
---
    [ab]

### inside double quotes the pair is removed

```sh
(do (sh-eval (Str8 join nl (list "printf \"[%s]\" \"a\\" "b\"; echo"))) ())
```
---
    [ab]

### inside single quotes it stays

```sh
(do (sh-eval (Str8 join nl (list "printf \"[%s]\" 'a\\" "b' | tr '\\n' '~'; echo"))) ())
```
---
    [a\~b]

### a comment ends at its newline, backslash or not

```sh
(do (sh-eval (Str8 join nl (list "printf \"[%s]\" a # note \\" "printf \"[%s]\" b; echo"))) ())
```
---
    [a][b]

### an escaped backslash does not join

```sh
(do (sh-eval (Str8 join nl (list "printf \"[%s]\" a\\\\" "printf \"[%s]\" b; echo"))) ())
```
---
    [a\][b]

### a command substitution joins inside

```sh
(do (sh-eval (Str8 join nl (list "v=$(echo a\\" "b); printf \"[%s]\" \"$v\"; echo"))) ())
```
---
    [ab]

### single quotes in a substitution in double quotes keep theirs

```sh
(do (sh-eval (Str8 join nl (list "printf \"[%s]\" \"$(echo 'a\\" "b')\" | tr '\\n' '~'; echo"))) ())
```
---
    [a\~b]

### parameter and arithmetic expansions join

```sh
(do (sh-eval (Str8 join nl (list "printf \"[%s]\" ${lc_unset:-a\\" "b} $((1+\\" "2)); echo"))) ())
```
---
    [ab][3]

### a for list goes on

```sh
(do (sh-eval (Str8 join nl (list "for i in 1 \\" "2; do printf \"[%s]\" $i; done; echo"))) ())
```
---
    [1][2]

### an unquoted here-document joins its lines

```sh
(do (sh-eval (Str8 join nl (list "cat <<EOF | tr '\\n' '~'" "a \\" "b" "EOF" "echo"))) ())
```
---
    a b~

### before its delimiter is looked for

```sh
(do (sh-eval (Str8 join nl (list "cat <<EOF | tr '\\n' '~'" "x\\" "EOF" "EOF" "echo"))) ())
```
---
    xEOF~

### a quoted delimiter keeps both characters

```sh
(do (sh-eval (Str8 join nl (list "cat <<'EOF' | tr '\\n' '~'" "a \\" "b" "EOF" "echo"))) ())
```
---
    a \~b~
