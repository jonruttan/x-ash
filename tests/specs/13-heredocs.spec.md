## sh-eval here-documents

The body lives on lines the tokenizer has not reached, so here-documents are
lifted out of the raw text before tokenizing: `<<DELIM` becomes `<<N` and the
body lines are removed. These specs build multi-line input with an explicit
newline, since a spec fence is one line per snippet.

### the body reaches the command

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "cat <<EOF" "one" "two" "EOF" "echo -n :end"))) (newline))
```
---
    :end

### commands after the terminator still run

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "cat <<EOF" "body" "EOF" "echo -n after"))) (newline))
```
---
    after

### an unquoted delimiter expands the body

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "V=world" "cat <<EOF" "hello $V" "EOF"))) ())
```
---
    hello world

### a quoted delimiter does not

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "V=world" "cat <<'EOF'" "hello $V" "EOF"))) ())
```
---
    hello $V

### a double-quoted delimiter is literal too

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "V=world" "cat <<\"EOF\"" "hello $V" "EOF"))) ())
```
---
    hello $V

### <<- strips leading tabs from body and terminator

```sh
(do (def nl (make-string 1 (convert 10 %char))) (def tab (make-string 1 (convert 9 %char))) (sh-eval (Str8 join nl (list "cat <<-EOF" (string-append tab "stripped") (string-append tab "EOF")))) ())
```
---
    stripped

### two here-documents on one line are taken in order

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "cat <<A; cat <<B" "first" "A" "second" "B" "echo -n :end"))) (newline))
```
---
    :end

### an unterminated body runs to the end of the input

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "cat <<EOF" "no terminator"))) ())
```
---
    no terminator

### a command substitution can read one

```sh
(do (def nl (make-string 1 (convert 10 %char))) (sh-eval (Str8 join nl (list "X=$(cat <<EOF" "captured" "EOF" ")" "echo $X"))) ())
```
---
    captured

## sh-eval what is NOT a here-document

### << inside double quotes is text

```sh
(do (sh-eval "echo \"a << b\"") ())
```
---
    a << b

### << inside single quotes is text

```sh
(do (sh-eval "echo 'a << b'") ())
```
---
    a << b

### a lone < is still an input redirection

```sh
(do (sh-eval "read a < /dev/null; echo -n done") (newline))
```
---
    done

### arithmetic comparison is not a here-document

```sh
(do (sh-eval "echo $((3<5))") ())
```
---
    1
