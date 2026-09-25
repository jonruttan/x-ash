## sh-eval where a reserved word is one

A reserved word is recognized only where the grammar can take one: as the
first word of a command, as the word after a reserved word other than `case`,
`for` or `in`, as the `in` of a case and the `in` or `do` of a for, and as an
`esac` where a clause's pattern would start.  Anywhere else it is an ordinary
word, and a quoted one never is.

Before each complete command runs, one walk over its tokens marks each word
that stands in such a place, and every later scan reads the mark: the stop
words that end a command list, the nesting a skipped body counts, the `esac` a
case looks for.

Expectations match `/bin/sh` and `dash`.

### the walk marks a reserved word where one stands

```sh
(write (%sh-mark-keywords (sh-tokenize "echo done; done")))
```
---
    ((tok-word "echo") (tok-word "done") (tok-op ";") (tok-word "done" #t))

### done is an argument in a loop body

```sh
(do (sh-eval "for i in 1; do printf \"[%s]\" done; done; echo") ())
```
---
    [done]

### then and fi are arguments in an if

```sh
(do (sh-eval "if printf \"[%s]\" then; then printf \"[%s]\" fi; fi; echo") ())
```
---
    [then][fi]

### elif and else are arguments in its body

```sh
(do (sh-eval "if true; then printf \"[%s]\" elif else; fi; echo") ())
```
---
    [elif][else]

### and in an elif condition

```sh
(do (sh-eval "if false; then :; elif printf \"[%s]\" then; then printf \"[%s]\" elif; fi; echo") ())
```
---
    [then][elif]

### do is an argument in a while condition

```sh
(do (sh-eval "while printf \"[%s]\" do; false; do :; done; echo") ())
```
---
    [do]

### esac is an argument in a case clause

```sh
(do (sh-eval "case x in x) printf \"[%s]\" esac;; esac; echo") ())
```
---
    [esac]

### a closing brace is an argument in a function body

```sh
(do (sh-eval "f() { printf \"[%s]\" }; }; f; echo") ())
```
---
    [}]

### an opener as an argument opens nothing

```sh
(do (sh-eval "for i in 1; do printf \"[%s]\" for if while case {; done; echo") ())
```
---
    [for][if][while][case][{]

### a skipped if body does not count its arguments

```sh
(do (sh-eval "if false; then echo done fi esac; echo x; fi; printf \"[end]\"; echo") ())
```
---
    [end]

### nor does a skipped loop body

```sh
(do (sh-eval "while false; do echo done fi; done; printf \"[end]\"; echo") ())
```
---
    [end]

### nor a skipped case clause

```sh
(do (sh-eval "case y in x) echo esac done;; y) printf \"[y]\";; esac; echo") ())
```
---
    [y]

### a redirection's target is a word

```sh
(do (sh-eval "d=$(mktemp -d); ( cd \"$d\"; for i in 1; do { echo hi; } > done; done; printf \"[%s]\" \"$(cat done)\" ); rm -rf \"$d\"; echo") ())
```
---
    [hi]

### a for list's words are words

```sh
(do (sh-eval "for x in done fi esac; do printf \"[%s]\" \"$x\"; done; echo") ())
```
---
    [done][fi][esac]

### a for variable may be named like a reserved word

```sh
(do (sh-eval "for do in 1 2; do printf \"[%s]\" \"$do\"; done; echo") ())
```
---
    [1][2]

### a case subject and its pattern may be reserved words

```sh
(do (sh-eval "case done in done) printf \"[match]\";; esac; echo") ())
```
---
    [match]

### in may be both

```sh
(do (sh-eval "case in in in) printf \"[in]\";; esac; echo") ())
```
---
    [in]

### esac after a bar is a pattern

```sh
(do (sh-eval "case esac in a|esac) printf \"[m]\";; esac; printf \"[after]\"; echo") ())
```
---
    [m][after]

### a reserved word may follow a closing brace

```sh
(do (sh-eval "if { true; } then printf \"[then]\"; fi; echo") ())
```
---
    [then]

### or a fi

```sh
(do (sh-eval "if true; then if true; then printf \"[a]\"; fi fi; echo") ())
```
---
    [a]

### or an esac

```sh
(do (sh-eval "for i in 1; do case x in x) printf \"[x]\";; esac done; echo") ())
```
---
    [x]

### a pattern on its own line may be a reserved word

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "case x in" "x) printf \"[x]\";;" "for) printf \"[for]\";;" "esac" "printf \"[after]\"; echo"))) ())
```
---
    [x][after]

### so may a parenthesized one

```sh
(do (sh-eval (Str8 join nl (list "case if in" "(if) printf \"[if]\";;" "esac" "printf \"[after]\"; echo"))) ())
```
---
    [if][after]

### a case's in may stand on the next line

```sh
(do (sh-eval (Str8 join nl (list "case x" "in x) printf \"[m]\";; esac; echo"))) ())
```
---
    [m]

### so may a for's

```sh
(do (sh-eval (Str8 join nl (list "for x" "in a b; do printf \"[%s]\" \"$x\"; done; echo"))) ())
```
---
    [a][b]

### a quoted reserved word is a command name

```sh
(do (sh-eval "for i in 1; do 'done' 2>/dev/null; printf \"[%s]\" $?; done; echo") ())
```
---
    [127]

### so is a variable holding one

```sh
(do (sh-eval "v=done; for i in 1; do $v 2>/dev/null; printf \"[%s]\" $?; done; echo") ())
```
---
    [127]
