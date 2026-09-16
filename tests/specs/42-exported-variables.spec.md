## sh-eval which variables a command inherits

A variable is exported or it is not, and a command the shell runs inherits the
exported ones only.  An assignment leaves a variable as it was: a new name
is not exported, and a name already exported stays exported with its new
value.  `export` gives a name the attribute, before or after it has a value,
and `unset` takes both away.

A prefix assignment is exported to the command it prefixes and nothing
after it, and the variable is then what it was before.  On a special builtin
it outlives the command instead, as an ordinary assignment.  bash also exports
that one; `dash` does not, and neither does this shell.

`read`, `for` and `${NAME:=word}` assign like anything else, and IFS, which the
shell sets when it starts, is not exported.

Each case asks a child shell what it inherited.  Expectations match `dash`,
and `/bin/sh` everywhere but the special builtin's prefix.

### an assignment is not exported

```sh
(do (sh-eval "V1=1; echo \"[$(/bin/sh -c 'printf %s \"$V1\"')]\"") ())
```
---
    []

### export with a value is

```sh
(do (sh-eval "export V2=1; echo \"[$(/bin/sh -c 'printf %s \"$V2\"')]\"") ())
```
---
    [1]

### so is export after the assignment

```sh
(do (sh-eval "V3=1; export V3; echo \"[$(/bin/sh -c 'printf %s \"$V3\"')]\"") ())
```
---
    [1]

### export before a value exports the value it gets

```sh
(do (sh-eval "export V4; V4=2; echo \"[$(/bin/sh -c 'printf %s \"$V4\"')]\"") ())
```
---
    [2]

### every operand of export is exported

```sh
(do (sh-eval "export V5=1 V6=2; echo \"[$(/bin/sh -c 'printf %s \"$V5$V6\"')]\"") ())
```
---
    [12]

### an exported variable takes a new value

```sh
(do (sh-eval "V7=a; export V7; V7=b; echo \"[$(/bin/sh -c 'printf %s \"$V7\"')]\"") ())
```
---
    [b]

### unset takes the export attribute away

```sh
(do (sh-eval "export V8=a; unset V8; V8=b; echo \"[$(/bin/sh -c 'printf %s \"$V8\"')]\"") ())
```
---
    []

### an exported name with no value gives a child nothing

```sh
(do (sh-eval "V9=1; unset V9; export V9; echo \"[$(/bin/sh -c 'printf %s \"${V9-unset}\"')]\"") ())
```
---
    [unset]

### a prefix assignment is exported to its command

```sh
(do (sh-eval "echo \"[$(V10=1 /bin/sh -c 'printf %s \"$V10\"')]\"") ())
```
---
    [1]

### and does not outlive it

```sh
(do (sh-eval "V11=1 /bin/sh -c :; echo \"[${V11-unset}]\"") ())
```
---
    [unset]

### a variable covered by a prefix is itself again after

```sh
(do (sh-eval "V12=5; echo \"[$(V12=6 /bin/sh -c 'printf %s \"$V12\"')][$V12]\"") ())
```
---
    [6][5]

### a prefix on a function is exported while it runs

```sh
(do (sh-eval "f13() { /bin/sh -c 'printf %s \"$V13\"'; }; echo \"[$(V13=1 f13)][${V13-unset}]\"") ())
```
---
    [1][unset]

### a prefix on a special builtin stays, unexported

```sh
(do (sh-eval "V14=1 :; echo \"[$V14][$(/bin/sh -c 'printf %s \"$V14\"')]\"") ())
```
---
    [1][]

### a prefix on export stays and is exported

```sh
(do (sh-eval "V15=1; V15=2 export V15; echo \"[$V15][$(/bin/sh -c 'printf %s \"$V15\"')]\"") ())
```
---
    [2][2]

### read assigns an unexported variable

```sh
(do (sh-eval "read V16 <<END\nhi\nEND\necho \"[$V16][$(/bin/sh -c 'printf %s \"$V16\"')]\"") ())
```
---
    [hi][]

### so does for

```sh
(do (sh-eval "for V17 in a; do :; done; echo \"[$V17][$(/bin/sh -c 'printf %s \"$V17\"')]\"") ())
```
---
    [a][]

### so does an assigning expansion

```sh
(do (sh-eval ": ${V18:=7}; echo \"[$V18][$(/bin/sh -c 'printf %s \"$V18\"')]\"") ())
```
---
    [7][]

### a child is not handed IFS

```sh
(do (sh-eval "echo \"[$(/bin/sh -c 'env | grep -c ^IFS=')]\"") ())
```
---
    [0]

### tilde reads HOME whether or not it is exported

```sh
(do (sh-eval "( unset HOME; HOME=/abc; echo \"[$(echo ~)][$(/bin/sh -c 'printf %s \"$HOME\"')]\" )") ())
```
---
    [/abc][]

