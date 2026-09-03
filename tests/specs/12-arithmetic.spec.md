## sh-eval arithmetic expansion

### addition

```sh
(do (sh-eval "echo $((1+2))") ())
```
---
    3

### multiplication binds tighter than addition

```sh
(do (sh-eval "echo $((2+3*4))") ())
```
---
    14

### parentheses override precedence

```sh
(do (sh-eval "echo $(( (2+3) * 4 ))") ())
```
---
    20

### subtraction is left-associative

```sh
(do (sh-eval "echo $((10-3-2))") ())
```
---
    5

### division truncates toward zero

```sh
(do (sh-eval "echo $((10/3))") ())
```
---
    3

### and truncates toward zero for negatives too

```sh
(do (sh-eval "echo $((-10/3))") ())
```
---
    -3

### modulo

```sh
(do (sh-eval "echo $((10%3))") ())
```
---
    1

### unary minus

```sh
(do (sh-eval "echo $((-5+8))") ())
```
---
    3

### logical not

```sh
(do (sh-eval "echo $((!0)) $((!7))") ())
```
---
    1 0

### division by zero is an error

```sh
(write (guard (e (lit raised)) (sh-eval "echo $((1/0))")))
```
---
    raised

## sh-eval arithmetic and variables

### a name evaluates to its value

```sh
(do (sh-eval "N=5; echo $((N*2))") ())
```
---
    10

### an unset name is zero

```sh
(do (sh-eval "echo $((NOSUCHVAR_ASH+1))") ())
```
---
    1

### a non-numeric value is zero

```sh
(do (sh-eval "X=abc; echo $((X+7))") ())
```
---
    7

### the result can be assigned

```sh
(do (sh-eval "N=1; N=$((N+1)); echo $N") ())
```
---
    2

### a counting loop terminates

```sh
(do (sh-eval "i=0; while test $i -lt 3; do echo -n $i; i=$((i+1)); done; echo :end") ())
```
---
    012:end

## sh-eval arithmetic comparisons

### less-than and greater-than

```sh
(do (sh-eval "echo $((3<5)) $((3>5))") ())
```
---
    1 0

### the or-equal forms

```sh
(do (sh-eval "echo $((3<=3)) $((3>=4))") ())
```
---
    1 0

### equality

```sh
(do (sh-eval "echo $((4==4)) $((4!=4))") ())
```
---
    1 0

### and / or

```sh
(do (sh-eval "echo $((1&&0)) $((1||0))") ())
```
---
    0 1

## sh-eval telling $(( from $(

### a substitution is still a substitution

```sh
(do (sh-eval "echo $(echo hi)") ())
```
---
    hi

### a space makes a subshell inside a substitution

```sh
(do (sh-eval "echo $( (echo sub) )") ())
```
---
    sub

### arithmetic inside double quotes

```sh
(do (sh-eval "echo \"n=$((2*3))\"") ())
```
---
    n=6

### single quotes suppress it

```sh
(do (sh-eval "echo '$((1+1))'") ())
```
---
    $((1+1))
