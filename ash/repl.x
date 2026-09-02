; # x-ash -- a POSIX shell on x-lang
;
; ## ash/repl.x -- the session, reading SHELL
;
; @description The `$ ` prompt and the -f batch reader.  Reads lines, hands
;   them to sh-eval, and continues an entry that is not finished yet.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; THE PLATFORM REPL READS SEXPS, AND NO PROMPT STRING CHANGES THAT.  This is
; the bug this file exists to fix, and it was total: run.x set %repl-prompt to
; "$ " and %repl-print to ash's writer and stopped there, so `x -l ash` came up
; with a shell's prompt, a shell's banner, and x's READER underneath --
;
;   $ ls
;   Error: Unbound SYMBOL 'ls'
;   $ echo
;   Error: Unbound SYMBOL 'echo'
;
; -- which is the whole shell, unreachable.  Every one of the 82 specs called
; sh-eval directly and passed; nothing in the suite ever started a session.
; The platform loop customizes PROMPT and PRINT only (lib/x/repl/loop.x): its
; read is the ambient reader and its eval is eval!.  A lang whose unit is not
; an s-expression has to replace the LOOP, which is what x-python's repl.x and
; x-logo's do, and what run.x now does with (set! repl %ash-repl).
;
; A SHELL'S UNIT IS A LINE -- until it is not.  `for f in a b c; do echo $f;
; done` is one entry on one line, and the same entry typed over four lines is
; the same entry; %ash-complete? below is what tells them apart.

(import ash/base)
(import ash/prims)
(import x/sys/posix)

; The line reader lives in ash/prims.x, because the `read` builtin needs the
; same one: "a line from the current input, or nil at EOF" is one question,
; and two copies of it would drift the day one of them learns about \r.

; --- is this entry finished? -------------------------------------------------
;
; THE SCAN IS OVER TEXT, NOT TOKENS, and deliberately.  Asking the tokenizer
; would be the tidier answer and is the wrong one twice: the quote readers are
; this bundle's two recorded failures (tests/contract/known-failures.txt), so
; the one construct where continuation matters most is the one the token
; stream gets wrong -- and a tokenizer that raises on unterminated input
; cannot distinguish "broken" from "not finished yet", which is the entire
; question here.  A character scan tracking quote state answers it directly.
;
; What continues an entry, and each is a line a real shell keeps reading after:
;   - an unclosed ' or " (a quoted string spanning lines)
;   - a trailing backslash (explicit continuation)
;   - a trailing |, && or || (the pipeline/list wants a right-hand side)
;   - an unbalanced compound: if..fi, case..esac, do..done, and ( .. )
;
; KEYWORDS ARE COUNTED POSITIONALLY-UNAWARE, which is the documented limit of
; this heuristic: `echo done` at the prompt decrements the do-depth it never
; incremented.  Depths are floored at zero so that under-counting can only
; ever end an entry early -- never hang the prompt waiting for a `done` the
; user has no reason to type.  A shell that will not come back to the prompt
; is unusable in a way that a mis-parsed `echo done` is not.

; --- Is this entry finished? -------------------------------------------------
;
; TWO PASSES, because the two questions are independent.  The first strips
; quoting and answers "is a quote or an escape still open"; the second counts
; brackets and keywords over what is left.  Done as one walk it needed eight
; positional parameters threaded through every branch -- quote state, four
; depths, a word accumulator, the index -- which is how a scanner becomes
; unreadable.  Neither pass now carries more than four.
;
; THE SCAN IS OVER TEXT, NOT TOKENS, and deliberately.  Asking the tokenizer
; would be tidier and is wrong twice: a tokenizer that raises on unterminated
; input cannot distinguish "broken" from "not finished yet", which is the whole
; question here -- and the answer is needed BEFORE the input is worth
; tokenizing.
;
; What continues an entry, each a line a real shell keeps reading after:
;   - an unclosed ' or " (a quoted string spanning lines)
;   - a trailing backslash (explicit continuation)
;   - a trailing |, && or || (the pipeline wants a right-hand side)
;   - an unbalanced if..fi, case..esac, loop..done, ( .. ) or { .. }

(def %ash-tab 9)
(def %ash-nl 10)
(def %ash-space 32)
(def %ash-dq 34)
(def %ash-hash 35)
(def %ash-sq 39)
(def %ash-lparen 40)
(def %ash-rparen 41)
(def %ash-semi 59)
(def %ash-amp 38)
(def %ash-pipe 124)
(def %ash-bs 92)
(def %ash-lbrace 123)
(def %ash-rbrace 125)

(def %ash-ws?
  (fn (_ c) (or (= c %ash-space) (= c %ash-tab) (= c %ash-nl))))

; --- Pass 1: strip quoting ---------------------------------------------------
;
; Quoted text is replaced by SPACES rather than removed: it must not
; contribute keywords (`echo 'done'` closes nothing) and must not glue its
; neighbours into one word.  The result is the same length as the input, which
; keeps the "what precedes this character" test in pass 2 honest.
;
; Answers (bare . open?), where open? is true when a quote or a trailing
; backslash is still waiting.
(def %ash-bare (fn (_ text open?) (pair text open?)))
(def %ash-bare-text (fn (_ r) (first r)))
(def %ash-bare-open? (fn (_ r) (rest r)))

(def %ash-strip
  (fn (_ s)
    (let ((n (Str8 length s)))
      (def go
        (fn (self i mode out)
          (if (>= i n)
            (%ash-bare out (if (= mode 0) () #t))
            (let ((c (Str8 ref i s)))
              (cond
                ; Inside '...' -- only the matching quote closes it, and a
                ; backslash is literal (POSIX): 'it\' IS closed.
                ((= mode 1)
                  (self (+ i 1) (if (= c %ash-sq) 0 1)
                        (Str8 append out " ")))
                ; Inside "..." -- a backslash escapes the next character.
                ((= mode 2)
                  (if (and (= c %ash-bs) (< (+ i 1) n))
                    (self (+ i 2) 2 (Str8 append out "  "))
                    (self (+ i 1) (if (= c %ash-dq) 0 2)
                          (Str8 append out " "))))
                ; Outside quotes.  A backslash at the very END is the
                ; continuation; anywhere else it just escapes one character.
                ((= c %ash-bs)
                  (if (= (+ i 1) n)
                    (%ash-bare out #t)
                    (self (+ i 2) 0 (Str8 append out "  "))))
                ((= c %ash-sq) (self (+ i 1) 1 (Str8 append out " ")))
                ((= c %ash-dq) (self (+ i 1) 2 (Str8 append out " ")))
                ; A comment runs to the end of the line -- but `#` only starts
                ; one where a word could start, the same rule the tokenizer
                ; follows, so `echo $#` is not a comment.
                ((and (= c %ash-hash) (%ash-word-boundary? s i))
                  (self (%ash-eol s (+ i 1) n) 0 out))
                (else
                  (self (+ i 1) 0 (Str8 append out (Str8 sub i 1 s)))))))))
      (go 0 0 ""))))

(def %ash-eol
  (fn (self s i n)
    (if (>= i n)
      i
      (if (= (Str8 ref i s) %ash-nl) i (self s (+ i 1) n)))))

; Does a word (or a comment, or a standalone brace) begin at I?  True at the
; start of the entry and after whitespace or a `;`.
(def %ash-word-boundary?
  (fn (_ s i)
    (if (= i 0)
      #t
      (let ((p (Str8 ref (- i 1) s)))
        (or (%ash-ws? p) (= p %ash-semi))))))

; --- Pass 2: count what is still open ---------------------------------------
;
; The depths travel as ONE vector rather than five parameters:
;   (paren brace if loop case)
; Kept separate rather than summed to a single counter, because a `done` inside
; an if body would otherwise cancel the `if` and the prompt would evaluate an
; unfinished entry -- `if true; then echo done; fi` typed over four lines.
(def %ash-depth-zero (list 0 0 0 0 0))
(def %ash-delta-none (list 0 0 0 0 0))

; Floored at zero, so under-counting can only end an entry EARLY -- never hang
; the prompt waiting for a closer the user has no reason to type.  A shell that
; will not come back to the prompt is unusable in a way that a mis-read
; `echo done` is not.
(def %ash-depth-add
  (fn (self ds delta)
    (if (null? ds)
      ()
      (pair (let ((v (+ (first ds) (first delta)))) (if (< v 0) 0 v))
            (self (rest ds) (rest delta))))))

(def %ash-depth-open?
  (fn (self ds)
    (if (null? ds) () (if (> (first ds) 0) #t (self (rest ds))))))

; THE LOOP KEYWORD OPENS THE LOOP, NOT `do`.  Counting `do` against `done`
; reads `for f in a b` as FINISHED, because the `do` is on the next line and
; nothing is yet unbalanced -- the prompt then answered "parse error: expected
; do" before the user had finished typing.  `for`, `while` and `until` each
; require exactly one `done`, so they are what counts.
(def %ash-kw-delta
  (fn (_ w)
    (match
      ((str=? w "if")    (list 0 0  1  0  0))
      ((str=? w "fi")    (list 0 0 -1  0  0))
      ((str=? w "for")   (list 0 0  0  1  0))
      ((str=? w "while") (list 0 0  0  1  0))
      ((str=? w "until") (list 0 0  0  1  0))
      ((str=? w "done")  (list 0 0  0 -1  0))
      ((str=? w "case")  (list 0 0  0  0  1))
      ((str=? w "esac")  (list 0 0  0  0 -1))
      (#t %ash-delta-none))))

(def %ash-word-char?
  (fn (_ c)
    (or (and (>= c 97) (<= c 122))            ; a-z
        (and (>= c 65) (<= c 90))             ; A-Z
        (and (>= c 48) (<= c 57))             ; 0-9
        (= c 95))))                           ; _

; A brace counts only when it stands on its own -- the `{` and `}` of a
; function body.  `${NAME}` never does, and counting every brace would break on
; an unclosed `${` inside a string, which must not hang the prompt.
(def %ash-brace-delta
  (fn (_ s i c)
    (if (not (%ash-word-boundary? s i))
      %ash-delta-none
      (match
        ((= c %ash-lbrace) (list 0  1 0 0 0))
        ((= c %ash-rbrace) (list 0 -1 0 0 0))
        (#t %ash-delta-none)))))

(def %ash-char-delta
  (fn (_ s i c)
    (match
      ((= c %ash-lparen) (list  1 0 0 0 0))
      ((= c %ash-rparen) (list -1 0 0 0 0))
      (#t (%ash-brace-delta s i c)))))

; Walk the stripped text, folding each completed word and each bracket into the
; depth vector.
(def %ash-depths-of
  (fn (_ s)
    (let ((n (Str8 length s)))
      (def go
        (fn (self i ds word)
          (if (>= i n)
            (%ash-depth-add ds (%ash-kw-delta word))
            (let ((c (Str8 ref i s)))
              (if (%ash-word-char? c)
                (self (+ i 1) ds (Str8 append word (Str8 sub i 1 s)))
                ; A non-word character closes the word in hand, then may open
                ; or close a bracket itself.
                (self (+ i 1)
                      (%ash-depth-add
                        (%ash-depth-add ds (%ash-kw-delta word))
                        (%ash-char-delta s i c))
                      ""))))))
      (go 0 %ash-depth-zero ""))))

; --- Does the entry end mid-construct? --------------------------------------
;
; A trailing operator wants a right-hand side.  Checked on the raw tail rather
; than in either walk: it is about what the LAST thing on the line was, not
; about nesting.
(def %ash-rstrip-end
  (fn (self s e)
    (if (= e 0)
      0
      (if (%ash-ws? (Str8 ref (- e 1) s)) (self s (- e 1)) e))))

(def %ash-dangling-op?
  (fn (_ s)
    (let ((e (%ash-rstrip-end s (Str8 length s))))
      (if (= e 0)
        ()
        (let ((c (Str8 ref (- e 1) s)))
          (cond
            ; `|` covers | and ||.
            ((= c %ash-pipe) #t)
            ; A lone `&` is a background job and is COMPLETE; only `&&` waits.
            ((= c %ash-amp)
              (if (< e 2) () (= (Str8 ref (- e 2) s) %ash-amp)))
            (else ())))))))

; %ash-complete? INPUT -> #t when the entry can be evaluated, () when the
; prompt should keep reading.
(def %ash-complete?
  (fn (_ s)
    (if (= (Str8 length s) 0)
      #t
      (if (%ash-dangling-op? s)
        ()
        (let ((stripped (%ash-strip s)))
          (if (%ash-bare-open? stripped)
            ()
            ; `()` for false, not `#f`: this bundle spells falsity `()`
            ; throughout, and `not` would answer `#f` here.
            (if (%ash-depth-open? (%ash-depths-of (%ash-bare-text stripped)))
              ()
              #t)))))))

(def %ash-read-entry
  (fn (_ first-line)
    (def more
      (fn (self acc)
        (if (%ash-complete? acc)
          acc
          (do
            (display "> ")
            (let ((line (sh-read-line)))
              ; EOF mid-entry: hand back what there is and let sh-eval report
              ; the parse error, rather than looping on nil forever.
              (if (null? line)
                acc
                (self (Str8 append acc (Str8 append "\n" line)))))))))
    (more first-line)))

; --- the banner --------------------------------------------------------------
;
; The releases arrive as BOOT DATA, not file reads: x.sh emits %platform-release
; (x-lang's, from the install's contract/release) and %param-release (the
; engine's).  A checkout emits no platform release and an older x.sh emits
; neither, so every lookup is guarded and the banner degrades to what it knows.
(def %ash-global
  (fn (_ form) (guard (%ash-e ()) (eval! form))))

(def %ash-banner
  (fn (_)
    (display "ASH Shell v" ash-version " on x-lang")
    (let ((rel (%ash-global (lit %platform-release))))
      (unless (null? rel) (display " " rel)))
    (let ((er (%ash-global (lit %param-release))))
      (unless (null? er) (display ", engine " er)))
    (newline)
    (display "exit or ctrl-d to leave")
    (newline)))

; --- error reporting ---------------------------------------------------------
;
; A shell reports to STDERR and carries on; only the status changes.  Err
; instances render through the platform writer -- (symbol->str err) on a
; structured error reads its memory as a symbol name and prints garbage bytes.
(def %ash-report
  (fn (_ err)
    (%stderr "ash: ")
    (%stderr (if (str? err) err (%repl-write-to-str err)))
    (%stderr "\n")))

; --- the loop ----------------------------------------------------------------
(def %ash-repl ())
(set! %ash-repl
  (fn (_)
    ; FIRST CALL: reclaim terminal stdin from fd 3.  x.sh parks the user's
    ; stdin there while the boot stream occupies fd 0, so a loop that skips
    ; this reads the EXHAUSTED boot pipe and every line arrives as EOF -- a
    ; prompt that never evaluates anything, which is x-python's measured
    ; fd-3 bug and would be this one.  Guarded: under the spec harness there
    ; is no fd 3 to take.
    (guard (%ash-e ()) (do (Sys dup2 3 0) (Sys close 3)))
    (%ash-repl-loop)))

(def %ash-repl-loop ())
(set! %ash-repl-loop
  (fn (_)
    (display %repl-prompt)
    (let ((line (sh-read-line)))
      (if (null? line)
        ; ctrl-d leaves, with the last command's status -- `x -l ash -f x.sh`
        ; and an interactive session both answer $? to the caller.
        (do (newline) (Sys exit %sh-status))
        (do
          (guard (err (%ash-report err))
            (let ((entry (%ash-read-entry line)))
              (unless (= (Str8 length entry) 0) (sh-eval entry))))
          (%ash-repl-loop))))))

; --- batch (-f) --------------------------------------------------------------
;
; x.sh cats the named file onto the engine's stdin AFTER this bundle's entry,
; so by the time run.x's last form runs, stdin holds the shell script -- and it
; is shell syntax, which the C read-eval loop that would otherwise resume
; cannot parse.  Slurp it and push it through sh-eval, then exit with the
; status the script ended on, the way `sh script.sh` does.
;
; NO fd-3 SWAP HERE, and that is the whole difference between the two entry
; points: the swap is what discards the program.  x-logo's entry records the
; same trap.
(def %ash-batch ())
(set! %ash-batch
  (fn (_)
    (def slurp
      (fn (self acc)
        (let ((line (sh-read-line)))
          (if (null? line) (List reverse acc) (self (pair line acc))))))
    (let ((src (Str8 join "\n" (slurp ()))))
      (guard (err
          (%ash-report err)
          (Sys exit 1))
        (unless (= (Str8 length src) 0) (sh-eval src))
        (Sys exit %sh-status)))))

(provide ash/repl %ash-repl %ash-batch %ash-banner %ash-complete?)
