## sh-eval a descriptor number and a word of digits

Digits written against a redirection operator name its descriptor: `2>err`.
Digits a blank separates from the operator are a word like any other, and so
is a word an expansion or quoting makes, whatever it holds: `echo 2 >out`
and `echo "$n" >out` write the word to out.  The tokenizer is where the two
are told apart, so the digits of `2>err` reach the parser as a tok-io.

Expectations match `/bin/sh` and `dash`.

### digits against the operator are a descriptor number

```sh
(write (sh-tokenize "echo 2>f"))
```
---
    ((tok-word "echo") (tok-io "2") (tok-op ">") (tok-word "f"))

### digits a blank separates are a word

```sh
(write (sh-tokenize "echo 2 >f"))
```
---
    ((tok-word "echo") (tok-word "2") (tok-op ">") (tok-word "f"))

### a number is written to the file

```sh
(do (sh-eval "( f=$(mktemp); echo 12345 > \"$f\"; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    12345

### so is a variable holding one

```sh
(do (sh-eval "( f=$(mktemp); n=7; echo \"$n\" > \"$f\"; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    7

### a pid file

```sh
(do (sh-eval "( f=$(mktemp); echo \"$$\" > \"$f\"; [ \"$(cat \"$f\")\" = \"$$\" ] && echo pid-written; rm -f \"$f\" )") ())
```
---
    pid-written

### printf's last argument

```sh
(do (sh-eval "( f=$(mktemp); printf '%d\\n' 42 > \"$f\"; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    42

### a quoted digit

```sh
(do (sh-eval "( f=$(mktemp); echo \"1\" > \"$f\"; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    1

### a digit before >&2 is an argument

```sh
(do (sh-eval "( x=$( (echo 1 >&2) 2>&1 ); echo \"[$x]\" )") ())
```
---
    [1]

### every argument reaches the file

```sh
(do (sh-eval "( f=$(mktemp); echo 1 2 3 > \"$f\"; cat \"$f\"; rm -f \"$f\" )") ())
```
---
    1 2 3

### and each append

```sh
(do (sh-eval "( f=$(mktemp); x=10; echo $x >> \"$f\"; echo $x >> \"$f\"; wc -l < \"$f\" | tr -d ' '; rm -f \"$f\" )") ())
```
---
    2

### a digit before < is a file name

```sh
(do (sh-eval "( f=$(mktemp); echo hi > \"$f\"; cat 0 < \"$f\" 2>/dev/null || echo no-file-0; rm -f \"$f\" )") ())
```
---
    no-file-0

### a group's descriptor number

```sh
(do (sh-eval "( x=$( { echo out; echo err >&2; } 2>&1 ); echo $x )") ())
```
---
    out err

### a word of digits, then a descriptor number

```sh
(do (sh-eval "( x=$(echo 12 2>/dev/null); echo \"[$x]\" )") ())
```
---
    [12]
