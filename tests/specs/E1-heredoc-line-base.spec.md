## sh-eval the compiled line base reads here-document text as the walk does

A text holding a here-document is read in lines.  Once enough such text has
been read, the lines come from a base whose two states are compiled
(ash/tokens.x), and the base marks the lines the scan must see; until then,
and wherever the states cannot be compiled, the lines are cut by hand
(ash/eval.x).  These cases compile the base in a child, by setting the
threshold to nothing, and hold the base to the walk: the same lines, the same
marks, the same extractions.

Each case answers the same wherever it runs.  Where the compile lane works --
asked independently, with a state of the same shape -- the base must be
active, so a refusal the guard swallowed cannot pass for agreement; where the
lane does not, there is nothing to compare, and the case answers as if it
had.

### the base reads the lines the walk cuts, and marks the lines it would ask

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (do (display "error: ") (write e) (newline) (sh-exit 5)))
      (alloc-limit! (+ (Heap count) 30000000))
      (def lane? (guard (e ()) (do (import x/tool/compile)
        (compile-asm (lit (fn (me buffer score chr) (if (= chr 10) (%score-set score 1 buffer) me))) () #t) #t)))
      (set! %sh-hd-jit-threshold 0)
      (%sh-hd-lines "x")
      (def texts (list "" "a" "a\n" "\n\n" "plain line\nanother\n"
        "echo 'q' \"d\" $x\n(sub)\n#c\n<in\n\\esc\n" "cat <<EOF\nbody\nEOF\n"
        "tab\tline\nend" "cr\rline\n" "a)b\nc(d\ne$f\ng#h\n"))
      (def agree?
        (fn (self ts)
          (if (null? ts) #t
            (do
              (def s (string-append (first ts) "\n"))
              (def cut (%sh-hd-cut s 0 0 (string-length s) ()))
              (def read (%token-read-str %sh-hd-raw s))
              (if (equal? (map %sh-hd-line-text read) cut)
                (if (equal? (map (fn (_ t) (if (%sh-hd-passes? t #t) (lit plain) (lit scan))) read)
                            (map (fn (_ l) (if (%sh-hd-passes? l ()) (lit plain) (lit scan))) cut))
                  (self (rest ts))
                  (list (lit marks) (first ts)))
                (list (lit lines) (first ts)))))))
      (write (if lane? (if (eq? %sh-hd-jit (lit active)) (agree? texts) (list (lit not-active) %sh-hd-jit)) #t))
      (newline)
      (sh-exit 7))
    (sh-wait pid))
  ())
```
---
    #t

### here-documents extract through the base as they do by hand

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (do (display "error: ") (write e) (newline) (sh-exit 5)))
      (alloc-limit! (+ (Heap count) 30000000))
      (def lane? (guard (e ()) (do (import x/tool/compile)
        (compile-asm (lit (fn (me buffer score chr) (if (= chr 10) (%score-set score 1 buffer) me))) () #t) #t)))
      (def scripts (list
        "cat <<EOF\nhello\nEOF\necho after\n"
        "cat <<'E'\n$x 'q' \"d\"\n\ttab\nE\n"
        "cat <<-E\n\tstripped\n\tE\n"
        "cat <<E\nline\\\njoined\nE\n"
        "cat <<A; cat <<B\none\nA\ntwo\nB\n"
        "echo \"x <<y\" 'z <<w' # c <<v\ncat <<E\nbody\nE"
        "x=$(cat <<E\nin\nE\n)\necho $((1<<2))\n"
        "cat <<E\nunterminated\n"))
      (def extract-all
        (fn (self ss)
          (if (null? ss) ()
            (do
              (def text (%sh-heredoc-extract (first ss)))
              (pair (list text %sh-heredocs) (self (rest ss)))))))
      (set! %sh-hd-jit-threshold 100000000)
      (def by-hand (extract-all scripts))
      (set! %sh-hd-jit-threshold 0)
      (%sh-hd-lines "x")
      (def by-base (extract-all scripts))
      (write (if lane? (if (eq? %sh-hd-jit (lit active)) (equal? by-hand by-base) (list (lit not-active) %sh-hd-jit)) #t))
      (newline)
      (sh-exit 7))
    (sh-wait pid))
  ())
```
---
    #t
