## sh-eval type and command report aliases

`command -v NAME` answers what would run, and for an alias that is the `alias`
command that would define it (POSIX).  `command -V NAME` and `type NAME` say
what the name is, and an alias is "an alias for" its value.  A reserved word is
taken before an alias of the same name, as the shell reads it, and an alias
before a function or a builtin.

Expectations match `dash`.  `/bin/sh` (bash 3.2) agrees on `command -v`; for
`-V` and `type` it says "is aliased to `...'", and this shell's `type` already
says what dash says of keywords, builtins and functions.  bash also reports an
alias named `if` ahead of the reserved word, where dash, and this shell's
reader, take the reserved word.  A single quote in a value is written `'\''`,
as `alias` writes it.

Each case clears the aliases it made.  A case that holds on main as well is
stated as a pin.

### type says an alias is one

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo x'\ntype zq9"))
    (sh-eval "unalias -a") ())
```
---
    zq9 is an alias for echo x

### command -V says it as type does

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo x'\ncommand -V zq9"))
    (sh-eval "unalias -a") ())
```
---
    zq9 is an alias for echo x

### command -v writes the alias command that would define it

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9='echo x'\ncommand -v zq9"))
    (sh-eval "unalias -a") ())
```
---
    alias zq9='echo x'

### a single quote in the value is written to be read back

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=\"echo it's\"\ncommand -v zq9"))
    (sh-eval "unalias -a") ())
```
---
    alias zq9='echo it'\''s'

### an alias is found before a function of the same name

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "zq9() { :; }\nalias zq9='echo a'\ntype zq9"))
    (sh-eval "unalias -a; unset -f zq9") ())
```
---
    zq9 is an alias for echo a

### an alias is found before a builtin of the same name

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias echo='echo x'\ncommand -v echo"))
    (sh-eval "unalias -a") ())
```
---
    alias echo='echo x'

### both answer 0 for an alias

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=x\ncommand -v zq9 >/dev/null; a=$?; type zq9 >/dev/null; echo \"$a $?\""))
    (sh-eval "unalias -a") ())
```
---
    0 0

### pin: a reserved word is taken before an alias of its name

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias if=echo\n{ type if; command -v if; } | tr '\\n' ,; echo"))
    (sh-eval "unalias -a") ())
```
---
    if is a shell keyword,if,

### pin: an alias removed is found nowhere

```sh
(do (guard (e (do (display "error: ") (write e) (newline)))
      (sh-eval "alias zq9=x\nunalias zq9\ncommand -v zq9 || echo none"))
    (sh-eval "unalias -a") ())
```
---
    none
