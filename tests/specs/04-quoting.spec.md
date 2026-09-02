## sh-tokenize quoted strings

### tokenizes single-quoted string

```sh
(write (sh-tokenize "'a'"))
```
---
    ((tok-sq "a"))

### tokenizes empty single-quoted string

```sh
(write (sh-tokenize "''"))
```
---
    ((tok-sq ""))

### keeps spaces inside single quotes

```sh
(write (sh-tokenize "'a b c'"))
```
---
    ((tok-sq "a b c"))

### tokenizes double-quoted string

```sh
(write (sh-tokenize "\"a b\""))
```
---
    ((tok-dq "a b"))

### a backslash-escaped quote does not close the string

```sh
(write (sh-tokenize "\"a\\\"b\""))
```
---
    ((tok-dq "a\\\"b"))

### quoted words sit beside bare ones

```sh
(write (sh-tokenize "echo 'hi' \"yo\""))
```
---
    ((tok-word "echo") (tok-sq "hi") (tok-dq "yo"))

## sh-eval quoting

### a double-quoted word is one argument

```sh
(do (sh-eval "echo \"a b\"") ())
```
---
    a b

### single quotes suppress expansion

```sh
(do (sh-eval "X=v; echo '$X'") ())
```
---
    $X

### double quotes do not suppress expansion

```sh
(do (sh-eval "X=v; echo \"got $X\"") ())
```
---
    got v

### a backslash-escaped dollar stays a dollar

```sh
(do (sh-eval "X=v; echo \"esc \\$X\"") ())
```
---
    esc $X

### a backslash outside quotes escapes the dollar

```sh
(do (sh-eval "X=v; echo \\$X") ())
```
---
    $X

### a non-escapable backslash keeps both characters

```sh
(do (sh-eval "echo \"a\\db\"") ())
```
---
    a\db

## sh-eval word concatenation

### a quoted assignment value is one word

```sh
(do (sh-eval "X=\"a b\"; echo [$X]") ())
```
---
    [a b]

### a mid-word quote does not split the word

```sh
(do (sh-eval "echo pre\"mid\"post") ())
```
---
    premidpost

### a word may open a quoted region anywhere

```sh
(do (sh-eval "echo a\"b c\"d") ())
```
---
    ab cd

### a word that starts quoted continues past the closing quote

```sh
(do (sh-eval "V=v; echo \"$V\"/bin") ())
```
---
    v/bin

### adjacent quoted regions join into one word

```sh
(do (sh-eval "V=v; echo 'no'\"$V\"'no'") ())
```
---
    novno

### a single-quoted region inside a word stays literal

```sh
(do (sh-eval "V=v; echo pre'$V'post") ())
```
---
    pre$Vpost

### a lone quoted word keeps its token type

```sh
(write (sh-tokenize "X=\"a b\""))
```
---
    ((tok-word "X=\"a b\""))

## sh-eval subshells

A subshell FORKS, and the awk harness cannot see the child's stdout: the child
writes into its inherited copy of the interpreter's output buffer, and there is
no flush primitive to force it out before `Sys exit`.  Run directly, `( echo
inner ); echo after` prints `inner` then `after` exactly once, to a terminal
and through a pipe alike -- but only the first case below is observable from
here.  So the leak that %collect-subshell-tokens fixes (the child used to run
every command AFTER the subshell as well, because %eval-list does not stop at
`)`) is asserted through the parent-side facts the harness CAN see: the status,
and that the parser lands past the closing paren.

### a subshell runs its body

```sh
(do (sh-eval "( echo inner )") ())
```
---
    inner

### a subshell's status is its last command's

```sh
(sh-eval "( true )")
```
---
    0

### a failing subshell reports failure

```sh
(sh-eval "( false )")
```
---
    1

### an explicit exit status comes back from the child

```sh
(sh-eval "( exit 3 )")
```
---
    3

### the parser continues after the closing paren

```sh
(sh-eval "( true ); false")
```
---
    1

### a multi-command subshell reports its LAST command's status

```sh
(sh-eval "( true; false )")
```
---
    1
