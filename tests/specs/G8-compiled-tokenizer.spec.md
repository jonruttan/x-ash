## sh-tokenize the compiled base reads a text as the interpreted one does

Once enough text has been read in the shell's own process, a text is read
through a base whose states are compiled (ash/tokens.x); until then, in a
child, and wherever the states cannot be compiled, it is read through the
interpreted base.  A quoted string's analyser says whether the token is one
quoted string or a word, so its reader does not ask the text.

The first case holds on main too.  The others compile the base in a child,
by setting the threshold to nothing and the shell's pid to the child's.  Each
answers the same wherever it runs: where the compile lane works -- asked
independently, with an equivalent state -- the base must be active, so
a refusal the guard swallowed cannot pass for agreement.

### a quoted string, and a word that holds one, to the end of the text

```sh
(map sh-tokenize
  (list "'a'" "'a' " "'a'b" "\"a\"" "\"a\"b c" "a'b'" "'a''b'" "'a'\\'" "'a'\"b'"
        "\"a\"'b" "'a'$(b '" "'a'`b" "\"a $(b \"c\") d\"" "\"a $(b) d\"" "\"a\\\"b\"" "''" "\"\"x"))
```
---
    (((tok-sq "a")) ((tok-sq "a")) ((tok-word "'a'b")) ((tok-dq "a")) ((tok-word "\"a\"b") (tok-word "c")) ((tok-word "a'b'")) ((tok-word "'a''b'")) ((tok-word "'a'\\'")) ((tok-word "'a'\"b'")) ((tok-word "\"a\"'b")) ((tok-word "'a'$(b '")) ((tok-word "'a'`b")) ((tok-word "\"a $(b \"c\") d\"")) ((tok-dq "a $(b) d")) ((tok-dq "a\\\"b")) ((tok-sq "")) ((tok-word "\"\"x")))

### the compiled base gives the tokens the interpreted base gives

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (do (display "error: ") (write e) (newline) (sh-exit 5)))
      (alloc-limit! (+ (Heap count) 60000000))
      (def lane? (guard (e ()) (do
        (%sh-compile-asm (lit (fn (me buffer score chr)
                            (if (= chr 10)
                              (%seq (%score-label! score 1) (%score-set score 1 buffer))
                              me)))
                     ())
        #t)))
      (def texts (list "" " " "a" "a b" ": a b c; x=1; echo x >/dev/null\n"
        "echo 'q' \"d\" $x ${y:-a b} $(sub 'z' \")\") `bt x` $((1+2))\n"
        "a'b'c \"d\"e f\"g h\"i 'j k'l\n" "x=\"a $y\" z='1 2'\n"
        "a\\ b \; \\$x \"e\\\"f\" 'g'\\''h'\n" "# comment\necho a#b # c\n"
        "a|b||c&d&&e;f;;g<h<<i<<-j>k>>l<&m>&n<>o>|p(q)r>>-s<|t\n"
        "2>err 1<in 10>>x echo 2 >out 12abc 3rd -0 +5 -007 -a --x - -lt 50$ 7'q' 8\"r\"\n"
        "if [ $i -lt 50 ]; then i=$((i+1)); fi\nfor f in a b; do echo $f; done\n"
        "case $x in a*) y=1;; *) y=2;; esac\nf() { local v=$1; }\n"
        "\"unterminated" "'unterminated" "$(unterminated" "${unterminated" "`unterminated"
        "a\\" "\"a $(b \"c\" 'd') e\" \"${f:-\"g\"}\" \"`h`\" \"$$ $\"\n"
        "tab\tsep\t\tx\n\n\n  lead" "a$" "$" "$b$c" "1$" "1`x`" "1\;2" "<" ">>" "<<-" "&" "("
        "'a'" "'a' " "'a'b" "\"a\"b c" "'a''b'" "'a'\\'" "'a'\"b'" "\"a\"'b" "'a'$(b '" "'a'`b"))
      (def before (map sh-tokenize texts))
      (set! %sh-pid (sh-getpid))
      (set! %sh-jit-threshold 0)
      (sh-tokenize "x")
      (def differ
        (fn (self ts a b)
          (match
            ((null? ts) ())
            ((equal? (first a) (first b)) (self (rest ts) (rest a) (rest b)))
            (#t (pair (first ts) (self (rest ts) (rest a) (rest b)))))))
      (write
        (match
          ((null? lane?) #t)
          ((eq? %sh-jit (lit active)) (null? (differ texts before (map sh-tokenize texts))))
          (#t (list (lit not-active) %sh-jit))))
      (newline)
      (sh-exit 7))
    (sh-wait pid))
  ())
```
---
    #t

### a script runs the same read through either base

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (do (display "error: ") (write e) (newline) (sh-exit 5)))
      (alloc-limit! (+ (Heap count) 60000000))
      (def script "g8_out=$( g8_n=0; for g8_i in 1 2 3; do g8_n=$((g8_n+g8_i)); done; g8_f() { echo \"$1:$g8_n\" 'q r' ${g8_u:-d e} `echo bt`; }; g8_f a | tr a A; if [ \"$g8_n\" = 6 ]; then echo six; fi; [ $g8_n -lt 7 ] && echo less >&2 2>/dev/null; echo done )")
      (sh-eval script)
      (def before (%sh-var-get "g8_out"))
      (sh-eval "g8_out=")
      (set! %sh-pid (sh-getpid))
      (set! %sh-jit-threshold 0)
      (sh-eval script)
      (write (list before (equal? before (%sh-var-get "g8_out"))))
      (newline)
      (sh-exit 7))
    (sh-wait pid))
  ())
```
---
    ("A:6 q r d e bt\nsix\ndone" #t)

### a child makes no base of its own

```sh
(do
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (do (display "error: ") (write e) (newline) (sh-exit 5)))
      (set! %sh-jit (lit off))
      (set! %sh-jit-bytes 0)
      (set! %sh-jit-threshold 0)
      (write (sh-tokenize "a 'b'"))
      (write %sh-jit)
      (newline)
      (sh-exit 7))
    (sh-wait pid))
  ())
```
---
    ((tok-word "a") (tok-sq "b"))failed
