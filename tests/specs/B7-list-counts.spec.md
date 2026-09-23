## sh-eval counting along a list

The list vocabulary the evaluator uses -- `length`, `take`, `drop`, and `nth`
through it -- walks pairs, and counts on the integer doors: a count there is a
position in a list the caller holds, never nil and never a bignum.  `[` takes
its words but the closing `]`, `shift` drops the first ones, `getopts` reads
the word at `OPTIND`, and `$2` the second parameter.

Expectations match `/bin/sh` and `dash`, and hold on main too.  The cost is
compared rather than counted, as spec 36 compares its tests.

### what the walks answer

```sh
(do (sh-eval "( set -- a b c d; shift 2; echo \"[$*]\"; [ 1 -lt 2 ] && echo lt; [ b = b ] && echo eq; set -- -a -b x; while getopts ab o; do printf %s \"$o\"; done; echo \" $OPTIND\"; set -- p q r; echo \"[${2}][$#]\" ) | tr '\\n' ','; echo") ())
```
---
    [c d],lt,eq,ab 3,[q][3],

### and the lists themselves

```sh
(list (length (list 1 2 3 4)) (take 3 (list 1 2 3 4)) (drop 3 (list 1 2 3 4))
      (nth 1 (list 1 2 3)) (take 0 (list 1 2)) (drop 5 (list 1 2)) (nth 5 (list 1 2)))
```
---
    (4 (1 2 3) (4) 2 () () ())

### taking all but the last word costs less than a comparison per word

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (wds (list "5" "-lt" "20" "]")))
  (< (cost (fn (_) (take 3 wds)))
     (cost (fn (_) ((fn (self i) (if (fx<? i 4) (do (>= i 3) (self (fx+ i 1))) ())) 0)))))
```
---
    #t
