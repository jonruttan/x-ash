## sh-eval field splitting

A word is split on whitespace AFTER it expands, and only the expanded part is
split. The count is what these assert, so each runs through a function whose
body is `echo $#`.

### an unquoted expansion splits

```sh
(do (sh-eval "n() { echo $#; }; X=\"a b\"; n $X") ())
```
---
    2

### quoting it does not

```sh
(do (sh-eval "n() { echo $#; }; X=\"a b\"; n \"$X\"") ())
```
---
    1

### a command substitution splits

```sh
(do (sh-eval "n() { echo $#; }; n $(echo a b c)") ())
```
---
    3

### newlines and tabs split too

```sh
(do (sh-eval "n() { echo $#; }; n $(printf 'a\\nb\\tc\\n')") ())
```
---
    3

### literal text around an expansion joins the first and last fields

```sh
(do (sh-eval "n() { echo $#; }; X=\"a b\"; n p${X}s") ())
```
---
    2

### and the joined text is what you would expect

```sh
(do (sh-eval "X=\"a b\"; echo p${X}s") ())
```
---
    pa bs

## sh-eval empty expansions

### an unquoted empty expansion produces NO field

```sh
(do (sh-eval "n() { echo $#; }; n $NOSUCHVAR_ASH") ())
```
---
    0

### a quoted empty expansion produces one empty field

```sh
(do (sh-eval "n() { echo $#; }; n \"$NOSUCHVAR_ASH\"") ())
```
---
    1

### an empty literal string is one field

```sh
(do (sh-eval "n() { echo $#; }; n \"\"") ())
```
---
    1

### an all-whitespace expansion produces no field

```sh
(do (sh-eval "n() { echo $#; }; X=\"   \"; n $X") ())
```
---
    0

### single quotes make an empty field, not none

```sh
(do (sh-eval "n() { echo $#; }; n ''") ())
```
---
    1

## sh-eval splitting in for and case

### for iterates once per field of a substitution

```sh
(do (sh-eval "for f in $(echo 1 2 3); do echo -n $f; done; echo :end") ())
```
---
    123:end

### for iterates once per LINE of a multi-line substitution

```sh
(do (sh-eval "for f in $(printf 'x\\ny\\n'); do echo -n [$f]; done; echo :end") ())
```
---
    [x][y]:end

### a case subject is NOT split

```sh
(do (sh-eval "X=\"a b\"; case \"$X\" in \"a b\") echo MATCH ;; *) echo NO ;; esac") ())
```
---
    MATCH

### an unquoted case subject is not split either

```sh
(do (sh-eval "X=\"a b\"; case $X in \"a b\") echo MATCH ;; *) echo NO ;; esac") ())
```
---
    MATCH
