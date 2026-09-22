## sh-eval finding a builtin

A command name is looked up in the builtin table once, and the handler found
is what runs.  The table is walked from its start, so the builtins a loop runs
most -- `[`, `test`, `echo`, `:` -- come first, and a name that is no builtin
is the one that walks all of it.

The table names each builtin once: a second entry for a name would never be
reached.  The cost is compared rather than counted, as spec 36 compares its
tests.

### each name once

```sh
(= (length (List distinct (List map first %sh-builtin-table)))
   (length %sh-builtin-table))
```
---
    #t

### running `:` costs less than finding that `ls` is no builtin

```sh
(let ((cost (fn (_ thunk)
              (do (thunk)
                  (let ((before (Heap count))) (thunk) (- (Heap count) before))))))
  (< (cost (fn (_) (%sh-dispatch (list ":") () %sh-functions)))
     (cost (fn (_) (%sh-builtin? "ls")))))
```
---
    #t
