## sh-eval function definitions

### a function runs when called

```sh
(do (sh-eval "f() { echo called; }; f") ())
```
---
    called

### a definition on its own answers 0

```sh
(sh-eval "f() { echo x; }")
```
---
    0

### a function sees its arguments

```sh
(do (sh-eval "f() { echo \"$1-$2\"; }; f a b") ())
```
---
    a-b

### $# counts the arguments

```sh
(do (sh-eval "f() { echo $#; }; f a b c") ())
```
---
    3

### $@ joins them

```sh
(do (sh-eval "f() { echo \"[$@]\"; }; f a b") ())
```
---
    [a b]

### $0 is the shell, not the function

```sh
(do (sh-eval "f() { echo $0; }; f a") ())
```
---
    ash

### an out-of-range parameter is empty

```sh
(do (sh-eval "f() { echo [$9]; }; f a") ())
```
---
    []

### ${10} reaches the tenth argument

```sh
(do (sh-eval "f() { echo ${10}; }; f 1 2 3 4 5 6 7 8 9 TEN") ())
```
---
    TEN

### a redefinition wins

```sh
(do (sh-eval "f() { echo old; }; f() { echo new; }; f") ())
```
---
    new

### a function beats an external of the same name

```sh
(do (sh-eval "true() { echo shadowed; }; echo ok") ())
```
---
    ok

## sh-eval return and shift

### return sets the status

```sh
(sh-eval "f() { return 7; }; f")
```
---
    7

### return stops the body

```sh
(do (sh-eval "f() { echo first; return 0; echo second; }; f") ())
```
---
    first

### a bare return uses the last status

```sh
(sh-eval "f() { false; return; }; f")
```
---
    1

### shift drops the first parameter

```sh
(do (sh-eval "f() { shift; echo \"[$@]\"; }; f a b c") ())
```
---
    [b c]

### shift n drops n

```sh
(do (sh-eval "f() { shift 2; echo \"[$@]\"; }; f a b c") ())
```
---
    [c]

### shifting past the end fails and changes nothing

```sh
(do (sh-eval "f() { shift 5; echo \"[$@]\"; }; f a b") ())
```
---
    [a b]

## sh-eval parameter scoping

### a call restores the caller's parameters

```sh
(do (sh-eval "inner() { echo \"in=$1\"; }; outer() { inner X; echo \"out=$1\"; }; outer Y") ())
```
---
    out=Y

### parameters do not leak to the top level

```sh
(do (sh-eval "f() { echo x; }; f a b; echo [$1]") ())
```
---
    []

## sh-eval function bodies containing braces and compounds

### a compound inside a body does not confuse the brace count

```sh
(do (sh-eval "f() { if true; then echo A; fi; }; f") ())
```
---
    A

### a case inside a body

```sh
(do (sh-eval "f() { case x in x) echo C ;; esac; }; f") ())
```
---
    C

### ${NAME} is not a body brace

```sh
(do (sh-eval "f() { X=v; echo ${X}; }; f") ())
```
---
    v

### a nested definition closes at its own brace

```sh
(do (sh-eval "f() { g() { echo inner; }; g; }; f") ())
```
---
    inner
