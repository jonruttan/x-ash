## the shell's arguments

`ash-operands` takes the shell's arguments out of the engine's, and `ash-plan`
says what they ask for: a session, the script on stdin, a command, or a file.
The expectations are BusyBox ash's reading of the same arguments.

### the engine's name and flags, and the wrapper's `--`, are not the shell's

```sh
(write (ash-operands (list "x-bin" "--batch" "--" "-c" "echo hi" "--quiet")))
```
---
    ("-c" "echo hi")

### no arguments is a session

```sh
(write (%ash-plan-get (lit label) (ash-plan ())))
```
---
    session

### -c takes the command, then $0, then the parameters

```sh
(let ((p (ash-plan (list "-c" "echo $1" "name" "a" "b"))))
  (write (list (%ash-plan-get (lit label) p) (%ash-plan-get (lit text) p)
               (%ash-plan-get (lit arg0) p) (%ash-plan-get (lit params) p))))
```
---
    (command "echo $1" "name" ("a" "b"))

### -c with a command and nothing after leaves $0 alone

```sh
(let ((p (ash-plan (list "-c" "true"))))
  (write (list (%ash-plan-get (lit arg0) p) (%ash-plan-get (lit params) p))))
```
---
    (() ())

### -c with no command is a usage error

```sh
(write (%ash-plan-get (lit label) (ash-plan (list "-c"))))
```
---
    usage

### a first word that is no option is a file, and is $0

```sh
(let ((p (ash-plan (list "s.sh" "one" "-x"))))
  (write (list (%ash-plan-get (lit label) p) (%ash-plan-get (lit text) p)
               (%ash-plan-get (lit arg0) p) (%ash-plan-get (lit params) p))))
```
---
    (file "s.sh" "s.sh" ("one" "-x"))

### options ahead of a file go to set

```sh
(let ((p (ash-plan (list "-e" "-u" "s.sh"))))
  (write (list (%ash-plan-get (lit label) p) (%ash-plan-get (lit opts) p))))
```
---
    (file ("-e" "-u"))

### c in a cluster is the command's, and the rest of it set's

```sh
(let ((p (ash-plan (list "-ec" "false; echo no"))))
  (write (list (%ash-plan-get (lit label) p) (%ash-plan-get (lit opts) p)
               (%ash-plan-get (lit text) p))))
```
---
    (command ("-e") "false; echo no")

### -s is the script on stdin, with parameters

```sh
(let ((p (ash-plan (list "-s" "arg"))))
  (write (list (%ash-plan-get (lit label) p) (%ash-plan-get (lit params) p))))
```
---
    (stdin ("arg"))

### -- ends the options, so a file may begin with a dash

```sh
(let ((p (ash-plan (list "-e" "--" "-odd"))))
  (write (list (%ash-plan-get (lit label) p) (%ash-plan-get (lit opts) p)
               (%ash-plan-get (lit text) p))))
```
---
    (file ("-e") "-odd")

### -o takes the word after it

```sh
(let ((p (ash-plan (list "-o" "errexit" "s.sh"))))
  (write (list (%ash-plan-get (lit label) p) (%ash-plan-get (lit opts) p))))
```
---
    (file ("-o" "errexit"))

### $0 is what the shell was started to run

```sh
(do (set! %sh-arg0 "s.sh") (sh-eval "echo $0") (set! %sh-arg0 "ash") ())
```
---
    s.sh
