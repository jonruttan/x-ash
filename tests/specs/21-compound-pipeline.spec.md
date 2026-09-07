## sh-eval a compound command as a pipeline stage

`( echo p ) | tr p P` cuts at the `|` like any other pipeline.  It did not:
a compound was evaluated before any stage was collected, so the `|` after one
was never looked for -- it was left unread, `%eval-list` ended its list at it,
and the rest of the script was silently dropped.

The stage collector now counts nesting, so the `;` inside a loop and the
`done` that closes it belong to the stage rather than ending it.  A `case`
pattern's `)` closes nothing, so a closing paren only counts when there is an
open one to match.

Every case ends in a marker line: the suite compares the last line of output,
so a case that merely printed the piped text would pass on the broken code
too -- the text simply arrived unpiped.  Each expectation was taken from
`/bin/sh` first.

### a subshell feeds the next stage

```sh
(do (sh-eval "o=$( ( echo p ) | tr p P ); echo \"got=$o\"") ())
```
---
    got=P

### a for loop feeds it, internal semicolons and all

```sh
(do (sh-eval "o=$( for i in 1 2; do echo n$i; done | tr -d n | tr \"\\n\" \",\" ); echo \"got=$o\"") ())
```
---
    got=1,2,

### an if feeds it

```sh
(do (sh-eval "o=$( if true; then echo t; fi | tr t T ); echo \"got=$o\"") ())
```
---
    got=T

### a case feeds it, and its pattern paren is not a stage end

Not written inside `$( ... )`: a case pattern's `)` closes an old-style
command substitution early, which `/bin/sh` itself rejects as a syntax error.
The pipeline is what is under test, so it is written the way both shells
accept.

```sh
(do (sh-eval "case y in y) echo c;; esac | tr c C") ())
```
---
    C

### a subshell RECEIVES from the previous stage

```sh
(do (sh-eval "o=$( echo feed | ( cat ) ); echo \"got=$o\"") ())
```
---
    got=feed

### a while loop receives, so read in a pipeline works

```sh
(do (sh-eval "o=$( echo x | while read v; do echo \"v=$v\"; done ); echo \"got=$o\"") ())
```
---
    got=v=x

### a multi-command subshell is one stage

```sh
(do (sh-eval "o=$( ( echo a; echo b ) | wc -l | tr -d \" \" ); echo \"got=$o\"") ())
```
---
    got=2

### THE COMMANDS AFTER IT STILL RUN -- the silent truncation this fixes

```sh
(do (sh-eval "( echo p ) | tr p P > /dev/null; echo reached") ())
```
---
    reached

### a redirected compound is still a stage of its own

```sh
(do (sh-eval "( echo r ) > /dev/null; o=$( ( echo s ) | tr s S ); echo \"got=$o\"") ())
```
---
    got=S
