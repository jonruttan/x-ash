## sh-eval read at the end of the input

`read` assigns every name it is given, and answers 1 when it met the end of
the input.  With nothing left to read the names are assigned empty: so after
`while read line; do ...; done` the variable is empty rather than the last
line.  A last line without a newline is still assigned, with status 1.

Expectations match `/bin/sh` and `dash`.

### nothing to read empties the name

```sh
(do (sh-eval "v=abc; read v < /dev/null; printf \"[%s][%s]\" \"$v\" \"$?\"; echo") ())
```
---
    [][1]

### every name

```sh
(do (sh-eval "a=1 b=2; read a b < /dev/null; printf \"[%s][%s][%s]\" \"$a\" \"$b\" \"$?\"; echo") ())
```
---
    [][][1]

### with -r as well

```sh
(do (sh-eval "printf '' | { v=keep; read -r v; printf \"[%s][%s]\" \"$v\" \"$?\"; }; echo") ())
```
---
    [][1]

### so a read loop leaves its variable empty

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "line=before" "while read line; do printf \"[%s]\" \"$line\"; done <<EOF" "l1" "l2" "EOF" "printf \"[after:%s]\" \"$line\"; echo"))) ())
```
---
    [l1][l2][after:]

### a last line without a newline is assigned

```sh
(do (sh-eval "printf 'abc' | { v=old; read v; printf \"[%s][%s]\" \"$v\" \"$?\"; }; echo") ())
```
---
    [abc][1]

### and a name it has no field for is emptied

```sh
(do (sh-eval "printf 'x y' | { a=1 b=2 c=3; read a b c; printf \"[%s][%s][%s][%s]\" \"$a\" \"$b\" \"$c\" \"$?\"; }; echo") ())
```
---
    [x][y][][1]

### a loop does not run for a last line without a newline

```sh
(do (sh-eval "printf 'last' | while read l; do printf \"[%s]\" \"$l\"; done; printf \"[end]\"; echo") ())
```
---
    [end]
