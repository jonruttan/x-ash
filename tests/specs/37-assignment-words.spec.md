## sh-eval which words are assignments

A word in assignment position is an assignment when its first `=` comes after
its first character.  The text before that `=` is the name and everything
after it is the value, further `=` included.  A word that starts with `=` is
an ordinary word, so it names a command.

Every word in assignment position is tested, the first word of every command
among them, so the test is one scan that builds nothing.  Its cost is compared
with one conversion rather than counted.

Expectations match `/bin/sh` and `dash`.

### a name and a value

```sh
(do (sh-eval "ASH_A=1; echo \"[$ASH_A]\"") ())
```
---
    [1]

### the first `=` ends the name

```sh
(do (sh-eval "ASH_B=c=d; echo \"[$ASH_B]\"") ())
```
---
    [c=d]

### the value may be empty

```sh
(do (sh-eval "ASH_C=; echo \"[$ASH_C]\"") ())
```
---
    []

### two assignments in a row

```sh
(do (sh-eval "ASH_D=1 ASH_E=2; echo \"[$ASH_D$ASH_E]\"") ())
```
---
    [12]

### a word that starts with `=` names a command

```sh
(do (sh-eval "=x 2>/dev/null; echo \"[$?]\"") ())
```
---
    [127]

### telling a word is an assignment converts nothing

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (%is-assignment? "abcdefgh=1")))
     (cost (fn (_) (convert #\= %ash-int-type)))))
```
---
    #t
