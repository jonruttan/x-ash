## sh-eval a declaration utility's arguments

`export`, `readonly` and `local` take assignments, so each of their arguments
is read the way the assignment itself would be: the value is neither split on
`IFS` nor matched against the filesystem, however many plain names come
before it.

Everywhere else an assignment is a fact of position -- the leading run of a
command, which ends at the command's own name.

Expectations match `/bin/sh` and `dash`.

### local after a bare name

```sh
(do (sh-eval "v=\"a b\"; f() { local x y=$v; echo \"[$y]\"; }; f") ())
```
---
    [a b]

### export after a bare name

```sh
(do (sh-eval "v=\"a b\"; export x y=$v; echo \"[$y]\"") ())
```
---
    [a b]

### readonly after a bare name

```sh
(do (sh-eval "v=\"a b\"; readonly r1 r2=$v; echo \"[$r2]\"") ())
```
---
    [a b]

### a local's own value is not split

```sh
(do (sh-eval "v=\"a b\"; f() { local x=$v; echo \"[$x]\"; }; f") ())
```
---
    [a b]

### two assignment words in a row

```sh
(do (sh-eval "v=\"a b\"; f() { local x=$v y=$v; echo \"[$x][$y]\"; }; f") ())
```
---
    [a b][a b]

### quoted beside unquoted

```sh
(do (sh-eval "v=\"a b\"; export z=\"$v\" w=$v; echo \"[$z][$w]\"") ())
```
---
    [a b][a b]

### nor is the value matched against the filesystem

```sh
(do (sh-eval "d=$(mktemp -d); touch \"$d/x=aa\" \"$d/x=bb\"; cd \"$d\"; f() { local x=*; echo \"[$x]\"; }; f; cd /; rm -rf \"$d\"") ())
```
---
    [*]

### a plain command splits as ever

```sh
(do (sh-eval "v=\"a b\"; set -- $v; echo \"[$1][$2]\"") ())
```
---
    [a][b]

### and the leading run ends at the command's name

```sh
(do (sh-eval "v=\"a b\"; a=1 printf \"[%s]\" x=$v; echo") ())
```
---
    [x=a][b]

### a declaration utility named as an argument is just a word

```sh
(do (sh-eval "v=\"a b\"; printf \"[%s]\" export y=$v; echo") ())
```
---
    [export][y=a][b]
