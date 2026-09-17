## sh-eval the prompt variables

PS1 is the prompt before each command, PS2 the prompt before each line that
continues a command, and PS4 the text before each line `set -x` writes.  Each
starts with POSIX's default unless the environment holds it, and each is
expanded as double-quoted text is every time it is shown, so a prompt may
carry a parameter or a command substitution.

The defaults match `dash`; bash 3.2 leaves PS1 and PS2 unset when it is not
interactive.  The prompts an interactive session shows, and the traces under
PS4, match both.

### the defaults

```sh
(do (sh-eval "printf \"[%s][%s][%s]\" \"$PS1\" \"$PS2\" \"$PS4\"; echo") ())
```
---
    [$ ][> ][+ ]

### the session prompts with PS1, and with PS2 for a line that continues

A stand-in reader answers the session's reads and records the prompt each was
made with; when it has no lines left it raises, which ends the loop.

```sh
(do
  (import ash/line)
  (let ((prompts ())
        (lines (list "PS1='mine> '; PS2='more? '" "if true" "then :; fi"))
        (read %ash-read-line)
        (collect %ash-collect))
    (set! %ash-collect (fn (_) ()))
    (set! %ash-read-line
      (fn (_ prompt)
        (set! prompts (pair prompt prompts))
        (if (null? lines)
          (error "no more lines")
          (let ((line (first lines))) (set! lines (rest lines)) line))))
    (guard (e ()) (%ash-repl-loop))
    (set! %ash-read-line read)
    (set! %ash-collect collect)
    (write (reverse prompts))))
```
---
    ("$ " "mine> " "more? " "mine> ")

### a prompt shows the value it is set to

```sh
(do (sh-eval "PS1='my-prompt> '") (write (%sh-prompt "PS1")))
```
---
    "my-prompt> "

### it is expanded when it is shown, not when it is set

```sh
(do (sh-eval "x=world; PS1='$x$ '; x=there") (write (%sh-prompt "PS1")))
```
---
    "there$ "

### a command substitution in a prompt runs

```sh
(do (sh-eval "PS1='$(echo cs)> '") (write (%sh-prompt "PS1")))
```
---
    "cs> "

### the continuation prompt

```sh
(do (sh-eval "PS2='more? '") (write (%sh-prompt "PS2")))
```
---
    "more? "

### set -x writes PS4 before each command

```sh
(do (sh-eval "( PS4='trace: '; set -x; echo hi ) 2>&1 | tr '\\n' '|'; echo") ())
```
---
    trace: echo hi|hi|

### and expands it

```sh
(do (sh-eval "( x=T; PS4='$x> '; set -x; echo hi ) 2>&1 | tr '\\n' '|'; echo") ())
```
---
    T> echo hi|hi|

### a substitution in PS4 is not itself traced

Expanding PS4 with tracing on would trace the substitution, and so expand PS4
again, without end.  bash runs the substitution; dash shows PS4 as written.

```sh
(do (sh-eval "( PS4='$(echo cs)> '; set -x; echo hi ) 2>&1 | tr '\\n' '|'; echo") ())
```
---
    cs> echo hi|hi|

### an unset prompt shows nothing

```sh
(do (sh-eval "unset PS1") (write (%sh-prompt "PS1")))
```
---
    ""
