## sh-eval a word is read once into a plan

A word is read once into a plan -- the steps its expansion takes: runs of
plain text, quotes that open a field, escapes, parameters, substitutions,
arithmetic, `${...}`, tildes -- and the plan runs each time the word is
expanded, asking then for what can change: a value, a substitution's output,
HOME.  The word's token keeps its plan, so the body of a loop or a function is
read once however often it runs.

The first case is a pin that holds on main too; its expectation matches
`dash` and `/bin/sh`.  The second counts the scans a word's text takes.  The
third keeps plans across a collect before every simple command.

### every variant of step, run twice round a loop

```sh
(do (sh-eval "( HOME=/h; set -- p q; for i in 1 2; do x=\"a$i\"; echo \"$x\" ${x}b $((i*2)) \\$i '$i' ~/z \"$@\" ${u:-d e} `echo q$i`; done ) | tr '\\n' ','; echo") ())
```
---
    a1 a1b 2 $i $i /h/z p q d e q1,a2 a2b 4 $i $i /h/z p q d e q2,

### a word is read once however often its loop goes round

The words of `: a$i "b$i"` are scanned as often going round three times as
going round once.

```sh
(let ((saved %sh-plain-run)
      (scans 0)
      (run (fn (_ text)
             (let ((ts (first (%sh-mark-command (sh-tokenize text)))))
               (fn (_) (%eval-list (%mk-cursor ts)))))))
  (def count
    (fn (_ text)
      (def thunk (run text))
      (set! scans 0)
      (set! %sh-plain-run
        (fn (_ s i n mode meta? tilde?)
          (set! scans (+ scans 1))
          (saved s i n mode meta? tilde?)))
      (guard (e (do (set! %sh-plain-run saved) (error e))) (thunk))
      (set! %sh-plain-run saved)
      scans))
  (= (count "for i in 1; do : a$i \"b$i\"; done")
     (count "for i in 1 2 3; do : a$i \"b$i\"; done")))
```
---
    #t

### a word's plan is kept across collects

A child process collects before every simple command while a loop goes round
20 times, each word's plan read the first time round and run on the rest.

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (set! %sh-sweeps? #t)
      (set! %sh-sweep-every 1)
      (set! %sh-sweep-left 1)
      (sh-eval "f8_i=0; while [ $f8_i -lt 20 ]; do f8_i=$((f8_i+1)); f8_x=\"a$f8_i\"; f8_s=\"${f8_x}b$((f8_i*2))\"; done")
      (sh-exit (if (string=? (%sh-var-get "f8_s") "a20b40") 7 3)))
    (write (sh-wait pid)))
  ())
```
---
    7
