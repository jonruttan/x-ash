; # x-ash -- a POSIX shell on x-lang
;
; ## ash/reader.x -- complete commands read in the shell's base
;
; @description The shell's grammar, read by the tokenizer's own loop: a read
;   handler that meets the first token of a command reads the whole complete
;   command through `tok read` and answers its node.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A script is read as ash reads one: a complete command at a time, each to its
; end before any of it runs, and a syntax error anywhere in one refuses the
; whole of it.  The reading base is the tokenizer's with each type's read
; handler wrapped (%sh-rd-handlers): inside a command a handler answers its
; token, and at the start of one it reads the command (%sh-rd-command).  So
; `token-read-string` over a script answers an item for each complete command:
;
;   (cmd NODE RAW)     NODE the command's list, RAW its tokens as read, the
;                      newline that ends it among them
;   (err MESSAGE RAW)  a command the grammar refuses, raised when it is reached
;   (tok-newline)      a line with no command on it
;
; A node is what the runners in ash/eval.x run ("Loops and functions read into
; nodes"): lists, and-or lists, pipelines, simple commands read into steps, and
; compound commands.  What a run would otherwise keep on a token -- a word's
; plan, a literal name's builtin -- is made here as the token is read.
; Everything a read handler makes is on the tokenizer's chain, and a collect of
; the evaluator's heap does not follow its own objects through that chain, so
; nothing the evaluator makes later may be kept on what is read here.
;
; Each rule answers nil once an error is found, which %sh-rd-err keeps: a read
; handler cannot raise, since the reader's C loop is below it.

; --- The token source ----------------------------------------------------------
;
; The tokens a command is read from: the buffer the tokenizer reads, through
; `tok read`, with the tokens given back in front of it.  Nil is the end of the
; input.
(def %sh-rd-read (prim-ref (lit tok) (lit read)))
(def %sh-rd-buf ())       ; the buffer
(def %sh-rd-next ())      ; (tok read BUF), evaluated in the reading base
(def %sh-rd-pend ())      ; tokens given back, the first taken first
(def %sh-rd-raw ())       ; the command's tokens as read, latest first
(def %sh-rd-err ())       ; the first error found, or nil
(def %sh-rd-depth 0)      ; 0 between commands

(def %sh-rd-peek
  (fn (_)
    (match
      ((null? %sh-rd-pend)
        (%sh-rd-fetch (%sh-rd-own (%sh-base-eval %sh-rd-raw-base %sh-rd-next))))
      (#t (first %sh-rd-pend)))))

(def %sh-rd-fetch
  (fn (_ tok)
    (match
      ((null? tok) ())
      (#t (do (set! %sh-rd-pend (list tok)) tok)))))

; TOK as a token: a word when the tokenizer answered something else.
(def %sh-rd-own
  (fn (_ tok)
    (match
      ((null? tok) ())
      ((pair? tok) tok)
      (#t (mk-tok-word (convert tok %ash-string-type))))))

; The token at hand, taken.
(def %sh-rd-take
  (fn (_)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) ())
      (#t (%sh-rd-taken tok)))))

(def %sh-rd-taken
  (fn (_ tok)
    (set! %sh-rd-pend (rest %sh-rd-pend))
    (set! %sh-rd-raw (pair tok %sh-rd-raw))
    tok))

(def %sh-rd-newline?
  (fn (_ tok) (match ((null? tok) ()) (#t (eq? (first tok) (lit tok-newline))))))

(def %sh-rd-op?
  (fn (_ tok op) (match ((null? tok) ()) (#t (%tok-is-op? tok op)))))

; Whether TOK is the reserved word WORD: a bare word spelled so.
(def %sh-rd-word?
  (fn (_ tok word)
    (match
      ((null? tok) ())
      ((eq? (first tok) (lit tok-word)) (string=? (first (rest tok)) word))
      (#t ()))))

(def %sh-rd-skip-newlines
  (fn (self)
    (match
      ((%sh-rd-newline? (%sh-rd-peek)) (do (%sh-rd-take) (self)))
      (#t ()))))

; --- Errors --------------------------------------------------------------------

; MESSAGE kept, the first error's, and nil answered.
(def %sh-rd-fail
  (fn (_ message)
    (match ((null? %sh-rd-err) (set! %sh-rd-err message)) (#t ()))
    ()))

; TOK refused where it stands.
(def %sh-rd-unexpected
  (fn (_ tok)
    (%sh-rd-fail
      (string-append "parse error: unexpected "
        (match
          ((null? tok) "EOF")
          ((%sh-rd-newline? tok) "newline")
          (#t (%tok-word-val tok)))))))

(def %sh-rd-expected
  (fn (_ word) (%sh-rd-fail (string-append "parse error: expected " word))))

; The reserved word WORD taken, or the error that it is missing.
(def %sh-rd-expect
  (fn (_ word)
    (match
      ((%sh-rd-word? (%sh-rd-peek) word) (%sh-rd-take))
      (#t (%sh-rd-expected word)))))

; --- Complete commands -----------------------------------------------------------

; The item for the complete command TOK starts, read from BUF.  %sh-rd-depth
; keeps the handlers answering tokens while it is read.
(def %sh-rd-command
  (fn (_ tok buf)
    (set! %sh-rd-buf buf)
    (set! %sh-rd-next (list %sh-rd-read buf))
    (set! %sh-rd-pend (list tok))
    (set! %sh-rd-raw ())
    (set! %sh-rd-err ())
    (set! %sh-rd-depth 1)
    (def node (%sh-rd-items #t ()))
    (set! %sh-rd-depth 0)
    (match
      ((null? %sh-rd-err) (list (lit cmd) node (reverse %sh-rd-raw)))
      (#t (%sh-rd-error-item)))))

; An error item: the message, and the tokens to the end of the line it was
; found on, taken so that the next item starts a line.
(def %sh-rd-error-item
  (fn (_)
    (set! %sh-rd-depth 1)
    (%sh-rd-to-line-end)
    (set! %sh-rd-depth 0)
    (list (lit err) %sh-rd-err (reverse %sh-rd-raw))))

(def %sh-rd-to-line-end
  (fn (self)
    (def tok (%sh-rd-take))
    (match
      ((null? tok) ())
      ((%sh-rd-newline? tok) ())
      (#t (self)))))

; --- Lists -------------------------------------------------------------------------

; The and-or lists of a list, ITEMS those read, latest first, each (sync ANDOR)
; or (async ANDOR).  TOP? says the list is a complete command, which a newline
; ends; any other list is a construct's, which newlines separate and one of the
; words or operators that close a construct ends, left in place.
(def %sh-rd-items
  (fn (self top? items)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-list-done items))
      ((%sh-rd-newline? tok)
        (do
          (%sh-rd-take)
          (match (top? (%sh-rd-list-done items)) (#t (self top? items)))))
      ((%sh-rd-closer? tok)
        (match (top? (%sh-rd-unexpected tok)) (#t (%sh-rd-list-done items))))
      (#t (%sh-rd-items-on self top? items (%sh-rd-andor))))))

(def %sh-rd-list-done
  (fn (_ items)
    (match
      ((null? %sh-rd-err) (%sh-list-node (reverse items)))
      (#t ()))))

; After the and-or list ANDOR: a `;` or `&` after it, or what ends the list.
(def %sh-rd-items-on
  (fn (_ walk top? items andor)
    (def tok (%sh-rd-peek))
    (match
      ((null? andor) ())
      ((null? tok) (walk top? (pair (list (lit sync) andor) items)))
      ((%sh-rd-op? tok ";")
        (do (%sh-rd-take) (walk top? (pair (list (lit sync) andor) items))))
      ((%sh-rd-op? tok "&")
        (do (%sh-rd-take) (walk top? (pair (list (lit async) andor) items))))
      ((%sh-rd-newline? tok) (walk top? (pair (list (lit sync) andor) items)))
      ((%sh-rd-closer? tok) (walk top? (pair (list (lit sync) andor) items)))
      (#t (%sh-rd-unexpected tok)))))

; What closes a construct's list where a command could start: a reserved word
; that ends or closes one, a `)`, a `;;`.
(def %sh-rd-closer?
  (fn (_ tok)
    (match
      ((null? tok) ())
      ((eq? (first tok) (lit tok-op))
        (match
          ((string=? (first (rest tok)) ")") #t)
          ((string=? (first (rest tok)) ";;") #t)
          (#t ())))
      ((eq? (first tok) (lit tok-word)) (%sh-word-in? (first (rest tok)) %sh-rd-closers))
      (#t ()))))

(def %sh-rd-closers (list "then" "elif" "else" "fi" "do" "done" "esac" "}"))

; --- And-or lists and pipelines ---------------------------------------------------

; (andor PIPELINE OPS), OPS each (AND? . PIPELINE).
(def %sh-rd-andor
  (fn (_) (%sh-rd-andor-ops (%sh-rd-pipeline) ())))

(def %sh-rd-andor-ops
  (fn (self first-pipe ops)
    (def tok (%sh-rd-peek))
    (match
      ((null? first-pipe) ())
      ((%sh-rd-and-or? tok)
        (do
          (%sh-rd-take)
          (%sh-rd-skip-newlines)
          (%sh-rd-andor-next self first-pipe ops (%sh-rd-op? tok "&&") (%sh-rd-pipeline))))
      (#t (%sh-rd-andor-end first-pipe (reverse ops))))))

(def %sh-rd-andor-next
  (fn (_ walk first-pipe ops and? pipe)
    (match
      ((null? pipe) ())
      (#t (walk first-pipe (pair (pair and? pipe) ops))))))

; The and-or list, each pipeline told whether an operator follows it.
(def %sh-rd-andor-end
  (fn (_ first-pipe ops)
    (list (lit andor) (%sh-rd-pipe-node first-pipe (not (null? ops)))
          (%sh-rd-ops-nodes ops))))

(def %sh-rd-ops-nodes
  (fn (self ops)
    (match
      ((null? ops) ())
      (#t (pair (pair (first (first ops))
                      (%sh-rd-pipe-node (rest (first ops)) (not (null? (rest ops)))))
                (self (rest ops)))))))

(def %sh-rd-and-or?
  (fn (_ tok) (match ((null? tok) ()) (#t (%sh-and-or-tok? tok)))))

; A pipeline read: (NEGATE . COMMANDS), each command (simple STEPS),
; (compound NODE) or (fn-def NAME NODE).  Its node is made once the and-or list
; says whether an operator follows it (%sh-rd-pipe-node).
(def %sh-rd-pipeline
  (fn (_)
    (match
      ((%sh-rd-word? (%sh-rd-peek) "!")
        (do (%sh-rd-take) (%sh-rd-stages #t (%sh-rd-cmd) ())))
      (#t (%sh-rd-stages () (%sh-rd-cmd) ())))))

(def %sh-rd-stages
  (fn (self negate cmd cmds)
    (match
      ((null? cmd) ())
      ((%sh-rd-op? (%sh-rd-peek) "|")
        (do
          (%sh-rd-take)
          (%sh-rd-skip-newlines)
          (self negate (%sh-rd-cmd) (pair cmd cmds))))
      (#t (pair negate (reverse (pair cmd cmds)))))))

(def %sh-rd-pipe-node
  (fn (_ pipe andor?)
    (match
      ((null? (rest (rest pipe)))
        (%sh-rd-stage-node (first pipe) (first (rest pipe)) andor?))
      (#t (list (lit piped) (first pipe) (map %sh-rd-stage (rest pipe)) andor?)))))

; A command that is its pipeline's one stage.
(def %sh-rd-stage-node
  (fn (_ negate cmd andor?)
    (match
      ((eq? (first cmd) (lit simple))
        (list (lit simple) negate () () andor? (first (rest cmd))))
      ((eq? (first cmd) (lit compound))
        (list (lit compound) negate () (%sh-rd-alone? (first (rest cmd))) andor?
              (first (rest cmd))))
      (#t (list (lit fn-def) negate (first (rest cmd)) (first (rest (rest cmd)))
                andor?)))))

; Whether a compound command's status is its own, as %sh-compound-alone? asks:
; not a subshell's, whose failure `set -e` answers as a command's.
(def %sh-rd-alone?
  (fn (_ node)
    (match
      ((eq? (first node) (lit subshell)) ())
      ((eq? (first node) (lit redirected)) (%sh-rd-alone? (first (rest node))))
      (#t #t))))

; A command that is one stage of several.
(def %sh-rd-stage (fn (_ cmd) (%sh-rd-stage-node () cmd ())))

; --- Commands ------------------------------------------------------------------------

; The command at hand: (simple STEPS), (compound NODE) or (fn-def NAME NODE).
(def %sh-rd-cmd
  (fn (_)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-unexpected tok))
      ((%sh-rd-op? tok "(") (%sh-rd-compound (%sh-rd-subshell)))
      ((%sh-rd-compound-word? tok) (%sh-rd-compound (%sh-rd-compound-at tok)))
      ((eq? (first tok) (lit tok-word)) (%sh-rd-word-first (%sh-rd-take)))
      (#t (%sh-rd-simple ())))))

(def %sh-rd-compound-word?
  (fn (_ tok)
    (match
      ((eq? (first tok) (lit tok-word)) (%sh-word-in? (first (rest tok)) %sh-rd-openers))
      (#t ()))))

(def %sh-rd-openers (list "{" "if" "while" "until" "for" "case"))

; A command whose first token TOK is a bare word, taken: a function's
; definition when `()` follows it, a closing word or `!` refused, any other
; the name of a simple command.
(def %sh-rd-word-first
  (fn (_ tok)
    (match
      ((%sh-rd-closer? tok) (%sh-rd-unexpected tok))
      ((%sh-rd-word? tok "!") (%sh-rd-unexpected tok))
      ((%sh-rd-op? (%sh-rd-peek) "(") (%sh-rd-fn-def tok))
      (#t (%sh-rd-simple (list tok))))))

; --- Simple commands --------------------------------------------------------------

; The simple command whose tokens TS, latest first, are read already: its words
; and redirections to the operator or newline that ends it, read into steps.
(def %sh-rd-simple
  (fn (self ts)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-simple-end ts))
      ((%tok-is-word? tok) (do (%sh-rd-take) (self (pair tok ts))))
      ((%tok-is-io? tok) (do (%sh-rd-take) (%sh-rd-io self ts tok)))
      ((%redir-op? tok) (do (%sh-rd-take) (%sh-rd-target self (pair tok ts))))
      ((%sh-rd-op? tok "(") (%sh-rd-unexpected tok))
      (#t (%sh-rd-simple-end ts)))))

; After the digits of `2>err`, the operator.
(def %sh-rd-io
  (fn (_ walk ts io)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-fail "parse error: redirect without operator"))
      ((%redir-op? tok) (do (%sh-rd-take) (%sh-rd-target walk (pair tok (pair io ts)))))
      (#t (%sh-rd-fail "parse error: redirect without operator")))))

; After a redirection's operator, its target.
(def %sh-rd-target
  (fn (_ walk ts)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-fail "parse error: redirect without target"))
      ((%tok-is-word? tok) (do (%sh-rd-take) (walk (pair tok ts))))
      (#t (%sh-rd-unexpected tok)))))

(def %sh-rd-simple-end
  (fn (_ ts)
    (match
      ((null? ts) (%sh-rd-unexpected (%sh-rd-peek)))
      (#t (list (lit simple) (%sh-rd-steps (map %sh-lit-or-word (reverse ts))))))))

; The steps of a simple command's tokens TS, with what running them would keep
; on a token made now.
(def %sh-rd-steps
  (fn (_ ts) (%sh-rd-ready (%sh-simple-steps ts ()))))

(def %sh-rd-ready
  (fn (_ steps)
    (match
      ((eq? (first steps) (lit assigns)) (map %sh-rd-ready-assign (rest steps)))
      (#t (map %sh-rd-ready-step steps)))
    steps))

(def %sh-rd-ready-step
  (fn (_ step)
    (match
      ((= (first step) 1) (%sh-lit-facts (first (rest (rest step)))))
      ((= (first step) 3) (%sh-rd-plan (first (rest step)) (first (rest (rest step)))))
      ((= (first step) 4) (%sh-rd-plan (first (first (rest (rest (rest step))))) ()))
      (#t ()))))

(def %sh-rd-ready-assign
  (fn (_ spec)
    (match
      ((< 1 (first (rest spec))) (%sh-rd-plan (first (rest (rest spec))) #t))
      (#t ()))))

; The plan a word's expansion runs, made and kept on its token now.
(def %sh-rd-plan
  (fn (_ tok assign?)
    (match
      ((eq? (first tok) (lit tok-word)) (%sh-tok-plan tok assign?))
      ((eq? (first tok) (lit tok-dq)) (%sh-tok-plan tok assign?))
      (#t ()))))

(def %sh-rd-plan-each
  (fn (self toks)
    (match
      ((null? toks) ())
      (#t (do (%sh-rd-plan (first toks) ()) (self (rest toks)))))))

; --- Function definitions ------------------------------------------------------------

; NAME read, and its `(` at hand: the `()`, the newlines, and the compound
; command that is the body, redirections and all.
(def %sh-rd-fn-def
  (fn (_ name)
    (def paren (%sh-rd-take))
    (match
      ((not (%sh-rd-op? (%sh-rd-peek) ")")) (%sh-rd-unexpected paren))
      ((not (%sh-name? (%tok-word-val name)))
        (%sh-rd-fail (string-append "parse error: bad function name "
                                    (%tok-word-val name))))
      (#t (do
            (%sh-rd-take)
            (%sh-rd-skip-newlines)
            (%sh-rd-fn-body (%tok-word-val name)))))))

(def %sh-rd-fn-body
  (fn (_ name)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-no-body name))
      ((%sh-rd-op? tok "(") (%sh-rd-fn-node name (%sh-rd-compound (%sh-rd-subshell))))
      ((%sh-rd-compound-word? tok)
        (%sh-rd-fn-node name (%sh-rd-compound (%sh-rd-compound-at tok))))
      (#t (%sh-rd-no-body name)))))

(def %sh-rd-no-body
  (fn (_ name)
    (%sh-rd-fail (string-append "parse error: no compound command after " name "()"))))

; (fn-def NAME BODY), BODY the list the body runs as: one and-or list of the
; one compound command.
(def %sh-rd-fn-node
  (fn (_ name cmd)
    (match
      ((null? cmd) ())
      (#t (list (lit fn-def) name
            (%sh-list-node
              (list (list (lit sync)
                          (list (lit andor) (%sh-rd-stage-node () cmd ()) ())))))))))

; --- Compound commands ---------------------------------------------------------------

; The compound command NODE read, and any redirections after it: (compound
; NODE), NODE a (redirected NODE REDIRS) when there are some.
(def %sh-rd-compound
  (fn (_ node)
    (match
      ((null? node) ())
      (#t (%sh-rd-redirs node ())))))

(def %sh-rd-redirs
  (fn (self node ts)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-redirected node ts))
      ((%tok-is-io? tok) (do (%sh-rd-take) (%sh-rd-io-redir self node ts tok)))
      ((%redir-op? tok) (do (%sh-rd-take) (%sh-rd-redir-target self node (pair tok ts))))
      ((%sh-rd-closer? tok) (%sh-rd-redirected node ts))
      ((%tok-is-word? tok) (%sh-rd-unexpected tok))
      ((%sh-rd-op? tok "(") (%sh-rd-unexpected tok))
      (#t (%sh-rd-redirected node ts)))))

(def %sh-rd-io-redir
  (fn (_ walk node ts io)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-fail "parse error: redirect without operator"))
      ((%redir-op? tok)
        (do (%sh-rd-take) (%sh-rd-redir-target walk node (pair tok (pair io ts)))))
      (#t (%sh-rd-fail "parse error: redirect without operator")))))

(def %sh-rd-redir-target
  (fn (_ walk node ts)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-fail "parse error: redirect without target"))
      ((%tok-is-word? tok)
        (do (%sh-rd-take) (%sh-rd-plan tok ()) (walk node (pair tok ts))))
      (#t (%sh-rd-unexpected tok)))))

(def %sh-rd-redirected
  (fn (_ node ts)
    (match
      ((null? ts) (list (lit compound) node))
      (#t (list (lit compound) (list (lit redirected) node (reverse ts)))))))

; The construct the reserved word TOK opens.
(def %sh-rd-compound-at
  (fn (_ tok)
    (def word (first (rest tok)))
    (%sh-rd-take)
    (match
      ((string=? word "{") (%sh-rd-group))
      ((string=? word "if") (%sh-rd-if ()))
      ((string=? word "while") (%sh-rd-loop (lit while)))
      ((string=? word "until") (%sh-rd-loop (lit until)))
      ((string=? word "for") (%sh-rd-for))
      (#t (%sh-rd-case)))))

; A construct's list.
(def %sh-rd-body (fn (_) (%sh-rd-items () ())))

(def %sh-rd-group
  (fn (_)
    (def body (%sh-rd-body))
    (match
      ((null? body) ())
      ((null? (%sh-rd-expect "}")) ())
      (#t (list (lit group) body)))))

(def %sh-rd-subshell
  (fn (_)
    (%sh-rd-take)
    (def body (%sh-rd-body))
    (match
      ((null? body) ())
      ((%sh-rd-op? (%sh-rd-peek) ")") (do (%sh-rd-take) (list (lit subshell) body)))
      (#t (%sh-rd-expected ")")))))

; if: each clause (COND BODY), CLAUSES those read, latest first.
(def %sh-rd-if
  (fn (self clauses)
    (def cond (%sh-rd-body))
    (match
      ((null? cond) ())
      ((null? (%sh-rd-expect "then")) ())
      (#t (%sh-rd-if-body self cond clauses (%sh-rd-body))))))

(def %sh-rd-if-body
  (fn (_ walk cond clauses body)
    (match
      ((null? body) ())
      (#t (%sh-rd-if-next walk (pair (list cond body) clauses))))))

(def %sh-rd-if-next
  (fn (_ walk clauses)
    (def tok (%sh-rd-peek))
    (match
      ((%sh-rd-word? tok "elif") (do (%sh-rd-take) (walk clauses)))
      ((%sh-rd-word? tok "else") (do (%sh-rd-take) (%sh-rd-if-else clauses (%sh-rd-body))))
      ((%sh-rd-word? tok "fi") (do (%sh-rd-take) (list (lit if) (reverse clauses) ())))
      (#t (%sh-rd-expected "fi")))))

(def %sh-rd-if-else
  (fn (_ clauses else)
    (match
      ((null? else) ())
      ((null? (%sh-rd-expect "fi")) ())
      (#t (list (lit if) (reverse clauses) else)))))

; while or until: (loop KIND COND BODY).
(def %sh-rd-loop
  (fn (_ kind)
    (def cond (%sh-rd-body))
    (match
      ((null? cond) ())
      (#t (%sh-rd-loop-do kind cond)))))

(def %sh-rd-loop-do
  (fn (_ kind cond)
    (match
      ((null? (%sh-rd-expect "do")) ())
      (#t (%sh-rd-loop-done kind cond (%sh-rd-body))))))

(def %sh-rd-loop-done
  (fn (_ kind cond body)
    (match
      ((null? body) ())
      ((null? (%sh-rd-expect "done")) ())
      (#t (list (lit loop) kind cond body)))))

; for: (for VAR IN? WORDS BODY).
(def %sh-rd-for
  (fn (_)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-fail "parse error: for without variable"))
      ((%sh-rd-newline? tok) (%sh-rd-fail "parse error: for without variable"))
      ((%sh-name? (%tok-word-val tok))
        (do (%sh-rd-take) (%sh-rd-for-in (%tok-word-val tok))))
      (#t (%sh-rd-fail (string-append "parse error: bad for loop variable "
                                       (%tok-word-val tok)))))))

(def %sh-rd-for-in
  (fn (_ var)
    (%sh-rd-skip-newlines)
    (match
      ((%sh-rd-word? (%sh-rd-peek) "in") (do (%sh-rd-take) (%sh-rd-for-words var ())))
      ((%sh-rd-op? (%sh-rd-peek) ";")
        (do (%sh-rd-take) (%sh-rd-skip-newlines) (%sh-rd-for-do var () ())))
      (#t (%sh-rd-for-do var () ())))))

(def %sh-rd-for-words
  (fn (self var words)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-for-do var #t (reverse words)))
      ((%sh-rd-newline? tok)
        (do (%sh-rd-skip-newlines) (%sh-rd-for-do var #t (reverse words))))
      ((%sh-rd-op? tok ";")
        (do (%sh-rd-take) (%sh-rd-skip-newlines) (%sh-rd-for-do var #t (reverse words))))
      ((%tok-is-word? tok)
        (do (%sh-rd-take) (self var (pair (%sh-lit-or-word tok) words))))
      (#t (%sh-rd-unexpected tok)))))

(def %sh-rd-for-do
  (fn (_ var in? words)
    (%sh-rd-plan-each words)
    (match
      ((null? (%sh-rd-expect "do")) ())
      (#t (%sh-rd-for-done var in? words (%sh-rd-body))))))

(def %sh-rd-for-done
  (fn (_ var in? words body)
    (match
      ((null? body) ())
      ((null? (%sh-rd-expect "done")) ())
      (#t (list (lit for) var in? words body)))))

; case: (case SUBJECT CLAUSES), each clause (PATTERNS BODY).
(def %sh-rd-case
  (fn (_)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-fail "parse error: case without a word"))
      ((not (%tok-is-word? tok)) (%sh-rd-fail "parse error: case without a word"))
      (#t (do (%sh-rd-take) (%sh-rd-plan tok ()) (%sh-rd-case-in tok))))))

(def %sh-rd-case-in
  (fn (_ subject)
    (%sh-rd-skip-newlines)
    (match
      ((null? (%sh-rd-expect "in")) ())
      (#t (%sh-rd-clauses subject ())))))

(def %sh-rd-clauses
  (fn (self subject clauses)
    (%sh-rd-skip-newlines)
    (def tok (%sh-rd-peek))
    (match
      ((%sh-rd-word? tok "esac")
        (do (%sh-rd-take) (list (lit case) subject (reverse clauses))))
      ((%sh-rd-op? tok "(")
        (do (%sh-rd-take) (%sh-rd-patterns self subject clauses ())))
      (#t (%sh-rd-patterns self subject clauses ())))))

; A clause's patterns, to the `)` that ends them.
(def %sh-rd-patterns
  (fn (self walk subject clauses pats)
    (def tok (%sh-rd-peek))
    (match
      ((null? tok) (%sh-rd-fail "parse error: expected ) in case"))
      ((%tok-is-word? tok)
        (do
          (%sh-rd-take)
          (%sh-rd-plan tok ())
          (%sh-rd-pattern-next self walk subject clauses (pair tok pats))))
      (#t (%sh-rd-fail "parse error: expected ) in case")))))

(def %sh-rd-pattern-next
  (fn (_ more walk subject clauses pats)
    (def tok (%sh-rd-peek))
    (match
      ((%sh-rd-op? tok "|") (do (%sh-rd-take) (more walk subject clauses pats)))
      ((%sh-rd-op? tok ")")
        (do (%sh-rd-take) (%sh-rd-clause-body walk subject clauses (reverse pats))))
      (#t (%sh-rd-fail "parse error: expected ) in case")))))

; A clause's body, which may be empty, and the `;;` or `esac` after it.
(def %sh-rd-clause-body
  (fn (_ walk subject clauses pats)
    (def body (%sh-rd-body))
    (def tok (%sh-rd-peek))
    (match
      ((null? body) ())
      ((%sh-rd-op? tok ";;")
        (do (%sh-rd-take) (walk subject (pair (list pats body) clauses))))
      ((%sh-rd-word? tok "esac")
        (do (%sh-rd-take)
            (list (lit case) subject (reverse (pair (list pats body) clauses)))))
      (#t (%sh-rd-expected "esac")))))

; --- The reading base ----------------------------------------------------------------

; A read handler's token, answered as it is inside a command, and at the start
; of one read on into the whole complete command.  A newline between commands
; is its own item.
(def %sh-rd-yield
  (fn (_ tok buf)
    (match
      ((= %sh-rd-depth 0) (%sh-rd-top tok buf))
      (#t tok))))

(def %sh-rd-top
  (fn (_ tok buf)
    (match
      ((%sh-rd-newline? tok) tok)
      (#t (do (set! %sh-rd-start (list tok buf))
              (%sh-base-eval %sh-rd-main %sh-rd-begin))))))

; A command is read in the evaluator's base, not the reading base a handler
; runs in: the engine's types an evaluation makes objects of are registered on
; the base it runs in, and on the reading base their analysers would try every
; token after.  Only `tok read` (%sh-rd-next) is evaluated in the reading base.
(def %sh-base-eval (prim-ref (lit base) (lit eval)))
(def %sh-rd-main (%base))
(def %sh-rd-start ())     ; the (TOK BUF) a command starts from
(def %sh-rd-begin (lit (%sh-rd-begun)))

(def %sh-rd-begun
  (fn (_)
    (%sh-rd-command (%sh-rd-own (first %sh-rd-start)) (first (rest %sh-rd-start)))))

(def %sh-rd-wrap
  (fn (_ read) (fn (_ . args) (%sh-rd-yield (apply read args) (first args)))))

; HANDLERS with their read handler wrapped.
(def %sh-rd-handlers
  (fn (self hs)
    (match
      ((null? hs) ())
      ((eq? (first (first hs)) (lit read))
        (pair (pair (lit read) (%sh-rd-wrap (rest (first hs)))) (rest hs)))
      (#t (pair (first hs) (self (rest hs)))))))

; TYPES, each (NAME . HANDLERS), with their read handlers wrapped.
(def %sh-rd-types
  (fn (_ types) (map (fn (_ t) (pair (first t) (%sh-rd-handlers (rest t)))) types)))

; The reading base for TYPES, each (NAME . HANDLERS), newest first: registered
; oldest first, as %sh-base-make registers the tokenizer's.
(def %sh-rd-base-make
  (fn (_ types)
    (def b (make-token-base))
    (%sh-rd-register b (%sh-rd-types types))
    b))

(def %sh-rd-register
  (fn (self b types)
    (match
      ((null? types) ())
      (#t (do (self b (rest types))
              (base-make-type b (first (first types)) (rest (first types))))))))

; The reading base, and the raw base a script is read through: the compiled
; one once the tokenizer's states are compiled (%sh-rd-adopt!), the
; interpreted one until then.  Made again after an image load, as the
; tokenizer's base is.
(def %sh-rd-base ())
(def %sh-rd-cbase ())
(def %sh-rd-raw-base ())

(def %sh-rd-reset!
  (fn (_)
    (set! %sh-rd-main (%base))
    (set! %sh-rd-base (%sh-rd-base-make (first %sh-tok-types)))
    (set! %sh-rd-cbase ())
    (set! %sh-rd-raw-base (Base raw-of %sh-rd-base))))
(%sh-rd-reset!)
(set! %image-transients
  (pair (lit %sh-rd-main) (pair (lit %sh-rd-base) (pair (lit %sh-rd-cbase)
    (pair (lit %sh-rd-raw-base) %image-transients)))))
(set! %image-recache-hooks (pair (fn (_) (%sh-rd-reset!)) %image-recache-hooks))

; The compiled reading base: the compiled tokenizer's ENTRIES under the
; reading base's read handlers.
(def %sh-rd-adopt!
  (fn (_ entries)
    (set! %sh-rd-cbase (%sh-jit-base (%sh-rd-types (first %sh-tok-types)) entries))
    (set! %sh-rd-raw-base (Base raw-of %sh-rd-cbase))))

(def %sh-rd-refused
  (fn (_)
    (set! %sh-rd-cbase ())
    (set! %sh-rd-raw-base (Base raw-of %sh-rd-base))))

; The items of TEXT (see the top of this file).
(def sh-read
  (fn (_ text)
    (%sh-jit-tick! (string-length text))
    (set! %sh-rd-depth 0)
    (%token-read-str %sh-rd-raw-base text)))

; The reading base TYPES make with each read handler wrapped by WRAP.
(def %sh-rd-base-make-with
  (fn (_ types wrap)
    (def b (make-token-base))
    (%sh-rd-register b
      (map (fn (_ t) (pair (first t) (%sh-rd-wrapped (rest t) wrap))) types))
    b))

(def %sh-rd-wrapped
  (fn (self hs wrap)
    (match
      ((null? hs) ())
      ((eq? (first (first hs)) (lit read))
        (pair (pair (lit read) (wrap (rest (first hs)))) (rest hs)))
      (#t (pair (first hs) (self (rest hs) wrap))))))
