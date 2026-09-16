## sh-eval a loop runs every pass it asks for

Nothing is collected while a command list runs, so what each pass of a loop
allocates adds up across the whole loop.  This suite runs under an allocation
ceiling, and a pass that costs too much ends the case with `allocation limit
exceeded` instead of an answer.

The evaluator's list operations -- length, append, take, last, reverse, and
the test for a word in a set -- walk pairs directly rather than calling the
platform's List class, whose methods cost tens of thousands of heap objects a
call.  The evaluator makes several of those calls for every word of every
command.

One case: a loop this long takes seconds, and a spec file has a minute.

### a hundred and fifty passes of a test and a count

```sh
(do (sh-eval "n=0; while [ $n -lt 150 ]; do n=$((n+1)); done; echo $n") ())
```
---
    150
