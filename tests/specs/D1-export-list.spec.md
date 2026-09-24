## sh-eval `export -p`

`export -p`, and `export` with no operand, write every exported name as the
command that would export it again, sorted by name: a name the environment
holds with its value quoted, and a name marked for export with no value yet
on its own.  A name the shell holds unexported is not written.  The value is
quoted the way `readonly -p` quotes one, in single quotes; dash quotes the
same way and bash in double quotes, so the cases read the names, and read a
value back through `eval`.

Expectations match `/bin/sh` and `dash`.

### a name marked for export, and one with a value

```sh
(do (sh-eval "( export M_EXP; export Z_EXP=1; export -p | grep -E '^export (M_EXP|Z_EXP)(=|$)' | cut -d= -f1 | tr '\\n' ','; echo )") ())
```
---
    export M_EXP,export Z_EXP,

### `export` alone writes the same

```sh
(do (sh-eval "( export Z_EXP=1; export | grep -c '^export Z_EXP=' )") ())
```
---
    1

### what it writes reads back

```sh
(do (sh-eval "( export Q_EXP=\"it's a \\$x\"; s=$(export -p | grep '^export Q_EXP='); unset Q_EXP; eval \"$s\"; echo \"[$Q_EXP]\" )") ())
```
---
    [it's a $x]

### sorted by name

```sh
(do (sh-eval "( export B_EXP=2 A_EXP=1; export -p | grep -E '^export [AB]_EXP=' | cut -d= -f1 | tr '\\n' ','; echo )") ())
```
---
    export A_EXP,export B_EXP,

### an unexported name is not written

```sh
(do (sh-eval "( U_EXP=local; export -p | grep -c 'U_EXP' )") ())
```
---
    0
