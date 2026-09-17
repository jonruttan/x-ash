## sh-eval a shift is not a here-document

A here-document starts at `<<` outside quotes.  Inside an arithmetic expansion
`<<` is a shift, so the expansion is passed over whole when the here-documents
are lifted out of a text: `$((a<<2))` is four, and the lines after it are
commands, not a here-document's body.

Expectations match `/bin/sh` and `dash`.

### a shift in an assignment leaves the next line a command

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "a=1; a=$((a<<2)); printf \"[%s]\" \"$a\"" "printf \"[next]\"; echo"))) ())
```
---
    [4][next]

### shifts in arguments

```sh
(do (sh-eval "printf \"[%s]\" $((1<<4)) $(( 3 << 1 )); echo") ())
```
---
    [16][6]

### a shift in a subshell

```sh
(do (sh-eval "( a=$((1<<2)); printf \"[%s]\" \"$a\" ); echo") ())
```
---
    [4]

### a shifting assignment operator

```sh
(do (sh-eval "n=2; : $((n<<=1)); printf \"[%s]\" \"$n\"; echo") ())
```
---
    [4]

### a here-document after a shift on the same line

```sh
(do (sh-eval (Str8 join nl (list "x=$((1<<2)); cat <<EOF" "body $x" "EOF"))) ())
```
---
    body 4

### a here-document in a command substitution is still one

```sh
(do (sh-eval (Str8 join nl (list "v=$(cat <<EOF" "inner" "EOF" "); printf \"[%s]\" \"$v\"; echo"))) ())
```
---
    [inner]

### so is a quoted shift not one

```sh
(do (sh-eval "printf \"[%s]\" \"$((2<<1))\"; echo") ())
```
---
    [4]

### nor a shift in a here-document's body

```sh
(do (sh-eval (Str8 join nl (list "cat <<EOF" "$((1<<3))" "EOF"))) ())
```
---
    8
