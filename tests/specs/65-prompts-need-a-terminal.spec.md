## sh-eval a prompt is for a session

A shell is interactive when its own input and its reports are both terminals.
Only then is there anyone to prompt, so a script arriving down a pipe or out
of a file gets no prompt and no banner, and stdout carries what the commands
wrote and nothing else.  The prompts themselves go to standard error, where
POSIX puts them.

The suite is not a session, so these cases hold the silent half: what a
session writes to a terminal has no terminal here to be written to.

### the suite is not a session

```sh
(do (import ash/line) (write (if (%ash-interactive?) "yes" "no")) ())
```
---
    "no"

### so a prompt writes nothing

```sh
(do (import ash/line) (%ash-show-prompt "$ ") (write "after") ())
```
---
    "after"

### and neither does the banner

```sh
(do (import ash/repl) (%ash-banner) (write "after") ())
```
---
    "after"

### nor the newline that ends a session

A stand-in reader answers the loop's first read with end-of-input, and a
stand-in exit lets the loop return rather than leaving the process.

```sh
(do
  (import ash/repl)
  (let ((read %ash-read-line)
        (collect %ash-collect)
        (leave %sh-exit-shell))
    (set! %ash-collect (fn (_) ()))
    (set! %ash-read-line (fn (_ prompt) ()))
    (set! %sh-exit-shell (fn (_ status) status))
    (guard (e ()) (%ash-repl-loop))
    (set! %ash-read-line read)
    (set! %ash-collect collect)
    (set! %sh-exit-shell leave))
  (write "after")
  ())
```
---
    "after"
