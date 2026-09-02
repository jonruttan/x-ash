; eval.x -- Combined token-list evaluator for ASH shell
;
; Replaces parser.x + old eval.x. Works directly on the flat
; token list from sh-tokenize using recursive descent that
; evaluates as it goes.
;
; Grammar (precedence low to high):
;   list      = and_or ((';'|'&'|newline) and_or)*
;   and_or    = pipeline (('&&'|'||') pipeline)*
;   pipeline  = command ('|' command)*
;   command   = compound | simple
;   compound  = if | while | for | '(' list ')'
;   simple    = (word|redirect)+
; --- Shell state ---

(def %sh-status 0)

(def %sh-pid (sh-getpid))
; --- Cursor: mutable box holding remaining token list ---

(def %mk-cursor (fn (_ tokens) (pair tokens ())))

(def %cursor-peek
  (fn (_ cur) (if (null? (first cur)) () (first (first cur)))))

(def %cursor-advance!
  (fn (_ cur) (set-first! cur (rest (first cur))) ()))

(def %cursor-empty? (fn (_ cur) (null? (first cur))))
; --- Token predicates ---

(def %tok-is-word?
  (fn (_ tok)
    (or
      (eq? (first tok) (lit tok-word))
      (eq? (first tok) (lit tok-sq))
      (eq? (first tok) (lit tok-dq)))))

; A KEYWORD IS A BARE WORD.  %tok-is-word? is true of tok-sq and tok-dq too --
; correct when asking "is this an argument", wrong when asking "is this the
; word `done`".  The keyword scanners asked the first question and meant the
; second, so
;
;   while test $N -eq 0; do echo "while"; N=1; done
;
; counted the QUOTED "while" as opening a nested loop, went looking for a
; second `done`, and swallowed the rest of the script -- reported as
; "parse error: unexpected EOF in while", pointing at a loop that is correct.
; Any loop or if whose body echoed one of the fifteen reserved words did it.
;
; %at-stop-word?, %is-compound-start?, %skip-case-body and %skip-to-esac spell
; this check out inline and were always right; the if/while family used the
; loose predicate.  Naming it is what makes the difference visible at the call
; site.
(def %tok-is-keyword?
  (fn (_ tok) (eq? (first tok) (lit tok-word))))

(def %tok-is-op?
  (fn (_ tok op)
    (and
      (eq? (first tok) (lit tok-op))
      (string=? (first (rest tok)) op))))

(def %tok-is-newline?
  (fn (_ tok) (eq? (first tok) (lit tok-newline))))

(def %tok-word-val
  (fn (_ tok)
    (if (eq? (first tok) (lit tok-newline))
      ()
      (first (rest tok)))))
; --- Match helpers ---

(def %match-op
  (fn (_ cur op)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (and
              (eq? (first tok) (lit tok-op))
              (string=? (first (rest tok)) op))
          (do (%cursor-advance! cur) #t)
          ())))))

(def %skip-newlines
  (fn (_ cur)
    (if (and
          (not (%cursor-empty? cur))
          (%tok-is-newline? (%cursor-peek cur)))
      (do (%cursor-advance! cur) (%skip-newlines cur))
      ())))
; --- Reserved word check ---

(def %reserved-word?
  (fn (_ word)
    (or
      (string=? word "if")
      (string=? word "then")
      (string=? word "elif")
      (string=? word "else")
      (string=? word "fi")
      (string=? word "while")
      (string=? word "until")
      (string=? word "for")
      (string=? word "do")
      (string=? word "done")
      (string=? word "case")
      (string=? word "in")
      (string=? word "esac")
      (string=? word "!")
      (string=? word "{")
      (string=? word "}"))))
; --- Stop-word helper ---

(def %at-stop-word?
  (fn (_ cur)
    (if (%cursor-empty? cur)
      #t
      (let ((tok (%cursor-peek cur)))
        (if (eq? (first tok) (lit tok-word))
          (let ((w (first (rest tok))))
            (or
              (string=? w "then")
              (string=? w "elif")
              (string=? w "else")
              (string=? w "fi")
              (string=? w "do")
              (string=? w "done")
              (string=? w "esac")
              (string=? w "}")))
          (if (eq? (first tok) (lit tok-op))
            (or
              (string=? (first (rest tok)) ")")
              (string=? (first (rest tok)) ";;"))
            ()))))))

(def %expect-word
  (fn (_ cur word)
    (if (%cursor-empty? cur)
      (error (string-append "parse error: expected " word))
      (let ((tok (%cursor-peek cur)))
        (if (and
              (eq? (first tok) (lit tok-word))
              (string=? (first (rest tok)) word))
          (do (%cursor-advance! cur) #t)
          (error (string-append "parse error: expected " word)))))))
; --- Variable expansion ---

; EXPANSION USED TO BE ALL-OR-NOTHING, and the test was the FIRST CHARACTER.
; A word was expanded only when it began with `$`, and then the whole of the
; rest of it was taken as the variable name -- so `$HOME` worked, and
;
;   echo "n=$f"      ->  n=$f
;   echo pre$X       ->  pre$X
;   echo ${HOME}     ->  (nothing: the name looked up was "{HOME}")
;
; all failed, silently and as literals.  Embedded expansion is not a corner of
; shell syntax; `"n=$f"` is the second thing anyone types into a for loop.
;
; So the scan walks the whole word.  What it understands:
;   $NAME     a name is [A-Za-z_][A-Za-z0-9_]*, ending at the first character
;             that is not one -- which is what makes `pre$X.txt` work
;   ${NAME}   the braces delimit, for exactly the cases where the run would
;             not end where you meant it to
;   $?  $$    the last status and the shell's pid, as before
;   $         anything else -- a literal dollar, which is what a shell does
;             with `echo 50$`
;
; An unset variable expands to the empty string, which is POSIX default (no
; `set -u` here yet).

(def %sh-dollar 36)
(def %sh-lbrace 123)
(def %sh-rbrace 125)

(def %sh-name-start?
  (fn (_ c)
    (or (and (>= c 65) (<= c 90))
        (or (and (>= c 97) (<= c 122))
            (= c 95)))))

(def %sh-name-char?
  (fn (_ c)
    (or (%sh-name-start? c) (and (>= c 48) (<= c 57)))))

(def %sh-var-value
  (fn (_ name)
    (if (string=? name "?")
      (convert %sh-status %string)
      (if (string=? name "$")
        (convert %sh-pid %string)
        (let ((val (sh-getenv name))) (if (null? val) "" val))))))

; The end of the name run starting at I.
(def %sh-name-end
  (fn (self s i n)
    (if (>= i n)
      i
      (if (%sh-name-char? (convert (string-ref s i) %int))
        (self s (+ i 1) n)
        i))))

; The index of the closing brace at or after I, or -1.
(def %sh-brace-end
  (fn (self s i n)
    (if (>= i n)
      (- 0 1)
      (if (= (convert (string-ref s i) %int) %sh-rbrace)
        i
        (self s (+ i 1) n)))))

(def %sh-backslash 92)
(def %sh-squote 39)
(def %sh-dquote 34)

; Inside double quotes a backslash is literal EXCEPT before one of $ ` " \ and
; newline -- so `"a\db"` keeps its backslash and `"a\$b"` does not.  Outside
; quotes a backslash escapes whatever follows it.
(def %sh-dq-escapable?
  (fn (_ c)
    (or (= c %sh-dollar)
        (or (= c 96)                       ; `
            (or (= c %sh-dquote)
                (or (= c %sh-backslash)
                    (= c 10)))))))         ; newline

; QUOTING IS A PROPERTY OF REGIONS WITHIN A WORD, not of the word, and this
; scanner is where that becomes true.  `X="a b"` arrives as ONE word token
; whose raw text still carries its quotes (see %sh-word-body in tokens.x), and
; `pre'lit'$X` is three regions in one word.  So the walk carries a MODE:
;
;   0  unquoted   -- quotes open regions, backslash escapes anything,
;                    $ expands
;   1  '...'      -- everything literal until the closing quote
;   2  "..."      -- $ expands, backslash escapes only the POSIX five
;
; A tok-word starts in mode 0.  A tok-dq starts in mode 2 -- its outer quotes
; were already stripped by the reader, so there is no opening quote left to
; switch on.  A tok-sq never gets here at all.
;
; The quote characters that switch mode are NOT emitted, which is what removes
; them from the final argument.
(def %sh-expand-str
  (fn (_ s mode0)
    (let ((n (string-length s)))
      (def go
        (fn (self i mode acc)
          (if (>= i n)
            acc
            (let ((c (convert (string-ref s i) %int)))
              (match
                ; --- inside single quotes: literal until the closing quote
                ((= mode 1)
                  (if (= c %sh-squote)
                    (self (+ i 1) 0 acc)
                    (self (+ i 1) 1 (string-append acc (substring s i (+ i 1))))))
                ; --- region switches
                ((and (= mode 0) (= c %sh-squote)) (self (+ i 1) 1 acc))
                ((and (= mode 0) (= c %sh-dquote)) (self (+ i 1) 2 acc))
                ((and (= mode 2) (= c %sh-dquote)) (self (+ i 1) 0 acc))
                ; --- backslash: emit what it protects, and resume PAST it, so
                ;     a `$` it protected stays a `$`
                ((and (= c %sh-backslash) (< (+ i 1) n))
                  (let ((d (convert (string-ref s (+ i 1)) %int)))
                    (if (or (= mode 0) (%sh-dq-escapable? d))
                      (self (+ i 2) mode
                        (string-append acc (substring s (+ i 1) (+ i 2))))
                      ; Not escapable in this context: both characters stand.
                      (self (+ i 2) mode
                        (string-append acc (substring s i (+ i 2)))))))
                ; --- expansion
                ((= c %sh-dollar) (%sh-expand-dollar self s i n mode acc))
                (#t
                  (self (+ i 1) mode
                    (string-append acc (substring s i (+ i 1))))))))))
      (go 0 mode0 ""))))

; The `$` arm, lifted out so the walk above stays readable.  CONT is the
; walker's own continuation, called with the index to resume at.
(def %sh-expand-dollar
  (fn (_ cont s i n mode acc)
    ; A `$` at the very end is a literal `$`.
    (if (>= (+ i 1) n)
      (string-append acc "$")
      (let ((d (convert (string-ref s (+ i 1)) %int)))
        (match
          ((= d %sh-lbrace)
            (let ((e (%sh-brace-end s (+ i 2) n)))
              (if (< e 0)
                ; No closing brace: literal, the way a shell that cannot parse
                ; it prints it back.
                (cont (+ i 1) mode (string-append acc "$"))
                (cont (+ e 1) mode
                  (string-append acc (%sh-var-value (substring s (+ i 2) e)))))))
          ((or (= d 63) (= d %sh-dollar))          ; $? and $$
            (cont (+ i 2) mode
              (string-append acc
                (%sh-var-value (substring s (+ i 1) (+ i 2))))))
          ((%sh-name-start? d)
            (let ((e (%sh-name-end s (+ i 1) n)))
              (cont e mode
                (string-append acc
                  (%sh-var-value (substring s (+ i 1) e))))))
          ; $ followed by anything else is a literal $.
          (#t (cont (+ i 1) mode (string-append acc "$"))))))))

; The unquoted default, for the sites that hold a string rather than a token.
(def %sh-expand-word
  (fn (_ word)
    (if (not (string? word)) word (%sh-expand-str word 0))))

; SINGLE QUOTES SUPPRESS EXPANSION, and that fact lives in the TOKEN, not in
; the string -- by the time a word is a string, `'$HOME'` and `$HOME` are the
; same three characters.  The tokenizer already distinguishes them; what was
; missing is a caller that asks.  So every site that turns a word token into a
; value goes through here, and expansion happens ONCE, at extraction, where the
; quoting is still known.
(def %sh-expand-tok
  (fn (_ tok)
    (let ((val (%tok-word-val tok)))
      (if (eq? (first tok) (lit tok-sq))
        val
        (%sh-expand-str val (if (eq? (first tok) (lit tok-dq)) 2 0))))))

(def %sh-expand-words
  (fn (_ wds)
    (if (null? wds)
      ()
      (pair
        (%sh-expand-word (first wds))
        (%sh-expand-words (rest wds))))))
; --- Redirection ---

(def %redir-op?
  (fn (_ tok)
    (if (not (eq? (first tok) (lit tok-op)))
      ()
      (let ((op (first (rest tok))))
        (if (or
              (string=? op "<")
              (string=? op ">")
              (string=? op ">>")
              (string=? op "<<")
              (string=? op "<&")
              (string=? op ">&")
              (string=? op "<>")
              (string=? op ">|")
              (string=? op "<<-"))
          op
          ())))))

(def %all-digits?
  (fn (_ s)
    (def %check ())
    (set! %check
      (fn (_ i len)
        (if (= i len)
          #t
          (let ((c (convert (string-ref s i) %int)))
            (if (and (>= c (convert #\0 %int)) (<= c (convert #\9 %int)))
              (%check (+ i 1) len)
              ())))))
    (if (= (string-length s) 0)
      ()
      (%check 0 (string-length s)))))

(def %default-fd
  (fn (_ op)
    (if (string=? op "<")
      0
      (if (string=? op "<>") 0 (if (string=? op "<&") 0 1)))))

(def %sh-setup-redir
  (fn (_ redir)
    (let ((op (first (rest redir)))
           (fd-val (first (rest (rest redir))))
           ; Expanded at collection, with its quoting in hand.
           (target (first (rest (rest (rest redir))))))
      (let ((fd (if (string? fd-val) (convert fd-val %int) fd-val)))
        (if (string=? op "<")
          (let ((fh (sh-open-read target)))
            (sh-dup2 fh fd)
            (sh-close fh))
          (if (string=? op ">")
            (let ((fh (sh-open-write target)))
              (sh-dup2 fh fd)
              (sh-close fh))
            (if (string=? op ">>")
              (let ((fh (sh-open-append target)))
                (sh-dup2 fh fd)
                (sh-close fh))
              (if (string=? op "<>")
                (let ((fh (sh-open-read target)))
                  (sh-dup2 fh fd)
                  (sh-close fh))
                (if (string=? op ">&")
                  (sh-dup2 (convert target %int) fd)
                  (if (string=? op "<&")
                    (sh-dup2 (convert target %int) fd)
                    ()))))))))))

(def %sh-setup-redirs
  (fn (_ redirs)
    (if (null? redirs)
      ()
      (do
        (%sh-setup-redir (first redirs))
        (%sh-setup-redirs (rest redirs))))))

; A BUILTIN'S REDIRECTIONS WERE DROPPED ON THE FLOOR.  %sh-run-cmd handed
; `redirs` to %sh-run-external and to nothing else, so
;
;   echo hi > out.txt
;
; printed hi to the terminal and created no file -- while `/bin/echo hi >
; out.txt` worked, because the external path sets its redirections up in the
; CHILD, after the fork, where nothing has to be undone.
;
; A builtin runs in the shell itself, so its redirections have to be undone or
; the shell keeps them: one `echo > log` and every later command in the session
; writes to log.  That is the same shape as the pipeline's stdin leak below,
; and it takes the same answer -- save the descriptor, redirect, run, restore.
;
; SAVED ONE FD AT A TIME, at a fixed offset, which is what makes the restore
; exact: fd N is parked at N + %sh-fd-save-base for the duration.  The base is
; high enough to clear the descriptors a script plausibly names itself (and
; x.sh's fd 3, and %sh-stdin-save at 19).
(def %sh-fd-save-base 30)

(def %sh-redir-fd
  (fn (_ redir)
    (let ((fd-val (first (rest (rest redir)))))
      (if (string? fd-val) (convert fd-val %int) fd-val))))

(def %sh-save-fds
  (fn (self redirs)
    (unless (null? redirs)
      (let ((fd (%sh-redir-fd (first redirs))))
        (sh-dup2 fd (+ %sh-fd-save-base fd))
        (self (rest redirs))))))

(def %sh-restore-fds
  (fn (self redirs)
    (unless (null? redirs)
      (let ((fd (%sh-redir-fd (first redirs))))
        (sh-dup2 (+ %sh-fd-save-base fd) fd)
        (sh-close (+ %sh-fd-save-base fd))
        (self (rest redirs))))))
; --- Built-in commands ---

(def %sh-builtin?
  (fn (_ name)
    (or
      (string=? name "echo")
      (or (string=? name "cd")
      (or (string=? name "export")
      (or (string=? name "exit")
      (or (string=? name "true")
      (or (string=? name "false")
      (or (string=? name ":")
      (or (string=? name "test")
      (or (string=? name "[")
      ; --- added: a shell without these is a demo, not a shell -----------
      (or (string=? name "pwd")
      (or (string=? name "unset")
      (or (string=? name "read")
      (or (string=? name ".")
          (string=? name "source"))))))))))))))))

; `-n` suppresses the trailing newline.  Only the FIRST argument is read as
; the flag, and only when it is exactly "-n": `echo -n -n` prints "-n", which
; is what dash does.
(def %sh-echo
  (fn (_ wds)
    (def %print-words ())
    (set! %print-words
      (fn (_ ws first-word)
        (if (null? ws)
          ()
          (do
            (if first-word () (display " "))
            (display (first ws))
            (%print-words (rest ws) ())))))
    (let ((suppress (if (null? wds) () (string=? (first wds) "-n"))))
      (%print-words (if suppress (rest wds) wds) #t)
      (if suppress () (newline))
      0)))

(def %sh-cd
  (fn (_ wds)
    (let ((dir
            (if (null? wds)
              (let ((home (sh-getenv "HOME")))
                (if (null? home) "/" home))
              (first wds))))
      (let ((result (sh-chdir dir)))
        (if (= result -1)
          (do
            (display "ash: cd: ")
            (display dir)
            (display ": No such file or directory")
            (newline)
            1)
          0)))))

(def %sh-export
  (fn (_ wds)
    (if (null? wds)
      0
      (let ((word (first wds)))
        (def %find-eq ())
        (set! %find-eq
          (fn (_ i)
            (if (= i (string-length word))
              -1
              (if (= (convert (string-ref word i) %int) (convert #\= %int))
                i
                (%find-eq (+ i 1))))))
        (let ((eq-pos (%find-eq 0)))
          (if (= eq-pos -1)
            0
            (do
              (sh-setenv
                (substring word 0 eq-pos)
                (substring word (+ eq-pos 1) (string-length word)))
              0)))))))

; --- test / [ -------------------------------------------------------------
;
; The 2024 version knew -n, -z, = and != and answered 1 (false) to everything
; else, which meant `test -f config` and `test "$n" -gt 3` were not wrong so
; much as silently always-false -- the worst answer a conditional can give.

; FLAT, VIA match, NOT A NESTED if-CHAIN.  The first version of these two was
; a six-deep if ladder and it came out one closing paren short -- which does
; not fail loudly: the parenthesis deficit swallowed every def that followed,
; so %sh-run-builtin and the rest bound INSIDE this function's body instead of
; at the top level, and the shell died with "Unbound SYMBOL '%sh-run-builtin'"
; at the first command.  A flat match cannot make that mistake.
(def %sh-test-file
  (fn (_ op path)
    (let ((kind (sh-path-kind path)))
      (match
        ((string=? op "-e") (if (null? kind) 1 0))
        ((string=? op "-f") (if (eq? kind (lit file)) 0 1))
        ((string=? op "-d") (if (eq? kind (lit dir)) 0 1))
        ((string=? op "-s")
          (if (null? kind) 1 (if (> (sh-path-size path) 0) 0 1)))
        ; nil, not 1: "this is not a file operator", which the caller has to
        ; be able to tell apart from "the test was false".
        (#t ())))))

(def %sh-test-num
  (fn (_ l op r)
    (let ((a (convert l %int)) (b (convert r %int)))
      (match
        ((string=? op "-eq") (if (= a b) 0 1))
        ((string=? op "-ne") (if (= a b) 1 0))
        ((string=? op "-lt") (if (< a b) 0 1))
        ((string=? op "-le") (if (<= a b) 0 1))
        ((string=? op "-gt") (if (> a b) 0 1))
        ((string=? op "-ge") (if (>= a b) 0 1))
        (#t ())))))

(def %sh-test ())
(set! %sh-test
  (fn (_ wds)
    (if (null? wds)
      1
      (if (= (length wds) 1)
        (if (= (string-length (first wds)) 0) 1 0)
        (if (= (length wds) 2)
          (let ((op (first wds)) (val (first (rest wds))))
            (if (string=? op "-n")
              (if (= (string-length val) 0) 1 0)
              (if (string=? op "-z")
                (if (= (string-length val) 0) 0 1)
                (if (string=? op "!")
                  (if (= (%sh-test (rest wds)) 0) 1 0)
                  (let ((r (%sh-test-file op val)))
                    ; An unknown unary operator is a usage error (2), not a
                    ; false -- `test -q x` should complain, not quietly fail.
                    (if (null? r)
                      (do (%stderr "ash: test: " op ": unary operator expected\n") 2)
                      r))))))
          (if (= (length wds) 3)
            (let ((left (first wds))
                   (op (first (rest wds)))
                   (right (first (rest (rest wds)))))
              (if (string=? op "=")
                (if (string=? left right) 0 1)
                (if (string=? op "!=")
                  (if (string=? left right) 1 0)
                  (let ((r (%sh-test-num left op right)))
                    (if (null? r)
                      (do (%stderr "ash: test: " op ": binary operator expected\n") 2)
                      r)))))
            ; `! EXPR` at any length, so `test ! -f x` works.
            (if (string=? (first wds) "!")
              (if (= (%sh-test (rest wds)) 0) 1 0)
              1)))))))

; --- pwd / unset / read / . -----------------------------------------------

(def %sh-pwd
  (fn (_ wds)
    (let ((d (sh-getcwd)))
      (if (null? d) 1 (do (display d) (newline) 0)))))

(def %sh-unset
  (fn (_ wds)
    (if (null? wds)
      0
      (do (sh-unsetenv (first wds)) (%sh-unset (rest wds))))))

; `read VAR...` -- one line from stdin, split on whitespace across the names,
; with the LAST name taking everything that is left (POSIX).  A bare `read`
; with no names still consumes the line, and EOF answers 1, which is what
; `while read line` needs to terminate.
(def %sh-read-split
  (fn (self s i n)
    ; index of the first non-space at or after i
    (if (>= i n)
      i
      (let ((c (convert (string-ref s i) %int)))
        (if (or (= c 32) (= c 9)) (self s (+ i 1) n) i)))))

(def %sh-read-word-end
  (fn (self s i n)
    (if (>= i n)
      i
      (let ((c (convert (string-ref s i) %int)))
        (if (or (= c 32) (= c 9)) i (self s (+ i 1) n))))))

(def %sh-read-assign
  (fn (self names line i n)
    (if (null? names)
      0
      (let ((start (%sh-read-split line i n)))
        (if (null? (rest names))
          ; Last name: the rest of the line, verbatim.
          (do (sh-setenv (first names) (substring line start n)) 0)
          (let ((e (%sh-read-word-end line start n)))
            (sh-setenv (first names) (substring line start e))
            (self (rest names) line e n)))))))

; Reads fd 0 DIRECTLY, not the engine's reader -- see sh-read-line-fd in
; ash/prims.x for why the two are not interchangeable.
(def %sh-read
  (fn (_ wds)
    (let ((line (sh-read-line-fd 0)))
      (if (null? line)
        1
        (if (null? wds)
          0
          (%sh-read-assign wds line 0 (string-length line)))))))

; `.` / `source` FILE -- read the file and run it in THIS shell, so its
; assignments and cd survive.  The status is the last command's.
(def %sh-source
  (fn (_ wds)
    (if (null? wds)
      (do (%stderr "ash: .: filename argument required\n") 2)
      (let ((path (first wds)))
        (guard (e (do (%stderr "ash: .: " path ": cannot read\n") 1))
          (sh-eval (sh-read-file path))
          %sh-status)))))

; FLAT, VIA match.  This was a fourteen-deep nested-if dispatch, and adding
; four builtins to the bottom of it is how the file acquired a stray closing
; paren -- the counterpart to the missing one in %sh-test-num above, and
; between them the two hid each other in the whole-file total.  A match arm
; per builtin is one line each and cannot be miscounted.
(def %sh-run-builtin
  (fn (_ name wds)
    (match
      ((string=? name "echo")   (%sh-echo wds))
      ((string=? name "cd")     (%sh-cd wds))
      ((string=? name "export") (%sh-export wds))
      ((string=? name "exit")
        (sh-exit (if (null? wds) %sh-status (convert (first wds) %int))))
      ((string=? name "true")   0)
      ((string=? name "false")  1)
      ((string=? name ":")      0)
      ((string=? name "test")   (%sh-test wds))
      ((string=? name "[")
        ; `[ ... ]` -- drop the closing bracket before testing.
        (%sh-test
          (if (null? wds)
            wds
            (if (string=? (last wds) "]")
              (take (- (length wds) 1) wds)
              wds))))
      ((string=? name "pwd")    (%sh-pwd wds))
      ((string=? name "unset")  (%sh-unset wds))
      ((string=? name "read")   (%sh-read wds))
      ((or (string=? name ".") (string=? name "source")) (%sh-source wds))
      (#t 1))))

; A builtin under redirection: park the descriptors, run, put them back.  The
; guard is not decoration -- a builtin that raises with fd 1 still pointing at
; a file would leave the SHELL writing there, and the prompt would vanish into
; out.txt.  Restore, then re-raise, the way lib/x/sys/stream.x does it.
(def %sh-run-builtin-redir
  (fn (_ name wds redirs)
    (if (null? redirs)
      (%sh-run-builtin name wds)
      (do
        (%sh-save-fds redirs)
        (guard (e (do (%sh-restore-fds redirs) (error e)))
          (%sh-setup-redirs redirs)
          (let ((status (%sh-run-builtin name wds)))
            (%sh-restore-fds redirs)
            status))))))

; --- External command execution ---

(def %sh-run-external
  (fn (_ name wds redirs)
    (let ((pid (sh-fork)))
      (if (= pid 0)
        (do
          (%sh-setup-redirs redirs)
          (sh-exec name wds)
          (display "ash: ")
          (display name)
          (display ": command not found")
          (newline)
          (sh-exit 127))
        (sh-wait pid)))))
; --- Assignment handling ---

(def %is-assignment?
  (fn (_ word)
    (def %has-eq ())
    (set! %has-eq
      (fn (_ i)
        (if (= i (string-length word))
          ()
          (if (= (convert (string-ref word i) %int) (convert #\= %int))
            (if (= i 0) () #t)
            (%has-eq (+ i 1))))))
    (if (= (string-length word) 0) () (%has-eq 0))))

(def %process-assignments
  (fn (_ wds)
    (if (null? wds)
      ()
      (if (%is-assignment? (first wds))
        (do
          (%sh-export (list (first wds)))
          (%process-assignments (rest wds)))
        wds))))
; --- Execute collected command ---

(def %sh-run-cmd
  (fn (_ wds redirs)
    ; ALREADY EXPANDED, at extraction (%collect-cmd-tokens).  Re-expanding
    ; here would expand a variable's VALUE -- `X='$Y'; echo $X` would print
    ; $Y's contents rather than the two characters it holds.
    (let ((expanded wds))
      (let ((remaining (%process-assignments expanded)))
        (if (null? remaining)
          (do (set! %sh-status 0) 0)
          (let ((name (first remaining)) (cmd-wds (rest remaining)))
            (if (%sh-builtin? name)
              (let ((status (%sh-run-builtin-redir name cmd-wds redirs)))
                (set! %sh-status status)
                status)
              (let ((status (%sh-run-external name cmd-wds redirs)))
                (set! %sh-status status)
                status))))))))
; Save C pipe primitive before we shadow it

(def %sh-pipe-create sh-pipe)
; --- Forward declarations ---

(def %eval-list ())

(def %eval-command ())

(def %sh-pipe-chain ())

(def %skip-to-fi ())

(def %skip-body-to-elif-else-fi ())

(def %eval-elif-chain ())

(def %skip-to-done ())

(def %eval-while-body ())

(def %eval-until-body ())

(def %eval-for-body ())

(def %eval-case-clauses ())
; --- Compound command detection ---

(def %is-compound-start?
  (fn (_ cur)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (eq? (first tok) (lit tok-word))
          (let ((w (first (rest tok))))
            (or
              (string=? w "if")
              (string=? w "while")
              (string=? w "until")
              (string=? w "for")
              (string=? w "case")))
          (if (eq? (first tok) (lit tok-op))
            (string=? (first (rest tok)) "(")
            ()))))))
; --- Simple command: collect words/redirects and execute ---

(def %collect-cmd-tokens ())

(set! %collect-cmd-tokens
  (fn (_ cur wds redirs)
    (if (%cursor-empty? cur)
      (%sh-run-cmd (reverse wds) (reverse redirs))
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-newline? tok)
          (%sh-run-cmd (reverse wds) (reverse redirs))
          (let ((rop (%redir-op? tok)))
            (if rop
              (do
                (%cursor-advance! cur)
                (let ((fd
                        (if (and (not (null? wds)) (%all-digits? (first wds)))
                          (let ((n (first wds))) (set! wds (rest wds)) n)
                          (%default-fd rop))))
                  (if (%cursor-empty? cur)
                    (error "parse error: redirect without target")
                    (let ((target (%sh-expand-tok (%cursor-peek cur))))
                      (%cursor-advance! cur)
                      (%collect-cmd-tokens
                        cur
                        wds
                        (pair (list (lit sh-redir) rop fd target) redirs))))))
              (if (%tok-is-word? tok)
                (let ((val (%tok-word-val tok)))
                  (if (and
                        (not (null? wds))
                        (eq? (first tok) (lit tok-word))
                        (%reserved-word? val))
                    (%sh-run-cmd (reverse wds) (reverse redirs))
                    (do
                      (%cursor-advance! cur)
                      ; EXPANDED HERE, not in %sh-run-cmd, because this is the
                      ; last place the token's QUOTING is still known.  `val`
                      ; above stays raw: POSIX recognises reserved words before
                      ; expansion, so a variable holding "then" must not become
                      ; one.
                      (%collect-cmd-tokens
                        cur (pair (%sh-expand-tok tok) wds) redirs))))
                (%sh-run-cmd (reverse wds) (reverse redirs))))))))))

(def %eval-simple-cmd
  (fn (_ cur) (%collect-cmd-tokens cur () ())))
; --- Compound commands: parse structure, evaluate directly ---
; if cond; then body [elif cond; then body]... [else body] fi

(def %eval-if
  (fn (_ cur)
    (%cursor-advance! cur)
    ; consume 'if'

    (%skip-newlines cur)
    (let ((cond-result (%eval-list cur)))
      (%skip-newlines cur)
      (%expect-word cur "then")
      (%skip-newlines cur)
      (if (= cond-result 0)
        ; True: eval body, skip remaining

        (let ((result (%eval-list cur)))
          (%skip-to-fi cur 0)
          (set! %sh-status result)
          result)
        ; False: skip body, try elif/else

        (do
          (%skip-body-to-elif-else-fi cur 0)
          (%eval-elif-chain cur))))))
; Skip balanced tokens to elif/else/fi at depth 0

(set! %skip-body-to-elif-else-fi
  (fn (_ cur depth)
    (if (%cursor-empty? cur)
      (error "parse error: unexpected EOF in if")
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-keyword? tok)
          (let ((w (%tok-word-val tok)))
            (if (or
                  (string=? w "if")
                  (string=? w "while")
                  (string=? w "until")
                  (string=? w "for")
                  (string=? w "case"))
              (do
                (%cursor-advance! cur)
                (%skip-body-to-elif-else-fi cur (+ depth 1)))
              (if (or
                    (string=? w "fi")
                    (string=? w "done")
                    (string=? w "esac"))
                (if (= depth 0)
                  ; fi at our level: consume and stop

                  (do (%cursor-advance! cur) ())
                  (do
                    (%cursor-advance! cur)
                    (%skip-body-to-elif-else-fi cur (- depth 1))))
                (if (and
                      (= depth 0)
                      (or (string=? w "elif") (string=? w "else")))
                  ; Stop here (don't consume) for elif/else handling

                  ()
                  (do
                    (%cursor-advance! cur)
                    (%skip-body-to-elif-else-fi cur depth))))))
          (do
            (%cursor-advance! cur)
            (%skip-body-to-elif-else-fi cur depth)))))))
; Skip to matching fi (after we evaluated the true branch)

(set! %skip-to-fi
  (fn (_ cur depth)
    (if (%cursor-empty? cur)
      (error "parse error: unexpected EOF in if")
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-keyword? tok)
          (let ((w (%tok-word-val tok)))
            (%cursor-advance! cur)
            (if (or
                  (string=? w "if")
                  (string=? w "while")
                  (string=? w "for"))
              (%skip-to-fi cur (+ depth 1))
              (if (string=? w "fi")
                (if (= depth 0) () (%skip-to-fi cur (- depth 1)))
                (if (string=? w "done")
                  (%skip-to-fi cur (- depth 1))
                  (%skip-to-fi cur depth)))))
          (do (%cursor-advance! cur) (%skip-to-fi cur depth)))))))
; Handle elif/else chain after condition was false

(set! %eval-elif-chain
  (fn (_ cur)
    (if (%cursor-empty? cur)
      (error "parse error: expected fi")
      (let ((tok (%cursor-peek cur)))
        (if (and
              (%tok-is-keyword? tok)
              (string=? (%tok-word-val tok) "elif"))
          ; elif: evaluate its condition

          (do
            (%cursor-advance! cur)
            (%skip-newlines cur)
            (let ((cond-result (%eval-list cur)))
              (%skip-newlines cur)
              (%expect-word cur "then")
              (%skip-newlines cur)
              (if (= cond-result 0)
                (let ((result (%eval-list cur)))
                  (%skip-to-fi cur 0)
                  (set! %sh-status result)
                  result)
                (do
                  (%skip-body-to-elif-else-fi cur 0)
                  (%eval-elif-chain cur)))))
          (if (and
                (%tok-is-keyword? tok)
                (string=? (%tok-word-val tok) "else"))
            ; else: evaluate body, expect fi

            (do
              (%cursor-advance! cur)
              (%skip-newlines cur)
              (let ((result (%eval-list cur)))
                (%skip-newlines cur)
                (%expect-word cur "fi")
                (set! %sh-status result)
                result))
            (if (and
                  (%tok-is-keyword? tok)
                  (string=? (%tok-word-val tok) "fi"))
              ; fi: no else, return 0

              (do (%cursor-advance! cur) (set! %sh-status 0) 0)
              (error "parse error: expected elif, else, or fi"))))))))
; while cond; do body; done

(def %eval-while
  (fn (_ cur)
    (%cursor-advance! cur)
    ; consume 'while'

    ; Save position to loop back

    (let ((saved (first cur))) (%eval-while-body cur saved))))

(set! %eval-while-body
  (fn (_ cur saved)
    (set-first! cur saved)
    ; reset cursor to condition

    (%skip-newlines cur)
    (let ((cond-result (%eval-list cur)))
      (%skip-newlines cur)
      (%expect-word cur "do")
      (%skip-newlines cur)
      (if (= cond-result 0)
        (let ((result (%eval-list cur)))
          (%skip-newlines cur)
          (%expect-word cur "done")
          (let ((new-saved saved)) (%eval-while-body cur new-saved)))
        ; Condition false: skip body, done

        (do (%skip-to-done cur 0) (set! %sh-status 0) 0)))))
; until cond; do body; done (loops while condition fails)

(def %eval-until
  (fn (_ cur)
    (%cursor-advance! cur)
    ; consume 'until'

    (let ((saved (first cur))) (%eval-until-body cur saved))))

(set! %eval-until-body
  (fn (_ cur saved)
    (set-first! cur saved)
    ; reset cursor to condition

    (%skip-newlines cur)
    (let ((cond-result (%eval-list cur)))
      (%skip-newlines cur)
      (%expect-word cur "do")
      (%skip-newlines cur)
      (if (not (= cond-result 0))
        (let ((result (%eval-list cur)))
          (%skip-newlines cur)
          (%expect-word cur "done")
          (let ((new-saved saved)) (%eval-until-body cur new-saved)))
        ; Condition succeeded: skip body, done

        (do (%skip-to-done cur 0) (set! %sh-status 0) 0)))))
; Skip to matching done

(set! %skip-to-done
  (fn (_ cur depth)
    (if (%cursor-empty? cur)
      (error "parse error: unexpected EOF in while")
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-keyword? tok)
          (let ((w (%tok-word-val tok)))
            (%cursor-advance! cur)
            (if (or
                  (string=? w "while")
                  (string=? w "until")
                  (string=? w "for")
                  (string=? w "if")
                  (string=? w "case"))
              (%skip-to-done cur (+ depth 1))
              (if (or
                    (string=? w "done")
                    (string=? w "fi")
                    (string=? w "esac"))
                (if (= depth 0) () (%skip-to-done cur (- depth 1)))
                (%skip-to-done cur depth))))
          (do (%cursor-advance! cur) (%skip-to-done cur depth)))))))
; Collect for-in word list from cursor

(def %collect-for-words ())

(set! %collect-for-words
  (fn (_ cur ws)
    (if (or
          (%cursor-empty? cur)
          (%tok-is-newline? (%cursor-peek cur))
          (and
            (eq? (first (%cursor-peek cur)) (lit tok-op))
            (string=? (first (rest (%cursor-peek cur))) ";")))
      (reverse ws)
      (let ((w (%sh-expand-tok (%cursor-peek cur))))
        (%cursor-advance! cur)
        (%collect-for-words cur (pair w ws))))))
; for var [in words...]; do body; done

(def %eval-for
  (fn (_ cur)
    (%cursor-advance! cur)
    ; consume 'for'

    (%skip-newlines cur)
    (if (%cursor-empty? cur)
      (error "parse error: for without variable")
      (let ((var (%tok-word-val (%cursor-peek cur))))
        (%cursor-advance! cur)
        (%skip-newlines cur)
        ; Collect in-list if present

        (let ((words
                (if (and
                      (not (%cursor-empty? cur))
                      (eq? (first (%cursor-peek cur)) (lit tok-word))
                      (string=? (first (rest (%cursor-peek cur))) "in"))
                  (do
                    (%cursor-advance! cur)
                    ; consume 'in'

                    (%collect-for-words cur ()))
                  ())))
          ; Skip separator

          (%skip-newlines cur)
          (if (not (%cursor-empty? cur))
            (if (%match-op cur ";") (%skip-newlines cur) ())
            ())
          (%expect-word cur "do")
          (%skip-newlines cur)
          ; Save position for looping

          (let ((body-start (first cur))
                 (expanded words))
            (%eval-for-body cur var expanded body-start)))))))

(set! %eval-for-body
  (fn (_ cur var words body-start)
    (if (null? words)
      (do (set! %sh-status 0) 0)
      (do
        (sh-setenv var (first words))
        (set-first! cur body-start)
        ; reset to body

        (let ((result (%eval-list cur)))
          (%skip-newlines cur)
          (%expect-word cur "done")
          (if (null? (rest words))
            (do (set! %sh-status 0) 0)
            (%eval-for-body cur var (rest words) body-start)))))))
; case WORD in PATTERN[|PATTERN]...) BODY;; ... esac

; CASE PATTERNS ARE GLOBS, and this used to be `pat = "*"` or string equality
; -- so `case $f in a*)` never matched anything, and `*.txt)` never matched
; anything, and a `case` whose arms all miss falls through silently.  The two
; commonest shapes a case statement is written in were both dead.
;
; This is PATTERN MATCHING, not pathname expansion: it answers "does this word
; look like that", which is what `case` needs and what `test`-style code
; reaches for.  Filename globbing (expanding `*.txt` against a directory) is a
; separate feature and is still absent -- see the README.
;
; Supported: `*` (any run, including empty), `?` (one character), `[abc]`,
; `[a-z]`, `[!abc]` / `[^abc]` negation, and `\` escaping any of them.  An
; unterminated `[` is a literal `[`, which is what POSIX says.

; The character-class helpers, taking the class body as the half-open range
; [lo, hi) -- lo just after the `[`, hi at the `]`.
(def %sh-glob-class-scan
  (fn (self pat i hi c)
    (if (>= i hi)
      ()
      ; A range `a-b` needs its closing character inside the class.
      (if (and (< (+ i 2) hi)
               (= (convert (string-ref pat (+ i 1)) %int) 45))       ; -
        (if (and (>= c (convert (string-ref pat i) %int))
                 (<= c (convert (string-ref pat (+ i 2)) %int)))
          #t
          (self pat (+ i 3) hi c))
        (if (= c (convert (string-ref pat i) %int))
          #t
          (self pat (+ i 1) hi c))))))

(def %sh-glob-class-match?
  (fn (_ pat lo hi s si)
    (let ((c (convert (string-ref s si) %int)))
      (let ((neg (if (< lo hi)
                   (let ((f (convert (string-ref pat lo) %int)))
                     (or (= f 33) (= f 94)))                          ; ! ^
                   ())))
        (let ((hit (%sh-glob-class-scan pat (if neg (+ lo 1) lo) hi c)))
          (if neg (if hit () #t) (if hit #t ())))))))

; The index of the `]` closing a class opened at I, or -1.  A `!`/`^` and then
; a `]` immediately after the opening bracket are both literal.
(def %sh-glob-class-end
  (fn (_ pat i pn)
    (def scan
      (fn (self j)
        (if (>= j pn)
          (- 0 1)
          (if (= (convert (string-ref pat j) %int) 93) j (self (+ j 1))))))
    (let ((a (if (and (< i pn)
                      (let ((c (convert (string-ref pat i) %int)))
                        (or (= c 33) (= c 94))))
               (+ i 1) i)))
      (scan (if (and (< a pn) (= (convert (string-ref pat a) %int) 93))
              (+ a 1) a)))))

(def %sh-glob-at ())
(def %sh-glob-star ())

; `*` -- try the rest of the pattern at every position from here to the end.
(set! %sh-glob-star
  (fn (self pat pi pn s si sn)
    (if (%sh-glob-at pat pi pn s si sn)
      #t
      (if (>= si sn) () (self pat pi pn s (+ si 1) sn)))))

(set! %sh-glob-at
  (fn (self pat pi pn s si sn)
    (if (>= pi pn)
      ; Pattern exhausted: a match only if the word is exhausted too.
      (if (>= si sn) #t ())
      (let ((pc (convert (string-ref pat pi) %int)))
        (match
          ((= pc 42) (%sh-glob-star pat (+ pi 1) pn s si sn))         ; *
          ((= pc 63)                                                  ; ?
            (if (>= si sn) () (self pat (+ pi 1) pn s (+ si 1) sn)))
          ((= pc 91)                                                  ; [
            (let ((e (%sh-glob-class-end pat (+ pi 1) pn)))
              (if (< e 0)
                ; Unterminated: a literal [
                (if (and (< si sn) (= (convert (string-ref s si) %int) 91))
                  (self pat (+ pi 1) pn s (+ si 1) sn)
                  ())
                (if (and (< si sn) (%sh-glob-class-match? pat (+ pi 1) e s si))
                  (self pat (+ e 1) pn s (+ si 1) sn)
                  ()))))
          ((and (= pc 92) (< (+ pi 1) pn))                            ; backslash
            (if (and (< si sn)
                     (= (convert (string-ref pat (+ pi 1)) %int)
                        (convert (string-ref s si) %int)))
              (self pat (+ pi 2) pn s (+ si 1) sn)
              ()))
          (#t
            (if (and (< si sn) (= pc (convert (string-ref s si) %int)))
              (self pat (+ pi 1) pn s (+ si 1) sn)
              ())))))))

(def %sh-pattern-match?
  (fn (_ pat word)
    (%sh-glob-at pat 0 (string-length pat) word 0 (string-length word))))

(def %collect-case-patterns ())

(set! %collect-case-patterns
  (fn (_ cur pats)
    (if (%cursor-empty? cur)
      (error "parse error: expected ) in case")
      (let ((tok (%cursor-peek cur)))
        (if (and
              (eq? (first tok) (lit tok-op))
              (string=? (first (rest tok)) ")"))
          (do (%cursor-advance! cur) (reverse pats))
          (if (and
                (eq? (first tok) (lit tok-op))
                (string=? (first (rest tok)) "|"))
            (do
              (%cursor-advance! cur)
              (%collect-case-patterns cur pats))
            (do
              (%cursor-advance! cur)
              (%collect-case-patterns
                cur
                (pair (%tok-word-val tok) pats)))))))))

(def %case-match?
  (fn (_ pats word)
    (if (null? pats)
      ()
      (if (%sh-pattern-match? (first pats) word)
        #t
        (%case-match? (rest pats) word)))))

(def %skip-case-body ())

(set! %skip-case-body
  (fn (_ cur depth)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (eq? (first tok) (lit tok-word))
          (let ((w (%tok-word-val tok)))
            (%cursor-advance! cur)
            (if (and (= depth 0) (string=? w "esac"))
              ()
              (if (or
                    (string=? w "if")
                    (string=? w "while")
                    (string=? w "until")
                    (string=? w "for")
                    (string=? w "case"))
                (%skip-case-body cur (+ depth 1))
                (if (or
                      (string=? w "fi")
                      (string=? w "done")
                      (string=? w "esac"))
                  (%skip-case-body cur (- depth 1))
                  (%skip-case-body cur depth)))))
          (if (eq? (first tok) (lit tok-op))
            (do
              (%cursor-advance! cur)
              (if (and (= depth 0) (string=? (first (rest tok)) ";;"))
                ()
                (%skip-case-body cur depth)))
            (do (%cursor-advance! cur) (%skip-case-body cur depth))))))))

(def %skip-to-esac ())

(set! %skip-to-esac
  (fn (_ cur depth)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (eq? (first tok) (lit tok-word))
          (let ((w (%tok-word-val tok)))
            (%cursor-advance! cur)
            (if (or
                  (string=? w "if")
                  (string=? w "while")
                  (string=? w "until")
                  (string=? w "for")
                  (string=? w "case"))
              (%skip-to-esac cur (+ depth 1))
              (if (or
                    (string=? w "fi")
                    (string=? w "done")
                    (string=? w "esac"))
                (if (= depth 0) () (%skip-to-esac cur (- depth 1)))
                (%skip-to-esac cur depth))))
          (do (%cursor-advance! cur) (%skip-to-esac cur depth)))))))

(set! %eval-case-clauses
  (fn (_ cur word)
    (%skip-newlines cur)
    (if (%cursor-empty? cur)
      (do (set! %sh-status 0) 0)
      (let ((tok (%cursor-peek cur)))
        (if (and
              (eq? (first tok) (lit tok-word))
              (string=? (first (rest tok)) "esac"))
          (do (%cursor-advance! cur) (set! %sh-status 0) 0)
          (let ((pats (%collect-case-patterns cur ())))
            (%skip-newlines cur)
            (if (%case-match? pats word)
              ; Match: evaluate body, skip remaining

              (let ((result (%eval-list cur)))
                ; Consume ;; if present

                (if (and
                      (not (%cursor-empty? cur))
                      (not (eq? (first (%cursor-peek cur)) (lit tok-word))))
                  (if (and
                        (eq? (first (%cursor-peek cur)) (lit tok-op))
                        (string=? (first (rest (%cursor-peek cur))) ";;"))
                    (%cursor-advance! cur)
                    ())
                  ())
                (%skip-to-esac cur 0)
                (set! %sh-status result)
                result)
              ; No match: skip body, try next clause

              (do (%skip-case-body cur 0) (%eval-case-clauses cur word)))))))))

(def %eval-case
  (fn (_ cur)
    (%cursor-advance! cur)
    ; consume 'case'

    (let ((word-tok (%cursor-peek cur)))
      (%cursor-advance! cur)
      ; consume WORD

      (let ((word (%sh-expand-tok word-tok)))
        (%skip-newlines cur)
        (%expect-word cur "in")
        (%skip-newlines cur)
        (%eval-case-clauses cur word)))))
; ( list ) — subshell

; THE CHILD USED TO RUN THE REST OF THE SCRIPT.  It forked and called
; %eval-list on the SHARED cursor, and %eval-list does not stop at `)` -- so
; the subshell evaluated its body and then kept going, through every command
; after it, before exiting.  In batch mode, where the whole file is one token
; stream, that means everything following a `( ... )` happened twice:
;
;   ( echo hi )        ->  hi
;   echo after             after
;                          after      <- the child, still going
;
; Invisible for a subshell at the end of a script, and doubled side effects
; anywhere else.
;
; So the body is COLLECTED FIRST, in the one process, and the child evaluates
; a cursor over just those tokens.  The parent is then already positioned past
; the closing paren and needs no separate skip.
(def %collect-subshell-tokens
  (fn (self cur depth toks)
    (if (%cursor-empty? cur)
      (error "parse error: expected )")
      (let ((tok (%cursor-peek cur)))
        (%cursor-advance! cur)
        (if (eq? (first tok) (lit tok-op))
          (let ((op (first (rest tok))))
            (if (string=? op "(")
              (self cur (+ depth 1) (pair tok toks))
              (if (string=? op ")")
                (if (= depth 0)
                  (reverse toks)
                  (self cur (- depth 1) (pair tok toks)))
                (self cur depth (pair tok toks)))))
          (self cur depth (pair tok toks)))))))

(def %eval-subshell
  (fn (_ cur)
    (%cursor-advance! cur)
    ; consume '('

    (%skip-newlines cur)
    (let ((body (%collect-subshell-tokens cur 0 ())))
      (let ((pid (sh-fork)))
        (if (= pid 0)
          (do
            (unless (null? body) (%eval-list (%mk-cursor body)))
            (sh-exit %sh-status))
          (let ((status (sh-wait pid)))
            (set! %sh-status status)
            status))))))

(def %skip-to-close-paren
  (fn (_ cur depth)
    (if (%cursor-empty? cur)
      (error "parse error: expected )")
      (let ((tok (%cursor-peek cur)))
        (%cursor-advance! cur)
        (if (eq? (first tok) (lit tok-op))
          (let ((op (first (rest tok))))
            (if (string=? op "(")
              (%skip-to-close-paren cur (+ depth 1))
              (if (string=? op ")")
                (if (= depth 0) () (%skip-to-close-paren cur (- depth 1)))
                (%skip-to-close-paren cur depth))))
          (%skip-to-close-paren cur depth))))))
; --- Compound command dispatch ---

(def %eval-compound
  (fn (_ cur)
    (let ((tok (%cursor-peek cur)))
      (if (eq? (first tok) (lit tok-op))
        (%eval-subshell cur)
        (let ((word (first (rest tok))))
          (if (string=? word "if")
            (%eval-if cur)
            (if (string=? word "while")
              (%eval-while cur)
              (if (string=? word "until")
                (%eval-until cur)
                (if (string=? word "for")
                  (%eval-for cur)
                  (if (string=? word "case")
                    (%eval-case cur)
                    (error (string-append "parse error: unexpected " word))))))))))))
; --- Pipeline execution ---

(set! %sh-pipe-chain
  (fn (_ cmds)
    (if (null? (rest cmds))
      ; Last command: evaluate directly

      (let ((cur (%mk-cursor (first cmds)))) (%eval-command cur))
      ; Pipe: fork left, chain right

      (let ((p (%sh-pipe-create))
             (left-tokens (first cmds))
             (rest-cmds (rest cmds)))
        (let ((read-fd (first p)) (write-fd (rest p)) (pid (sh-fork)))
          (if (= pid 0)
            ; Child: stdout → pipe, eval left

            (do
              (sh-close read-fd)
              (sh-dup2 write-fd 1)
              (sh-close write-fd)
              (let ((cur (%mk-cursor left-tokens))) (%eval-command cur))
              (sh-exit %sh-status))
            ; Parent: stdin ← pipe, continue chain

            (do
              (sh-close write-fd)
              (sh-dup2 read-fd 0)
              (sh-close read-fd)
              (let ((result (%sh-pipe-chain rest-cmds)))
                (sh-wait pid)
                result))))))))
; THE PARENT'S STDIN IS THE SHELL'S STDIN, and %sh-pipe-chain moves it.
;
; The chain runs its LAST stage in the shell process, so the parent dup2s each
; pipe's read end onto fd 0 and leaves it there.  Nothing restores it.  In a
; one-shot process -- which is every one of the 82 specs, each calling sh-eval
; once and exiting -- that is invisible.  In a SESSION it ends the session: run
; `echo hello | grep h` at the prompt and the shell's stdin is now an exhausted
; pipe, so the next read is EOF and ash exits without a word.  The bug was
; latent for exactly as long as there was no session to expose it.
;
; `exec 9<&0` is how a shell says this, and dup2 onto a high spare fd is what
; that compiles to.  19 rather than 9: a script may legitimately redirect 9
; (`exec 9>log`), and x.sh has already claimed 3 for the terminal stdin it
; parks while the boot stream owns 0.
;
; RESTORED ON THE ERROR PATH TOO, via the guard/re-raise shape lib/x/sys/
; stream.x uses for the output fd.  A pipeline that raises mid-chain would
; otherwise leave the prompt reading the pipe -- the same dead session,
; reached by the path that is harder to notice.
(def %sh-stdin-save 19)

(def %sh-run-pipeline
  (fn (_ stages)
    (sh-dup2 0 %sh-stdin-save)
    (guard (e
        (do (sh-dup2 %sh-stdin-save 0) (sh-close %sh-stdin-save) (error e)))
      (let ((result (%sh-pipe-chain stages)))
        (sh-dup2 %sh-stdin-save 0)
        (sh-close %sh-stdin-save)
        result))))

; --- Recursive descent evaluator ---
; command: compound or simple

(set! %eval-command
  (fn (_ cur)
    (if (%is-compound-start? cur)
      (%eval-compound cur)
      (%eval-simple-cmd cur))))
; --- Pipeline stage collection ---
; Collect tokens for one stage (until | or end of command)

(def %collect-stage ())

(set! %collect-stage
  (fn (_ cur toks)
    (if (%cursor-empty? cur)
      (reverse toks)
      (let ((tok (%cursor-peek cur)))
        (if (or
              (%tok-is-newline? tok)
              (%tok-is-op? tok "|")
              (%tok-is-op? tok ";")
              (%tok-is-op? tok "&")
              (%tok-is-op? tok "&&")
              (%tok-is-op? tok "||"))
          (reverse toks)
          (if (and (%tok-is-word? tok) (%at-stop-word? cur))
            (reverse toks)
            (do
              (%cursor-advance! cur)
              (%collect-stage cur (pair tok toks)))))))))
; Collect all pipeline stages

(def %collect-stages ())

(set! %collect-stages
  (fn (_ cur stages)
    (let ((stage (%collect-stage cur ())))
      (if (%match-op cur "|")
        (do
          (%skip-newlines cur)
          (%collect-stages cur (pair stage stages)))
        (reverse (pair stage stages))))))
; pipeline: ['!'] command ('|' command)*

(def %eval-pipeline
  (fn (_ cur)
    (%skip-newlines cur)
    ; Check for ! negation

    (let ((negate
            (if (and
                  (not (%cursor-empty? cur))
                  (%tok-is-word? (%cursor-peek cur))
                  (string=? (%tok-word-val (%cursor-peek cur)) "!"))
              (do (%cursor-advance! cur) (%skip-newlines cur) #t)
              ())))
      ; Compound commands (if/while/for) contain internal ';' delimiters

      ; that %collect-stage would incorrectly split on. Handle directly.

      (let ((result
              (if (%is-compound-start? cur)
                (%eval-compound cur)
                (let ((stages (%collect-stages cur ())))
                  (if (null? (rest stages))
                    (let ((cur (%mk-cursor (first stages))))
                      (%eval-command cur))
                    (%sh-run-pipeline stages))))))
        (if negate
          (let ((neg-result (if (= result 0) 1 0)))
            (set! %sh-status neg-result)
            neg-result)
          result)))))
; and_or: pipeline (('&&'|'||') pipeline)*

(def %eval-and-or
  (fn (_ cur)
    (let ((result (%eval-pipeline cur)))
      (if (%cursor-empty? cur)
        result
        (if (%match-op cur "&&")
          (do
            (%skip-newlines cur)
            (if (= result 0)
              (%eval-and-or cur)
              ; Short-circuit: skip remaining, but need to not evaluate right side

              ; Actually, since we use recursive descent, the right side

              ; won't be evaluated if we just return

              result))
          (if (%match-op cur "||")
            (do
              (%skip-newlines cur)
              (if (= result 0) 0 (%eval-and-or cur)))
            result))))))
; list: and_or ((';'|'&'|newline) and_or)*

(set! %eval-list
  (fn (_ cur)
    (%skip-newlines cur)
    (if (%at-stop-word? cur)
      (do (set! %sh-status 0) 0)
      (let ((result (%eval-and-or cur)))
        (if (%cursor-empty? cur)
          result
          (let ((tok (%cursor-peek cur)))
            (if (%tok-is-newline? tok)
              (do
                (%cursor-advance! cur)
                (%skip-newlines cur)
                (if (%at-stop-word? cur) result (%eval-list cur)))
              (if (%match-op cur ";")
                (do
                  (%skip-newlines cur)
                  (if (%at-stop-word? cur) result (%eval-list cur)))
                (if (%match-op cur "&")
                  (let ((pid (sh-fork)))
                    (if (= pid 0)
                      (do result (sh-exit 0))
                      (do
                        (set! %sh-status 0)
                        (%skip-newlines cur)
                        (if (%at-stop-word? cur) 0 (%eval-list cur)))))
                  result)))))))))
; --- Public API ---

(def sh-eval
  (fn (_ input)
    (let ((tokens (sh-tokenize input)))
      (if (null? tokens)
        0
        (let ((cur (%mk-cursor tokens))) (%eval-list cur))))))
