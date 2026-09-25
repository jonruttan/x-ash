## sh-eval sweeps while a script runs

With `%sh-sweeps?` on, as run.x turns it on for a session and a script, the
evaluator collects once every `%sh-sweep-every` simple commands, so a loop
holds what it keeps and not everything it has allocated.  An evaluation whose
token list is longer than `%sh-sweep-long` holds sweeps off until it ends,
since a collect with a list that long alive dies in the engine.

The first case bounds a child at 10 million objects above what it inherited
while a loop allocates four times that; the second counts collects with a
stand-in.  The third runs a script with a collect before every simple command
and expects what `/bin/sh` and `dash` print for it.  The last pins that the
suite runs with sweeps off, so its cases count what was allocated.  On main,
which has no sweeps, all four fail.

### a loop that allocates four times its bound finishes under it

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (set! %sh-sweeps? #t)
      (set! %sh-sweep-every 64)
      (set! %sh-sweep-left 64)
      (alloc-limit! (+ (Heap count) 10000000))
      (sh-eval "d9_i=0; while [ $d9_i -lt 1000 ]; do d9_i=$((d9_i+1)); done")
      (sh-exit (if (string=? (%sh-var-get "d9_i") "1000") 7 3)))
    (write (sh-wait pid)))
  ())
```
---
    7

### a long script holds sweeps off, and they resume after it

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (alloc-limit! (+ (Heap count) 45000000))
      (def count 0)
      (set! %sh-collect (fn (_) (set! count (+ count 1))))
      (set! %sh-sweeps? #t)
      (set! %sh-sweep-every 64)
      (set! %sh-sweep-left 64)
      (def loop "d9_i=0; while [ $d9_i -lt 50 ]; do d9_i=$((d9_i+1)); done")
      (sh-eval loop)
      (def before count)
      (sh-eval (string-append (Str8 repeat 25100 "\n") loop))
      (def during (- count before))
      (sh-eval loop)
      (def after (- count before during))
      (sh-exit (if (fx<? 0 before) (if (= during 0) (if (fx<? 0 after) 7 4) 3) 6)))
    (write (sh-wait pid)))
  ())
```
---
    7

### a collect before every command changes no answer

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (sh-exit 5))
      (set! %sh-sweeps? #t)
      (set! %sh-sweep-every 1)
      (set! %sh-sweep-left 1)
      (alloc-limit! (+ (Heap count) 20000000))
      (sh-eval "f() { local x=$1; echo \"f:$x\"; }\nr=\nfor i in 1 2 3; do r=\"$r$(f $i)\"; done\ncase $r in *f:2*) r=\"$r+case\";; esac\ns=$(printf '%s\\n' c b a | sort | tr '\\n' ,)\nh=$(cat <<EOF\nhere $i\nEOF\n)\n( exit 3 ); st=$?\nv=${r%%+*}; n=${#v}\nw=$(printf '1\\n2\\n3\\n' | while read x; do c=$((c+x)); echo $c; done | tail -1)\nset -- a \"b c\" d; p=\"$#:$2\"\nk=0; while [ $k -lt 5 ]; do k=$((k+1)); done\necho \"$r|$s|$h|$st|$n|$w|$p|$k\"\n")
      (sh-exit 7))
    (sh-wait pid))
  ())
```
---
    f:1f:2f:3+case|a,b,c,|here 3|3|9|6|3:b c|5

### the suite runs with sweeps off

```sh
(do (write %sh-sweeps?) ())
```
---
    ()
