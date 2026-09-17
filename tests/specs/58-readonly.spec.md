## sh-eval readonly

`readonly NAME[=value]...` marks names that may not be assigned or unset
again.  An assignment to one is refused and ends a shell that is not
interactive, which is what POSIX asks of an error in a special builtin.  The
status is the shell's to choose -- dash answers 2 and bash 1 -- so the cases
ask only that it is not 0.

`readonly` and `readonly -p` write the marked names, each as the command that
would mark it again.

Expectations match `/bin/sh` and `dash`.

### readonly assigns as it marks

```sh
(do (sh-eval "readonly ro_v=1; printf \"[%s]\" \"$ro_v\"; echo") ())
```
---
    [1]

### an assignment to a marked name ends the shell

```sh
(do (sh-eval "( readonly ro_a=1; ro_a=2; printf \"[after]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; printf \"[on]\"; echo") ())
```
---
    [failed][on]

### and is reported

```sh
(do (sh-eval "x=$( ( readonly ro_r=1; ro_r=2 ) 2>&1 ); [ -n \"$x\" ] && printf \"[reported]\"; printf \"[end]\"; echo") ())
```
---
    [reported][end]

### a name already set can be marked

```sh
(do (sh-eval "( ro_b=1; readonly ro_b; ro_b=2; printf \"[after]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [failed]

### so can a name with no value yet

```sh
(do (sh-eval "readonly ro_c; printf \"[%s]\" $?; ( ro_c=1 ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [0][failed]

### the shell that marked it keeps its value

```sh
(do (sh-eval "readonly ro_d=1; ( ro_d=2 ) 2>/dev/null; printf \"[%s]\" \"$ro_d\"; echo") ())
```
---
    [1]

### export of a marked name ends the shell too

```sh
(do (sh-eval "( readonly ro_e=1; export ro_e=2; printf \"[after]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [failed]

### as does a for loop over one

```sh
(do (sh-eval "( readonly ro_f=1; for ro_f in a; do :; done; printf \"[after]\" ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; echo") ())
```
---
    [failed]

### read into one fails, and the shell goes on

```sh
(do (sh-eval "( readonly ro_g=1; printf 'v\\n' | read ro_g; printf \"[after:%s]\" \"$ro_g\" ) 2>/dev/null; printf \"[sub:%s]\" $?; echo") ())
```
---
    [after:1][sub:0]

### a marked name is exported like any other

```sh
(do (sh-eval "readonly ro_h=1; export ro_h; printf \"[%s]\" \"$(sh -c 'printf %s \"$ro_h\"')\"; echo") ())
```
---
    [1]

### marking in a function marks for the shell

```sh
(do (sh-eval "f() { readonly ro_i=9; }; f; printf \"[%s]\" \"$ro_i\"; echo") ())
```
---
    [9]

### readonly -p writes the marked names

```sh
(do (sh-eval "readonly ro_j=1; x=$(readonly -p); case \"$x\" in *ro_j*) printf \"[has]\";; *) printf \"[no]\";; esac; echo") ())
```
---
    [has]
