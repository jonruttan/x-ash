## ash/syntax -- the sh highlighting grammar

The bundle's lang.xon declares a grammar, `sh`, that x/tool/syntax colours
shell scripts with. Its module, `ash/syntax`, imports only x-lang libraries
and registers the grammar as it loads.

The cases share one process, and a registered grammar stays registered, so
the catalogue's case comes first: it finds the grammar through lang.xon,
before anything has imported the module.

### the catalogue finds sh by suffix, by name, by #! and by modeline

The langs directory holds this bundle, linked as `ash`. The row comes from
lang.xon, its module not loaded until a file asks for the grammar, and the
grammar takes lang.xon's suffixes, names and interpreters.

```sh
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
    (def root (Str8 replace "/ash/syntax.x" "" (%module-resolve-file "ash/syntax.x")))
    (def tmp (File temp "/tmp/x-ash-spec-langs-"))
    (File close (first tmp))
    (def d (rest tmp))
    (File unlink d)
    (File mkdir d)
    (File symlink root (Str8 append d "/ash"))
    (def was (Sys getenv "X_LANG_DIR"))
    (Sys setenv "X_LANG_DIR" d)
    (Syntax forget!)
    (def row (List find (fn (_ r) (eq? (first r) (lit sh))) (Syntax catalogue)))
    (def name (fn (_ path . text)
      (let ((g (apply Syntax (pair (lit for-file) (pair path text))))) (if (null? g) () (g name)))))
    (def seen
      (list (List ref 1 row)
            (name "x.sh") (name "home/.profile")
            (name "run" "#!/bin/sh\necho hi\n")
            (name "run" "#!/usr/bin/env dash\n")
            (name "run" "echo hi\n# vi: set ft=sh:\n")
            (name "x.txt")
            (let ((g (Syntax named (lit sh)))) (list (g files) (g names) (g interpreters)))))
    (File unlink (Str8 append d "/ash"))
    (File rmdir d)
    (Sys setenv "X_LANG_DIR" (if (null? was) "" was))
    (Syntax forget!)
    seen)
```
---
    (ash/syntax sh sh sh sh sh () ((".sh") (".profile") ("sh" "ash" "dash")))

### a script's spans: comments, strings, expansions, numbers and keywords

```sh
(do (import x/tool/syntax) (import ash/syntax)
    ((Syntax named (lit sh)) spans
      "#!/bin/sh\nif [ \"$x\" = 'a b' ]; then\n  echo ${y:-z} $1 2>&1 # c\nfi\nf() { cd \\$HOME; }\n"))
```
---
    ((0 9 comment) (10 2 keyword) (13 1 keyword) (15 4 string) (22 5 string) (29 1 operator) (31 4 keyword) (38 4 keyword) (43 7 name) (51 2 name) (54 1 number) (55 2 operator) (57 1 number) (59 3 comment) (63 2 keyword) (67 1 operator) (68 1 operator) (70 1 keyword) (72 2 keyword) (75 2 escape) (81 1 operator) (83 1 keyword))

### a command substitution's commands are read as any others

`$(`, `$((` and a backquote are operators, and what they hold is coloured as
it would be on its own; `$'...'` is a string, a quote escaped inside it.

```sh
(do (import x/tool/syntax) (import ash/syntax)
    ((Syntax named (lit sh)) spans "a=$(pwd) b=$((1+2)) `echo $'c\\'d'` e#f"))
```
---
    ((2 2 operator) (4 3 keyword) (7 1 operator) (11 3 operator) (17 1 operator) (18 1 operator) (20 1 operator) (21 4 keyword) (26 7 string) (33 1 operator))

### a string or an expansion left open runs to the end

```sh
(do (import x/tool/syntax) (import ash/syntax)
    (List map (fn (_ s) ((Syntax named (lit sh)) spans s))
      (list "echo 'a" "echo \"a $(b \")\") c" "echo ${a")))
```
---
    (((0 4 keyword) (5 2 string)) ((0 4 keyword) (5 13 string)) ((0 4 keyword) (5 3 name)))

### the grammar's words are the shell's reserved words and builtins

```sh
(do (import ash/syntax sh-syntax-reserved-words sh-syntax-builtins)
    (import ash/eval sh-reserved-words)
    (list (equal? sh-syntax-reserved-words sh-reserved-words)
          (equal? sh-syntax-builtins (map first sh-builtin-table))))
```
---
    (#t #t)

### a window reads from the line above it that starts a command

Spans walk back from a window's first line to one starting with a name, a
comment or a closing brace, so a string opened on an indented line above
colours the window's start.

```sh
(do (import x/tool/syntax) (import ash/syntax)
    ((Syntax named (lit sh)) spans "if x\n  echo 'a\n  b' c\nfi\n" 15 6))
```
---
    ((15 4 string))
