## sh-eval a here-document's delimiter

The word after `<<` has its quoting removed, and the body ends at a line that
is exactly what is left.  Quoting any part of the word -- a backslash, or
single or double quotes around some of it -- leaves the body unexpanded, its
backslashes included.  The word ends at a blank or an operator.

Expectations match `/bin/sh` and `dash`.

### a backslash quotes the delimiter

```sh
(do (sh-eval "( cat <<\\EOF\n$HOME\nEOF\n)") ())
```
---
    $HOME

### and the input after the body still runs

```sh
(do (sh-eval "( cat <<\\EOF\nbody\nEOF\necho after\n)") ())
```
---
    after

### a backslash inside the word

```sh
(do (sh-eval "( cat <<E\\OF\n$HOME\nEOF\n)") ())
```
---
    $HOME

### double quotes around part of it

```sh
(do (sh-eval "( cat <<E\"O\"F\n$HOME\nEOF\n)") ())
```
---
    $HOME

### single quotes around part of it

```sh
(do (sh-eval "( cat <<'E'OF\n$HOME\nEOF\n)") ())
```
---
    $HOME

### a quoted body keeps a backslash at the end of a line

```sh
(do (sh-eval "( cat <<\\EOF\na\\\nb\nEOF\n)") ())
```
---
    b

### the word ends at an operator

```sh
(do (sh-eval "( x=1; cat <<EOF|tr a-z A-Z\nlow $x\nEOF\n)") ())
```
---
    LOW 1

### <<- with a quoted delimiter strips tabs and does not expand

```sh
(do (def tab (make-string 1 (integer->char 9))) (sh-eval (Str8 join "" (list "( cat <<-\\EOF\n" tab tab "tabbed $HOME\n" tab "EOF\n)"))) ())
```
---
    tabbed $HOME
