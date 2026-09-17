## sh-eval an error in a forked child ends the child

A subshell, a pipeline stage, a command substitution, an asynchronous list and
the fork an external command is run from each run in a child process.  An
error in one ends that child: it is reported on stderr and the child exits
with a status other than 0, while the shell that forked it carries on.  A
`return` or loop signal that nothing in the child catches ends the child too,
with the status the signal carries, and does not reach the function or loop
around the subshell in the parent.

Without this the error unwound through the code the child had copied from the
shell that forked it, and the child ran on as a second copy of that shell.

Expectations match `/bin/sh` and `dash`.

### an error in a subshell ends it with a failing status

```sh
(do (sh-eval "( : $((1/0)) ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; printf \"[after]\"; echo") ())
```
---
    [failed][after]

### and is reported

```sh
(do (sh-eval "x=$( ( : $((1/0)) ) 2>&1 ); [ -n \"$x\" ] && printf \"[reported]\"; echo") ())
```
---
    [reported]

### in a command substitution

```sh
(do (sh-eval "v=$( : $((1/0)) ) 2>/dev/null; [ $? -ne 0 ] && printf \"[failed]\"; printf \"[v=%s]\" \"$v\"; echo") ())
```
---
    [failed][v=]

### in a pipeline stage the pipeline answers its last stage

```sh
(do (sh-eval "{ echo $((1/0)) | cat; } 2>/dev/null; printf \"[after:%s]\" $?; echo") ())
```
---
    [after:0]

### in an asynchronous list

```sh
(do (sh-eval "{ : $((1/0)); } 2>/dev/null & wait $!; [ $? -ne 0 ] && printf \"[failed]\"; printf \"[after]\"; echo") ())
```
---
    [failed][after]

### break in a subshell ends the subshell, not the loop around it

```sh
(do (sh-eval "for i in 1 2; do ( break ); printf \"[%s]\" $i; done; echo") ())
```
---
    [1][2]

### return in a subshell ends the subshell with its status

```sh
(do (sh-eval "f() { ( return 3 ); printf \"[in:%s]\" $?; }; f; echo") ())
```
---
    [in:3]

### after a failing subshell at the prompt, one process reads the next line

The session itself, driven by a stand-in reader that notes the process each
read is made from: an error in a subshell must not leave a second copy of the
session reading lines.

```sh
(do
  (import ash/line)
  (let ((lines (list "( : $((1/0)) ) 2>/dev/null" ":"))
        (read %ash-read-line)
        (collect %ash-collect))
    (sh-eval "readers_log=$(mktemp)")
    (set! %ash-collect (fn (_) ()))
    (set! %ash-read-line
      (fn (_ prompt)
        (sh-eval "sh -c 'echo $PPID' >> \"$readers_log\"")
        (if (null? lines)
          (error "no more lines")
          (let ((line (first lines))) (set! lines (rest lines)) line))))
    (guard (e ()) (%ash-repl-loop))
    (set! %ash-read-line read)
    (set! %ash-collect collect)
    (sh-eval "printf \"[%s]\" \"$(sort -u \"$readers_log\" | wc -l | tr -d ' ')\"; rm -f \"$readers_log\"; echo")
    ()))
```
---
    [1]
