## ash/line -- the line editor's seams

The editor carries no grammar. The shell fills its two seams: `%ash-paint`
displays a line with the tokenizer's own verdicts on words, operators and
strings, and `%ash-complete` answers a word from the reserved words, the
builtins and the executables on PATH.

### with no terminal, painting returns the line unchanged

```sh
(do (import ash/line) (let ((s "if true; then echo \"a b\"; fi # c")) (Str8 =? (%ash-paint s) s)))
```
---
    #t

### the word being completed ends at the cursor and starts after a separator

```sh
(do (import ash/line)
    (let ((ed (Edit make)))
      (ed insert! "echo one | gre")
      (%ash-word-at ed)))
```
---
    "gre"

### a reserved word and a builtin complete from their own tables

```sh
(do (import ash/line)
    (let ((ed (Edit make)))
      (ed insert! "whi")
      (let ((r (%ash-complete ed)))
        (list (first r) (List includes? "while" (rest r))))))
```
---
    ("whi" #t)

### an empty word offers nothing

```sh
(do (import ash/line)
    (let ((ed (Edit make)))
      (%ash-complete ed)))
```
---
    ("")
