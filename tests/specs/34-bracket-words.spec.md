## sh-eval a `[` is a pattern only when a `]` closes it

A `[` starts a bracket expression only when a `]` later in the word closes it.
Otherwise it is an ordinary character, as POSIX has it, and a word whose only
pattern character is such a `[` is not a pattern: it is not matched against
the directory at all.  That is what keeps `[ ... ]` as cheap in a directory of
a thousand files as in an empty one.

A `]` straight after the opening `[`, or after `[!`, is a member of the
expression rather than its end, so `[]` is unclosed and `[]]` matches `]`.

An unclosed `[` does not stop the rest of the word being a pattern: `[*` is a
literal bracket followed by a star.  POSIX and bash match the bracket as
itself there; `dash` answers those two words unexpanded.

Each case makes a directory holding `a`, `b`, `[`, `[a`, `]` and `x[`.

### a lone bracket is itself

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; echo [; cd /; rm -rf $d") ())
```
---
    [

### an unclosed bracket is itself

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; echo [a; cd /; rm -rf $d") ())
```
---
    [a

### a closed bracket is a pattern

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; echo [ab]; cd /; rm -rf $d") ())
```
---
    a b

### a bracket just after the opening one does not close it

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; echo []; cd /; rm -rf $d") ())
```
---
    []

### so a second one does

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; echo []]; cd /; rm -rf $d") ())
```
---
    ]

### nor does one just after the negation

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; echo [!]; cd /; rm -rf $d") ())
```
---
    [!]

### a bracket may hold an opening bracket

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; echo [[]; cd /; rm -rf $d") ())
```
---
    [

### an unclosed bracket leaves a star live

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; echo [*; cd /; rm -rf $d") ())
```
---
    [ [a

### and a star before it

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; echo *[; cd /; rm -rf $d") ())
```
---
    [ x[

### a closed bracket in a value is a pattern

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; x='[ab]'; echo $x; cd /; rm -rf $d") ())
```
---
    a b

### an unclosed one in a value is not

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; : > a; : > b; : > '['; : > '[a'; : > ']'; : > 'x['; x='['; echo $x; cd /; rm -rf $d") ())
```
---
    [

### a test costs the same in a directory of a thousand files

```sh
(do (sh-eval "d=$(mktemp -d); cd $d; seq 1000 | xargs touch; i=0; while [ $i -lt 20 ]; do i=$((i+1)); done; cd /; rm -rf $d; echo $i") ())
```
---
    20
