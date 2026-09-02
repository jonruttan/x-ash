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

(def %ash-sq 39)   ; '
(def %ash-dq 34)   ; "
(def %ash-bs 92)   ; \
(def %ash-lbrace 123)
(def %ash-rbrace 125)

; Is the character at I a brace standing on its own -- the `{` and `}` that
; open and close a function body -- rather than one of `${NAME}`?  The test is
; what PRECEDES it: a standalone brace follows whitespace, a `;`, or the start
; of the entry, and `${` never does.
;
; Counting every brace would work for `${NAME}` (balanced, so it nets out) and
; break on `"${X"` inside a string; counting only standalone ones is both
; narrower and what a shell actually means by the word `{`.
(def %ash-standalone-brace?
  (fn (_ s i)
    (if (= i 0)
      #t
      (let ((p (Str8 ref (- i 1) s)))
        (or (= p 32) (or (= p 9) (or (= p 10) (= p 59))))))))

; The scanner's state rides in a list so one walk answers everything:
;   (quote-char paren-depth if-depth do-depth case-depth word-acc last-op)
; quote-char is 0 outside a string, else 39 or 34.

(def %ash-word-char?
  (fn (_ c)
    (or (and (>= c 97) (<= c 122))            ; a-z
        (or (and (>= c 65) (<= c 90))         ; A-Z
            (or (and (>= c 48) (<= c 57))     ; 0-9
                (= c 95))))))                 ; _

; Bump a depth, never below zero -- see the floor note above.
(def %ash-bump
  (fn (_ n d) (let ((v (+ n d))) (if (< v 0) 0 v))))

; A completed word adjusts exactly one depth.  Returns the delta triple
; (if-delta loop-delta case-delta).
;
; THE LOOP KEYWORD OPENS THE LOOP, NOT `do`.  Counting `do` against `done` --
; which is what this did first -- reads `for f in a b` as a FINISHED entry,
; because the `do` is on the next line and nothing yet is unbalanced.  The
; prompt then evaluated it and answered "parse error: expected do" before the
; user had finished typing.  `for`, `while` and `until` each require exactly
; one `done`, so they are what counts; `do` itself contributes nothing.
(def %ash-kw-delta
  (fn (_ w)
    (match
      ((str=? w "if")    (list  1  0  0))
      ((str=? w "fi")    (list -1  0  0))
      ((str=? w "for")   (list  0  1  0))
      ((str=? w "while") (list  0  1  0))
      ((str=? w "until") (list  0  1  0))
      ((str=? w "done")  (list  0 -1  0))
      ((str=? w "case")  (list  0  0  1))
      ((str=? w "esac")  (list  0  0 -1))
      (#t (list 0 0 0)))))

; %ash-complete? INPUT -> #t when the entry can be evaluated, () when the
; prompt should keep reading.
(def %ash-complete?
  (fn (_ s)
    (let ((n (Str8 length s)))
      (def go
        (fn (self i q paren brace ifd dod cased word)
          ; End of input: fold any trailing word, then decide.
          (if (>= i n)
            (let ((d (%ash-kw-delta word)))
              (let ((ifd2   (%ash-bump ifd   (first d)))
                    (dod2   (%ash-bump dod   (first (rest d))))
                    (cased2 (%ash-bump cased (first (rest (rest d))))))
                (if (not (= q 0))
                  ()                                  ; inside a quoted string
                  (if (> paren 0)
                    ()
                  (if (> brace 0)
                    ()
                    (if (> ifd2 0)
                      ()
                      (if (> dod2 0)
                        ()
                        (if (> cased2 0) () #t))))))))
            (let ((c (Str8 ref i s)))
              (if (not (= q 0))
                ; Inside a string: only the matching quote closes it.  A
                ; backslash escapes the next character in a "..." but is
                ; literal in a '...', which is POSIX and matters here --
                ; 'it\' is a CLOSED string, "it\" is not.
                (if (and (= q %ash-dq) (= c %ash-bs))
                  (self (+ i 2) q paren brace ifd dod cased word)
                  (if (= c q)
                    (self (+ i 1) 0 paren brace ifd dod cased word)
                    (self (+ i 1) q paren brace ifd dod cased word)))
                ; Outside a string.
                (if (= c %ash-bs)
                  ; A backslash at the very end IS the continuation; anywhere
                  ; else it just escapes one character.
                  (if (= (+ i 1) n)
                    ()
                    (self (+ i 2) q paren brace ifd dod cased ""))
                  (if (or (= c %ash-sq) (= c %ash-dq))
                    (self (+ i 1) c paren brace ifd dod cased word)
                    (if (%ash-word-char? c)
                      (self (+ i 1) q paren brace ifd dod cased
                            (Str8 append word (Str8 sub i 1 s)))
                      ; A non-word character closes the word in hand and
                      ; applies its keyword delta.
                      (let ((d (%ash-kw-delta word)))
                        (let ((ifd2   (%ash-bump ifd   (first d)))
                              (dod2   (%ash-bump dod   (first (rest d))))
                              (cased2 (%ash-bump cased (first (rest (rest d))))))
                          (if (= c 40)                       ; (
                            (self (+ i 1) q (+ paren 1) brace ifd2 dod2 cased2 "")
                            (if (= c 41)                     ; )
                              (self (+ i 1) q (%ash-bump paren -1) brace ifd2 dod2 cased2 "")
                              (if (= c 35)                   ; # -- comment
                                (self n q paren brace ifd2 dod2 cased2 "")
                                (if (and (= c %ash-lbrace)
                                         (%ash-standalone-brace? s i))
                                  (self (+ i 1) q paren (+ brace 1)
                                        ifd2 dod2 cased2 "")
                                (if (and (= c %ash-rbrace)
                                         (%ash-standalone-brace? s i))
                                  (self (+ i 1) q paren (%ash-bump brace -1)
                                        ifd2 dod2 cased2 "")
                                  (self (+ i 1) q paren brace
                                        ifd2 dod2 cased2 ""))))))))))))))))
      (if (= n 0)
        #t
        ; A trailing operator wants a right-hand side.  Checked on the raw
        ; tail rather than in the walk: the walk is about nesting, and this is
        ; about what the LAST thing on the line was.
        (if (%ash-dangling-op? s)
          ()
          (go 0 0 0 0 0 0 0 ""))))))

; Does the input end in an operator that needs more?  Trailing whitespace is
; ignored first, and a `|` that is part of `||` is the same answer either way.
(def %ash-dangling-op?
  (fn (_ s)
    (def rstrip
      (fn (self e)
        (if (= e 0)
          0
          (let ((c (Str8 ref (- e 1) s)))
            (if (or (= c 32) (or (= c 9) (= c 10)))
              (self (- e 1))
              e)))))
    (let ((e (rstrip (Str8 length s))))
      (if (= e 0)
        ()
        (let ((c (Str8 ref (- e 1) s)))
          ; `|` and `&` cover |, ||, && ; a lone `&` is a background job and
          ; is COMPLETE, so it is excluded by requiring a doubled ampersand.
          (if (= c 124)                                    ; |
            #t
            (if (= c 38)                                   ; &
              (if (< e 2) () (= (Str8 ref (- e 2) s) 38))   ; && only
              ())))))))

; --- read one entry, continuing while it is unfinished -----------------------
;
; The continuation prompt is PS2, `> `, and the accumulated text keeps its
; newlines: the tokenizer emits sh-newline tokens and %eval-list treats one as
; a list separator, which is exactly what a `do` body needs between commands.
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
