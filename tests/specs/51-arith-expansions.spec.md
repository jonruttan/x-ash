## sh-eval expansions inside arithmetic

An arithmetic expansion's expression is expanded as double-quoted text before
it is evaluated: parameters, command substitutions and nested arithmetic give
it text, which the evaluator then reads (POSIX 2.6.4).  So `$x` and `x` both
read a variable, but `$x` puts its value in as text, and a substitution runs
even in a branch the evaluation does not take.  An expression with nothing to
expand is not walked by the expander.

Expectations match `/bin/sh` and `dash`.

### a parameter in an expression

```sh
(do (sh-eval "x=5; printf \"[%s]\" $(($x*2)) $((x*2)); echo") ())
```
---
    [10][10]

### a counter written with a dollar

```sh
(do (sh-eval "i=0; while [ $i -lt 3 ]; do i=$(($i+1)); done; printf \"[%s]\" \"$i\"; echo") ())
```
---
    [3]

### positional and special parameters

```sh
(do (sh-eval "set -- 4 5; printf \"[%s]\" $(($1+$2)) $(($#*10)); echo") ())
```
---
    [9][20]

### a parameter expansion with an operator

```sh
(do (sh-eval "v=abc; printf \"[%s]\" $((${#v}+1)) $((1+${lc_unset:-2})); echo") ())
```
---
    [4][3]

### nested arithmetic

```sh
(do (sh-eval "printf \"[%s]\" $((1+$((2)))); echo") ())
```
---
    [3]

### command substitutions of both spellings

```sh
(do (sh-eval "printf \"[%s]\" $((1+$(echo 2))) $((`echo 3`+1)); echo") ())
```
---
    [3][4]

### a value is put in as text

```sh
(do (sh-eval "x='1+2'; printf \"[%s]\" $(($x*3)); echo") ())
```
---
    [7]

### so an operator may come from a substitution

```sh
(do (sh-eval "printf \"[%s]\" $(( $(( 2 )) $(printf \"%s\" \"*\") 3 )); echo") ())
```
---
    [6]

### and a substitution runs where evaluation would not reach

```sh
(do (sh-eval "( printf \"[%s]\" $(( 0 && $(echo ran >&2; echo 1) )) ) 2>&1 | tr '\\n' ' '; echo") ())
```
---
    ran [0]

### a conditional with parameters

```sh
(do (sh-eval "x=3; printf \"[%s]\" \"$(( x > 2 ? $x * 2 : 0 ))\"; echo") ())
```
---
    [6]

### an expression with nothing to expand is not walked

```sh
(let ((cost (fn (_ thunk) (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%sh-arith-text "(count + 1)" 1 10)))
     (cost (fn (_) (%sh-expand-str-dq "count + 1")))))
```
---
    #t
