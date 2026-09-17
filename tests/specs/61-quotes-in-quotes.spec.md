## sh-eval a quote mark inside the other quotes

Inside double quotes a single quote is ordinary text, and inside single quotes
a double quote is: neither opens a region there.  So `"it's"` is one word, and
an argument may start with a quote mark -- which is how `printf` is told to
read a character's numeric value, `"'A"` being 65.

Expectations match `/bin/sh` and `dash`.

### an apostrophe inside double quotes

```sh
(do (sh-eval "printf \"[%s]\" \"it's\"; printf \"[end]\"; echo") ())
```
---
    [it's][end]

### in a variable's value

```sh
(do (sh-eval "v=\"don't\"; printf \"[%s]\" \"$v\"; echo") ())
```
---
    [don't]

### beside an expansion in the same word

```sh
(do (sh-eval "x=world; printf \"[%s]\" \"it's $x\"; echo") ())
```
---
    [it's world]

### printf reads a leading quote as a character's value

```sh
(do (sh-eval "printf \"[%d][%d]\" \"'A\" \"'z\"; echo") ())
```
---
    [65][122]

### and a leading double quote the same way

```sh
(do (sh-eval "printf \"[%d]\" '\"A'; echo") ())
```
---
    [65]

### a double quote inside single quotes

```sh
(do (sh-eval "printf \"[%s]\" 'a\"b'; echo") ())
```
---
    [a"b]

### an apostrophe in a here-document's body

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "cat <<EOF" "it's here" "EOF"))) ())
```
---
    it's here
