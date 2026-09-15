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

The completer reads the buffer through one method, `before`, the text to the
left of the cursor; a stand-in with that method is enough to test it, and
lets these cases run on a platform that has no editor to build a buffer with.

### the word being completed ends at the cursor and starts after a separator

```sh
(do (import ash/line)
    (def-class %spec-buf () text (method before (self) (member (lit text))))
    (%ash-word-at (new %spec-buf text "echo one | gre")))
```
---
    "gre"

### a reserved word and a builtin complete from their own tables

```sh
(do (import ash/line)
    (let ((r (%ash-complete (new %spec-buf text "whi"))))
      (list (first r) (List includes? "while" (rest r)))))
```
---
    ("whi" #t)

### an empty word offers nothing

```sh
(do (import ash/line)
    (%ash-complete (new %spec-buf text "")))
```
---
    ("")
