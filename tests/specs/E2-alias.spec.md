## sh-eval alias and unalias

`alias NAME=VALUE` makes an unquoted word NAME, where a command's name stands,
read as VALUE instead (POSIX 2.3.1).  A script runs one complete command at a
time, each read to its end before it runs (POSIX 2.3), so an alias is in
effect from the next complete command on: not for the rest of the line that
defines it, and not inside an `if` or a function body read along with the
definition.  A function's body is read when the function is defined, and keeps
the aliases it was read with.

Expectations match `/bin/sh` (bash 3.2) and `dash`, with these choices where
they part:

- A redirection in front of the name, `2>/dev/null ll`, leaves it the
  command's name, and it is substituted: POSIX and dash.  bash 3.2 runs `ll`.
- `alias` writes a value's single quote as `'\''`, as bash does and as this
  shell's `export -p` and `trap` do; dash writes `'"'"'`.  Both read back.
- `unalias` with no operand is a usage error, 2: POSIX asks for a name or
  `-a`, and bash answers 2; dash answers 0.
- `alias --` passes over the `--`, as POSIX writes its own `alias -- -0=...`
  example; dash reads `--` as a name and answers 1.

Each case clears the aliases it made.  Cases that hold on main as well are
stated as pins: they keep the boundaries of a complete command where they are.

### an alias stands for its value from the next command on

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo long'\nzq9 x"))
    (sh-eval "unalias -a") ())
```
---
    long x

### not in the rest of the line that defines it

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo long'; zq9 x 2>/dev/null; a=$?\nb=$(zq9 y); echo \"$a $b\""))
    (sh-eval "unalias -a") ())
```
---
    127 long y

### alias writes every definition sorted, quoted to be read back

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=\"echo it's\" zq8=ls\nalias | tr '\\n' ,; echo"))
    (sh-eval "unalias -a") ())
```
---
    zq8='ls',zq9='echo it'\''s',

### alias NAME writes one, and a name with none answers 1

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo a'\n{ alias zq9 zq7 zq9 2>/dev/null; echo \"st=$?\"; } | tr '\\n' ,; echo"))
    (sh-eval "unalias -a") ())
```
---
    zq9='echo a',zq9='echo a',st=1,

### unalias removes, and a name with none answers 1 and the rest go on

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=a zq8=b\n{ unalias zq7 zq9 2>/dev/null; echo \"st=$?\"; alias; } | tr '\\n' ,; echo"))
    (sh-eval "unalias -a") ())
```
---
    st=1,zq8='b',

### unalias -a removes every one

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=a zq8=b\nunalias -a; alias zq7=c; alias"))
    (sh-eval "unalias -a") ())
```
---
    zq7='c'

### pin: unalias with no operand is a usage error

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "unalias 2>/dev/null; echo \"st=$?\""))
    (sh-eval "unalias -a") ())
```
---
    st=2

### alias -- passes over the --

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias -- zq9='echo dd'\nzq9"))
    (sh-eval "unalias -a") ())
```
---
    dd

### a value ending in a blank lets the next word be an alias too

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo ' zq8=word\nzq9 zq8"))
    (sh-eval "unalias -a") ())
```
---
    word

### after a blank the next word is still no reserved word

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo '\nzq9 if"))
    (sh-eval "unalias -a") ())
```
---
    if

### an alias is not substituted inside its own value

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias echo='echo [e]'\necho x"))
    (sh-eval "unalias -a") ())
```
---
    [e] x

### nor inside the value of an alias its value names

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='zq8' zq8='echo x; zq9'\n{ zq9 2>/dev/null; echo \"st=$?\"; } | tr '\\n' ,; echo"))
    (sh-eval "unalias -a") ())
```
---
    x,st=127,

### a reserved word is recognized before an alias, and a value may be one

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=if if=echo\nzq9 true; then echo y; fi"))
    (sh-eval "unalias -a") ())
```
---
    y

### the name after assignments and redirections is substituted

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=echo\nX=1 2>/dev/null zq9 hi"))
    (sh-eval "unalias -a") ())
```
---
    hi

### a quoted word is not substituted

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=echo\n'zq9' a 2>/dev/null; x=$?; \\zq9 b 2>/dev/null; y=$?; zq9 \"$x $y\""))
    (sh-eval "unalias -a") ())
```
---
    127 127

### an empty value leaves the next word the command's name

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=''\nzq9 echo empty"))
    (sh-eval "unalias -a") ())
```
---
    empty

### a value may end a command, and one may follow it

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo a;'\n{ zq9 echo b; } | tr '\\n' ,; echo"))
    (sh-eval "unalias -a") ())
```
---
    a,b,

### the value is expanded where it is used

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo \"$v\"'\nv=late; zq9"))
    (sh-eval "unalias -a") ())
```
---
    late

### an if spanning lines is read whole before it runs

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='printf %s, out'\nif true; then\n  alias zq9='printf %s, in'\n  zq9\nfi\nzq9; echo"))
    (sh-eval "unalias -a") ())
```
---
    out,in,

### a function body is read when the function is defined

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo one'\nf() {\n  zq9\n}\nalias zq9='echo two'\nf"))
    (sh-eval "unalias -a") ())
```
---
    one

### a function's body may start on the line after its ()

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo a'\nf()\n{ zq9; }\nf"))
    (sh-eval "unalias -a") ())
```
---
    a

### pin: a line ending in && goes on into the next

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo a' &&\nzq9 2>/dev/null; echo \"st=$?\""))
    (sh-eval "unalias -a") ())
```
---
    st=127

### subshells, eval and command substitutions see the aliases

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo in'\n{ ( zq9 sub ); eval 'zq9 ev'; echo \"$(zq9 cs)\"; } | tr '\\n' ,; echo"))
    (sh-eval "unalias -a") ())
```
---
    in sub,in ev,in cs,

### eval reads its text a command at a time

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "eval 'alias zq9=echo\nzq9 evald'"))
    (sh-eval "unalias -a") ())
```
---
    evald

### pin: an alias made in a command substitution stays there

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "x=$(alias zq9=echo)\nzq9 hi 2>/dev/null; echo \"st=$?\""))
    (sh-eval "unalias -a") ())
```
---
    st=127

### an alias outlives the text that made it

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo two'")
      (sh-eval "zq9 x"))
    (sh-eval "unalias -a") ())
```
---
    two x
