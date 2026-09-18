## sh-eval a name is a name, wherever one is taken

A variable or a function is called by a NAME: a letter or underscore, then
letters, digits and underscores.  A word that is not one is refused wherever
one is taken -- by `export`, `readonly`, `unset`, `local` and `read`, as a
function's name, and as a `for` loop's variable.

`export`, `readonly` and `unset` are special builtins, and POSIX ends a script
over a special builtin's error; `local` and `read` report the word and answer
1.  `unset -f` removes a function, every definition of it, and leaves a
variable of the same name alone; `unset -v` is the plain `unset`.

Expectations match `/bin/sh` and `dash` but where the two disagree with each
other:

  - over a bad name `export`, `readonly` and `unset` end the script, as in
    dash and POSIX; bash reports it and carries on
  - `local` answers 1, as in bash; dash answers 0
  - `read` answers 1, as in bash; dash answers 2

### export ends the script

```sh
(do (sh-eval "( export 1x=5; printf \"[after]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [failed]

### the names before the bad one were taken

```sh
(do (sh-eval "( trap 'echo \"ok=$ok_e\"' EXIT; export ok_e=1 1x=5 ) 2>/dev/null") ())
```
---
    ok=1

### readonly ends the script

```sh
(do (sh-eval "( readonly a-b=1; printf \"[after]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [failed]

### unset ends the script

```sh
(do (sh-eval "( unset a-b; printf \"[after]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [failed]

### unset -f removes a function

```sh
(do (sh-eval "( f() { echo fn; }; unset -f f; f 2>/dev/null; echo \"s=$?\" )") ())
```
---
    s=127

### every definition of it

```sh
(do (sh-eval "( f() { echo one; }; f() { echo two; }; unset -f f; f 2>/dev/null; echo \"s=$?\" )") ())
```
---
    s=127

### and leaves a variable of that name

```sh
(do (sh-eval "( x=1; x() { :; }; unset -f x; echo \"[$x]\" )") ())
```
---
    [1]

### unset -v removes a variable

```sh
(do (sh-eval "( x=1; unset -v x; echo \"[${x-gone}]\" )") ())
```
---
    [gone]

### an option unset does not know ends the script

```sh
(do (sh-eval "( unset -x y; printf \"[after]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [failed]

### local answers 1 and goes on

```sh
(do (sh-eval "( f() { local 9=1 ok_l=2; echo \"s=$? ok=$ok_l\"; }; f ) 2>/dev/null") ())
```
---
    s=1 ok=2

### read answers 1

```sh
(do (sh-eval "( echo hi | { read a-b; echo \"s=$?\"; } ) 2>/dev/null") ())
```
---
    s=1

### a function must be called by a name

```sh
(do (sh-eval "a-b() { echo dashed; }") ())
```
---
    Error: parse error: bad function name a-b

### and so must a for loop's variable

```sh
(do (sh-eval "for 1x in a; do :; done") ())
```
---
    Error: parse error: bad for loop variable 1x
