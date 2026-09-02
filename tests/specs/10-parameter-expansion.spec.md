## sh-eval default and alternative

### :- uses the word when unset

```sh
(do (sh-eval "echo [${NOSUCH_ASH:-fallback}]") ())
```
---
    [fallback]

### :- uses the word when null

```sh
(do (sh-eval "X=; echo [${X:-fallback}]") ())
```
---
    [fallback]

### :- leaves a set value alone

```sh
(do (sh-eval "X=v; echo [${X:-fallback}]") ())
```
---
    [v]

### the colonless form treats null as SET

```sh
(do (sh-eval "X=; echo [${X-fallback}]") ())
```
---
    []

### the colonless form still fires when unset

```sh
(do (sh-eval "echo [${NOSUCH_ASH-fallback}]") ())
```
---
    [fallback]

### := assigns as well as answering

```sh
(do (sh-eval "echo -n [${ASSIGNED_ASH:=set-here}]; echo :[$ASSIGNED_ASH]") ())
```
---
    [set-here]:[set-here]

### :+ answers the word only when SET

```sh
(do (sh-eval "X=v; echo [${X:+alt}]") ())
```
---
    [alt]

### :+ answers nothing when unset

```sh
(do (sh-eval "echo [${NOSUCH_ASH:+alt}]") ())
```
---
    []

### the word is itself expanded

```sh
(do (sh-eval "Y=inner; echo [${NOSUCH_ASH:-${Y}}]") ())
```
---
    [inner]

### the word may be a command substitution

```sh
(do (sh-eval "echo [${NOSUCH_ASH:-$(echo sub)}]") ())
```
---
    [sub]

### it works inside double quotes

```sh
(do (sh-eval "echo \"q=${NOSUCH_ASH:-dq}\"") ())
```
---
    q=dq

## sh-eval length

### ${#name} is the length of the value

```sh
(do (sh-eval "X=hello; echo ${#X}") ())
```
---
    5

### the length of a null value is 0

```sh
(do (sh-eval "X=; echo ${#X}") ())
```
---
    0

### ${#} alone is still the parameter count

```sh
(do (sh-eval "f() { echo ${#}; }; f a b c") ())
```
---
    3

## sh-eval prefix and suffix removal

### # removes the shortest matching prefix

```sh
(do (sh-eval "X=aabbcc; echo ${X#a}") ())
```
---
    abbcc

### ## removes the longest matching prefix

```sh
(do (sh-eval "X=aabbcc; echo ${X##a*b}") ())
```
---
    cc

### % removes the shortest matching suffix

```sh
(do (sh-eval "X=file.tar.gz; echo ${X%.*}") ())
```
---
    file.tar

### %% removes the longest matching suffix

```sh
(do (sh-eval "X=file.tar.gz; echo ${X%%.*}") ())
```
---
    file

### a pattern that does not match leaves the value alone

```sh
(do (sh-eval "X=abc; echo ${X#zz}") ())
```
---
    abc

### the basename idiom

```sh
(do (sh-eval "P=/usr/local/bin/tool; echo ${P##*/}") ())
```
---
    tool

### the dirname idiom

```sh
(do (sh-eval "P=/usr/local/bin/tool; echo ${P%/*}") ())
```
---
    /usr/local/bin

### the pattern is expanded first

```sh
(do (sh-eval "S=.gz; X=f.tar.gz; echo ${X%$S}") ())
```
---
    f.tar

## sh-eval unknown and degenerate forms

### an unclosed brace is literal

```sh
(do (sh-eval "echo ${X") ())
```
---
    ${X

### a plain ${name} still expands

```sh
(do (sh-eval "X=v; echo ${X}ly") ())
```
---
    vly

### an unset plain ${name} is empty

```sh
(do (sh-eval "echo [${NOSUCH_ASH}]") ())
```
---
    []
