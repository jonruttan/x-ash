## sh-eval an error ends a shell with no terminal

A shell whose input and reports are not both terminals is running a script,
and an error ends a script (POSIX 2.8.1): a syntax error, an expansion error,
an error of a special builtin.  So a script piped in stops at its first error,
as one run with -f does, and both leave with 2, the status a subshell ended by
an error answers.  At a terminal the error is reported and the prompt reads
on.

Expectations match `dash`, which leaves with 2 after every error; bash 3.2
leaves with 2 after a syntax error and 1 after the others.  Each case drives
the session with a stand-in reader that hands out lines and raises when it has
none left, and a stand-in exit that records the status and raises, so that
the case can see what the shell did and where it stopped.  The third and
fourth cases are pins that hold on main too.

### a syntax error ends a session with no terminal before its next line

```sh
(do
  (import ash/line)
  (import ash/repl)
  (let ((lines (list "echo a" "fi" "echo b"))
        (left ())
        (read ash-read-line)
        (collect (%repl-ref (lit %ash-collect)))
        (leave sh-exit-shell))
    (%repl-set! (lit %ash-collect) (fn (_) ()))
    (%ash-set! (lit ash-read-line)
      (fn (_ prompt)
        (if (null? lines)
          (error "no more lines")
          (let ((line (first lines))) (set! lines (rest lines)) line))))
    (%ash-set! (lit sh-exit-shell) (fn (_ status) (set! left status) (error "left")))
    (guard (e ()) (%ash-repl-loop))
    (%ash-set! (lit ash-read-line) read)
    (%repl-set! (lit %ash-collect) collect)
    (%ash-set! (lit sh-exit-shell) leave)
    (write (list left lines))
    ()))
```
---
    (2 ("echo b"))

### so do an expansion error and an arithmetic one

```sh
(do
  (import ash/line)
  (import ash/repl)
  (let ((read ash-read-line)
        (collect (%repl-ref (lit %ash-collect)))
        (leave sh-exit-shell))
    (def session
      (fn (_ lines)
        (def left ())
        (%ash-set! (lit ash-read-line)
          (fn (_ prompt)
            (if (null? lines)
              (error "no more lines")
              (let ((line (first lines))) (set! lines (rest lines)) line))))
        (%ash-set! (lit sh-exit-shell) (fn (_ status) (set! left status) (error "left")))
        (guard (e ()) (%ash-repl-loop))
        (list left lines)))
    (%repl-set! (lit %ash-collect) (fn (_) ()))
    (def r (list (session (list ": ${d7_unset_name?unset}" "echo b"))
                 (session (list ": $((1/0))" "echo b"))))
    (%ash-set! (lit ash-read-line) read)
    (%repl-set! (lit %ash-collect) collect)
    (%ash-set! (lit sh-exit-shell) leave)
    (write r)
    ()))
```
---
    ((2 ("echo b")) (2 ("echo b")))

### at a terminal the error is reported and the prompt reads on

```sh
(do
  (import ash/line)
  (import ash/repl)
  (let ((lines (list "fi" "echo b"))
        (left ())
        (read ash-read-line)
        (collect (%repl-ref (lit %ash-collect)))
        (leave sh-exit-shell)
        (terminal? ash-interactive?))
    (%repl-set! (lit %ash-collect) (fn (_) ()))
    (%ash-set! (lit ash-interactive?) (fn (_) #t))
    (%ash-set! (lit ash-read-line)
      (fn (_ prompt)
        (if (null? lines)
          (error "no more lines")
          (let ((line (first lines))) (set! lines (rest lines)) line))))
    (%ash-set! (lit sh-exit-shell) (fn (_ status) (set! left status) (error "left")))
    (guard (e ()) (%ash-repl-loop))
    (%ash-set! (lit ash-read-line) read)
    (%repl-set! (lit %ash-collect) collect)
    (%ash-set! (lit sh-exit-shell) leave)
    (%ash-set! (lit ash-interactive?) terminal?)
    (write (list left lines))
    ()))
```
---
    (() ())

### a `break` with no loop is no error, and the script goes on

```sh
(do
  (import ash/line)
  (import ash/repl)
  (let ((lines (list "break" "echo b"))
        (left ())
        (read ash-read-line)
        (collect (%repl-ref (lit %ash-collect)))
        (leave sh-exit-shell))
    (%repl-set! (lit %ash-collect) (fn (_) ()))
    (%ash-set! (lit ash-read-line)
      (fn (_ prompt)
        (if (null? lines)
          (error "no more lines")
          (let ((line (first lines))) (set! lines (rest lines)) line))))
    (%ash-set! (lit sh-exit-shell) (fn (_ status) (set! left status) (error "left")))
    (guard (e ()) (%ash-repl-loop))
    (%ash-set! (lit ash-read-line) read)
    (%repl-set! (lit %ash-collect) collect)
    (%ash-set! (lit sh-exit-shell) leave)
    (write (list left lines))
    ()))
```
---
    (() ())

### a script run with -f leaves with the same status

```sh
(do
  (import ash/repl)
  (let ((lines (list "echo a" "fi" "echo b"))
        (left ())
        (read sh-read-line)
        (leave sh-exit-shell))
    (%ash-set! (lit sh-read-line)
      (fn (_)
        (if (null? lines)
          ()
          (let ((line (first lines))) (set! lines (rest lines)) line))))
    (%ash-set! (lit sh-exit-shell) (fn (_ status) (set! left status) (error "left")))
    (guard (e ()) (ash-batch))
    (%ash-set! (lit sh-read-line) read)
    (%ash-set! (lit sh-exit-shell) leave)
    (write left)
    ()))
```
---
    2
