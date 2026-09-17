## sh-eval a case pattern's parens

A case clause ends its pattern with a `)`, and may open it with one.  Neither
closes a subshell, so the walks that count parens -- the one that takes a
subshell's tokens, the one that reads past a compound, the one that cuts a
pipeline into stages, the one that skips an and-or operand -- step over them.
The marking pass knows where a pattern stands, and marks them there.

A `(` that opens a pattern is punctuation rather than a pattern of its own, so
a subject that is a parenthesis matches only what it should.

Expectations match `/bin/sh` and `dash`.

### a case inside a subshell

```sh
(do (sh-eval "( case x in x) printf \"[x]\";; esac ); printf \"[after]\"; echo") ())
```
---
    [x][after]

### inside subshells within subshells

```sh
(do (sh-eval "( ( case y in x) printf \"[x]\";; y) printf \"[y]\";; esac ) ); echo") ())
```
---
    [y]

### with a pattern that opens with a paren

```sh
(do (sh-eval "( case x in (x) printf \"[p]\";; esac ); echo") ())
```
---
    [p]

### that paren is not a pattern of its own

```sh
(do (sh-eval "case \"(\" in (x) printf \"[bad]\";; *) printf \"[ok]\";; esac; echo") ())
```
---
    [ok]

### a substitution in a clause's body keeps its parens

```sh
(do (sh-eval "case x in x) printf \"[%s]\" \"$(echo sub)\";; esac; echo") ())
```
---
    [sub]

### so does a subshell in one

```sh
(do (sh-eval "case x in x) ( printf \"[sub]\" );; esac; printf \"[after]\"; echo") ())
```
---
    [sub][after]

### a subshell holding a case is one stage of a pipeline

```sh
(do (sh-eval "( case x in x) printf \"x\";; esac ) | tr x X; echo") ())
```
---
    X

### and one command of a function

```sh
(do (sh-eval "f() { ( case x in x) printf \"[f]\";; esac ); }; f; echo") ())
```
---
    [f]

### an operand that is not taken is stepped over whole

```sh
(do (sh-eval "false && ( case x in x) printf \"[no]\";; esac ); printf \"[after]\"; echo") ())
```
---
    [after]

### and a redirection is read after it

```sh
(do (sh-eval "( case x in x) printf \"[r]\";; esac ) > /dev/null; printf \"[after]\"; echo") ())
```
---
    [after]
