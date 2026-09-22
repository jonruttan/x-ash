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

; $$ IS THIS PROCESS'S, and it is read once because it cannot change for the
; life of a shell.  That makes it exactly the kind of value a state image must
; not carry: the image is written by another process, and a shell booted from
; it would report the WRITER's pid for $$ forever.  Re-read after a load, the
; same way it is read here.
(def %sh-pid (sh-getpid))
(set! %image-transients (pair (lit %sh-pid) %image-transients))
(set! %image-recache-hooks
  (pair (fn (_) (set! %sh-pid (sh-getpid))) %image-recache-hooks))
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

; The digits of `2>err`, which the tokenizer reads apart from any other word
; because they run straight into a redirection operator.
(def %tok-is-io? (fn (_ tok) (eq? (first tok) (lit tok-io))))

; A reserved word is one only where the grammar can take one: `done` closes a
; loop in `echo x; done` and is an argument in `echo done`, and a quoted "done"
; is never one.  %sh-mark-keywords walks the tokens once, as they come from the
; tokenizer, and marks each bare word that stands where a reserved word is
; recognized; this reads the mark, so every later scan -- stop words, nesting,
; skipped branches -- agrees on which words are syntax.
(def %tok-is-keyword?
  (fn (_ tok)
    (if (eq? (first tok) (lit tok-word)) (not (null? (rest (rest tok)))) ())))

; The same mark on an operator: a paren the walk found where a case pattern
; stands, which closes no subshell and is counted by nothing.
(def %tok-pattern-paren?
  (fn (_ tok)
    (if (eq? (first tok) (lit tok-op)) (not (null? (rest (rest tok)))) ())))

; --- Reserved words, by position ---------------------------------------------
;
; A reserved word is recognized as the first word of a command, as the word
; after a reserved word other than `case`, `for` or `in`, as the `in` of a case
; and the `in` or `do` of a for, and as an `esac` where a case clause's pattern
; would start.  The walk's state is what the next token may be:
;
;   cmd           where any reserved word is one
;   arg           a word of a command already begun
;   target        the word a redirection names
;   for-name      the variable after `for`
;   for-list      after that variable, where `in` and `do` are reserved
;   case-subject  the word after `case`
;   case-in       after the subject, where `in` is reserved
;   pattern       where a clause's pattern starts, and `esac` may end the case
;   pattern-word  inside a pattern, before its `)`; after a `|` as well, so
;                 `a|esac)` is two patterns
(def %sh-redirect-ops (list "<" ">" ">>" "<<" "<<-" "<&" ">&" "<>" ">|"))

; Where a reserved word leaves the walk.  `for` and `case` wait for a name and
; a subject, and the words after `in` are a list; after any other reserved
; word, another may follow, as in `fi fi` or `} then`.
(def %sh-keyword-next
  (list (pair "for" (lit for-name)) (pair "case" (lit case-subject))
        (pair "in" (lit arg))))

(def %sh-for-list-words (list "in" "do"))

(def %sh-mark-reserved?
  (fn (_ val state)
    (match
      ((eq? state (lit cmd)) (%sh-word-in? val %sh-reserved-words))
      ((eq? state (lit for-list)) (%sh-word-in? val %sh-for-list-words))
      ((eq? state (lit case-in)) (string=? val "in"))
      ((eq? state (lit pattern)) (string=? val "esac"))
      (#t ()))))

(def %sh-mark-after-keyword
  (fn (_ val state)
    (if (eq? state (lit case-in))
      (lit pattern)
      (let ((next (%sh-table-get val %sh-keyword-next)))
        (if (null? next) (lit cmd) next)))))

(def %sh-mark-after-word
  (fn (_ state)
    (match
      ((eq? state (lit for-name)) (lit for-list))
      ((eq? state (lit case-subject)) (lit case-in))
      ((eq? state (lit pattern)) (lit pattern-word))
      ((eq? state (lit pattern-word)) (lit pattern-word))
      (#t (lit arg)))))

(def %sh-mark-after-op
  (fn (_ op state)
    (match
      ((%sh-word-in? op %sh-redirect-ops) (lit target))
      ((string=? op ";;") (lit pattern))
      ((eq? state (lit pattern)) (if (string=? op ")") (lit cmd) (lit pattern)))
      ((eq? state (lit pattern-word)) (if (string=? op "|") state (lit cmd)))
      (#t (lit cmd)))))

; A newline ends a command, but a for or a case may wait across one for its
; `in`, its `do` or its next pattern.
(def %sh-mark-after-newline
  (fn (_ state)
    (match
      ((eq? state (lit for-list)) state)
      ((eq? state (lit case-in)) state)
      ((eq? state (lit pattern)) state)
      (#t (lit cmd)))))

(def %sh-mark-keyword?
  (fn (_ tok state)
    (if (eq? (first tok) (lit tok-word))
      (%sh-mark-reserved? (first (rest tok)) state)
      ())))

; A case clause's parens are the case's: the `(` a pattern may open with and
; the `)` that ends one close no subshell, so they are marked here and the
; walks that count parens step over them.  Only where a pattern stands -- the
; `)` of `$(cmd)` inside a clause's body is a paren like any other.
(def %sh-mark-pattern-paren?
  (fn (_ op state)
    (and (or (string=? op "(") (string=? op ")"))
         (or (eq? state (lit pattern)) (eq? state (lit pattern-word))))))

; Answers the tokens in order, each word that stands where a reserved word is
; recognized, and each paren that belongs to a case pattern, given a third
; element, #t.
(def %sh-mark-walk
  (fn (self toks state acc)
    (match
      ((null? toks) (reverse acc))
      ((eq? (first (first toks)) (lit tok-newline))
        (self (rest toks) (%sh-mark-after-newline state) (pair (first toks) acc)))
      ((eq? (first (first toks)) (lit tok-op))
        (let ((op (first (rest (first toks)))))
          (self (rest toks) (%sh-mark-after-op op state)
                (pair (if (%sh-mark-pattern-paren? op state)
                        (list (lit tok-op) op #t)
                        (first toks))
                      acc))))
      ((%sh-mark-keyword? (first toks) state)
        (self (rest toks)
              (%sh-mark-after-keyword (first (rest (first toks))) state)
              (pair (list (lit tok-word) (first (rest (first toks))) #t) acc)))
      (#t (self (rest toks) (%sh-mark-after-word state)
                (pair (first toks) acc))))))

(def %sh-mark-keywords
  (fn (_ tokens) (%sh-mark-walk tokens (lit cmd) ())))

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

; --- Word sets --------------------------------------------------------------
;
; A set of words is a LIST of words.  Written as a chain of string=? it reads
; as logic when it is data, and every addition means editing the shape rather
; than the contents.
;
; A pair walk, not (List index-of): the tokenizer asks this of every word and
; the arithmetic parser of every operator at every precedence level, and the
; class method is tens of thousands of heap objects a call.  string=? is
; unchecked -- a nil argument crashes it -- so anything but a string is simply
; not in the set.
(def %sh-word-in?
  (fn (_ word words) (if (string? word) (%sh-word-walk word words) ())))

(def %sh-word-walk
  (fn (self word words)
    (match
      ((null? words) ())
      ((string=? word (first words)) #t)
      (#t (self word (rest words))))))

; A TABLE is an alist of (key . value) keyed by string; %sh-table-get is the
; only thing that knows that.  Dispatch throughout this file is a table plus
; this lookup, rather than a `match` welding each key to its handler -- so the
; set of keys and what they do stay one fact instead of two.
(def %sh-table-get
  (fn (self key table)
    (match
      ((null? table) ())
      ((string=? key (first (first table))) (rest (first table)))
      (#t (self key (rest table))))))

(def %sh-table-without
  (fn (self key table)
    (match
      ((null? table) ())
      ((string=? key (first (first table))) (rest table))
      (#t (pair (first table) (self key (rest table)))))))

; Every entry for KEY gone, for a table that may hold several.
(def %sh-table-without-all
  (fn (self key table)
    (match
      ((null? table) ())
      ((string=? key (first (first table))) (self key (rest table)))
      (#t (pair (first table) (self key (rest table)))))))

(def %sh-words-without
  (fn (self word words)
    (match
      ((null? words) ())
      ((string=? word (first words)) (rest words))
      (#t (pair (first words) (self word (rest words)))))))

; --- Shell variables ---------------------------------------------------------
;
; A variable is exported or it is not.  An exported one lives in the process
; environment, which is what a child is given; any other lives in %sh-vars, a
; table only this process reads.  A name is in one place at a time.  A name
; exported before it has a value is kept in %sh-export-marks, so that the value
; it gets later goes to the environment: `export x; x=1` exports 1.
;
; Both belong to this process, so a state image carries neither: each is a
; transient, and a shell that loads an image starts with them empty.
(def %sh-vars ())
(def %sh-export-marks ())
(set! %image-transients
  (pair (lit %sh-vars) (pair (lit %sh-export-marks) %image-transients)))

; The value of NAME, or () when it is unset.
(def %sh-var-get
  (fn (_ name)
    (do
      (def v (%sh-table-get name %sh-vars))
      (if (null? v) (sh-getenv name) v))))

(def %sh-var-exported?
  (fn (_ name)
    (match
      ((not (null? (sh-getenv name))) #t)
      ((%sh-word-in? name %sh-export-marks) #t)
      (#t ()))))

; The names `readonly` has marked.  The mark belongs to this process, as the
; variables do, so a state image carries none.
(def %sh-readonly-names ())
(set! %image-transients (pair (lit %sh-readonly-names) %image-transients))

(def %sh-readonly? (fn (_ name) (%sh-word-in? name %sh-readonly-names)))

; An assignment to a marked name, or an unset of one, is refused here.  POSIX
; makes it an error of the special builtin that tried it, which ends a shell
; that is not interactive: the raise does that, and %sh-report says nothing
; more, the refusal having been written here.
(def %sh-readonly-refuse
  (fn (_ name)
    (do (%stderr "ash: " name ": is read only\n") (error (lit %sh-reported)))))

; Assign NAME where it already lives: the environment when it is exported,
; the table otherwise.  Under `set -a` every name assigned is exported, so one
; the table holds moves out of it.
(def %sh-var-set!
  (fn (_ name value)
    (when (%sh-readonly? name) (%sh-readonly-refuse name))
    (match
      ((%sh-var-exported? name)
        (do
          (set! %sh-export-marks (%sh-words-without name %sh-export-marks))
          (sh-setenv name value)))
      ((null? %sh-opt-allexport)
        (set! %sh-vars (pair (pair name value) (%sh-table-without name %sh-vars))))
      (#t
        (do
          (set! %sh-vars (%sh-table-without name %sh-vars))
          (sh-setenv name value))))))

; Unset NAME everywhere, the export attribute included.
(def %sh-var-unset!
  (fn (_ name)
    (when (%sh-readonly? name) (%sh-readonly-refuse name))
    (set! %sh-vars (%sh-table-without name %sh-vars))
    (set! %sh-export-marks (%sh-words-without name %sh-export-marks))
    (sh-unsetenv name)))

; --- Variables that belong to a call ----------------------------------------
;
; `local x` inside a function gives x a value for the call and puts the old
; one back when the call ends.  %sh-call-fn pushes a frame for each call and
; pops it on the way out, and `local` records a name's whole state there --
; its value, and whether it was exported -- before changing it.
;
; The scope is dynamic: a function called from this one sees the local, which
; is what every shell that has `local` does.
;
; A name is saved every time it is named, and the frame is restored
; front-to-back, so the oldest state recorded is the one applied last.  Two
; `local x` in one call need no lookup to sort out.
;
; The frame belongs to this process, as the variables do, so no state image
; carries one.
(def %sh-locals ())
(set! %image-transients (pair (lit %sh-locals) %image-transients))

(def %sh-var-state
  (fn (_ name)
    (let ((v (%sh-var-get name)))
      (if (null? v) () (pair v (%sh-var-exported? name))))))

(def %sh-local-save!
  (fn (_ name)
    (when (%sh-readonly? name) (%sh-readonly-refuse name))
    (set! %sh-locals
      (pair (pair (pair name (%sh-var-state name)) (first %sh-locals))
            (rest %sh-locals)))))

(def %sh-var-restore!
  (fn (_ entry)
    (let ((name (first entry)) (state (rest entry)))
      ; A `readonly` on a local is the call's too: the name carried no mark
      ; when it was saved, so it carries none afterwards.
      (set! %sh-readonly-names (%sh-words-without name %sh-readonly-names))
      (%sh-var-unset! name)
      (unless (null? state)
        (%sh-var-set! name (first state))
        (when (rest state) (%sh-var-export! name))))))

(def %sh-restore-frame
  (fn (self frame)
    (unless (null? frame)
      (%sh-var-restore! (first frame))
      (self (rest frame)))))

(def %sh-push-locals!
  (fn (_) (set! %sh-locals (pair () %sh-locals))))

(def %sh-pop-locals!
  (fn (_)
    (let ((frame (first %sh-locals)))
      (set! %sh-locals (rest %sh-locals))
      (%sh-restore-frame frame))))

; Give NAME the export attribute: a value it holds in the table moves to the
; environment, and a name with no value is marked.
(def %sh-var-export!
  (fn (_ name)
    (let ((v (%sh-table-get name %sh-vars)))
      (match
        ((not (null? v))
          (do
            (set! %sh-vars (%sh-table-without name %sh-vars))
            (sh-setenv name v)))
        ((%sh-var-exported? name) ())
        (#t (set! %sh-export-marks (pair name %sh-export-marks)))))))

(def %sh-reserved-words
  (list "if" "then" "elif" "else" "fi"
        "while" "until" "for" "do" "done"
        "case" "in" "esac" "!" "{" "}"))

; The reserved words that close a construct, and so end the command list in
; front of them: `then` ends a condition, `done` a loop body.  The rest open
; one or, like `in` and `!`, stand inside one.
(def %sh-closing-words
  (list "then" "elif" "else" "fi" "do" "done" "esac" "}"))

; The operators that end a command list the same way a closing word does.
(def %sh-stop-ops (list ")" ";;"))

; What nests, for the skip walks: every compound opens with one of these and
; closes with one of those, and the skippers count depth with them. `{` and
; `}` are included because a `;` inside a brace group belongs to the group, and
; `f() { ...; }` balances the same pair.
(def %sh-block-openers (list "if" "while" "until" "for" "case" "{"))
(def %sh-block-closers (list "fi" "done" "esac" "}"))

(def %reserved-word?
  (fn (_ word) (%sh-word-in? word %sh-reserved-words)))
; %sh-compound-depth is how deep inside a compound the parser is. `done` closes
; something only when something is open, so at the top level it is an ordinary
; word. It is bumped for the whole of any compound (see %eval-compound), so the
; closers keep their power exactly where a construct waits for them.
(def %sh-compound-depth 0)

(def %closing-word?
  (fn (_ word)
    (if (= %sh-compound-depth 0)
      ()
      (%sh-word-in? word %sh-closing-words))))

; --- Stop-word helper ---

(def %at-stop-word?
  (fn (_ cur)
    (if (%cursor-empty? cur)
      #t
      (let ((tok (%cursor-peek cur)))
        (cond
          ; The word branch is gated on the compound depth (see
          ; %closing-word?); the OP branch is not -- `)` and `;;` are
          ; punctuation, never words a script means literally.
          ((%tok-is-keyword? tok) (%closing-word? (first (rest tok))))
          ((eq? (first tok) (lit tok-op))
            (%sh-word-in? (first (rest tok)) %sh-stop-ops))
          (else ()))))))

; Nothing may be left unread.  A parser that evaluates as it reads stops in
; front of a token it cannot take -- a word after `fi`, a `)` that closes
; nothing -- and what follows it would never run: POSIX makes that a syntax
; error, where saying nothing turns a typo into a script that quietly ends
; halfway.  Every bounded run of tokens is checked as it finishes: a pipeline
; stage, a subshell body, a function body, and the whole input.
(def %sh-refuse-leftover
  (fn (_ cur)
    (unless (%cursor-empty? cur)
      (let ((tok (%cursor-peek cur)))
        (error (string-append "parse error: unexpected "
                              (if (%tok-is-newline? tok)
                                "newline"
                                (%tok-word-val tok))))))))

; A body of its own -- a subshell's, a function's -- read to its end.  The
; status is the shell's, which the commands in the body have set.
(def %sh-eval-body
  (fn (_ body)
    (unless (null? body)
      (let ((cur (%mk-cursor body)))
        (%eval-list cur)
        (%sh-refuse-leftover cur)))))

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

; Expansion walks the whole word, not just a leading $. What it understands:
;   $NAME     a name is [A-Za-z_][A-Za-z0-9_]*, ending at the first character
;             that is not one -- which is what makes `pre$X.txt` work
;   ${NAME}   the braces delimit, for the cases where the run would not end
;             where you meant it to
;   $?  $$    the last status and the shell's pid
;   $         anything else -- a literal dollar, as in `echo 50$`
;
; An unset variable expands to the empty string unless `set -u` is on.

; %sh-digit? is tokens.x's.  These classify characters out of string-ref, so
; they compare with the unchecked integer door -- see ash/prims.x.
(def %sh-name-start?
  (fn (_ c)
    (match
      ((fx<? c #\A) ())
      ((not (fx<? #\Z c)) #t)
      ((= c #\_) #t)
      ((fx<? c #\a) ())
      (#t (not (fx<? #\z c))))))

(def %sh-name-char?
  (fn (_ c) (match ((%sh-name-start? c) #t) (#t (%sh-digit? c)))))

; Is WORD a NAME: a letter or underscore, then letters, digits and
; underscores?  What every variable and function is called.
(def %sh-name?
  (fn (_ word)
    (match
      ((= (string-length word) 0) ())
      ((%sh-name-start? (string-ref word 0))
        (= (%sh-name-end word 1 (string-length word)) (string-length word)))
      (#t ()))))

(def %sh-bad-name
  (fn (_ who name) (%stderr "ash: " who ": " name ": bad variable name\n")))

; A word a special builtin -- `export`, `readonly`, `unset` -- was to take as
; a name, refused when it is not one.  POSIX ends a script over a special
; builtin's error: the raise does, the report being written here.
(def %sh-name-or-refuse!
  (fn (_ who name)
    (unless (%sh-name? name)
      (do (%sh-bad-name who name) (error (lit %sh-reported))))))

; `set -u`: expanding an unset parameter is an error -- `$X`, `${X}` and
; `${#X}`, a name, a positional past the last, or `$!` before any list has run
; in the background.  `$@` and `$*` never are.  `${X:-default}` and `${X+alt}`
; exist precisely to ask about an unset parameter, and POSIX exempts them, so
; they go through %sh-var-value directly.
(def %sh-var-value-checked
  (fn (_ name)
    (match
      ((null? %sh-opt-nounset) (%sh-var-value name))
      ((%sh-param-unset? name) (error (string-append name ": parameter not set")))
      (#t (%sh-var-value name)))))

; --- Positional parameters and the function table ---------------------------
;
; %sh-args holds $1 upward, as a plain list of strings.  It is SAVED AND
; RESTORED around a function call rather than being a stack: a shell function's
; parameters are dynamically scoped to the call, which is exactly what
; save/restore expresses, and nothing here is re-entrant in a way a list of
; frames would help with.
; --- Shell options ----------------------------------------------------------
;
; `set -e` exit on a failed command, `-u` treat an unset parameter as an error,
; `-x` trace commands to stderr, `-a` export every variable assigned, `-C`
; refuse `>` over a regular file, `-o pipefail` fail a pipeline when any stage
; fails.  `set +e` and friends turn them off, which is why each is a cell
; rather than a flag set once.
(def %sh-opt-errexit ())
(def %sh-opt-nounset ())
(def %sh-opt-xtrace ())
(def %sh-opt-noglob ())
(def %sh-opt-allexport ())
(def %sh-opt-noclobber ())
(def %sh-opt-pipefail ())

; errexit must not fire in a condition. `if false; then`, `false || echo`,
; `! cmd` and a `while` test all run commands whose failure is the point; POSIX
; exempts those contexts, and %sh-should-exit? asks whether any is open.
(def %sh-cond-depth 0)

(def %sh-in-condition
  (fn (_ thunk)
    (set! %sh-cond-depth (+ %sh-cond-depth 1))
    (guard (e (do (set! %sh-cond-depth (- %sh-cond-depth 1)) (error e)))
      (let ((r (thunk)))
        (set! %sh-cond-depth (- %sh-cond-depth 1))
        r))))

(def %sh-should-exit?
  (fn (_ status)
    (and %sh-opt-errexit (and (not (= status 0)) (= %sh-cond-depth 0)))))

(def %sh-args ())
(def %sh-functions ())
(def %sh-fn-depth 0)
(def %sh-dot-depth 0)
(def %sh-return-status 0)

(def %sh-join-with
  (fn (self args sep)
    (if (null? args)
      ""
      (if (null? (rest args))
        (first args)
        (string-append (first args)
          (string-append sep (self (rest args) sep)))))))

; `set -x` echoes the command as a person would have typed it, so it joins
; with a space whatever IFS happens to be.
(def %sh-join-args (fn (_ args) (%sh-join-with args " ")))

; WHAT GOES BETWEEN THE PARAMETERS in `$*`: the first character of IFS, and
; nothing at all when IFS is empty -- `IFS=:` makes `"$*"` `a:b:c`, `IFS=`
; makes it `abc`.  An unset IFS is a space because %sh-ifs answers the
; default.  Only the first character is used, however many IFS holds.
(def %sh-ifs-join-char
  (fn (_)
    (let ((ifs (%sh-ifs)))
      (if (= (string-length ifs) 0) "" (substring ifs 0 1)))))

(def %sh-join-params (fn (_ args) (%sh-join-with args (%sh-ifs-join-char))))

; $0 is the shell itself; $1 upward index into %sh-args.  Out of range is the
; empty string, which is POSIX and is what `test -z "$1"` relies on.
(def %sh-arg-at
  (fn (_ n)
    (if (= n 0)
      "ash"
      (if (> n (length %sh-args))
        ""
        (nth (- n 1) %sh-args)))))

; The variables whose name is punctuation.  Thunks, because each is a question
; about the shell's current state rather than a stored value.
(def %sh-special-vars
  (list (pair "?" (fn (_) (convert %sh-status %string)))
        (pair "$" (fn (_) (convert %sh-pid %string)))
        (pair "!" (fn (_) (if (null? %sh-bg-pid) "" (convert %sh-bg-pid %string))))
        (pair "-" (fn (_) (%sh-flags)))
        (pair "#" (fn (_) (convert (length %sh-args) %string)))
        ; $@ AND $* ARE THE SAME STRING ONLY HERE.  Quoted, they are not the
        ; same thing at all: `"$@"` is one field per parameter and never
        ; reaches this table -- %sh-expand-dollar answers it directly, because
        ; a table of strings cannot say "several fields".  What is left for
        ; both to share is the unquoted reading, where the string is built
        ; and then split again, and the JOIN is on IFS either way.
        (pair "@" (fn (_) (%sh-join-params %sh-args)))
        (pair "*" (fn (_) (%sh-join-params %sh-args)))))

(def %sh-var-value
  (fn (_ name)
    (do
      ; A name that begins with a letter or underscore is a variable's: no
      ; special's name does, so the table is not asked.
      (def special
        (match
          ((not (fx<? 0 (string-length name))) ())
          ((%sh-name-start? (string-ref name 0)) ())
          (#t (%sh-table-get name %sh-special-vars))))
      (match
        ((not (null? special)) (special))
        ((%all-digits? name) (%sh-arg-at (%sh-digits-int name)))
        ; An unset variable expands to the empty string, which is POSIX
        ; default -- there is no `set -u` here to make it an error.
        (#t (do (def v (%sh-var-get name)) (if (null? v) "" v)))))))

; The end of the name run starting at I.
(def %sh-name-end
  (fn (self s i n)
    (match
      ((not (fx<? i n)) i)
      ((%sh-name-char? (string-ref s i)) (self s (fx+ i 1) n))
      (#t i))))

; The index of the closing brace at or after I, or -1.
; The `}` closing a `${` opened before I, or -1.  Depth-aware, so a default
; that is itself an expansion -- `${X:-${Y}}` -- closes where it should.
(def %sh-brace-end
  (fn (self s i n depth)
    (if (not (fx<? i n))
      (- 0 1)
      (do
        (def c (string-ref s i))
        (match
          ((= c #\{) (self s (fx+ i 1) n (fx+ depth 1)))
          ((= c #\}) (if (= depth 0) i (self s (fx+ i 1) n (fx+ depth -1))))
          ; A backslash and a quoted string hide a brace, as they do in
          ; %sh-cs-end and in the tokenizer's reading of the same text:
          ; `${x:-\}}` and `${x:-"}"}` each close at the last brace.
          ((= c #\\) (self s (fx+ i 2) n depth))
          ((= c #\') (self s (%sh-skip-quoted s (fx+ i 1) n #\') n depth))
          ((= c #\") (self s (%sh-skip-quoted s (fx+ i 1) n #\") n depth))
          (#t (self s (fx+ i 1) n depth)))))))

; Inside double quotes a backslash is literal EXCEPT before one of $ ` " \ and
; newline -- so `"a\db"` keeps its backslash and `"a\$b"` does not.  Outside
; quotes a backslash escapes whatever follows it.
(def %sh-dq-escapable?
  (fn (_ c)
    (or (= c #\$) (= c #\`) (= c #\")
        (= c #\\) (= c #\newline))))

; Quoting is a property of regions within a word, not of the word. `X="a b"`
; arrives as one word token whose raw text still carries its quotes (see
; %sh-word-body in tokens.x), and `pre'lit'$X` is three regions. So the walk
; carries a mode:
;
;   0  unquoted   quotes open regions, backslash escapes anything, $ expands
;   1  '...'      everything literal until the closing quote
;   2  "..."      $ expands, backslash escapes only the POSIX five
;
; A tok-word starts in mode 0; a tok-dq starts in mode 2 (its outer quotes were
; stripped by the reader); a tok-sq never reaches here. The mode-switching
; quote characters are not emitted, which is what removes them from the field.
; --- Command substitution ----------------------------------------------------
;
; `$(...)` and the older backtick form run the text as a shell script in a
; child whose stdout is a pipe, and answer what it printed with trailing
; newlines removed.
;
; The status is not propagated: expansion happens while the command's words are
; collected, and %sh-run-cmd overwrites %sh-status with the command's own
; status afterwards. So `echo $(false)` reports echo's 0, and
; `X=$(false); echo $?` reports 0 where a POSIX shell says 1.

; The index of the `)` closing a substitution opened before I, or -1.  Quoted
; regions and escaped characters hide their parens, matching the tokenizer's
; own scan.
(def %sh-skip-quoted
  (fn (self s i n q)
    (if (>= i n)
      i
      (let ((c (string-ref s i)))
        (if (and (= q #\") (= c #\\))
          (self s (+ i 2) n q)
          (if (= c q) (+ i 1) (self s (+ i 1) n q)))))))

(def %sh-cs-end
  (fn (self s i n depth)
    (if (>= i n)
      (- 0 1)
      (let ((c (string-ref s i)))
        (match
          ((= c #\() (self s (+ i 1) n (+ depth 1)))
          ((= c #\)) (if (= depth 0) i (self s (+ i 1) n (- depth 1))))
          ((= c #\')
            (self s (%sh-skip-quoted s (+ i 1) n #\') n depth))
          ((= c #\")
            (self s (%sh-skip-quoted s (+ i 1) n #\") n depth))
          ((= c #\\) (self s (+ i 2) n depth))
          (#t (self s (+ i 1) n depth)))))))

; The index of the closing backtick, or -1.  A backslash escapes one character.
(def %sh-bt-end
  (fn (self s i n)
    (if (>= i n)
      (- 0 1)
      (let ((c (string-ref s i)))
        (if (= c #\\)
          (self s (+ i 2) n)
          (if (= c #\`) i (self s (+ i 1) n)))))))

; Inside backquotes a backslash keeps its literal meaning except before `$`, a
; backquote or another backslash, where POSIX takes it off before the command
; runs: that is what lets `\`` open a substitution inside one, and `\$` pass
; a `$` for the inner command to expand.
(def %sh-bt-escapable?
  (fn (_ c) (match ((= c #\$) #t) ((= c #\`) #t) (#t (= c #\\)))))

(def %sh-bt-unescape-from
  (fn (self s i n start pieces)
    (match
      ((fx<? (fx+ i 1) n)
        (match
          ((= (string-ref s i) #\\)
            (if (%sh-bt-escapable? (string-ref s (fx+ i 1)))
              (self s (fx+ i 2) n (fx+ i 2)
                (pair (substring s (fx+ i 1) (fx+ i 2))
                      (pair (substring s start i) pieces)))
              (self s (fx+ i 2) n start pieces)))
          (#t (self s (fx+ i 1) n start pieces))))
      (#t (%ash-join "" (reverse (pair (substring s start n) pieces)))))))

(def %sh-bt-unescape
  (fn (_ text)
    (if (%sh-has-backslash? text)
      (%sh-bt-unescape-from text 0 (string-length text) 0 ())
      text)))

; Trailing newlines come off, and only trailing ones -- `$(printf 'a\n\nb\n')`
; keeps the blank line in the middle.
(def %sh-rstrip-newlines
  (fn (_ out)
    (def back
      (fn (self e)
        (if (= e 0)
          0
          (if (= (string-ref out (- e 1)) #\newline)
            (self (- e 1))
            e))))
    (let ((e (back (string-length out))))
      (if (= e (string-length out)) out (substring out 0 e)))))

; The exit status of the last command substitution the command being expanded
; has performed, or () while it has performed none.  A command with no command
; name completes with it, which is what makes `if out=$(cmd)` test cmd.
(def %sh-subst-status ())

(def %sh-cmd-subst
  (fn (_ src)
    (let ((p (%sh-pipe-create)))
      (let ((read-fd (first p)) (write-fd (rest p)))
        (let ((pid (sh-fork)))
          (if (= pid 0)
            (do
              (sh-close read-fd)
              (%sh-move-fd write-fd 1)
              ; The substituted text is its own script, so it starts at the
              ; top level however deep the expansion was reached from -- with
              ; no traps, which a subshell does not inherit, and outside any
              ; condition: `v=$(false; echo x) || true` still stops at the
              ; `false` under -e, in dash and bash alike.
              (set! %sh-compound-depth 0)
              (set! %sh-cond-depth 0)
              (set! %sh-traps ())
              ; A failing substitution answers what it managed to print, the
              ; way a shell does, and its error goes to stderr.
              (%sh-in-child
                (fn (_) (do (sh-eval-extracted src) %sh-status))))
            ; Read before wait: a child whose output exceeds the pipe buffer
            ; blocks in write() until someone drains it, so waiting first would
            ; deadlock on any substitution larger than a pipe.
            (do
              (sh-close write-fd)
              (let ((out (sh-read-all-fd read-fd)))
                (sh-close read-fd)
                (set! %sh-subst-status (sh-wait pid))
                (%sh-rstrip-newlines out)))))))))

; --- FIELD SPLITTING -------------------------------------------------------
;
; The expander answers a list of fields, not a string. A word is split on
; whitespace after it expands, and only the expanded part is split:
;
;   X="a b"; cmd $X          two arguments
;   X="a b"; cmd "$X"        one
;   for f in $(cat list)     once per line, not once for the whole file
;   cmd $EMPTY               no argument at all
;   cmd "$EMPTY"             one empty argument
;
; The walker carries (fields cur started). `started` separates "an empty field"
; from "no field": literal text and quote marks set it, expanded text sets it
; only for the characters it contributes -- which is why `cmd "$EMPTY"` yields
; an empty argument and `cmd $EMPTY` yields none.

(def %sh-ws-char?
  (fn (_ c) (or (= c #\space) (= c #\tab) (= c #\newline))))

; The non-empty runs between whitespace, in order.
; --- IFS ---------------------------------------------------------------------
;
; POSIX gives IFS two kinds of character:
;
;   whitespace in IFS   a run of them is one delimiter; a leading or trailing
;                       run produces no field, so `a  b` is two fields
;   anything else       each occurrence delimits, so adjacent ones make empty
;                       fields: IFS=: over `a::b` is three
;
; A non-whitespace delimiter may have IFS whitespace either side, which belongs
; to it. IFS set but empty means no splitting at all.

(def %sh-ifs-default " \t\n")

; A shell starts with IFS set to that, whatever the environment held: POSIX
; lets a shell ignore an inherited IFS, and dash and bash both do.  So `$IFS`
; has a value to save, and `old=$IFS; IFS=:; ...; IFS=$old` puts splitting
; back.  It is an ordinary assignment, so IFS stays unexported unless the
; environment handed one in.  An image is written by another process, so a
; process that loads one sets it again, the way $$ is read again.
(%sh-var-set! "IFS" %sh-ifs-default)
(set! %image-recache-hooks
  (pair (fn (_) (%sh-var-set! "IFS" %sh-ifs-default)) %image-recache-hooks))

; The prompts are shell variables with POSIX's defaults: PS1 before each
; command, `# ` for the superuser and `$ ` for anyone else; PS2 before each line
; that continues one; PS4 before each line `set -x` writes.  A value the
; environment hands in is kept, and like IFS they are set again in a process
; that loads an image.
(def %sh-prompt-defaults!
  (fn (_)
    (do
      (when (null? (%sh-var-get "PS1"))
        (%sh-var-set! "PS1" (if (= (Sys geteuid) 0) "# " "$ ")))
      (when (null? (%sh-var-get "PS2")) (%sh-var-set! "PS2" "> "))
      (when (null? (%sh-var-get "PS4")) (%sh-var-set! "PS4" "+ ")))))
(%sh-prompt-defaults!)
(set! %image-recache-hooks
  (pair (fn (_) (%sh-prompt-defaults!)) %image-recache-hooks))

; What a prompt variable shows: its value expanded as double-quoted text is,
; each time it is shown, or nothing when it is unset.  The expansion runs with
; tracing off, so a substitution in PS4 is not itself traced -- which would
; expand PS4 again -- and a value that fails to expand is shown as written, so
; a bad PS1 cannot stop the shell from reading.
(def %sh-prompt
  (fn (_ name)
    (let ((v (%sh-var-get name)) (trace %sh-opt-xtrace))
      (if (null? v)
        ""
        (do
          (set! %sh-opt-xtrace ())
          (let ((text (guard (e v) (%sh-expand-str-dq v))))
            (set! %sh-opt-xtrace trace)
            text))))))

(def %sh-ifs
  (fn (_)
    (let ((v (%sh-var-get "IFS")))
      (if (null? v) %sh-ifs-default v))))

(def %sh-in-ifs? (fn (_ c ifs) (%sh-str-has-char? ifs c)))

(def %sh-str-has-char?
  (fn (_ text c) (%sh-has-char-from? text c 0 (string-length text))))

; Whether TEXT holds C at I or after, before N.
(def %sh-has-char-from?
  (fn (self text c i n)
    (match
      ((not (fx<? i n)) ())
      ((= (string-ref text i) c) #t)
      (#t (self text c (fx+ i 1) n)))))

; Whether TEXT holds an IFS character at I or after, before N.
(def %sh-has-ifs-from?
  (fn (self text ifs i n)
    (match
      ((not (fx<? i n)) ())
      ((%sh-in-ifs? (string-ref text i) ifs) #t)
      (#t (self text ifs (fx+ i 1) n)))))

; How far a run of IFS WHITESPACE reaches from I.
(def %sh-ifs-ws-end
  (fn (self text i n ifs)
    (if (and (< i n)
             (and (%sh-ws-char? (string-ref text i))
                  (%sh-in-ifs? (string-ref text i) ifs)))
      (self text (+ i 1) n ifs)
      i)))

; The fields of TEXT, N long, which holds a character of IFS.  A leading run
; of IFS whitespace is skipped rather than delimiting.
(def %sh-ifs-split
  (fn (_ text n ifs)
    (do
      (def i (%sh-ifs-ws-end text 0 n ifs))
      (%sh-ifs-fields text i n ifs i () ()))))

; The fields of TEXT from I, walked by index: FROM is where the field in hand
; began, and a field is cut out once, when it ends.  STARTED? is whether one is
; in hand, which an empty field between two non-whitespace delimiters is.
(def %sh-ifs-fields
  (fn (self text i n ifs from started? acc)
    (match
      ((not (fx<? i n))
        (reverse (if started? (pair (substring text from n) acc) acc)))
      ((not (%sh-in-ifs? (string-ref text i) ifs))
        (self text (fx+ i 1) n ifs (if started? from i) #t acc))
      ; A delimiter.  Take any IFS whitespace around it, and at most ONE
      ; non-whitespace delimiter with it.
      (#t
        (let ((after-ws (%sh-ifs-ws-end text i n ifs)))
          (let ((hard? (%sh-ifs-hard-at? text after-ws n ifs)))
            (let ((j (%sh-ifs-ws-end text (if hard? (fx+ after-ws 1) after-ws)
                                     n ifs)))
              ; A whitespace-only delimiter never makes an empty field; a
              ; non-whitespace one does.
              (if (if hard? #t started?)
                (self text j n ifs j (if hard? (fx<? j n) ())
                      (pair (substring text from i) acc))
                (self text j n ifs j () acc)))))))))

; Whether an IFS character that is not whitespace stands at I.
(def %sh-ifs-hard-at?
  (fn (_ text i n ifs)
    (match
      ((not (fx<? i n)) ())
      ((%sh-ws-char? (string-ref text i)) ())
      (#t (%sh-in-ifs? (string-ref text i) ifs)))))

; --- The word being built ---------------------------------------------------
;
; Three values travel through the expansion walk: the fields finished so far
; (reversed), the field currently being built, and whether anything has started
; it. A named constructor and accessors carry them, so no caller depends on the
; list layout.
;
; The field in hand is a list of pieces, not a string: pieces are pushed in
; reverse and joined once, when the field closes, so building an n-character
; word is one cons per character rather than a fresh copy each time.
;
; --- A finished field -------------------------------------------------------
;
; A field is its text plus two things pathname expansion would otherwise
; re-derive by scanning it: whether it holds a live wildcard (so it is a
; pattern) and whether it holds an escape this walk wrote (so the literal text
; differs from the text in hand). The walk knows both as it writes.
; first/rest chains, not (nth n): nth is (List ref), a class dispatch that
; costs far more heap than a raw pair walk for the same reach.
(def %sh-field (fn (_ text glob? esc?) (list text glob? esc?)))
(def %sh-field-text  (fn (_ f) (first f)))
(def %sh-field-glob? (fn (_ f) (first (rest f))))
(def %sh-field-esc?  (fn (_ f) (first (rest (rest f)))))

; The field as the user wrote it: escapes off, and only if this walk put any
; there.  A backslash that ARRIVED in the text -- out of a variable's value --
; is not an escape and is not touched, which is the difference `x='a\*b'`
; showed: unescaping unconditionally ate it.
(def %sh-field-plain
  (fn (_ f)
    (if (%sh-field-esc? f)
      (%sh-glob-unescape (%sh-field-text f))
      (%sh-field-text f))))

(def %sh-acc (fn (_ fields pieces started glob? esc?)
               (list fields pieces started glob? esc?)))
(def %sh-acc-fields  (fn (_ a) (first a)))
(def %sh-acc-pieces  (fn (_ a) (first (rest a))))
(def %sh-acc-started (fn (_ a) (first (rest (rest a)))))
(def %sh-acc-glob?   (fn (_ a) (first (rest (rest (rest a))))))
(def %sh-acc-esc?    (fn (_ a) (first (rest (rest (rest (rest a)))))))

(def %sh-acc-empty (%sh-acc () () () () ()))

; The field in hand, materialized.  Only the two closers below need it.
(def %sh-acc-cur
  (fn (_ a) (%ash-join "" (reverse (%sh-acc-pieces a)))))

; One piece, and what it contributes to the field in hand.  Anything literal
; starts a field, which is what makes `cmd ""` an empty argument.  Both flags
; are sticky: one wildcard anywhere makes the whole field a pattern.
(def %sh-acc-add-piece
  (fn (_ a text glob? esc?)
    (%sh-acc (%sh-acc-fields a)
             (pair text (%sh-acc-pieces a))
             #t
             (or (%sh-acc-glob? a) glob?)
             (or (%sh-acc-esc? a) esc?))))

; Bare text: its metacharacters are live, so META? is what makes the field a
; pattern, and nothing here is escaped.
(def %sh-acc-add
  (fn (_ a text meta?) (%sh-acc-add-piece a text meta? ())))

; Quoted or escaped text: its metacharacters go in ESCAPED, so they make no
; pattern -- and the escape is what the field will have to walk back off.
(def %sh-acc-add-literal
  (fn (_ a text meta?)
    (%sh-acc-add-piece a
      (if meta? (%sh-glob-escape-all text) text)
      ()
      meta?)))

; An unquoted expansion's result: its wildcards are live (`X='*'; echo $X`
; globs), but a backslash in a value is an ordinary character, not an escape.
; The glob machinery reads a backslash as an escape, so a literal one goes in
; doubled and %sh-field-plain takes it back off.
(def %sh-acc-add-value
  (fn (_ a text)
    (if (%sh-has-glob-inert? text)
      (%sh-acc-add-piece a
        (%sh-escape-chars text %sh-glob-inert)
        (%sh-has-active-glob? text)
        #t)
      (%sh-acc-add a text (%sh-has-active-glob? text)))))

; Take the mark back off: the field in hand is not a field after all.  Only
; "$@" with no positional parameters needs this -- see %sh-add-args.
(def %sh-acc-unstart
  (fn (_ a) (%sh-acc (%sh-acc-fields a) (%sh-acc-pieces a) ()
                     (%sh-acc-glob? a) (%sh-acc-esc? a))))

; Mark the field open without adding to it -- what a quote mark does.
(def %sh-acc-open
  (fn (_ a) (%sh-acc (%sh-acc-fields a) (%sh-acc-pieces a) #t
                     (%sh-acc-glob? a) (%sh-acc-esc? a))))

; The field in hand, as a field.
(def %sh-acc-field
  (fn (_ a) (%sh-field (%sh-acc-cur a) (%sh-acc-glob? a) (%sh-acc-esc? a))))

; Close the field in hand and begin the next one -- which starts clean, so the
; flags do not leak from one field of a word into the next.
(def %sh-acc-break
  (fn (_ a)
    (%sh-acc (pair (%sh-acc-field a) (%sh-acc-fields a)) () () () ())))

; Close the word: the field in hand becomes one iff anything started it.
(def %sh-acc-finish
  (fn (_ a)
    (reverse
      (if (%sh-acc-started a)
        (pair (%sh-acc-field a) (%sh-acc-fields a))
        (%sh-acc-fields a)))))

; --- Keeping quoted glob characters literal ---------------------------------
;
; Pathname expansion happens after the word is built, by which point `"*"` and
; `*` are the same character, so the accumulator carries the difference as a
; backslash: quoted or escaped text goes in with its glob metacharacters
; escaped, the notation %sh-glob-at understands and %sh-glob-unescape removes.
; A backslash is escaped too, so the unescape is exact.
; A metacharacter must be escaped to survive as itself; an active one is a
; wildcard. Every metacharacter is active but the backslash, so the active set
; is written as that subtraction rather than a second list to keep in step.
(def %sh-glob-meta (list #\* #\? #\[ #\\))
(def %sh-glob-active (filter (fn (_ c) (not (= c #\\))) %sh-glob-meta))

(def %sh-char-in?
  (fn (self c chars)
    (match
      ((null? chars) ())
      ((= c (first chars)) #t)
      (#t (self c (rest chars))))))

; The rest of that set: metacharacters that are not wildcards -- the backslash,
; and anything that ever joins it.  BELOW %sh-char-in? ON PURPOSE: these three
; are values computed as this file loads, not function bodies resolved when
; called, so a name they use has to already exist.
(def %sh-glob-inert
  (filter (fn (_ c) (not (%sh-char-in? c %sh-glob-active))) %sh-glob-meta))

; Scan first, build only if needed: text out of an expansion has not been
; through the walk, so it is the one thing still worth scanning -- for escaping
; if it goes in quoted, or for a pattern if bare.  The scan runs per character
; of every value, so it steps on the integer doors.
(def %sh-has-char-in?
  (fn (_ text chars) (%sh-has-char-in-from? text chars 0 (string-length text))))

; Whether TEXT holds one of CHARS at I or after, before N.
(def %sh-has-char-in-from?
  (fn (self text chars i n)
    (match
      ((not (fx<? i n)) ())
      ((%sh-char-in? (string-ref text i) chars) #t)
      (#t (self text chars (fx+ i 1) n)))))

(def %sh-has-glob-meta? (fn (_ text) (%sh-has-char-in? text %sh-glob-meta)))
(def %sh-has-active-glob? (fn (_ text) (%sh-has-char-in? text %sh-glob-active)))
(def %sh-has-glob-inert? (fn (_ text) (%sh-has-char-in? text %sh-glob-inert)))

; Build with every character of CHARS escaped.  NO SCAN to decide whether to:
; every caller already knows there is one, either from the run scan that found
; the end of this text or from %sh-has-char-in? on an expansion's result.
(def %sh-escape-chars
  (fn (_ text chars)
    (let ((n (string-length text)))
      (def go
        (fn (self i out)
          (if (>= i n)
            (%ash-join "" (reverse out))
            (let ((here (substring text i (+ i 1))))
              (self (+ i 1)
                (pair (if (%sh-char-in? (string-ref text i) chars)
                        (string-append "\\" here)
                        here)
                      out))))))
      (go 0 ()))))

; Quoted text: nothing in it may match, so every metacharacter goes in escaped.
(def %sh-glob-escape-all (fn (_ text) (%sh-escape-chars text %sh-glob-meta)))

; --- Splicing expanded text in --------------------------------------------
;
; Every piece after the first STARTS a field, so the one in hand is closed
; ahead of it.
(def %sh-add-pieces
  (fn (self a pieces)
    (if (null? pieces)
      a
      (self (%sh-acc-add-value (%sh-acc-break a) (first pieces))
            (rest pieces)))))

; Splice expanded TEXT into the accumulator, splitting it on IFS.
;
; A value that holds no IFS character is not split: it JOINS the field in hand
; whole (`p${X}s` is one word made of three), as every value does when IFS is
; empty.  Only a character of IFS counts: with IFS=: a space is text.
(def %sh-add-split
  (fn (_ a text)
    (do
      (def ifs (%sh-ifs))
      (def n (string-length text))
      (match
        ((%sh-has-ifs-from? text ifs 0 n)
          (%sh-add-split-fields a text n ifs (%sh-ifs-split text n ifs)))
        ; An empty value changes nothing.
        ((fx<? 0 n) (%sh-acc-add-value a text))
        (#t a)))))

; Splice the FIELDS of TEXT, N long, which holds a character of IFS.  The
; first field joins the field in hand and each later one starts its own.  An
; IFS character at the start closes the field in hand, and one at the end
; closes the last field, so what follows starts another.  A start that holds an
; IFS character other than whitespace is an empty first field, which joins the
; field in hand and so closes it once, whatever whitespace comes with it.  A
; value of IFS whitespace alone has no fields, and closes a field in hand that
; has started.
(def %sh-add-split-fields
  (fn (_ a text n ifs fields)
    (do
      (def opened
        (match
          ((null? (%sh-acc-started a)) a)
          ((null? fields) (%sh-acc-break a))
          ((= 0 (string-length (first fields))) a)
          ((%sh-in-ifs? (string-ref text 0) ifs) (%sh-acc-break a))
          (#t a)))
      (match
        ((null? fields) opened)
        (#t
          (do
            (def filled (%sh-add-pieces (%sh-acc-add-value opened (first fields))
                                        (rest fields)))
            (if (%sh-in-ifs? (string-ref text (fx+ n -1)) ifs)
              (%sh-acc-break filled)
              filled)))))))

; "$@" -- one field per positional parameter.
;
; Every other special answers a string, and inside quotes a string is one
; field. `"$@"` is the exception `cmd "$@"` rests on: it forwards each
; parameter as its own argument, with the spaces inside any of them intact.
;
; The parameters splice like other pieces: the first joins the field in hand,
; so `"x$@"` starts `x` on the first; each later one begins its own; the last
; is left open so `"$@y"` closes onto it. They go in as literal text -- quoted
; parameters are not split again and do not glob.
;
; With no parameters `"$@"` contributes nothing and produces no empty argument,
; so `cmd "$@"` with none passes none, where `cmd ""` passes one empty string.
; The field the opening quote started is un-started here, and only when nothing
; else has gone into it: `"x$@"` with no parameters is still the one field `x`.
(def %sh-add-args
  (fn (self a args)
    (if (null? args)
      (if (null? (%sh-acc-pieces a)) (%sh-acc-unstart a) a)
      (let ((filled (%sh-acc-add-literal a (first args)
                      (%sh-has-glob-meta? (first args)))))
        (if (null? (rest args))
          filled
          (self (%sh-acc-break filled) (rest args)))))))

; The positional parameters unquoted, as fields of their own that are not split
; again: the first joins the field in hand, and each later one closes it and
; begins the next.  An empty parameter adds nothing, so a field only it began
; is no field, while it still closes the one before it: with two empty
; parameters `x$*y` is `x` and `y`.
(def %sh-add-params
  (fn (self a args)
    (match
      ((null? args) a)
      (#t
        (do
          (def filled
            (if (fx<? 0 (string-length (first args)))
              (%sh-acc-add-value a (first args))
              a))
          (match
            ((null? (rest args)) filled)
            ((null? (%sh-acc-started filled)) (self filled (rest args)))
            (#t (self (%sh-acc-break filled) (rest args)))))))))

; `$@` and `$*`, and the same in braces; NAME is "@" or "*".  Quoted, "$@" is a
; field per parameter (%sh-add-args) and "$*" one field, the parameters joined
; on IFS's first character.  Unquoted, both are that joined text, which field
; splitting then splits apart again -- but with IFS empty there is no character
; to join on and nothing splits, so the parameters go in as fields of their own
; (%sh-add-params).  Where nothing is split -- an assignment, a `case` word --
; they are the joined text either way.
(def %sh-add-all-params
  (fn (_ a name mode split?)
    (match
      ((= mode %sh-mode-dq)
        (if (string=? name "@")
          (%sh-add-args a %sh-args)
          (%sh-add-expansion a mode (%sh-var-value name) split?)))
      ((if (%sh-splitting? split?) (= 0 (string-length (%sh-ifs))) ())
        (%sh-add-params a %sh-args))
      (#t (%sh-add-expansion a mode (%sh-var-value name) split?)))))

; Fields already built, each with what it holds, spliced in: the first joins
; the field in hand and each later one begins its own.
(def %sh-add-fields
  (fn (self a fields)
    (if (null? fields)
      a
      (let ((f (first fields)))
        (let ((filled (%sh-acc-add-piece a (%sh-field-text f)
                        (%sh-field-glob? f) (%sh-field-esc? f))))
          (if (null? (rest fields))
            filled
            (self (%sh-acc-break filled) (rest fields))))))))

; The word of `${x:-word}` or `${x:+word}` where the expansion stood.  Inside
; double quotes it is one string with its own quotes taken off; outside them
; its fields splice in as they were written, so a quoted part is neither split
; nor globbed and an unquoted part is both.
(def %sh-add-word
  (fn (_ a mode word split?)
    (if (= mode %sh-mode-dq)
      (let ((fs (%sh-expand-str word %sh-mode-dq () ())))
        (let ((text (if (null? fs) "" (%sh-field-plain (first fs)))))
          (%sh-acc-add-literal a text (%sh-has-glob-meta? text))))
      ; The word stands in the expansion's place, so it is read as that place
      ; is: split where splitting is on, and a pattern in a pattern.
      (%sh-add-fields a
        (%sh-expand-str word %sh-mode-bare
          (match
            ((eq? split? (lit pattern)) split?)
            ((%sh-splitting? split?) (lit fields))
            (#t ()))
          ())))))

; Whether SPLIT? has a word's expansions split into fields: `#t` or `fields`
; do, and a pattern, like nil, does not.
(def %sh-splitting?
  (fn (_ split?)
    (match
      ((eq? split? (lit pattern)) ())
      (#t split?))))

; One expansion's worth of text.  Split only when splitting is on AND we are
; outside quotes -- inside `"..."` a value keeps its spaces, which is the
; entire point of quoting it.
(def %sh-add-expansion
  (fn (_ a mode text split?)
    (if (= mode %sh-mode-bare)
      ; An unquoted expansion's RESULT is subject to both splitting and
      ; globbing -- `X='*'; echo $X` globs, `echo "$X"` does not.  In a
      ; pattern a backslash it holds escapes the character after it, as one
      ; written in the pattern would, so it goes in as it is.
      (match
        ((eq? split? (lit pattern))
          (%sh-acc-add a text (%sh-has-active-glob? text)))
        ((%sh-splitting? split?) (%sh-add-split a text))
        (#t (%sh-acc-add-value a text)))
      (%sh-acc-add-literal a text (%sh-has-glob-meta? text)))))

; Push a word's fields onto a REVERSED accumulator, in order.  Both callers
; build their word list backwards and reverse at the end.
(def %sh-push-fields
  (fn (self fields acc)
    (if (null? fields) acc (self (rest fields) (pair (first fields) acc)))))

; --- ${NAME OP WORD} --------------------------------------------------------
;
; The parameter expansion operators.  Each is a NAME, whether a `:` in front of
; it means "null counts as unset", and what it does -- so they are a table and
; the walk that finds them is written once.
;
;   ${X:-w} ${X-w}   w when X is unset (or null, with the colon)
;   ${X:=w} ${X=w}   as above, and ASSIGN it
;   ${X:?w} ${X?w}   as above, but raise w
;   ${X:+w} ${X+w}   w when X is SET -- the inverted one
;   ${#X}            the length of X
;   ${X#p} ${X##p}   shortest / longest PREFIX matching the glob p, removed
;   ${X%p} ${X%%p}   shortest / longest SUFFIX, removed

; Every value operator answers from the same four facts, so they share a
; signature: the name (for `=`), the current value, whether the operator FIRED,
; and the word as written.  The word is expanded only when the operator fires,
; so `${x:-$(cmd)}` runs nothing when x is set.
;
; For `-` and `+` the word stands where the expansion stood, with the quoting
; it was written with, and the caller expands it there (see %sh-add-word).
; `=` assigns the word's value and `?` reports it, so those two take it
; expanded, its quotes and escapes off.
(def %sh-in-place (fn (_ word) (pair (lit in-place) word)))

(def %sh-word-value
  (fn (_ word)
    (let ((fs (%sh-expand-str word %sh-mode-bare () ())))
      (if (null? fs) "" (%sh-field-plain (first fs))))))

(def %sh-param-default
  (fn (_ name val fired? word) (if fired? (%sh-in-place word) val)))

; Only a variable can be assigned this way: a positional parameter or a special
; that the operator would assign is refused, `${1:=x}` with no parameters.
(def %sh-param-assign
  (fn (_ name val fired? word)
    (match
      ((not fired?) val)
      ((not (%sh-name? name)) (error (string-append name ": bad variable name")))
      (#t (do (def v (%sh-word-value word)) (%sh-var-set! name v) v)))))

(def %sh-param-error
  (fn (_ name val fired? word)
    (if fired?
      (let ((v (%sh-word-value word)))
        (error (string-append name ": "
                 (if (= (string-length v) 0) "parameter not set" v))))
      val)))

; `+` fires on the opposite condition to the other three: it wants the word
; when the parameter IS set.  The caller inverts before calling, so this stays
; the same shape as its neighbours.
(def %sh-param-alt
  (fn (_ name val fired? word) (if fired? (%sh-in-place word) "")))

(def %sh-param-value-ops
  (list (pair "-" %sh-param-default)
        (pair "=" %sh-param-assign)
        (pair "?" %sh-param-error)
        (pair "+" %sh-param-alt)))

; --- Prefix and suffix trimming ---------------------------------------------
;
; %sh-glob-at answers "does this pattern match this WHOLE span", so trimming is
; a search for the span that matches: a prefix is s[0,k) and a suffix s[k,n).
; Scanning k upward finds the shortest prefix and the longest suffix; downward
; finds the other two.  One walk, a direction, and which end.
(def %sh-span-match
  (fn (self pat s from to k step)
    (if (or (< k 0) (> k (string-length s)))
      (- 0 1)
      (if (%sh-glob-at pat 0 (string-length pat) s (from k) (to k))
        k
        (self pat s from to (+ k step) step)))))

(def %sh-trim-prefix
  (fn (_ val pat longest?)
    (let ((n (string-length val)))
      (let ((k (%sh-span-match pat val (fn (_ k) 0) (fn (_ k) k)
                 (if longest? n 0) (if longest? (- 0 1) 1))))
        (if (< k 0) val (substring val k n))))))

(def %sh-trim-suffix
  (fn (_ val pat longest?)
    (let ((n (string-length val)))
      (let ((k (%sh-span-match pat val (fn (_ k) k) (fn (_ k) n)
                 (if longest? 0 n) (if longest? 1 (- 0 1)))))
        (if (< k 0) val (substring val 0 k))))))

(def %sh-param-trim-ops
  (list (pair "#"  (fn (_ val pat) (%sh-trim-prefix val pat ())))
        (pair "##" (fn (_ val pat) (%sh-trim-prefix val pat #t)))
        (pair "%"  (fn (_ val pat) (%sh-trim-suffix val pat ())))
        (pair "%%" (fn (_ val pat) (%sh-trim-suffix val pat #t)))))

; Longest first, so `##` is never read as `#` and `:-` never as `-`.
(def %sh-param-op-names
  (list ":-" ":=" ":?" ":+" "##" "%%" "-" "=" "?" "+" "#" "%"))

; --- Reading ${...} apart ----------------------------------------------------

(def %sh-str-starts?
  (fn (_ s prefix)
    (let ((n (string-length prefix)))
      (if (> n (string-length s))
        ()
        (string=? (substring s 0 n) prefix)))))

; `tail`, not `rest`: naming a parameter `rest` shadows the list primitive of
; that name, so the recursive step called a STRING.  ("object: no such method
; names".)
(def %sh-first-op
  (fn (self tail names)
    (if (null? names)
      ()
      (if (%sh-str-starts? tail (first names))
        (first names)
        (self tail (rest names))))))

; The leading parameter NAME: a run of name characters, a run of digits -- in
; braces a positional parameter's number may be more than one, `${10:-x}` --
; or a single special ($?, $#...), or empty when the braces open with an
; operator.
(def %sh-param-name
  (fn (_ inner)
    (let ((n (string-length inner)))
      (if (= n 0)
        ""
        (let ((c (string-ref inner 0)))
          (if (%sh-name-start? c)
            (substring inner 0 (%sh-name-end inner 0 n))
            (if (null? (%sh-table-get (substring inner 0 1) %sh-special-vars))
              (if (%sh-digit? c) (substring inner 0 (%sh-ar-digits-end inner 0 n)) "")
              (substring inner 0 1))))))))

; Is the parameter unset?  `$!` is until a list has run in the background; any
; other special is always set; a positional is set when it is within range;
; anything else asks the variables.
(def %sh-param-unset?
  (fn (_ name)
    (match
      ((string=? name "!") (null? %sh-bg-pid))
      ((not (null? (%sh-table-get name %sh-special-vars))) ())
      ((%all-digits? name) (> (%sh-digits-int name) (length %sh-args)))
      (#t (null? (%sh-var-get name))))))

(def %sh-param-apply
  (fn (_ name op word)
    (let ((val (%sh-var-value name))
          (trim (%sh-table-get op %sh-param-trim-ops)))
      (if (not (null? trim))
        ; A trim takes the word as a PATTERN, so it is expanded but not
        ; measured against set-ness.
        (trim val (%sh-expand-word word))
        ; A leading `:` makes null count as unset.  Tested once, here.
        (let ((colon? (%sh-str-starts? op ":")))
          (let ((base (if colon? (substring op 1 (string-length op)) op))
                (absent? (or (%sh-param-unset? name)
                             (and colon? (= (string-length val) 0)))))
            (let ((run (%sh-table-get base %sh-param-value-ops)))
              (if (null? run)
                val
                ; `+` fires on the opposite condition to the other three: it
                ; wants the word when the parameter is PRESENT.
                (run name val
                  (if (string=? base "+") (not absent?) absent?)
                  word)))))))))

; What `${...}` holds is a parameter, and then an operator or nothing at all.
; Anything else is no expansion: `${1a}`, `${a b}`, `${:-x}` and `${}` are
; refused rather than read as a name the shell has never been given.
(def %sh-bad-substitution
  (fn (_ inner)
    (error (string-append "${" inner "}: bad substitution"))))

; ${...} in full.  Answers the expanded text.
(def %sh-brace-expand
  (fn (_ inner)
    (let ((n (string-length inner)))
      (cond
        ((= n 0) (%sh-bad-substitution inner))
        ; ${#X} is a length when X is one parameter and nothing more.  ${#}
        ; alone is the parameter COUNT, which %sh-var-value already knows as
        ; the special "#" -- and so is the `#` an operator follows, in
        ; `${#:-x}` and `${##pat}`, which the arm below reads.
        ((and (> n 1) (= (string-ref inner 0) #\#)
              (= (string-length (%sh-param-name (substring inner 1 n))) (- n 1)))
          (convert
            (string-length (%sh-var-value-checked (substring inner 1 n)))
            %string))
        (else
          (let ((name (%sh-param-name inner)))
            (let ((tail (substring inner (string-length name) n)))
              (cond
                ((= (string-length name) 0) (%sh-bad-substitution inner))
                ((= (string-length tail) 0) (%sh-var-value-checked name))
                (else
                  (let ((op (%sh-first-op tail %sh-param-op-names)))
                    (if (null? op)
                      (%sh-bad-substitution inner)
                      (%sh-param-apply name op
                        (substring tail (string-length op)
                          (string-length tail))))))))))))))

; A plain run, and whether it holds a metacharacter, in one pass. Finding where
; the run ends looks at every character; the only other question about a run is
; whether it contains `*`, `?`, `[` or `\`, so asking here costs one test per
; character and saves two whole-field scans.  The flag rides in through the
; recursion, and once it is set the question is not asked again.
(def %sh-run (fn (_ end meta?) (pair end meta?)))
(def %sh-run-end (fn (_ r) (first r)))
(def %sh-run-meta? (fn (_ r) (rest r)))

; A run stops at a character the walk has an arm for.  In single quotes only
; the closing quote is special, so a `'...'` region is one run; inside double
; quotes a quote mark is ordinary text, and the walk has no arm for it there --
; a run that stopped at one would hand the walk a character it reads as
; neither, and the field would stand still.  A `~` ends a run only where one
; could expand, which is what TILDE? says; anywhere else it is ordinary text.
;
; Every character of every word comes through here, so the loop calls nothing
; but itself: the stop test and the metacharacter test are written out as
; matches rather than asked of helpers, which cost a call each per character.
; The four metacharacters are %sh-glob-meta's.
(def %sh-plain-run
  (fn (self s i n mode meta? tilde?)
    (match
      ((fx<? i n)
        (match
          ((match
             ((= (string-ref s i) #\')
               (match ((= mode %sh-mode-dq) ()) (#t #t)))
             ((= (string-ref s i) #\~) tilde?)
             ((= mode %sh-mode-sq) ())
             ((= (string-ref s i) #\") #t)
             ((= (string-ref s i) #\\) #t)
             ((= (string-ref s i) #\`) #t)
             ((= (string-ref s i) #\$) #t)
             (#t ()))
            (%sh-run i meta?))
          (meta? (self s (fx+ i 1) n mode #t tilde?))
          ((= (string-ref s i) #\*) (self s (fx+ i 1) n mode #t tilde?))
          ((= (string-ref s i) #\?) (self s (fx+ i 1) n mode #t tilde?))
          ((= (string-ref s i) #\[) (self s (fx+ i 1) n mode #t tilde?))
          ((= (string-ref s i) #\\) (self s (fx+ i 1) n mode #t tilde?))
          (#t (self s (fx+ i 1) n mode () tilde?))))
      (#t (%sh-run i meta?)))))

; --- Tilde expansion --------------------------------------------------------
;
; `~` stands for HOME, but only where a shell says it does: at the start of a
; word, and -- in an assignment word only -- straight after the `=` and after
; any `:` beyond it, which makes `PATH=~/bin:~/lib` work. Everywhere else it is
; ordinary:
;
;   echo a~b        not at the start
;   echo x~         not at the start
;   echo a=~/x      an argument that looks like an assignment is not one
;
; Assignment position is a fact of the command, not the word's shape, so it is
; passed in from %collect-cmd-tokens. Quoting suppresses tilde for free -- the
; walk only stands on a bare `~`, so `"~"`, `'~'` and `\~` never reach here.
;
; Only a bare `~` expands: the next character must be `/`, `:` or the end of
; the word. `~user` wants the password database, absent here, so it is left as
; written -- what a shell gives for a user that does not exist. `~+` and `~-`
; are not implemented.
(def %sh-first-eq
  (fn (self s i n)
    (match
      ((not (fx<? i n)) -1)
      ((= (string-ref s i) #\=) i)
      (#t (self s (fx+ i 1) n)))))

(def %sh-tilde-pos?
  (fn (_ s i assign? eq)
    (if (= i 0)
      #t
      (and assign?
           (let ((p (string-ref s (- i 1))))
             (or (and (= p #\=) (= (- i 1) eq))
                 (and (= p #\:) (> (- i 1) eq))))))))

(def %sh-tilde-bare?
  (fn (_ s i n)
    (or (= (+ i 1) n)
        (let ((d (string-ref s (+ i 1))))
          (or (= d #\/) (= d #\:))))))

; The home directory this `~` stands for, or () if it stands for nothing.
(def %sh-tilde-home
  (fn (_ s i n assign? eq)
    (if (and (%sh-tilde-pos? s i assign? eq) (%sh-tilde-bare? s i n))
      (let ((home (%sh-var-get "HOME")))
        (if (or (null? home) (= (string-length home) 0)) () home))
      ())))

; --- Arithmetic expansion: $(( ... )) ---------------------------------------
;
; The tokenizer already hands this over whole -- %sh-cs-end counts parens, so
; `$((1+2))` is one word -- and `$(` and `$((` are told apart by their CONTENT:
; an inner text that opens with `(` and closes with `)` is arithmetic.  That is
; also how POSIX disambiguates, and why `$( (cmd) )` needs its space: with one,
; the inner text starts with a space and is a command substitution.
;
; Integers only, which is what POSIX requires; a name evaluates to its value
; and anything unset or non-numeric is 0.

(def %sh-ar (fn (_ v i) (pair v i)))
(def %sh-ar-val (fn (_ r) (first r)))
(def %sh-ar-pos (fn (_ r) (rest r)))

(def %sh-bool-int (fn (_ p) (if p 1 0)))
(def %sh-truthy? (fn (_ n) (not (= n 0))))

; The operators, by precedence: each level binds tighter than the one before.
; Adding one is adding it to a level and to the table -- the parser below reads
; both and knows nothing else about them.
; Loosest binding first.  POSIX orders the bitwise operators between `&&` and
; the equality tests, and the shifts between the comparisons and `+`.
(def %sh-ar-levels
  (list (list "||")
        (list "&&")
        (list "|")
        (list "^")
        (list "&")
        (list "==" "!=")
        (list "<=" ">=" "<" ">")
        (list "<<" ">>")
        (list "+" "-")
        (list "*" "/" "%")))

(def %sh-ar-ops
  (list (pair "||" (fn (_ a b) (%sh-bool-int (or (%sh-truthy? a) (%sh-truthy? b)))))
        (pair "&&" (fn (_ a b) (%sh-bool-int (and (%sh-truthy? a) (%sh-truthy? b)))))
        (pair "==" (fn (_ a b) (%sh-bool-int (= a b))))
        (pair "!=" (fn (_ a b) (%sh-bool-int (not (= a b)))))
        (pair "<=" (fn (_ a b) (%sh-bool-int (<= a b))))
        (pair ">=" (fn (_ a b) (%sh-bool-int (>= a b))))
        (pair "<"  (fn (_ a b) (%sh-bool-int (< a b))))
        (pair ">"  (fn (_ a b) (%sh-bool-int (> a b))))
        (pair "+"  (fn (_ a b) (+ a b)))
        (pair "-"  (fn (_ a b) (- a b)))
        (pair "*"  (fn (_ a b) (* a b)))
        ; INTEGER division, truncating toward zero.  Bare `/` answers a
        ; RATIONAL here -- x has a numeric tower, so `$((10/3))` came out as
        ; the two characters `10/3` -- and POSIX arithmetic is integer-only.
        ; convert-to-int truncates the right way at both signs (10/3 -> 3,
        ; -10/3 -> -3).
        (pair "/"  (fn (_ a b)
                     (if (= b 0)
                       (error "arithmetic: division by 0")
                       (convert (/ a b) %int))))
        (pair "%"  (fn (_ a b)
                     (if (= b 0) (error "arithmetic: division by 0") (% a b))))
        ; Int-only operators, which is all POSIX arithmetic has: the tower's
        ; wider numbers never reach here because every operand is an integer.
        (pair "&"  (fn (_ a b) (& a b)))
        (pair "|"  (fn (_ a b) (| a b)))
        (pair "^"  (fn (_ a b) (^ a b)))
        (pair "<<" (fn (_ a b) (<< a b)))
        (pair ">>" (fn (_ a b) (>> a b)))))

(def %sh-ar-rank-names
  (fn (self names rank out)
    (if (null? names)
      out
      (self (rest names) rank (pair (pair (first names) rank) out)))))

(def %sh-ar-rank-levels
  (fn (self levels rank out)
    (if (null? levels)
      out
      (self (rest levels) (+ rank 1)
            (%sh-ar-rank-names (first levels) rank out)))))

; Every binary operator as (name . rank), its rank being its level's place in
; %sh-ar-levels counted from 1 at the loosest -- taken from the levels so the
; two cannot drift apart.  Below the walks that build it because this is a
; value read as the file loads, not a body resolved when it is called.
(def %sh-ar-ranks (%sh-ar-rank-levels %sh-ar-levels 1 ()))

(def %sh-ar-skip-ws
  (fn (self s i n)
    (match
      ((not (fx<? i n)) i)
      ((%sh-ws-char? (string-ref s i)) (self s (fx+ i 1) n))
      (#t i))))

; Does the text from K spell NAME from J?  It is asked of every operator name
; wherever an operator could stand and nearly always answers no, so it builds
; nothing and tests only with `=`: the ordering comparisons go through the
; numeric tower and cost hundreds of heap objects each.  J counts up to LEN
; and K up to N exactly, which is what lets equality stand in for them.
(def %sh-ar-spells?
  (fn (self s k n name j len)
    (match
      ((= j len) #t)
      ((= k n) ())
      ((= (string-ref s k) (string-ref name j))
        (self s (fx+ k 1) n name (fx+ j 1) len))
      (#t ()))))

(def %sh-ar-op-here?
  (fn (_ s i n name)
    (%sh-ar-spells? s i n name 0 (string-length name))))

; The operator written at I as its (name . rank) entry, or nil: the longest
; spelling, whatever its rank.  Asking one level at a time would read `a||b` as
; a bitwise or, because `|` binds tighter and would be found first.
(def %sh-ar-op-at
  (fn (self s i n entries best)
    (match
      ((null? entries) best)
      ; The first character rules out nearly every entry, so it is asked
      ; before the spelling is compared.
      ((not (= (string-ref s i) (string-ref (first (first entries)) 0)))
        (self s i n (rest entries) best))
      ((not (%sh-ar-op-here? s i n (first (first entries))))
        (self s i n (rest entries) best))
      ((null? best) (self s i n (rest entries) (first entries)))
      ((fx<? (string-length (first best)) (string-length (first (first entries))))
        (self s i n (rest entries) (first entries)))
      (#t (self s i n (rest entries) best)))))

(def %sh-ar-digits-end
  (fn (self s i n)
    (match
      ((not (fx<? i n)) i)
      ((%sh-digit? (string-ref s i)) (self s (fx+ i 1) n))
      (#t i))))

(def %sh-hex-digit?
  (fn (_ c)
    (match
      ((%sh-digit? c) #t)
      ((fx<? c #\A) ())
      ((not (fx<? #\F c)) #t)
      ((fx<? c #\a) ())
      (#t (not (fx<? #\f c))))))

; A digit's value, C being one of 0-9, a-f or A-F, as every caller has already
; seen to: 48 is the code of #\0, and a..f and A..F read as 10..15.
(def %sh-digit-value
  (fn (_ c)
    (do
      (def v (char->integer c))
      (match
        ((%sh-digit? c) (- v 48))
        ((fx<? c #\a) (- v 55))
        (#t (- v 87))))))

(def %sh-ar-hex-end
  (fn (self s i n)
    (match
      ((not (fx<? i n)) i)
      ((%sh-hex-digit? (string-ref s i)) (self s (fx+ i 1) n))
      (#t i))))

; A leading `0x` is hexadecimal; everything else is digits, and whether those
; read as octal or decimal is settled by the leading zero when the text is
; converted.
(def %sh-ar-hex-prefix?
  (fn (_ s i n)
    (and (< (+ i 1) n)
         (= (string-ref s i) #\0)
         (let ((c (string-ref s (+ i 1)))) (or (= c #\x) (= c #\X))))))

(def %sh-ar-number-end
  (fn (_ s i n)
    (if (%sh-ar-hex-prefix? s i n)
      (%sh-ar-hex-end s (+ i 2) n)
      (%sh-ar-digits-end s i n))))

; The digits from I, read in BASE.  A digit the base does not have is an
; error rather than a silent misreading: `08` is a typo for either 8 or 010,
; and answering one of them would be a guess.
(def %sh-ar-digits-value
  (fn (self text i n base acc)
    (if (fx<? i n)
      (do
        (def d (%sh-digit-value (string-ref text i)))
        (if (fx<? d base)
          (self text (fx+ i 1) n base (+ (* acc base) d))
          (error (string-append "arithmetic: invalid number " text))))
      acc)))

(def %sh-ar-hex?
  (fn (_ text n) (and (> n 2) (%sh-ar-hex-prefix? text 0 n))))

(def %sh-ar-octal?
  (fn (_ text n)
    (and (> n 1)
         (= (string-ref text 0) #\0)
         (%sh-digit? (string-ref text 1)))))

; An unset or non-numeric name is 0, which is POSIX.  `convert` answers nil
; for both rather than raising, so a guard alone does not catch it -- that nil
; reached `+` as an operand and the whole expansion died.
(def %sh-ar-num
  (fn (_ text)
    (do
      (def n (string-length text))
      (match
        ((%sh-ar-hex? text n) (%sh-ar-digits-value text 2 n 16 0))
        ((%sh-ar-octal? text n) (%sh-ar-digits-value text 1 n 8 0))
        ; Decimal digits by the same loop: `convert` costs several times as
        ; much, and is left for text that is not digits alone.
        ((%all-digits? text) (%sh-ar-digits-value text 0 n 10 0))
        (#t (do (def v (guard (_ ()) (convert text %int)))
                (if (null? v) 0 v)))))))

; A variable's value is read as an integer constant with blanks around it and a
; sign in front allowed, since $((n)) answers what $(($n)) does: `n=$(wc -l <
; f)` holds "       3" where wc pads its count.  A bare constant, the usual
; value, is read as it stands.
(def %sh-ar-value-num
  (fn (_ text)
    (let ((len (string-length text)))
      (match
        ((= len 0) 0)
        ((%sh-digit? (string-ref text 0))
          (if (%sh-ws-char? (string-ref text (- len 1)))
            (%sh-ar-padded-num text len)
            (%sh-ar-num text)))
        (#t (%sh-ar-padded-num text len))))))

; The index just past the last character of S before N that is not a blank.
(def %sh-ar-ws-before
  (fn (self s n)
    (match
      ((not (fx<? 0 n)) n)
      ((%sh-ws-char? (string-ref s (- n 1))) (self s (- n 1)))
      (#t n))))

(def %sh-ar-padded-num
  (fn (_ text len)
    (let ((n (%sh-ar-ws-before text len)))
      (let ((i (%sh-ar-skip-ws text 0 n)))
        (match
          ((not (fx<? i n)) 0)
          ((= (string-ref text i) #\-)
            (- 0 (%sh-ar-num (substring text (fx+ i 1) n))))
          ((= (string-ref text i) #\+)
            (%sh-ar-num (substring text (fx+ i 1) n)))
          (#t (%sh-ar-num (substring text i n))))))))

(def %sh-ar-binary ())
(def %sh-ar-climb ())
(def %sh-ar-primary ())

(set! %sh-ar-primary
  (fn (_ s i0 n live?)
    (do
      (def i (%sh-ar-skip-ws s i0 n))
      (if (not (fx<? i n))
        (%sh-ar 0 i)
        (do
          (def c (string-ref s i))
          (match
            ((= c #\()
              (do
                (def inner (%sh-ar-assignment s (fx+ i 1) n live?))
                ; Step over the closing paren if it is there.
                (def e (%sh-ar-skip-ws s (%sh-ar-pos inner) n))
                (%sh-ar (%sh-ar-val inner)
                        (if (if (fx<? e n) (= (string-ref s e) #\)) ())
                          (fx+ e 1)
                          e))))
            ((= c #\-)
              (do
                (def r (%sh-ar-primary s (fx+ i 1) n live?))
                (%sh-ar (- 0 (%sh-ar-val r)) (%sh-ar-pos r))))
            ((= c #\+) (%sh-ar-primary s (fx+ i 1) n live?))
            ((= c #\!)
              (do
                (def r (%sh-ar-primary s (fx+ i 1) n live?))
                (%sh-ar (%sh-bool-int (not (%sh-truthy? (%sh-ar-val r))))
                        (%sh-ar-pos r))))
            ; Two's complement, written as arithmetic so it needs no word
            ; width: ~x is -(x + 1) for every integer.
            ((= c #\~)
              (do
                (def r (%sh-ar-primary s (fx+ i 1) n live?))
                (%sh-ar (- 0 (+ (%sh-ar-val r) 1)) (%sh-ar-pos r))))
            ; A literal is read whether or not its branch is taken, so a
            ; digit its base does not have is still refused.  What a dead
            ; branch skips is arithmetic, not spelling.
            ((%sh-digit? c)
              (do
                (def e (%sh-ar-number-end s i n))
                (def v (%sh-ar-num (substring s i e)))
                (%sh-ar (if live? v 0) e)))
            ((%sh-name-start? c)
              (do
                (def e (%sh-name-end s i n))
                (%sh-ar (if live?
                          (%sh-ar-value-num (%sh-var-value (substring s i e)))
                          0)
                        e)))
            ; Anything else is not arithmetic; step over it rather than loop.
            (#t (%sh-ar 0 (fx+ i 1)))))))))

; Operands joined by binary operators, read by rank.  An operator ranked below
; LOWEST belongs to an enclosing call and ends this one.  The right operand of
; a rank-R operator is read with LOWEST at R+1, which takes tighter operators
; into it and leaves equal ones to this loop, so every level is
; left-associative.  The operator after an operand is read once for each call
; still open there, not once for every level.
(set! %sh-ar-binary
  (fn (_ s i n lowest live?)
    (%sh-ar-climb s (%sh-ar-primary s i n live?) n lowest live?)))

; Does this operator entry carry on an expression whose operators rank LOWEST
; or above?
(def %sh-ar-binds?
  (fn (_ entry lowest)
    (match
      ((null? entry) ())
      ((fx<? (rest entry) lowest) ())
      (#t #t))))

; Fold each further operator onto what is already built.  LIVE? says whether
; this side of the expression is one the answer depends on; when it is not, the
; text is still walked so the position comes out right, and nothing is
; computed.
(set! %sh-ar-climb
  (fn (self s left n lowest live?)
    (do
      (def i (%sh-ar-skip-ws s (%sh-ar-pos left) n))
      (def entry (if (fx<? i n) (%sh-ar-op-at s i n %sh-ar-ranks ()) ()))
      (if (not (%sh-ar-binds? entry lowest))
        (%sh-ar (%sh-ar-val left) i)
        (do
          (def op (first entry))
          (def known (%sh-ar-known op (%sh-ar-val left) live?))
          (def right (%sh-ar-binary s (fx+ i (string-length op)) n
                       (fx+ (rest entry) 1) (and live? (null? known))))
          (self s
            (%sh-ar (%sh-ar-combine op known (%sh-ar-val left)
                                    (%sh-ar-val right) live?)
                    (%sh-ar-pos right))
            n lowest live?))))))

; What `&&` and `||` answer from the left alone, or () when the right side is
; still needed.  C settles this and POSIX defers to C: the side not taken is
; not evaluated, which is what lets `$((n && total/n))` guard its own
; division.
(def %sh-ar-shorts
  (list (pair "&&" (fn (_ a) (if (%sh-truthy? a) () 0)))
        (pair "||" (fn (_ a) (if (%sh-truthy? a) 1 ())))))

(def %sh-ar-known
  (fn (_ op left live?)
    (if (not live?)
      ()
      (let ((short (%sh-table-get op %sh-ar-shorts)))
        (if (null? short) () (short left))))))

(def %sh-ar-combine
  (fn (_ op known left right live?)
    (match
      ((not live?) 0)
      ((not (null? known)) known)
      (#t ((%sh-table-get op %sh-ar-ops) left right)))))

; `c ? a : b`, looser than every binary operator and grouping to the right.
; Both branches are walked so the expression ends where it should; only the
; one taken is evaluated.
(def %sh-ar-conditional ())

(set! %sh-ar-conditional
  (fn (_ s i n live?)
    (do
      (def test (%sh-ar-binary s i n 1 live?))
      (def q (%sh-ar-skip-ws s (%sh-ar-pos test) n))
      (match
        ((not (fx<? q n)) test)
        ((not (= (string-ref s q) #\?)) test)
        (#t
          (do
            (def taken (and live? (%sh-truthy? (%sh-ar-val test))))
            ; The first branch is a whole expression, assignment included, as
            ; in C; the second is only a conditional.
            (def yes (%sh-ar-assignment s (fx+ q 1) n taken))
            (def c (%sh-ar-skip-ws s (%sh-ar-pos yes) n))
            (def no (%sh-ar-conditional s
                      (if (if (fx<? c n) (= (string-ref s c) #\:) ()) (fx+ c 1) c)
                      n (and live? (not taken))))
            (%sh-ar (if taken (%sh-ar-val yes) (%sh-ar-val no))
                    (%sh-ar-pos no))))))))

; The assignment operators, each with the binary operator it applies to the
; variable's value first -- () for plain `=`.
(def %sh-ar-assign-ops
  (list (pair "=" ()) (pair "+=" "+") (pair "-=" "-") (pair "*=" "*")
        (pair "/=" "/") (pair "%=" "%") (pair "<<=" "<<") (pair ">>=" ">>")
        (pair "&=" "&") (pair "^=" "^") (pair "|=" "|")))

; Does a binary operator longer than LEN start at K?  Then what looked like an
; assignment operator is only the front of it: `==` against `=`.
(def %sh-ar-longer-binary?
  (fn (_ s k n len)
    (do
      (def binary (%sh-ar-op-at s k n %sh-ar-ranks ()))
      (if (null? binary) () (fx<? len (string-length (first binary)))))))

; When the text at I is an assignment, its NAME, its operator entry and where
; its right side starts; () when it is not one.
(def %sh-ar-assign-target
  (fn (_ s i n)
    (if (if (fx<? i n) (%sh-name-start? (string-ref s i)) ())
      (do
        (def e (%sh-name-end s i n))
        (def k (%sh-ar-skip-ws s e n))
        (def op (if (fx<? k n) (%sh-ar-op-at s k n %sh-ar-assign-ops ()) ()))
        (match
          ((null? op) ())
          ((%sh-ar-longer-binary? s k n (string-length (first op))) ())
          (#t (list (substring s i e) op (fx+ k (string-length (first op)))))))
      ())))

; An assignment: the loosest expression, grouping to the right, so `x = y = 3`
; sets both.  Its value is the value assigned, and in a branch that is not
; taken it assigns nothing.
(def %sh-ar-assignment ())

(set! %sh-ar-assignment
  (fn (_ s i0 n live?)
    (do
      (def i (%sh-ar-skip-ws s i0 n))
      (def target (%sh-ar-assign-target s i n))
      (if (null? target)
        (%sh-ar-conditional s i n live?)
        (%sh-ar-assign s n target live?)))))

(def %sh-ar-assign
  (fn (_ s n target live?)
    (let ((name (first target))
          (op (first (rest target)))
          (right (%sh-ar-assignment s (first (rest (rest target))) n live?)))
      (if (not live?)
        (%sh-ar 0 (%sh-ar-pos right))
        (let ((value (if (null? (rest op))
                       (%sh-ar-val right)
                       ((%sh-table-get (rest op) %sh-ar-ops)
                        (%sh-ar-value-num (%sh-var-value name))
                        (%sh-ar-val right)))))
          (%sh-var-set! name (convert value %string))
          (%sh-ar value (%sh-ar-pos right)))))))

; The whole text is one expression.  Anything left after it is an error rather
; than text to skip, so `$((1 2))` and `$((1=2))` are refused.
(def %sh-arith-eval
  (fn (_ text)
    (let ((n (string-length text)))
      (let ((r (%sh-ar-assignment text 0 n #t)))
        (if (fx<? (%sh-ar-skip-ws text (%sh-ar-pos r) n) n)
          (error (string-append "arithmetic: syntax error in " text))
          (convert (%sh-ar-val r) %string))))))

; Is this `$(` inner text an arithmetic expansion rather than a command one?
(def %sh-arith?
  (fn (_ inner)
    (let ((n (string-length inner)))
      (and (>= n 2)
           (and (= (string-ref inner 0) #\()
                (= (string-ref inner (- n 1)) #\)))))))

; The expression inside an arithmetic expansion's `(( ))`, with its parameters,
; command substitutions and nested arithmetic expanded as in double quotes
; before it is evaluated (POSIX 2.6.4): `$((i+$j))`, `$(( $(wc -l <f) + 1 ))`.
; Most expressions are names, numbers and operators, and a plain run that
; reaches the end says there is nothing to expand without building anything.
(def %sh-arith-text
  (fn (_ inner)
    (let ((text (substring inner 1 (- (string-length inner) 1))))
      (let ((n (string-length text)))
        (if (= (%sh-run-end (%sh-plain-run text 0 n %sh-mode-dq #t ())) n)
          text
          (%sh-expand-str-dq text))))))

; --- The walk ---------------------------------------------------------------
;
; MODE says which kind of region the scan is in.  A word is not uniformly
; quoted: `X="a b"` and `pre'lit'$X` are each several regions in one word, and
; the mode is which one the scan is inside right now.
(def %sh-mode-bare 0)          ; outside quotes
(def %sh-mode-sq 1)            ; inside '...'
(def %sh-mode-dq 2)            ; inside "..."

; The run of plain text a word opens with, read as the walk below would read
; it first: none unless the word is bare, and none when it opens with a `~`,
; which the walk decides for itself.
(def %sh-lead-run
  (fn (_ s n mode0 assign?)
    (match
      ((not (= mode0 %sh-mode-bare)) (%sh-run 0 ()))
      ((= n 0) (%sh-run 0 ()))
      ((= (string-ref s 0) #\~) (%sh-run 0 ()))
      (#t (%sh-plain-run s 0 n mode0 () assign?)))))

; The walk over a word that is not one plain run, from START with the
; accumulator A0.  It is a function of its own so that a plain word, which
; never walks, never builds the walker either: `go` is a closure over this
; word, made on each call.
(def %sh-expand-walk
  (fn (_ s n mode0 split? assign? start a0)
    (let ((eq (if assign? (%sh-first-eq s 0 n) -1)))
      (def go
        (fn (self i mode a)
          (if (>= i n)
            (%sh-acc-finish a)
            (let ((c (string-ref s i)))
              (cond
                ; Inside single quotes: literal until the closing quote.
                ((= mode %sh-mode-sq)
                  (if (= c #\')
                    (self (+ i 1) %sh-mode-bare a)
                    (let ((r (%sh-plain-run s i n mode () ())))
                      (let ((e (%sh-run-end r)))
                        (self e mode
                          (%sh-acc-add-literal a (substring s i e)
                            (%sh-run-meta? r)))))))
                ; A quote mark switches region and starts a field.
                ((and (= mode %sh-mode-bare) (= c #\'))
                  (self (+ i 1) %sh-mode-sq (%sh-acc-open a)))
                ((and (= mode %sh-mode-bare) (= c #\"))
                  (self (+ i 1) %sh-mode-dq (%sh-acc-open a)))
                ((and (= mode %sh-mode-dq) (= c #\"))
                  (self (+ i 1) %sh-mode-bare (%sh-acc-open a)))
                ; A backslash emits what it protects and resumes past it, so a
                ; `$` it protected stays a `$`. A trailing backslash protects
                ; nothing and stands for itself; it is claimed here, because the
                ; plain-run scanner cannot consume a backslash and the arm below
                ; needs a character to protect.
                ((and (= c #\\) (>= (+ i 1) n))
                  (self (+ i 1) mode
                    (%sh-acc-add-literal a (substring s i (+ i 1)) #t)))
                ((and (= c #\\) (< (+ i 1) n))
                  (let ((d (string-ref s (+ i 1))))
                    (let ((text (if (or (= mode %sh-mode-bare)
                                        (%sh-dq-escapable? d))
                                  (substring s (+ i 1) (+ i 2))
                                  (substring s i (+ i 2)))))
                      (self (+ i 2) mode
                        (%sh-acc-add-literal a text
                          (%sh-has-glob-meta? text))))))
                ; The older backtick substitution.
                ((= c #\`)
                  (let ((e (%sh-bt-end s (+ i 1) n)))
                    (if (< e 0)
                      (self (+ i 1) mode
                        (%sh-acc-add a (substring s i (+ i 1)) ()))
                      (self (+ e 1) mode
                        (%sh-add-expansion a mode
                          (%sh-cmd-subst
                            (%sh-bt-unescape (substring s (+ i 1) e)))
                          split?)))))
                ((= c #\$) (%sh-expand-dollar self s i n mode a split?))
                ; A tilde where one may expand; an ordinary character where
                ; not.  It is asked here rather than scanned for beforehand
                ; because this is the only place that knows the `~` is bare.
                ((and (= c #\~) (= mode %sh-mode-bare))
                  (let ((home (%sh-tilde-home s i n assign? eq)))
                    (if (null? home)
                      (self (+ i 1) mode (%sh-acc-add a "~" ()))
                      ; The result is LITERAL: a home directory with a space
                      ; in it is one field, and one with a `*` is not a
                      ; pattern.
                      (self (+ i 1) mode
                        (%sh-acc-add-literal a home
                          (%sh-has-glob-meta? home))))))
                ; Ordinary text goes in a run at a time: a plain word is one
                ; substring rather than one per character. A bare `*` is the
                ; glob; the same character inside quotes is not, so the run is
                ; escaped or not by the mode it was read in.
                (else
                  (let ((r (%sh-plain-run s i n mode ()
                             (and assign? (= mode %sh-mode-bare)))))
                    (let ((e (%sh-run-end r)) (meta? (%sh-run-meta? r)))
                      ; A run of nothing would not advance, which would hang
                      ; rather than answer. Every non-plain character is
                      ; claimed by an earlier arm, so this is unreachable and
                      ; says so if it ever is.
                      (when (= e i)
                        (error "internal: expansion made no progress"))
                      (let ((run (substring s i e)))
                        (self e mode
                          (match
                            ; The word of `${x:-word}` in place is split
                            ; where it is not quoted, its literal text as
                            ; well as its expansions (see %sh-add-word).
                            ((= mode %sh-mode-bare)
                              (if (eq? split? (lit fields))
                                (%sh-add-split a run)
                                (%sh-acc-add a run meta?)))
                            (#t (%sh-acc-add-literal a run meta?)))))))))))))
      (go start mode0 a0))))

; SPLIT? is off for the two places POSIX does not split: a `case` subject, and
; a redirection target (where more than one field is an ambiguous redirect).
;
; A tok-word starts bare.  A tok-dq starts in mode 2 -- its outer quotes were
; already stripped by the reader, so there is no opening quote left to switch
; on, and the field must start open or `cmd ""` passes no argument at all.
;
; A bare word that is one plain run -- `true`, `-lt`, `*.c` -- is its own
; single field, with no accumulator to build and join and no walk to make.
; Any other word starts the walk past its leading run, so no character is read
; twice.  An empty word walks too, because an empty bare word is no field at
; all and an empty quoted one is one empty field, which the walk tells apart.
; SPLIT? may also be `fields`, for the word of `${x:-word}` standing in place:
; then its unquoted literal text is split as an expansion's would be, so that
; word is always walked, its leading run included.  And it may be `pattern`,
; for a word that is a pattern -- a `case` pattern, the operand of `${x#pat}`:
; nothing is split, and a backslash an expansion's value holds escapes the
; character after it (see %sh-add-expansion).
(def %sh-expand-str
  (fn (_ s mode0 split? assign?)
    (let ((n (string-length s))
          (lead (%sh-lead-run s (string-length s) mode0 assign?)))
      (match
        ((eq? split? (lit fields))
          (%sh-expand-walk s n mode0 split? assign? 0 %sh-acc-empty))
        ((= (%sh-run-end lead) 0)
          (%sh-expand-walk s n mode0 split? assign? 0
            (if (= mode0 %sh-mode-dq) (%sh-acc-open %sh-acc-empty) %sh-acc-empty)))
        ((= (%sh-run-end lead) n)
          (list (%sh-field s (%sh-run-meta? lead) ())))
        (#t
          (%sh-expand-walk s n mode0 split? assign? (%sh-run-end lead)
            (%sh-acc-add %sh-acc-empty (substring s 0 (%sh-run-end lead))
                         (%sh-run-meta? lead))))))))

; Whether C names a one-character parameter: $? $$ $! $- $# $@ $* and $1..$9.
; A single digit only, per POSIX: `$10` is `$1` followed by a literal 0, and
; `${10}` is how the tenth is spelled.
(def %sh-special-param?
  (fn (_ c)
    (match
      ((= c #\?) #t)
      ((= c #\$) #t)
      ((= c #\!) #t)
      ((= c #\-) #t)
      ((= c #\#) #t)
      ((= c #\@) #t)
      ((= c #\*) #t)
      (#t (%sh-digit? c)))))

; The `$` arm, lifted out so the walk above stays readable.  CONT is the
; walker's own continuation, resumed at an index with an accumulator.
(def %sh-expand-dollar
  (fn (_ cont s i n mode a split?)
    (do
      ; Two local helpers, bound here so they stay local: this file already
      ; has more module-level %-names than it needs, and neither is
      ; meaningful outside this function.
      (def literal-dollar
        (fn (_) (cont (fx+ i 1) mode (%sh-acc-add a "$" ()))))
      (def substitute
        (fn (_ next text)
          (cont next mode (%sh-add-expansion a mode text split?))))
      ; J is the character after the `$`.
      (def j (fx+ i 1))
      ; A `$` at the very end is a literal `$`.
      (if (not (fx<? j n))
        (%sh-acc-finish (%sh-acc-add a "$" ()))
        (do
          (def d (string-ref s j))
          (match
            ; $NAME, the most common, so asked first.
            ((%sh-name-start? d)
              (do
                (def e (%sh-name-end s (fx+ j 1) n))
                (substitute e (%sh-var-value-checked (substring s j e)))))
            ; $( ... ) -- a command substitution.
            ((= d #\()
              (do
                (def e (%sh-cs-end s (fx+ j 1) n 0))
                (if (fx<? e 0)
                  (literal-dollar)
                  (do
                    (def inner (substring s (fx+ j 1) e))
                    (substitute (fx+ e 1)
                      (if (%sh-arith? inner)
                        (%sh-arith-eval (%sh-arith-text inner))
                        (%sh-cmd-subst inner)))))))
            ; ${NAME}
            ((= d #\{)
              (do
                (def e (%sh-brace-end s (fx+ j 1) n 0))
                (if (fx<? e 0)
                  (literal-dollar)
                  (do
                    (def inner (substring s (fx+ j 1) e))
                    ; `${@}` and `${*}` ask exactly what `$@` and `$*` ask, so
                    ; they are answered in the same place.
                    (if (if (string=? inner "@") #t (string=? inner "*"))
                      (cont (fx+ e 1) mode (%sh-add-all-params a inner mode split?))
                      ; A value operator that fired answers its word to stand
                      ; here, rather than text (see %sh-param-default).
                      (do
                        (def r (%sh-brace-expand inner))
                        (if (pair? r)
                          (cont (fx+ e 1) mode (%sh-add-word a mode (rest r) split?))
                          (substitute (fx+ e 1) r))))))))
            ; `$@` and `$*` are the specials that are not one string -- see
            ; %sh-add-all-params.
            ((if (= d #\@) #t (= d #\*))
              (cont (fx+ j 1) mode
                (%sh-add-all-params a (if (= d #\@) "@" "*") mode split?)))
            ((%sh-special-param? d)
              (substitute (fx+ j 1)
                (%sh-var-value-checked (substring s j (fx+ j 1)))))
            ; $ followed by anything else is a literal $.
            (#t (literal-dollar))))))))

; --- Pathname expansion -----------------------------------------------------
;
; A field holding an UNESCAPED glob character is matched against the
; filesystem, and becomes the sorted list of what it matched.  A field that
; matches nothing stays as it is -- POSIX's default, and the reason
; `echo *.nosuch` prints the pattern rather than nothing.
;
; The escapes %sh-acc-add-literal put in are what distinguishes `echo *` from
; `echo "*"`; they come off here, whether or not the field globbed.

; Same short-circuit: a field with no backslash is already its own unescaping.
(def %sh-has-backslash?
  (fn (_ text)
    (let ((n (string-length text)))
      (def go
        (fn (self i)
          (if (>= i n)
            ()
            (if (= (string-ref text i) #\\) #t (self (+ i 1))))))
      (go 0))))

(def %sh-glob-unescape
  (fn (_ text)
    (if (not (%sh-has-backslash? text))
      text
      (let ((n (string-length text)))
        (def go
          (fn (self i out)
            (if (>= i n)
              (%ash-join "" (reverse out))
              (if (and (= (string-ref text i) #\\) (< (+ i 1) n))
                (self (+ i 2) (pair (substring text (+ i 1) (+ i 2)) out))
                (self (+ i 1) (pair (substring text i (+ i 1)) out))))))
        (go 0 ())))))

; Does this text hold a glob character the user meant AS one?  Escaped ones do
; not count, which is the whole point of the escaping, and neither does a `[`
; that no `]` closes: POSIX makes that an ordinary character, and %sh-glob-at
; matches it as one.  Both ask %sh-glob-class-end where a bracket expression
; ends, so they cannot disagree about it.
(def %sh-glob-pattern?
  (fn (_ text)
    (let ((n (string-length text)))
      (def go
        (fn (self i)
          (if (>= i n)
            ()
            (let ((c (string-ref text i)))
              (match
                ((= c #\\) (self (+ i 2)))
                ((= c #\*) #t)
                ((= c #\?) #t)
                ((and (= c #\[) (>= (%sh-glob-class-end text (+ i 1) n) 0)) #t)
                (#t (self (+ i 1))))))))
      (go 0))))

; Split on UNESCAPED `/`.
(def %sh-glob-split
  (fn (_ text)
    (let ((n (string-length text)))
      (def go
        (fn (self i seg acc)
          (if (>= i n)
            (reverse (pair seg acc))
            (let ((c (string-ref text i)))
              (if (= c #\\)
                (self (+ i 2) (string-append seg (substring text i (+ i 2))) acc)
                (if (= c #\/)
                  (self (+ i 1) "" (pair seg acc))
                  (self (+ i 1)
                    (string-append seg (substring text i (+ i 1))) acc)))))))
      (go 0 "" ()))))

; "" means the current directory, and stays invisible in what is built: a
; relative glob answers `bin/sh`, not `./bin/sh`.
(def %sh-path-join
  (fn (_ base name)
    (cond
      ((= (string-length base) 0) name)
      ((string=? base "/") (string-append "/" name))
      (else (string-append base (string-append "/" name))))))

(def %sh-dir-of (fn (_ base) (if (= (string-length base) 0) "." base)))

; A leading `.` is matched only by a pattern that starts with one -- the rule
; that keeps `*` from answering dotfiles.
(def %sh-glob-visible?
  (fn (_ pattern name)
    (if (= (string-ref name 0) #\.)
      (if (= (string-length pattern) 0)
        ()
        (= (string-ref pattern 0) #\.))
      #t)))

(def %sh-glob-entries
  (fn (_ base segment)
    (%sh-keep
      (fn (_ name)
        (and (%sh-glob-visible? segment name)
             (%sh-pattern-match? segment name)))
      (sh-list-dir (%sh-dir-of base)))))

(def %sh-keep
  (fn (self p xs)
    (if (null? xs)
      ()
      (if (p (first xs))
        (pair (first xs) (self p (rest xs)))
        (self p (rest xs))))))

; One segment against every base reached so far.
(def %sh-glob-step
  (fn (self segment bases acc)
    (if (null? bases)
      (reverse acc)
      (let ((base (first bases)))
        (self segment (rest bases)
          (%sh-prepend-rev
            (if (%sh-glob-pattern? segment)
              (%sh-map-join base (%sh-glob-entries base segment))
              ; A literal segment contributes only if it is really there.
              (let ((cand (%sh-path-join base (%sh-glob-unescape segment))))
                (if (null? (sh-path-kind cand)) () (list cand))))
            acc))))))

(def %sh-map-join
  (fn (self base names)
    (if (null? names)
      ()
      (pair (%sh-path-join base (first names))
            (self base (rest names))))))

(def %sh-prepend-rev
  (fn (self xs acc)
    (if (null? xs) acc (self (rest xs) (pair (first xs) acc)))))

(def %sh-glob-walk
  (fn (self segments bases)
    (if (or (null? segments) (null? bases))
      bases
      ; An empty segment is a `//` or a trailing `/`: it moves nothing on.
      (self (rest segments)
        (if (= (string-length (first segments)) 0)
          bases
          (%sh-glob-step (first segments) bases ()))))))

; A TRAILING `/` MEANS DIRECTORIES ONLY, and keeps the slash -- `echo */`
; answers `sub/`, not every entry.  The split leaves an empty last segment for
; it, which the walk skips as it does any empty one; the restriction is applied
; here, where the whole match is in hand.
(def %sh-dirs-only
  (fn (self hits)
    (if (null? hits)
      ()
      (let ((tail (self (rest hits))))
        (if (eq? (sh-path-kind (first hits)) (lit dir))
          (pair (string-append (first hits) "/") tail)
          tail)))))

(def %sh-trailing-slash?
  (fn (_ segments)
    (and (not (null? segments))
         (= (string-length (last segments)) 0))))

; The field knows whether it holds a live metacharacter and whether it carries
; escapes, which settles most words with no scan.  A word that does hold one
; is scanned once more before the directory is read, because the walk saw a
; `[` before it could know whether a `]` closes it -- the `]` can arrive in a
; later piece -- and a word that is not a pattern must not reach the directory.
; `set -f` turns pathname expansion off, so every field stands as written --
; its escapes removed, the way a field that is no pattern stands.
(def %sh-glob-field
  (fn (_ f)
    (if (or %sh-opt-noglob
            (not (and (%sh-field-glob? f) (%sh-glob-pattern? (%sh-field-text f)))))
      (list (%sh-field-plain f))
      (let ((field (%sh-field-text f))
            (absolute? (= (string-ref (%sh-field-text f) 0) #\/))
            (segments (%sh-glob-split (%sh-field-text f))))
        (let ((hits (%sh-glob-walk
                      (if absolute? (rest segments) segments)
                      (list (if absolute? "/" "")))))
          (let ((final (if (%sh-trailing-slash? segments)
                         (%sh-dirs-only hits)
                         hits)))
            ; No match: the pattern stands, with its escapes removed.
            ; No match: the pattern stands, as the user wrote it.
            (if (null? final) (list (%sh-field-plain f)) final)))))))

; GLOB TEXT THAT DID NOT COME THROUGH THE WALK -- a bare string, held by a
; caller with no field around it.  The two flags have to be derived by
; scanning here, which is precisely the work the walk exists to have done
; already; anything on the expansion path passes a field instead.
(def %sh-glob-text
  (fn (_ text)
    (%sh-glob-field
      (%sh-field text (%sh-glob-pattern? text) (%sh-has-backslash? text)))))

(def %sh-glob-fields
  (fn (self fields)
    (if (null? fields)
      ()
      (append (%sh-glob-field (first fields)) (self (rest fields))))))

; --- What the callers see ----------------------------------------------------
;
; A tok-sq is one field, always: single quotes suppress everything, splitting
; included, and `''` is an empty argument rather than none.
(def %sh-tok-mode
  (fn (_ tok)
    (if (eq? (first tok) (lit tok-dq)) %sh-mode-dq %sh-mode-bare)))

; ASSIGN? says this word is an assignment: a leading NAME=... of the command,
; or an argument to a utility whose arguments are assignments. Two POSIX rules
; turn on it.
;
; Its value is not split and not globbed: `v=$(echo a b)` is one field and
; `g=$(echo "*")` is a star, per "the word shall be expanded ... without field
; splitting or pathname expansion".
;
; Its tilde expands after the `=` (and after any `:` beyond it), which is
; %sh-tilde-pos?.
(def %sh-expand-tok
  (fn (_ tok assign?)
    (if (eq? (first tok) (lit tok-sq))
      ; Single quotes suppress everything, globbing included.
      (list (%tok-word-val tok))
      (let ((fs (%sh-expand-str (%tok-word-val tok) (%sh-tok-mode tok)
                  (not assign?) assign?)))
        (if (not assign?)
          (%sh-glob-fields fs)
          ; Unsplit by construction above, so there is one field or none; the
          ; escapes still come off, because nothing here is a pattern.
          (list (if (null? fs) "" (%sh-field-plain (first fs)))))))))

; The unsplit reading, for a `case` subject and a redirection target.
(def %sh-expand-tok-1
  (fn (_ tok)
    (if (eq? (first tok) (lit tok-sq))
      (%tok-word-val tok)
      (let ((fs (%sh-expand-str (%tok-word-val tok) (%sh-tok-mode tok) () ())))
        ; Not globbed, but the escapes still come off -- a redirection target
        ; and a case subject are literal strings.
        (if (null? fs) "" (%sh-field-plain (first fs)))))))

; A case pattern is expanded like any word -- a parameter, a substitution,
; arithmetic -- but it is a PATTERN afterwards, so the escapes stay on: what
; quoting made literal must stay literal to the matcher, and `case x in "*")`
; is a star to look for rather than a star to match anything with.  Neither
; split nor globbed, being one pattern rather than a list of filenames.
(def %sh-expand-pattern
  (fn (_ tok)
    (if (eq? (first tok) (lit tok-sq))
      (%sh-glob-escape-all (%tok-word-val tok))
      (let ((fs (%sh-expand-str (%tok-word-val tok) (%sh-tok-mode tok)
                  (lit pattern) ())))
        (if (null? fs) "" (%sh-field-text (first fs)))))))

; Still string-in, string-out, for the sites that hold a value rather than a
; token.  Unsplit by construction.
(def %sh-expand-word
  (fn (_ word)
    (if (not (string? word))
      word
      (let ((fs (%sh-expand-str word %sh-mode-bare (lit pattern) ())))
        ; The escapes stay on: this feeds pattern operands (`${x#pat}`), which
        ; read them. %sh-field-plain is for the sites that want literal text.
        (if (null? fs) "" (%sh-field-text (first fs)))))))

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
        (if (%sh-word-in? op %sh-redirect-ops) op ())))))

(def %all-digits-from?
  (fn (self s i len)
    (match
      ((= i len) #t)
      ((%sh-digit? (string-ref s i)) (self s (fx+ i 1) len))
      (#t ()))))

(def %all-digits?
  (fn (_ s)
    (if (= (string-length s) 0) () (%all-digits-from? s 0 (string-length s)))))

; The number S spells, S being digits only -- a descriptor, a here-document's
; index -- read by the arithmetic reader's digit loop rather than `convert`,
; which costs several times as much.  Nil when S is not all digits.
(def %sh-digits-int
  (fn (_ s)
    (if (%all-digits? s) (%sh-ar-digits-value s 0 (string-length s) 10 0) ())))

; Which descriptor an operator redirects when the script names none.
(def %sh-input-ops (list "<" "<>" "<&" "<<" "<<-"))

(def %default-fd
  (fn (_ op) (if (%sh-word-in? op %sh-input-ops) 0 1)))

; --- The redirection record -------------------------------------------------
;
; (sh-redir OP FD TARGET), and its three fields were read back as
; (first (rest (rest redir))) at each of three sites.  Named, so the shape
; lives in one place and a reader does not have to count `rest`s.
;
; FD is an int: %default-fd's, or the digits the script wrote against the
; operator (`2> log`), read once where the redirection is collected.
(def %sh-redir (fn (_ op fd target) (list (lit sh-redir) op fd target)))

; The target of a redirection whose OPERATOR HAS JUST BEEN CONSUMED.  Both
; places that read redirections come through here -- after a simple command's
; words, and after a compound -- so "redirect without target" and the
; unsplit reading of the target are each stated once.
;
; NOT SPLIT.  `> $f` with two fields in $f is an ambiguous redirect in POSIX,
; not two files; taking the unsplit reading keeps the common case right and
; the pathological one harmless.
(def %sh-read-redir-target
  (fn (_ cur rop fd)
    (if (%cursor-empty? cur)
      (error "parse error: redirect without target")
      (let ((target (%sh-expand-tok-1 (%cursor-peek cur))))
        (%cursor-advance! cur)
        (%sh-redir rop fd target)))))

; The redirection whose descriptor number is the tok-io IO, the cursor past it.
; The operator is the next token: the tokenizer ends such a run of digits only
; where one starts.
(def %sh-io-redir
  (fn (_ cur io)
    (let ((rop (if (%cursor-empty? cur) () (%redir-op? (%cursor-peek cur)))))
      (if (null? rop)
        (error "parse error: redirect without operator")
        (do
          (%cursor-advance! cur)
          (%sh-read-redir-target cur rop (%sh-digits-int (%tok-word-val io))))))))
(def %sh-redir-op     (fn (_ r) (first (rest r))))
(def %sh-redir-target (fn (_ r) (first (rest (rest (rest r))))))
(def %sh-redir-fd     (fn (_ r) (first (rest (rest r)))))

; A here-document's body reaches the command down a pipe.
;
; The writer is a forked child, not this process: writing the body here and
; reading it back would deadlock on any body larger than the pipe buffer, since
; nothing is draining the other end yet. The child writes and exits; the parent
; keeps the read end. It is not waited for -- waiting would deadlock from the
; other side -- so the writer is reaped when the shell exits.
(def %sh-setup-heredoc
  (fn (_ index fd)
    (let ((h (%sh-heredoc-at (%sh-digits-int index))))
      (if (null? h)
        ()
        (let ((text (if (%sh-heredoc-expand? h)
                      ; An unquoted delimiter expands the body the way a
                      ; double-quoted string is expanded.
                      (%sh-expand-str-dq (%sh-heredoc-text h))
                      (%sh-heredoc-text h))))
          (let ((p (%sh-pipe-create)))
            (let ((r (first p)) (w (rest p)))
              (let ((pid (sh-fork)))
                (if (= pid 0)
                  (do
                    (sh-close r)
                    (sh-fd-write w text)
                    (sh-close w)
                    (sh-exit 0))
                  (do
                    (sh-close w)
                    (%sh-move-fd r fd)))))))))))

(def %sh-heredoc-at
  (fn (self n)
    (def pick
      (fn (self i hs)
        (if (null? hs) () (if (= i n) (first hs) (self (+ i 1) (rest hs))))))
    (pick 0 %sh-heredocs)))

; The body of an unquoted here-document expands like a double-quoted string:
; parameters and substitutions, but no field splitting and no globbing.
(def %sh-expand-str-dq
  (fn (_ text)
    (let ((fs (%sh-expand-str text %sh-mode-dq () ())))
      (if (null? fs) "" (%sh-field-plain (first fs))))))

; A redirection that cannot be made is reported here, and answers nil.  What
; that does to the command is the caller's to say: a command's own redirection
; only keeps the command from running, while a special builtin's ends the shell.
(def %sh-redir-failed
  (fn (_ verb target)
    (do (%stderr "ash: cannot " verb " " target "\n") ())))

; FROM onto TO, and FROM closed: the descriptor moves.  An open or a pipe
; answers the lowest descriptor free, so FROM can already be TO -- `exec 3<f`
; with 3 free opens f as 3 -- and closing it then would close the file.
(def %sh-move-fd
  (fn (_ from to)
    (if (= from to) () (do (sh-dup2 from to) (sh-close from)))))

; The opened descriptor onto FD, or nil when the file could not be opened: the
; open answers -1 rather than raising.
(def %sh-redir-onto
  (fn (_ fh fd verb target)
    (if (fx<? fh 0)
      (%sh-redir-failed verb target)
      (do (%sh-move-fd fh fd) #t))))

; `>&2` and `<&0` name a descriptor the shell already has; `>&-` and `<&-`
; close FD instead, and closing one that is not open is no failure, as in
; both reference shells.  A word that is neither a number nor `-`, and a
; number nothing is open on, are both refusals.
(def %sh-redir-dup
  (fn (_ target fd)
    (if (string=? target "-")
      (do (sh-close fd) #t)
      (let ((from (%sh-digits-int target)))
        (if (null? from)
          (%sh-redir-failed "duplicate" target)
          (if (fx<? (sh-dup2 from fd) 0)
            (%sh-redir-failed "duplicate" target)
            #t))))))

; Answers whether the redirection was made.
(def %sh-setup-redir
  (fn (_ redir)
    (let ((op (%sh-redir-op redir))
           ; Expanded at collection, with its quoting in hand.
           (target (%sh-redir-target redir)))
      (let ((fd (%sh-redir-fd redir)))
        (match
          ((or (string=? op "<<") (string=? op "<<-"))
            (do (%sh-setup-heredoc target fd) #t))
          ((string=? op "<")
            (%sh-redir-onto (sh-open-read target) fd "open" target))
          ((string=? op ">")
            (%sh-redir-onto (%sh-open-output target) fd "create" target))
          ((string=? op ">|")
            (%sh-redir-onto (sh-open-write target) fd "create" target))
          ((string=? op ">>")
            (%sh-redir-onto (sh-open-append target) fd "create" target))
          ((string=? op "<>")
            (%sh-redir-onto (sh-open-rdwr target) fd "open" target))
          ((string=? op ">&") (%sh-redir-dup target fd))
          ((string=? op "<&") (%sh-redir-dup target fd))
          (#t #t))))))

; `>`'s file.  Under `set -C` a regular file already there is refused, as dash
; and bash refuse it, while a file that is not there is created only if it is
; still not there when opened, and anything else -- /dev/null, a terminal -- is
; written to as it is.  `>|` opens as `>` does without the option.
(def %sh-open-output
  (fn (_ path)
    (match
      ((null? %sh-opt-noclobber) (sh-open-write path))
      ((null? (sh-path-kind path)) (sh-open-new path))
      ((eq? (sh-path-kind path) (lit file)) (- 0 1))
      (#t (sh-open-existing path)))))

; All of them, in order, and nil as soon as one could not be made.
(def %sh-setup-redirs
  (fn (self redirs)
    (if (null? redirs)
      #t
      (if (%sh-setup-redir (first redirs)) (self (rest redirs)) ()))))

; The status a command answers when its redirection could not be made.  dash
; says 2 here and bash 1; POSIX leaves it to the shell.
(def %sh-redir-status 2)

; A command whose redirection could not be made does not run.  For a SPECIAL
; builtin that ends a shell that is not interactive (POSIX 2.8.1), which the
; raise does: the prompt reports nothing more and reads on, a script ends.
(def %sh-redir-refused
  (fn (_ name)
    (if (%sh-special-builtin? name)
      (error (lit %sh-reported))
      %sh-redir-status)))

; A builtin's redirections are applied and then undone. A builtin runs in the
; shell itself, so `echo x > out.txt` must not leave the shell writing to
; out.txt afterwards -- unlike an external, whose redirections are set up in
; the child after the fork. A function call's and a compound's are undone the
; same way, and so is the stdin a pipeline moves: save the descriptor,
; redirect, run, restore.
;
; These nest -- `log() { echo "$*" >&2; }; main >out 2>&1` applies echo's >&2
; while main's are in force -- so each descriptor a redirection changes is
; parked on a descriptor of its own, taken in turn from %sh-fd-park-base up
; and handed back as the redirection is undone, innermost first.  The base
; clears the descriptors a script plausibly names itself, and x.sh's fd 3.  A
; descriptor that was not open is parked as nil, and closed again after.
(def %sh-fd-park-base 30)
(def %sh-fd-park-next %sh-fd-park-base)

; Park each of FDS.  Answers ((fd . parked) ...) latest first, the order they
; are put back in, so an fd named twice gets its first value back last.
(def %sh-park-fds
  (fn (self fds parked)
    (if (null? fds)
      parked
      (let ((slot %sh-fd-park-next))
        (set! %sh-fd-park-next (fx+ slot 1))
        (self (rest fds)
              (pair (pair (first fds)
                          (if (fx<? (sh-dup2 (first fds) slot) 0) () slot))
                    parked))))))

; Put back what %sh-park-fds or %sh-save-fds parked.
(def %sh-restore-fds
  (fn (self parked)
    (unless (null? parked)
      (let ((fd (first (first parked))) (slot (rest (first parked))))
        (if (null? slot)
          (sh-close fd)
          (do (sh-dup2 slot fd) (sh-close slot)))
        (set! %sh-fd-park-next (- %sh-fd-park-next 1))
        (self (rest parked))))))

(def %sh-redir-fds
  (fn (self redirs)
    (if (null? redirs)
      ()
      (pair (%sh-redir-fd (first redirs)) (self (rest redirs))))))

; What REDIRS change, parked.
(def %sh-save-fds
  (fn (_ redirs) (%sh-park-fds (%sh-redir-fds redirs) ())))
; --- Built-in commands ---

; `echo` writes its operands with a space between each and a newline after, and
; reads a backslash in them as XSI has it: \a \b \f \n \r \t \v and \\ are
; those characters, \0 with up to three octal digits after it is the byte they
; make, and \c ends the output where it stands, newline and all.  Any other
; backslash is itself.  A first operand of -n leaves the newline off.  dash and
; bash read the escapes so.  Where the two part -- -n, which bash as sh
; prints; \NNN without its 0; \xHH -- ash reads -n as dash does, and the other
; two as the backslash and text POSIX leaves them.  A NUL byte cannot be held
; in a string here, so \0 making 0 writes nothing (see %sh-byte-string).
(def %sh-echo
  (fn (_ wds)
    (do
      (def suppress (if (null? wds) () (string=? (first wds) "-n")))
      (def r (%sh-echo-words (if suppress (rest wds) wds) () #t))
      (display (%ash-join "" (reverse (rest r))))
      (if (if suppress #t (first r)) () (newline))
      0)))

; The operands WS with their escapes read, pushed onto OUT with a space before
; each but the first: answers (STOPPED? . OUT), STOPPED? when a \c ended them.
(def %sh-echo-words
  (fn (self ws out first?)
    (match
      ((null? ws) (pair () out))
      (#t
        (do
          (def r (%sh-echo-escapes (first ws) 0 (string-length (first ws))
                   (if first? out (pair " " out))))
          (if (first r) r (self (rest ws) (rest r) ())))))))

; One operand from I, its escapes read, pushed onto OUT: answers
; (STOPPED? . OUT) as %sh-echo-words does.
(def %sh-echo-escapes
  (fn (self s i n out)
    (match
      ((not (fx<? i n)) (pair () out))
      ((not (= (string-ref s i) #\\))
        (do
          (def j (%sh-backslash-from s i n))
          (self s j n (pair (substring s i j) out))))
      ; A backslash at the end escapes nothing, and is itself.
      ((not (fx<? (fx+ i 1) n)) (pair () (pair "\\" out)))
      ((= (string-ref s (fx+ i 1)) #\c) (pair #t out))
      ((= (string-ref s (fx+ i 1)) #\0)
        (do
          (def e (%sh-octal-end s (fx+ i 2) n (fx+ i 5)))
          (def v (%sh-ar-digits-value s (fx+ i 2) e 8 0))
          (self s e n (pair (%sh-byte-string (if (fx<? v 256) v (fx+ v -256))) out))))
      (#t
        (do
          (def code (%sh-echo-escape-code (string-ref s (fx+ i 1))))
          (self s (fx+ i 2) n
            (pair (if (null? code) (substring s i (fx+ i 2)) (%sh-byte-string code))
                  out)))))))

; The code a letter after a backslash names, or nil for one that names none.
(def %sh-echo-escape-code
  (fn (_ c)
    (match
      ((= c #\a) 7)
      ((= c #\b) 8)
      ((= c #\f) 12)
      ((= c #\n) 10)
      ((= c #\r) 13)
      ((= c #\t) 9)
      ((= c #\v) 11)
      ((= c #\\) 92)
      (#t ()))))

; The index of the next backslash at or after I, or N.
(def %sh-backslash-from
  (fn (self s i n)
    (match
      ((not (fx<? i n)) n)
      ((= (string-ref s i) #\\) i)
      (#t (self s (fx+ i 1) n)))))

; The end of the run of octal digits from I, stopping by N and by LIMIT.
(def %sh-octal-end
  (fn (self s i n limit)
    (match
      ((not (fx<? i n)) i)
      ((not (fx<? i limit)) i)
      ((fx<? (string-ref s i) #\0) i)
      ((fx<? (string-ref s i) #\8) (self s (fx+ i 1) n limit))
      (#t i))))

; A string of the one byte V, as a byte rather than a character: \0377 is the
; byte 255, where a character 255 would be written as two.  A string ends at
; a NUL byte here, so the byte 0 is the empty string, and echo writes nothing
; for it.
(def %sh-byte-string
  (fn (_ v) (bytes->str (list v))))

; The working directory as a path rather than as an inode: the route the
; shell took to it, with any symlink on that route left as it was written.
; POSIX folds `.` and `..` in a cd operand by text instead of by following the
; link, so `cd /tmp` then `cd ..` arrives at `/` even where /tmp is a symlink
; to /private/tmp.  getcwd can only answer the resolved path, so the shell
; keeps its own and seeds it from getcwd once.
(def %sh-pwd-logical ())

(def %sh-cwd-logical
  (fn (_)
    (if (null? %sh-pwd-logical)
      (do
        (set! %sh-pwd-logical (let ((d (sh-getcwd))) (if (null? d) "/" d)))
        %sh-pwd-logical)
      %sh-pwd-logical)))

; One component against the components kept so far, which are held reversed.
; A `..` at the root stays at the root.
(def %sh-path-step
  (fn (_ kept part)
    (match
      ((= (string-length part) 0) kept)
      ((string=? part ".") kept)
      ((string=? part "..") (if (null? kept) kept (rest kept)))
      (#t (pair part kept)))))

; Fold `.` and `..` out of an absolute path by text.
(def %sh-path-fold
  (fn (_ path)
    (let ((n (string-length path)))
      (def walk
        (fn (self i start kept)
          (if (> i n)
            kept
            (if (or (= i n) (= (string-ref path i) #\/))
              (self (+ i 1) (+ i 1)
                (%sh-path-step kept (substring path start i)))
              (self (+ i 1) start kept)))))
      (let ((parts (reverse (walk 0 0 ()))))
        (if (null? parts) "/" (string-append "/" (%ash-join "/" parts)))))))

; Where an operand points, read against the logical directory rather than the
; resolved one.
(def %sh-cd-target
  (fn (_ dir base)
    (%sh-path-fold
      (if (%sh-str-starts? dir "/")
        dir
        (string-append base (string-append "/" dir))))))

; No operand means HOME.  `-` means OLDPWD, and answers () when there is none
; to return to.
(def %sh-cd-destination
  (fn (_ wds)
    (if (null? wds)
      (let ((home (%sh-var-get "HOME"))) (if (null? home) "/" home))
      (let ((operand (first wds)))
        (if (not (string=? operand "-"))
          operand
          (let ((old (%sh-var-get "OLDPWD")))
            (if (or (null? old) (= (string-length old) 0)) () old)))))))

; `-L` and `-P`, for cd and pwd, and letters of them run together: whether the
; directory is read physically, the last letter deciding.  `--` ends them, and
; `-` alone is cd's operand for OLDPWD.  Answers (physical? . words left).
(def %sh-lp-options
  (fn (self wds physical?)
    (match
      ((null? wds) (pair physical? wds))
      ((string=? (first wds) "--") (pair physical? (rest wds)))
      ((%sh-lp-word? (first wds))
        (self (rest wds)
              (= (string-ref (first wds) (- (string-length (first wds)) 1)) #\P)))
      (#t (pair physical? wds)))))

(def %sh-lp-word?
  (fn (_ w)
    (let ((n (string-length w)))
      (match
        ((fx<? n 2) ())
        ((= (string-ref w 0) #\-) (%sh-lp-letters? w 1 n))
        (#t ())))))

(def %sh-lp-letters?
  (fn (self w i n)
    (match
      ((not (fx<? i n)) #t)
      ((= (string-ref w i) #\L) (self w (fx+ i 1) n))
      ((= (string-ref w i) #\P) (self w (fx+ i 1) n))
      (#t ()))))

; The directory as getcwd resolves it, every symlink followed.
(def %sh-cwd-physical
  (fn (_) (let ((d (sh-getcwd))) (if (null? d) (%sh-cwd-logical) d))))

; `cd -P` goes where the kernel takes the operand, `..` after a symlink
; included, and PWD becomes the resolved path; `cd -L`, the default, folds the
; operand against the logical directory by text.
(def %sh-cd
  (fn (_ args)
    (let ((opts (%sh-lp-options args ())))
      (let ((physical? (first opts)) (wds (rest opts)))
        (let ((dest (%sh-cd-destination wds)))
          (if (null? dest)
            (do (%stderr "ash: cd: OLDPWD not set\n") 1)
            (let ((base (%sh-cwd-logical)))
              (let ((target (if physical? dest (%sh-cd-target dest base))))
                (if (= (sh-chdir target) -1)
                  (do
                    (%stderr "ash: cd: " dest ": No such file or directory\n")
                    1)
                  (let ((now (if physical? (%sh-cwd-physical) target)))
                    (%sh-var-set! "OLDPWD" base)
                    (%sh-var-set! "PWD" now)
                    (set! %sh-pwd-logical now)
                    ; `cd -` reports where it arrived, which is how a script
                    ; can use it without keeping its own copy of OLDPWD.
                    (unless (null? wds)
                      (when (string=? (first wds) "-")
                        (display now)
                        (newline)))
                    0))))))))))

; `export NAME[=VALUE]...`, every operand.  A value is assigned before the name
; is exported, so `export x=1` and `x=1; export x` leave the same variable, and
; a bare NAME with no value yet is marked for the value it gets later.
(def %sh-export
  (fn (self wds)
    (if (null? wds)
      0
      (let ((word (first wds)))
        (let ((eq (%sh-first-eq word 0 (string-length word))))
          (%sh-name-or-refuse! "export"
            (if (fx<? eq 0) word (substring word 0 eq)))
          (if (fx<? eq 0)
            (%sh-var-export! word)
            (do
              (%sh-var-set! (substring word 0 eq)
                            (substring word (fx+ eq 1) (string-length word)))
              (%sh-var-export! (substring word 0 eq))))
          (self (rest wds)))))))

; `local NAME[=VALUE]...` -- the shape `export` has, saving each name into the
; call's frame before it assigns.  A name given no value starts UNSET, which
; is bash and ksh; dash leaves the outer value showing through it, and that is
; the one thing the two disagree about.
;
; Outside a function there is no frame to record in, and nothing would ever
; put the value back, so it is refused.
; `local` is not a special builtin, so a word that is not a name is reported
; and answered with 1, and the words after it are still taken.
(def %sh-local-names
  (fn (self wds)
    (if (null? wds)
      0
      (let ((word (first wds)))
        (let ((eq (%sh-first-eq word 0 (string-length word))))
          (let ((name (if (fx<? eq 0) word (substring word 0 eq))))
            (if (%sh-name? name)
              (do
                (%sh-local-save! name)
                (if (fx<? eq 0)
                  (%sh-var-unset! name)
                  (%sh-var-set! name
                                (substring word (fx+ eq 1) (string-length word))))
                (self (rest wds)))
              (do
                (%sh-bad-name "local" name)
                (self (rest wds))
                1))))))))

(def %sh-local
  (fn (_ wds)
    (if (= %sh-fn-depth 0)
      (do (%stderr "ash: local: not in a function\n") 1)
      (%sh-local-names wds))))

; `readonly NAME[=VALUE]...` marks names that may not be assigned or unset
; again, assigning first where a value is given -- the shape `export` has.
; `readonly` and `readonly -p` write the marked names instead, each as the
; command that would mark it again.
(def %sh-readonly-mark!
  (fn (_ name)
    (unless (%sh-readonly? name)
      (set! %sh-readonly-names (pair name %sh-readonly-names)))))

(def %sh-readonly-names-each
  (fn (self wds)
    (if (null? wds)
      0
      (let ((word (first wds)))
        (let ((eq (%sh-first-eq word 0 (string-length word))))
          (%sh-name-or-refuse! "readonly"
            (if (fx<? eq 0) word (substring word 0 eq)))
          (if (fx<? eq 0)
            (%sh-readonly-mark! word)
            (do
              (%sh-var-set! (substring word 0 eq)
                            (substring word (fx+ eq 1) (string-length word)))
              (%sh-readonly-mark! (substring word 0 eq))))
          (self (rest wds)))))))

(def %sh-readonly-list
  (fn (self names)
    (unless (null? names)
      (let ((v (%sh-var-get (first names))))
        (display "readonly ")
        (display (first names))
        (unless (null? v)
          (display "=")
          (display (%sh-single-quote v)))
        (newline))
      (self (rest names)))))

(def %sh-readonly-builtin
  (fn (_ wds)
    (if (or (null? wds) (string=? (first wds) "-p"))
      (do (%sh-readonly-list (reverse %sh-readonly-names)) 0)
      (%sh-readonly-names-each wds))))

; A shell's truth is INVERTED: 0 is true.  %sh-bool turns a predicate's answer
; into that, once, instead of every arm spelling `(if p 0 1)`.
(def %sh-bool (fn (_ p) (if p 0 1)))

; --- test / [ -------------------------------------------------------------
;
; test knows -n, -z, =, != (string), the file predicates, and the numeric
; comparisons, joined by `!`, `-a`, `-o` and parentheses; an unknown operator
; is a usage error, not a silent false.

; Flat, via match: a nested if-ladder here once came out a closing paren short,
; which binds the defs that follow inside this function rather than at the top
; level and fails only later at the first command. A flat match cannot do that.
; The operator tables. A test operator is a name and a predicate; the shell's
; inverted truth (0 is true) is applied once, by the caller.
; One of the three bits above the permissions: setuid 0o4000, setgid 0o2000,
; sticky 0o1000.  A path that is not there has none, its mode reading 0.
(def %sh-mode-bit?
  (fn (_ path bit) (not (= 0 (& (sh-path-mode path) bit)))))

; `-L` and `-h` ask about the path itself, so they look without following a
; link; every other test follows it, as `-e` on a dangling link answers false.
; `-r`, `-w` and `-x` are not here: they are access(2)'s question, which asks
; about the process as well as the file, and the platform has no door to it.
(def %sh-file-ops
  (list (pair "-e" (fn (_ kind path) (not (null? kind))))
        (pair "-f" (fn (_ kind path) (eq? kind (lit file))))
        (pair "-d" (fn (_ kind path) (eq? kind (lit dir))))
        (pair "-s" (fn (_ kind path)
                     (and (not (null? kind)) (> (sh-path-size path) 0))))
        (pair "-L" (fn (_ kind path) (eq? (sh-path-lkind path) (lit link))))
        (pair "-h" (fn (_ kind path) (eq? (sh-path-lkind path) (lit link))))
        (pair "-p" (fn (_ kind path) (eq? kind (lit fifo))))
        (pair "-S" (fn (_ kind path) (eq? kind (lit socket))))
        (pair "-b" (fn (_ kind path) (eq? kind (lit block))))
        (pair "-c" (fn (_ kind path) (eq? kind (lit char))))
        (pair "-u" (fn (_ kind path) (%sh-mode-bit? path 2048)))
        (pair "-g" (fn (_ kind path) (%sh-mode-bit? path 1024)))
        (pair "-k" (fn (_ kind path) (%sh-mode-bit? path 512)))))

; `-t FD`: whether the descriptor is a terminal.  A word that is not a number
; names no descriptor, and is none.
(def %sh-tty?
  (fn (_ word)
    (let ((fd (convert word %int)))
      (if (null? fd) () (Sys isatty fd)))))

; Whether A was modified after B.  A path that is not there is older than any
; that is, so `new -nt missing` is true: POSIX's reading, and bash's, where
; dash answers false when either is missing.
(def %sh-newer?
  (fn (_ a b)
    (let ((ta (sh-path-mtime a)) (tb (sh-path-mtime b)))
      (match
        ((null? ta) ())
        ((null? tb) #t)
        (#t (fx<? tb ta))))))

; Answers nil -- NOT 1 -- when the operator is not a file test, so the caller
; can tell "not a file operator" from "the test was false".
(def %sh-test-file
  (fn (_ op path)
    (let ((p (%sh-table-get op %sh-file-ops)))
      (if (null? p) () (%sh-bool (p (sh-path-kind path) path))))))

(def %sh-num-ops
  (list (pair "-eq" (fn (_ a b) (= a b)))
        (pair "-ne" (fn (_ a b) (not (= a b))))
        (pair "-lt" (fn (_ a b) (< a b)))
        (pair "-le" (fn (_ a b) (<= a b)))
        (pair "-gt" (fn (_ a b) (> a b)))
        (pair "-ge" (fn (_ a b) (>= a b)))))

; A numeric operator's answer, nil when OP is not one, or 2 when an operand
; is no integer.
(def %sh-test-num
  (fn (_ l op r)
    (let ((p (%sh-table-get op %sh-num-ops)))
      (if (null? p)
        ()
        (let ((a (%sh-test-int l)) (b (%sh-test-int r)))
          (match
            ((null? a) (%sh-test-usage l "integer expression expected"))
            ((null? b) (%sh-test-usage r "integer expression expected"))
            (#t (%sh-bool (p a b)))))))))

; An integer operand: decimal digits with a sign in front and blanks around
; them allowed, so `010` is ten and `0x10` is no integer.  Answers the value,
; or nil for anything else.
(def %sh-test-int
  (fn (_ word)
    (let ((n (%sh-ar-ws-before word (string-length word))))
      (let ((i (%sh-ar-skip-ws word 0 n)))
        (match
          ((not (fx<? i n)) ())
          ((= (string-ref word i) #\-) (%sh-test-digits word (fx+ i 1) n #t))
          ((= (string-ref word i) #\+) (%sh-test-digits word (fx+ i 1) n ()))
          (#t (%sh-test-digits word i n ())))))))

(def %sh-test-digits
  (fn (_ word i n negative?)
    (match
      ((not (fx<? i n)) ())
      ((not (%all-digits-from? word i n)) ())
      (#t (let ((v (%sh-ar-digits-value word i n 10 0)))
            (if negative? (- 0 v) v))))))

(def %sh-test-1
  (fn (_ word) (%sh-bool (> (string-length word) 0))))

(def %sh-test-2
  (fn (_ op val)
    (match
      ((string=? op "-n") (%sh-bool (> (string-length val) 0)))
      ((string=? op "-z") (%sh-bool (= (string-length val) 0)))
      ((string=? op "-t") (%sh-bool (%sh-tty? val)))
      ((string=? op "!")  (%sh-test-not (%sh-test-1 val)))
      (#t
        (let ((r (%sh-test-file op val)))
          ; An unknown unary operator is a usage error (2), not a false --
          ; `test -q x` should complain, not quietly fail.
          (if (null? r)
            (do (%stderr "ash: test: " op ": unary operator expected\n") 2)
            r))))))

; A binary primary's answer, or nil when OP is not one.
(def %sh-test-binary
  (fn (_ left op right)
    (match
      ((string=? op "=")  (%sh-bool (string=? left right)))
      ((string=? op "!=") (%sh-bool (not (string=? left right))))
      ; By byte, the C locale's collation.
      ((string=? op "<")  (%sh-bool (Str8 <? left right)))
      ((string=? op ">")  (%sh-bool (Str8 <? right left)))
      ((string=? op "-nt") (%sh-bool (%sh-newer? left right)))
      ((string=? op "-ot") (%sh-bool (%sh-newer? right left)))
      (#t (%sh-test-num left op right)))))

(def %sh-test-unary?
  (fn (_ word)
    (match
      ((string=? word "-n") #t)
      ((string=? word "-z") #t)
      ((string=? word "-t") #t)
      (#t (not (null? (%sh-table-get word %sh-file-ops)))))))

; Statuses combine as the truths they stand for, and a usage error, 2, stands.
(def %sh-test-not
  (fn (_ s) (match ((= s 0) 1) ((= s 1) 0) (#t s))))

(def %sh-test-both
  (fn (_ a b) (match ((= a 2) a) ((= b 2) b) ((= a 0) b) (#t 1))))

(def %sh-test-either
  (fn (_ a b) (match ((= a 2) a) ((= b 2) b) ((= a 0) 0) (#t b))))

; A usage error is reported where it is found, and answers 2.
(def %sh-test-usage
  (fn (_ word what) (do (%stderr "ash: test: " word ": " what "\n") 2)))

; POSIX reads up to four words by how many there are.  Three: a binary primary
; in the middle first, `-a` and `-o` among them, so `! = x` compares two
; strings; then `!` before two words; then one word in parentheses.
(def %sh-test-three
  (fn (_ a b c)
    (let ((r (%sh-test-binary a b c)))
      (match
        ((not (null? r)) r)
        ((string=? b "-a") (%sh-test-both (%sh-test-1 a) (%sh-test-1 c)))
        ((string=? b "-o") (%sh-test-either (%sh-test-1 a) (%sh-test-1 c)))
        ((string=? a "!") (%sh-test-not (%sh-test-2 b c)))
        ((and (string=? a "(") (string=? c ")")) (%sh-test-1 b))
        (#t (%sh-test-expr (list a b c)))))))

; Four: `!` before three words, then two words in parentheses.
(def %sh-test-four
  (fn (_ wds)
    (let ((more (rest wds)))
      (match
        ((string=? (first wds) "!")
          (%sh-test-not
            (%sh-test-three (first more) (first (rest more))
                            (first (rest (rest more))))))
        ((and (string=? (first wds) "(") (string=? (last wds) ")"))
          (%sh-test-2 (first more) (first (rest more))))
        (#t (%sh-test-expr wds))))))

; Past what the count settles, the words are an expression, read by recursive
; descent as dash and bash read it: `!` binds tighter than `-a`, and `-a` than
; `-o`, and parentheses group.  Each step answers (status . words left), a
; status of 2 being a usage error already reported.
(def %sh-test-expr
  (fn (_ wds)
    (let ((r (%sh-test-or wds)))
      (match
        ((= (first r) 2) 2)
        ((null? (rest r)) (first r))
        (#t (%sh-test-usage (first (rest r)) "unexpected operator"))))))

; Whether the words left after the step that answered R begin with WORD.
(def %sh-test-next?
  (fn (_ r word)
    (match
      ((= (first r) 2) ())
      ((null? (rest r)) ())
      (#t (string=? (first (rest r)) word)))))

(def %sh-test-or
  (fn (self wds)
    (let ((l (%sh-test-and wds)))
      (if (%sh-test-next? l "-o")
        (let ((r (self (rest (rest l)))))
          (pair (%sh-test-either (first l) (first r)) (rest r)))
        l))))

(def %sh-test-and
  (fn (self wds)
    (let ((l (%sh-test-negation wds)))
      (if (%sh-test-next? l "-a")
        (let ((r (self (rest (rest l)))))
          (pair (%sh-test-both (first l) (first r)) (rest r)))
        l))))

; `!` with more after it negates what follows; alone, it is a word.
(def %sh-test-negation
  (fn (self wds)
    (match
      ((null? wds) (%sh-test-primary wds))
      ((null? (rest wds)) (%sh-test-primary wds))
      ((string=? (first wds) "!")
        (let ((r (self (rest wds))))
          (pair (%sh-test-not (first r)) (rest r))))
      (#t (%sh-test-primary wds)))))

(def %sh-test-primary
  (fn (_ wds)
    (match
      ((null? wds) (pair (%sh-test-usage "test" "argument expected") ()))
      ((string=? (first wds) "(") (%sh-test-group (rest wds)))
      (#t (%sh-test-operand wds)))))

(def %sh-test-group
  (fn (_ wds)
    (let ((r (%sh-test-or wds)))
      (match
        ((= (first r) 2) r)
        ((%sh-test-next? r ")") (pair (first r) (rest (rest r))))
        (#t (pair (%sh-test-usage "(" "closing paren expected") ()))))))

; A binary primary, a unary one, or a word, which is true when it is not
; empty.  An operator second decides before one first, as with three words.
(def %sh-test-operand
  (fn (_ wds)
    (let ((b (%sh-test-binary-of wds)))
      (match
        ((not (null? b)) (pair b (rest (rest (rest wds)))))
        ((null? (rest wds)) (pair (%sh-test-1 (first wds)) ()))
        ((%sh-test-unary? (first wds))
          (pair (%sh-test-2 (first wds) (first (rest wds))) (rest (rest wds))))
        (#t (pair (%sh-test-1 (first wds)) (rest wds)))))))

; The binary primary the first three words make, or nil.
(def %sh-test-binary-of
  (fn (_ wds)
    (match
      ((null? (rest wds)) ())
      ((null? (rest (rest wds))) ())
      (#t (%sh-test-binary (first wds) (first (rest wds))
                           (first (rest (rest wds))))))))

(def %sh-test
  (fn (_ wds)
    (let ((n (length wds)))
      (match
        ((= n 0) 1)
        ((= n 1) (%sh-test-1 (first wds)))
        ((= n 2) (%sh-test-2 (first wds) (first (rest wds))))
        ((= n 3) (%sh-test-three (first wds) (first (rest wds))
                                 (first (rest (rest wds)))))
        ((= n 4) (%sh-test-four wds))
        (#t (%sh-test-expr wds))))))

; --- pwd / unset / read / . -----------------------------------------------

; The logical directory, not getcwd's resolved one, and not $PWD either: a
; plain assignment to PWD leaves the shell's own idea of where it is alone.
; `pwd -P` answers getcwd's.
(def %sh-pwd
  (fn (_ wds)
    (display (if (first (%sh-lp-options wds ()))
               (%sh-cwd-physical)
               (%sh-cwd-logical)))
    (newline)
    0))

; `unset [-v] NAME...` unsets variables, and `unset -f NAME...` functions --
; every definition of one, since a redefinition shadows rather than replaces.
; A special builtin, so a word that is not a name ends a script, and so does
; an option it does not know, being no name either.
(def %sh-unset-each
  (fn (self wds fn?)
    (if (null? wds)
      0
      (do
        (%sh-name-or-refuse! "unset" (first wds))
        (if fn?
          (set! %sh-functions (%sh-table-without-all (first wds) %sh-functions))
          (%sh-var-unset! (first wds)))
        (self (rest wds) fn?)))))

(def %sh-unset
  (fn (_ wds)
    (match
      ((null? wds) 0)
      ((string=? (first wds) "-f") (%sh-unset-each (rest wds) #t))
      ((string=? (first wds) "-v") (%sh-unset-each (rest wds) ()))
      (#t (%sh-unset-each wds ())))))

; `read [-r] VAR...` -- one line from stdin, split on IFS across the names,
; with the LAST name taking everything that is left, separators and all.  A
; bare `read` with no names still consumes the line.
;
; Without -r a backslash quotes the character after it: the backslash goes
; away, the character keeps no special meaning, and a backslash at the end of
; a line joins the next one.  With -r a backslash is an ordinary character,
; which is what reading arbitrary data needs.
;
; The status is non-zero at end of input, including when a final line arrives
; without a terminator -- the line is still assigned, but `while read line`
; stops rather than seeing it twice.
(def %sh-read-options
  (fn (self wds raw?)
    (if (null? wds)
      (pair raw? ())
      (let ((w (first wds)))
        (match
          ((string=? w "-r") (self (rest wds) #t))
          ((string=? w "--") (pair raw? (rest wds)))
          ((and (%sh-str-starts? w "-") (> (string-length w) 1)) ())
          (#t (pair raw? wds)))))))

; A line, joined with the ones after it while it ends in a quoting backslash.
(def %sh-read-logical-line
  (fn (self raw?)
    (let ((line (sh-read-line-fd 0)))
      (if (or (null? line) raw? (not (%sh-read-continues? line)))
        line
        (let ((head (substring line 0 (- (string-length line) 1))))
          (let ((tail (self raw?)))
            (if (null? tail) head (string-append head tail))))))))

; A trailing backslash continues the line only when it is not itself quoted,
; so an even number of them at the end is data.
(def %sh-read-continues?
  (fn (_ line)
    (let ((n (string-length line)))
      (def count
        (fn (self i run)
          (if (or (< i 0) (not (= (string-ref line i) #\\)))
            run
            (self (- i 1) (+ run 1)))))
      (and (> n 0) (not (= 0 (% (count (- n 1) 0) 2)))))))

; One field from I, stopping at the first delimiter that a backslash has not
; quoted.  Answers (pair field next-index).
(def %sh-read-field
  (fn (_ line i n ifs raw?)
    (def walk
      (fn (self j pieces)
        (if (>= j n)
          (pair (%ash-join "" (reverse pieces)) j)
          (let ((c (string-ref line j)))
            (match
              ((and (not raw?) (= c #\\) (< (+ j 1) n))
                (self (+ j 2) (pair (substring line (+ j 1) (+ j 2)) pieces)))
              ((%sh-in-ifs? c ifs) (pair (%ash-join "" (reverse pieces)) j))
              (#t (self (+ j 1) (pair (substring line j (+ j 1)) pieces))))))))
    (walk i ())))

; The rest of the line, backslashes resolved.  Trailing IFS whitespace the
; line ended with is dropped; whitespace a backslash quoted is kept, so each
; piece carries whether it was quoted.
(def %sh-read-rest
  (fn (_ line i n ifs raw?)
    (def walk
      (fn (self j kept)
        (if (>= j n)
          kept
          (let ((c (string-ref line j)))
            (if (and (not raw?) (= c #\\) (< (+ j 1) n))
              (self (+ j 2)
                (pair (pair (substring line (+ j 1) (+ j 2)) #t) kept))
              (self (+ j 1) (pair (pair (substring line j (+ j 1)) ()) kept)))))))
    (%sh-read-text (%sh-read-trim (walk i ()) ifs))))

; KEPT is reversed, so what the line ended with is at its head.
(def %sh-read-trim
  (fn (self kept ifs)
    (if (null? kept)
      kept
      (let ((head (first kept)))
        (let ((c (string-ref (first head) 0)))
          (if (and (null? (rest head)) (%sh-in-ifs? c ifs) (%sh-ws-char? c))
            (self (rest kept) ifs)
            kept))))))

(def %sh-read-text
  (fn (self kept)
    (def texts
      (fn (self rows out)
        (if (null? rows) out (self (rest rows) (pair (first (first rows)) out)))))
    (%ash-join "" (texts kept ()))))

(def %sh-read-assign
  (fn (self names line i n ifs raw?)
    (%sh-name-or-refuse! "read" (first names))
    (let ((start (%sh-ifs-ws-end line i n ifs)))
      (if (null? (rest names))
        (do (%sh-var-set! (first names) (%sh-read-rest line start n ifs raw?)) 0)
        (let ((got (%sh-read-field line start n ifs raw?)))
          (%sh-var-set! (first names) (first got))
          (self (rest names) line (%sh-read-past line (rest got) n ifs) n
                ifs raw?))))))

; Step over the delimiter between two fields: any IFS whitespace, and at most
; one delimiter that is not whitespace.
(def %sh-read-past
  (fn (_ line i n ifs)
    (let ((after (%sh-ifs-ws-end line i n ifs)))
      (if (and (< after n) (%sh-in-ifs? (string-ref line after) ifs))
        (%sh-ifs-ws-end line (+ after 1) n ifs)
        after))))

; Reads fd 0 DIRECTLY, not the engine's reader -- see sh-read-line-fd in
; ash/prims.x for why the two are not interchangeable.
(def %sh-read
  (fn (_ wds)
    (let ((opts (%sh-read-options wds ())))
      (if (null? opts)
        (do (%stderr "ash: read: " (first wds) ": invalid option\n") 2)
        (let ((raw? (first opts)) (names (rest opts)))
          (let ((line (%sh-read-logical-line raw?)))
            ; At the end of the input with nothing read, the names are still
            ; assigned, all empty, and the status is 1: that is what leaves
            ; `line` empty after `while read line; do ...; done`.
            (let ((text (if (null? line) "" line)))
              ; `read` is not a special builtin, so a name that may not be
              ; assigned is this command's failure and not the shell's end:
              ; the refusal has been written, and the status is 1.
              (guard (e 1)
                (unless (null? names)
                  (%sh-read-assign names text 0 (string-length text)
                                   (%sh-ifs) raw?))
                (if (and (not (null? line)) (null? sh-read-hit-eof)) 0 1)))))))))

(def %sh-return
  (fn (_ wds)
    (let ((n (if (null? wds) %sh-status (convert (first wds) %int))))
      (if (and (= %sh-fn-depth 0) (= %sh-dot-depth 0))
        ; Outside a function or a dot script POSIX leaves this unspecified;
        ; report and carry on rather than unwinding to somewhere there is no
        ; frame for.
        (do
          (%stderr "ash: return: can only `return' from a function"
                   " or a dot script\n")
          1)
        (do (set! %sh-return-status n) (error (lit %sh-return)))))))

; --- Loop control -----------------------------------------------------------
;
; `break [n]` and `continue [n]` unwind to the n-th enclosing loop the way
; `return` unwinds to the call site: a sentinel symbol raised here and caught
; by the loop that owns the iteration (%sh-run-loop-body).  The count rides in
; %sh-loop-level, and every loop the signal passes through takes one off it.
;
; Measured against /bin/sh: outside any loop both are a silent no-op with
; status 0; a count deeper than the nesting leaves every loop there is; a
; count below one is "loop count out of range" and leaves the innermost loop
; with status 1 -- the one case where the signal carries a status.
(def %sh-loop-depth 0)
(def %sh-loop-level 0)
(def %sh-loop-status 0)

(def %sh-loop-count
  (fn (_ wds who)
    (if (null? wds)
      1
      (let ((n (convert (first wds) %int)))
        (if (< n 1)
          (do
            (%stderr (%ash-join "" (list "ash: " who ": " (first wds)
                                         ": loop count out of range\n")))
            ())
          n)))))

(def %sh-loop-signal
  (fn (_ wds who signal)
    (if (= %sh-loop-depth 0)
      0
      (let ((n (%sh-loop-count wds who)))
        (set! %sh-loop-level (if (null? n) 1 n))
        (set! %sh-loop-status (if (null? n) 1 0))
        (error (if (null? n) (lit %sh-break) signal))))))

(def %sh-break    (fn (_ wds) (%sh-loop-signal wds "break"    (lit %sh-break))))
(def %sh-continue (fn (_ wds) (%sh-loop-signal wds "continue" (lit %sh-continue))))

; `shift [n]` drops the first n positional parameters (default 1).  Shifting
; more than there are is an error and leaves them alone, which is what
; `while shift; do` relies on to terminate.
(def %sh-shift
  (fn (_ wds)
    (let ((n (if (null? wds) 1 (convert (first wds) %int))))
      (if (< n 0)
        1
        (if (> n (length %sh-args))
          1
          (do (set! %sh-args (drop n %sh-args)) 0))))))

; --- set --------------------------------------------------------------------
;
;   set -- a b c     replace the positional parameters
;   set -e -u -x     turn options on;  set +e  turns one off
;   set              answers 0 (POSIX prints the variables; nothing here reads
;                    that, and inventing a format would be inventing a
;                    contract)
;
; `--` ends the options even when no parameters follow, which is how a script
; clears them: `set --`.
; Each option's letter, what turns it, and what reads it.  `$-` asks the
; readers, `set` the setters, and an option is one row rather than a row here
; and an arm somewhere else.
(def %sh-set-opts
  (list (pair "e" (pair (fn (_ on?) (set! %sh-opt-errexit on?))
                        (fn (_) %sh-opt-errexit)))
        (pair "u" (pair (fn (_ on?) (set! %sh-opt-nounset on?))
                        (fn (_) %sh-opt-nounset)))
        (pair "x" (pair (fn (_ on?) (set! %sh-opt-xtrace on?))
                        (fn (_) %sh-opt-xtrace)))
        (pair "f" (pair (fn (_ on?) (set! %sh-opt-noglob on?))
                        (fn (_) %sh-opt-noglob)))
        (pair "a" (pair (fn (_ on?) (set! %sh-opt-allexport on?))
                        (fn (_) %sh-opt-allexport)))
        (pair "C" (pair (fn (_ on?) (set! %sh-opt-noclobber on?))
                        (fn (_) %sh-opt-noclobber)))))

(def %sh-set-opt-on! (fn (_ row on?) ((first row) on?)))
(def %sh-set-opt-on? (fn (_ row) ((rest row))))

; The letters of the options now set, which is what `$-` answers.  A shell
; that is not interactive and has none set answers the empty string.
(def %sh-flag-letters
  (fn (self rows out)
    (if (null? rows)
      (%ash-join "" (reverse out))
      (self (rest rows)
            (if (%sh-set-opt-on? (rest (first rows)))
              (pair (first (first rows)) out)
              out)))))

(def %sh-flags (fn (_) (%sh-flag-letters %sh-set-opts ())))

; `set -o noglob` names the same option `set -f` does.  The letters are what
; the table above is keyed by, so this says only which name belongs to which
; letter.
(def %sh-set-opt-names
  (list (pair "errexit" "e") (pair "nounset" "u")
        (pair "xtrace" "x") (pair "noglob" "f") (pair "allexport" "a")
        (pair "noclobber" "C")))

; The options that have a name and no letter.  `$-` is letters only, so these
; are not in it.
(def %sh-set-long-opts
  (list (pair "pipefail" (pair (fn (_ on?) (set! %sh-opt-pipefail on?))
                               (fn (_) %sh-opt-pipefail)))))

; The row that turns the option NAME on and off, or () for a name not known.
(def %sh-set-named-row
  (fn (_ name)
    (let ((letter (%sh-table-get name %sh-set-opt-names)))
      (if (null? letter)
        (%sh-table-get name %sh-set-long-opts)
        (%sh-table-get letter %sh-set-opts)))))

; `-o NAME` and `+o NAME` turn the same option the letter does.  An `o` with no
; name after it would write the options; nothing here reads that, and the
; format would be a contract invented rather than kept, so it answers 0.
(def %sh-set-named
  (fn (_ wds on?)
    (if (null? wds)
      0
      (let ((row (%sh-set-named-row (first wds))))
        (if (null? row)
          (do (%stderr "ash: set: " (first wds) ": unknown option\n") 2)
          (do (%sh-set-opt-on! row on?) 0))))))

; One `-abc` or `+abc` cluster, with WDS the words after it.  An `o` among the
; letters takes its option's name from those words, in turn -- so
; `set -euo pipefail` and `set -oe pipefail` both read as bash reads them, and
; `-o` alone is the one-letter cluster.  Answers (status . the words left).
(def %sh-set-flags
  (fn (self word on? i wds)
    (match
      ((fx<? i (string-length word))
        (match
          ((= (string-ref word i) #\o)
            (let ((r (%sh-set-named wds on?)))
              (match
                ((not (= r 0)) (pair r wds))
                ((null? wds) (pair 0 wds))
                (#t (self word on? (+ i 1) (rest wds))))))
          (#t
            (let ((f (%sh-table-get (substring word i (+ i 1)) %sh-set-opts)))
              (if (null? f)
                (do (%stderr "ash: set: " (substring word i (+ i 1))
                             ": unknown option\n")
                    (pair 2 wds))
                (do (%sh-set-opt-on! f on?) (self word on? (+ i 1) wds)))))))
      (#t (pair 0 wds)))))

(def %sh-set
  (fn (self wds)
    (if (null? wds)
      0
      (let ((w (first wds)))
        (cond
          ((string=? w "--") (do (set! %sh-args (rest wds)) 0))
          ((%sh-str-starts? w "-")
            (let ((r (%sh-set-flags w #t 1 (rest wds))))
              (if (= (first r) 0) (self (rest r)) (first r))))
          ((%sh-str-starts? w "+")
            (let ((r (%sh-set-flags w () 1 (rest wds))))
              (if (= (first r) 0) (self (rest r)) (first r))))
          ; A bare operand: POSIX treats `set a b` as setting the parameters.
          (else (do (set! %sh-args wds) 0)))))))

; `.` / `source` FILE -- read the file and run it in THIS shell, so its
; assignments and cd survive.  The status is the last command's, or the one a
; `return` in the file gives.  A file that cannot be read is an error of the
; `.` itself, raised as any other error is, so a script ends there and the
; prompt reports it and goes on.  What goes wrong while the file runs stays
; that error, and `break` and `continue` reach the loop the `.` runs in.
(def %sh-source
  (fn (_ wds)
    (if (null? wds)
      (do (%stderr "ash: .: filename argument required\n") 2)
      (let ((path (first wds)))
        (let ((text (guard (e ()) (sh-read-file path))))
          (if (null? text)
            (error (string-append ".: " path ": cannot read"))
            (%sh-run-dot text)))))))

; A dot script is a place `return` may end, the way a function call is: the
; innermost of the two catches it.
(def %sh-run-dot
  (fn (_ text)
    (do
      (set! %sh-dot-depth (+ %sh-dot-depth 1))
      (guard (e
          (do
            (set! %sh-dot-depth (- %sh-dot-depth 1))
            (if (%sh-return? e) %sh-return-status (error e))))
        (sh-eval text)
        (set! %sh-dot-depth (- %sh-dot-depth 1))
        %sh-status))))

; Flat, via match, rather than a deep nested-if dispatch that is easy to
; miscount a paren in. One match arm per builtin.
; The three builtins written inline in the dispatch. A table holds functions,
; so they have to be functions -- `:` and `true` differ only in name, clearer
; as two bindings to one function than two arms of a case.
(def %sh-true  (fn (_ wds) 0))
(def %sh-false (fn (_ wds) 1))

; `wait` with no pid waits for every asynchronous list not yet waited for and
; answers 0.  With pids it waits for each and answers the last one's status,
; which is 127 for a pid that is not one of this shell's asynchronous lists.
(def %sh-wait-all
  (fn (self pids)
    (unless (null? pids)
      (do (sh-wait (first pids)) (self (rest pids))))))

(def %sh-pids-without
  (fn (self pid pids)
    (match
      ((null? pids) ())
      ((= pid (first pids)) (self pid (rest pids)))
      (#t (pair (first pids) (self pid (rest pids)))))))

(def %sh-wait-pids
  (fn (self wds status)
    (if (null? wds)
      status
      (let ((pid (convert (first wds) %int)))
        (if (and (not (null? pid)) (%sh-char-in? pid %sh-bg-pids))
          (do
            (set! %sh-bg-pids (%sh-pids-without pid %sh-bg-pids))
            (self (rest wds) (sh-wait pid)))
          (self (rest wds) 127))))))

(def %sh-wait-builtin
  (fn (_ wds)
    (if (null? wds)
      (do (%sh-wait-all %sh-bg-pids) (set! %sh-bg-pids ()) 0)
      (%sh-wait-pids wds 0))))

(def %sh-exit
  (fn (_ wds)
    (%sh-exit-shell
      (if (null? wds) %sh-status (convert (first wds) %int)))))

; `[ ... ]` is `test` with the closing bracket dropped.
(def %sh-bracket
  (fn (_ wds)
    (%sh-test
      (if (null? wds)
        wds
        (if (string=? (last wds) "]") (take (- (length wds) 1) wds) wds)))))

; `eval` -- the arguments, joined by a space, read back as shell input.
;
; The join is why `eval echo a b` and `eval "echo a b"` are the same command:
; eval takes words, already expanded once by the time they arrive, and the
; second pass is the point --
;
;   a=b; b=c; eval "echo \$$a"
;
; expands to `echo $b` and then evaluates that.
;
; In this shell, never a subshell: `eval "v=1"` sets v for the caller and
; `eval "exit 3"` exits. The text is a fresh top level, so %sh-compound-depth
; is reset around it -- as %sh-call-fn resets it -- so a bare `echo done` in the
; text is not read as an enclosing `if`'s terminator. Restored on the way out
; and on a raise.
(def %sh-eval-builtin
  (fn (_ wds)
    (let ((src (%sh-join-args wds)))
      (if (= (string-length src) 0)
        ; `eval` with nothing to read is a command that did nothing and
        ; succeeded -- POSIX, and what `eval $unset_var` relies on.
        0
        (let ((saved-depth %sh-compound-depth))
          (set! %sh-compound-depth 0)
          (guard (e (do (set! %sh-compound-depth saved-depth) (error e)))
            (sh-eval src)
            (set! %sh-compound-depth saved-depth)
            %sh-status))))))

; --- exec -------------------------------------------------------------------
;
; Two commands wearing one name, told apart by whether a command follows:
;
;   exec CMD [args]   replace this shell with CMD; nothing after it runs
;   exec [redirs]     apply the redirections to this shell and carry on
;
; The second is why exec does not save and restore: `exec > log` sends the rest
; of the script to log, and `exec 3<file` leaves fd 3 open for later commands.
; With a command, the same non-restoring setup is what the replacement image
; inherits.
;
; A failed exec ends a non-interactive shell (POSIX): `sh -c "exec nosuchcmd;
; echo after"` prints nothing and exits 127. At a prompt the status is reported
; and the shell stays, rather than closing the session over a typo.
(def %sh-exec-builtin
  (fn (_ wds)
    (if (null? wds)
      ; Redirections only.  They are already applied, and not putting them
      ; back is the point.
      0
      (do
        (sh-exec (first wds) (rest wds))
        ; Only reached when the exec FAILED -- on success there is no return.
        (%stderr "ash: exec: " (first wds) ": not found\n")
        (if %batch? (sh-exit 127) 127)))))

; --- trap --------------------------------------------------------------------
;
; `trap ACTION CONDITION...` says what to do when a condition arrives; the two
; kinds are not equally answerable here.
;
;   EXIT (or 0)  when the shell exits. Implemented, and what scripts reach for
;                trap to do: clean up however the script ends.
;
;   a signal     an action cannot be run: the platform's (Sys signal) takes
;                only sig-ign or sig-dfl -- an x-lang closure cannot be a C
;                signal handler. So `trap "" INT` (ignore) and `trap - INT`
;                (default) are real; an action on a signal is refused with a
;                diagnostic rather than accepted and never run.
;
; A subshell does not inherit traps (POSIX): every fork clears the table in the
; child.
(def %sh-traps ())
(def %sh-exit-trap-ran ())

; The signals this shell will name. These numbers are the ones POSIX fixes on
; every system; USR1 and USR2 are absent because they differ between Linux and
; the BSDs and nothing here can ask which one it is on.
(def %sh-signal-numbers
  (list (pair "HUP" 1) (pair "INT" 2) (pair "QUIT" 3) (pair "PIPE" 13)
        (pair "ALRM" 14) (pair "TERM" 15)))

; `INT`, `SIGINT` and `2` all name the same condition; `EXIT` and `0` name the
; other one.  Answers the canonical name, or () for something unrecognised.
(def %sh-trap-cond
  (fn (_ name)
    (let ((bare (if (%sh-str-starts? name "SIG") (substring name 3 (string-length name)) name)))
      (if (or (string=? bare "EXIT") (string=? bare "0"))
        "EXIT"
        (if (not (null? (%sh-table-get bare %sh-signal-numbers)))
          bare
          (%sh-signal-named-by-number bare))))))

(def %sh-signal-named-by-number
  (fn (self text) (%sh-signal-scan text %sh-signal-numbers)))

(def %sh-signal-scan
  (fn (self text rows)
    (if (null? rows)
      ()
      (if (string=? text (convert (rest (first rows)) %string))
        (first (first rows))
        (self text (rest rows))))))

; `trap` with nothing to say prints what is set, in the form that would set it
; again -- which is what makes `trap` useful inside a script that means to
; restore what it found.
(def %sh-trap-list
  (fn (self rows)
    (unless (null? rows)
      (display "trap -- ")
      (display (%sh-single-quote (rest (first rows))))
      (display " ")
      (display (first (first rows)))
      (newline)
      (self (rest rows)))))

; The action as the shell would have to be given it back: inside single
; quotes, with any single quote in it spliced out and back in the only way
; single quotes allow -- `'\''`.
(def %sh-single-quote
  (fn (_ text)
    (string-append "'"
      (string-append (%sh-escape-quotes text 0 (string-length text) ()) "'"))))

(def %sh-escape-quotes
  (fn (self text i n out)
    (if (>= i n)
      (%ash-join "" (reverse out))
      (self text (+ i 1) n
        (pair (if (= (string-ref text i) #\')
                "'\\''"
                (substring text i (+ i 1)))
              out)))))

(def %sh-trap-remove
  (fn (self cond rows)
    (if (null? rows)
      ()
      (if (string=? (first (first rows)) cond)
        (self cond (rest rows))
        (pair (first rows) (self cond (rest rows)))))))

(def %sh-trap-put
  (fn (_ cond action)
    (set! %sh-traps (pair (pair cond action) (%sh-trap-remove cond %sh-traps)))))

(def %sh-trap-one
  (fn (_ action cond-name)
    (let ((cond (%sh-trap-cond cond-name)))
      (if (null? cond)
        (do (%stderr "ash: trap: " cond-name ": bad condition\n") 1)
        (if (string=? cond "EXIT")
          (do
            (if (string=? action "-")
              (set! %sh-traps (%sh-trap-remove cond %sh-traps))
              (%sh-trap-put cond action))
            0)
          ; A signal.  Only the two dispositions the platform can install.
          (let ((n (%sh-table-get cond %sh-signal-numbers)))
            (if (string=? action "-")
              (do (Sys signal n (Sys sig-dfl))
                  (set! %sh-traps (%sh-trap-remove cond %sh-traps))
                  0)
              (if (= (string-length action) 0)
                (do (Sys signal n (Sys sig-ign)) (%sh-trap-put cond action) 0)
                (do
                  (%stderr "ash: trap: " cond
                           ": an action on a signal is not supported;"
                           " only the empty action (ignore) and - (default)\n")
                  1)))))))))

(def %sh-trap-set
  (fn (self action conds worst)
    (if (null? conds)
      worst
      (let ((st (%sh-trap-one action (first conds))))
        (self action (rest conds) (if (> st worst) st worst))))))

(def %sh-trap-builtin
  (fn (_ wds)
    (if (null? wds)
      (do (%sh-trap-list %sh-traps) 0)
      (let ((action (first wds))
            (conds (rest wds)))
        (if (null? conds)
          (do (%stderr "ash: trap: usage: trap [action] condition ...\n") 2)
          (%sh-trap-set action conds 0))))))

; The exit trap, run once. An action that itself exits must not re-enter this:
; `trap "echo n; exit 9" EXIT; exit 1` prints n once and leaves with 9, the
; status the action chose.
(def %sh-run-exit-trap
  (fn (_)
    (unless %sh-exit-trap-ran
      (set! %sh-exit-trap-ran #t)
      (let ((action (%sh-table-get "EXIT" %sh-traps)))
        (unless (or (null? action) (= (string-length action) 0))
          (guard (e ()) (sh-eval action)))))))

; Every way the shell or a subshell finishes comes through here.  The forks
; that exist to become another program or to move bytes do not: they clear the
; table instead, so a trap set by the script cannot fire in them.
(def %sh-exit-shell
  (fn (_ status)
    (%sh-run-exit-trap)
    (sh-exit status)))

; Report an error the way the shell does: on stderr, after `ash: `.  A
; structured error is rendered by the platform writer, since its memory read as
; a symbol name would print garbage bytes.
(def %sh-write-to-str (prim-ref (lit io) (lit write-to-str)))
(def %sh-report
  (fn (_ err)
    ; A raise carrying this sentinel was reported where it happened, and is
    ; raised to end the shell rather than to say anything more.
    (unless (%sh-signal? err "%sh-reported")
      (%stderr "ash: " (if (str? err) err (%sh-write-to-str err)) "\n"))))

; What a forked child runs: THUNK answers the status the child exits with.  A
; raise ends the child here, since left to unwind it would carry on through the
; code of the shell that forked it, as a second copy of that shell.  A `return`
; or loop signal that nothing in the child caught ends it with the status the
; signal carries; any other error is reported, and ends it with 2.
(def %sh-in-child
  (fn (_ thunk)
    (%sh-exit-shell
      (guard (e (match
                  ((%sh-return? e) %sh-return-status)
                  ((not (null? (%sh-loop-signal-kind e))) %sh-status)
                  (#t (do (%sh-report e) 2))))
        (thunk)))))

; --- getopts ------------------------------------------------------------------
;
; `getopts OPTSTRING NAME [ARG...]` reads one option per call, driven by a loop:
;
;   while getopts "ab:c" opt; do
;     case $opt in a) ...;; b) use "$OPTARG";; esac
;   done
;   shift $((OPTIND - 1))
;
; Two things carry between calls. OPTIND is the index of the next argument and
; is a shell variable, so a script may reset it to 1 and parse again. The other
; is an offset inside the current argument, because `-abc` is three options in
; one word; it is private and is reset whenever OPTIND is not the value this
; builtin last wrote.
;
; Errors come in two flavours, chosen by a leading `:` in the optstring:
;
;                 unknown option          option missing its argument
;   normal        NAME=?, diagnostic      NAME=?, diagnostic
;   silent  `:`   NAME=? OPTARG=letter    NAME=: OPTARG=letter
;
; The silent form lets a script report in its own words.
(def %sh-optchar 1)
(def %sh-optind-seen 0)

(def %sh-str-index
  (fn (self text c i)
    (if (>= i (string-length text))
      (- 0 1)
      (if (= (string-ref text i) c) i (self text c (+ i 1))))))

(def %sh-optstring-silent?
  (fn (_ optstring)
    (and (> (string-length optstring) 0)
         (= (string-ref optstring 0) #\:))))

; () when the letter is not in the optstring; 1 when it takes an argument and
; 0 when it does not.  A `:` is never a letter -- leading it is the silent
; flag, and after a letter it is that letter's "takes an argument" mark.
(def %sh-optstring-kind
  (fn (_ optstring c)
    (if (= c #\:)
      ()
      (let ((i (%sh-str-index optstring c 0)))
        (if (< i 0)
          ()
          (if (and (< (+ i 1) (string-length optstring))
                   (= (string-ref optstring (+ i 1)) #\:))
            1
            0))))))

; OPTIND as an integer, defaulting to 1 -- and the private offset reset when
; the script has moved OPTIND itself.
(def %sh-getopts-optind
  (fn (_)
    (let ((v (%sh-var-get "OPTIND")))
      (let ((n (if (null? v) 1 (convert v %int))))
        (unless (= n %sh-optind-seen) (set! %sh-optchar 1))
        n))))

(def %sh-getopts-save
  (fn (_ optind)
    (set! %sh-optind-seen optind)
    (%sh-var-set! "OPTIND" (convert optind %string))))

; Finish one call: park OPTIND, set NAME and OPTARG, answer the status.
(def %sh-getopts-yield
  (fn (_ name value optarg optind status)
    (%sh-getopts-save optind)
    (%sh-var-set! "OPTARG" optarg)
    (%sh-var-set! name value)
    status))

(def %sh-getopts-done
  (fn (_ optind)
    (%sh-getopts-save optind)
    (set! %sh-optchar 1)
    1))

; The letter needs an argument.  It is the rest of THIS word when there is
; one -- `-bval` -- and otherwise the next word entirely.
(def %sh-getopts-argument
  (fn (_ optstring name args c word optind silent?)
    (let ((n (string-length word)))
      (if (<= %sh-optchar n)
        (let ((rest-of-word (substring word (- %sh-optchar 1) n)))
          (set! %sh-optchar 1)
          (%sh-getopts-yield name (%sh-char-str c) rest-of-word (+ optind 1) 0))
        (do
          (set! %sh-optchar 1)
          (if (> (+ optind 1) (length args))
            ; Nothing left to take.
            (if silent?
              (%sh-getopts-yield name ":" (%sh-char-str c) (+ optind 1) 0)
              (do
                (%stderr "ash: getopts: option requires an argument -- "
                         (%sh-char-str c) "\n")
                (%sh-getopts-yield name "?" "" (+ optind 1) 0)))
            (%sh-getopts-yield name (%sh-char-str c)
              (nth optind args) (+ optind 2) 0)))))))

(def %sh-char-str (fn (_ c) (bytes->str (list c))))

; One option, from the word at OPTIND and the offset within it.
(def %sh-getopts-letter
  (fn (_ optstring name args word optind silent?)
    (let ((c (string-ref word (- %sh-optchar 1))))
      (set! %sh-optchar (+ %sh-optchar 1))
      (let ((kind (%sh-optstring-kind optstring c)))
        (if (null? kind)
          ; Not an option this caller knows.
          (let ((consumed (if (> %sh-optchar (string-length word))
                            (do (set! %sh-optchar 1) (+ optind 1))
                            optind)))
            (if silent?
              (%sh-getopts-yield name "?" (%sh-char-str c) consumed 0)
              (do
                (%stderr "ash: getopts: illegal option -- "
                         (%sh-char-str c) "\n")
                (%sh-getopts-yield name "?" "" consumed 0))))
          (if (= kind 1)
            (%sh-getopts-argument optstring name args c word optind silent?)
            (let ((consumed (if (> %sh-optchar (string-length word))
                              (do (set! %sh-optchar 1) (+ optind 1))
                              optind)))
              (%sh-getopts-yield name (%sh-char-str c) "" consumed 0))))))))

(def %sh-getopts-run
  (fn (_ optstring name args optind silent?)
    (if (> optind (length args))
      (%sh-getopts-done optind)
      (let ((word (nth (- optind 1) args)))
        (if (> %sh-optchar 1)
          ; Mid-cluster: keep reading letters out of this same word.
          (%sh-getopts-letter optstring name args word optind silent?)
          ; At a fresh word: it is an option only if it looks like one.  A
          ; lone `-` is an argument by convention, and `--` ends the options
          ; and is stepped over.
          (if (or (not (%sh-str-starts? word "-"))
                  (string=? word "-"))
            (%sh-getopts-done optind)
            (if (string=? word "--")
              (%sh-getopts-done (+ optind 1))
              (do
                (set! %sh-optchar 2)
                (%sh-getopts-letter optstring name args word optind
                                    silent?)))))))))

(def %sh-getopts-builtin
  (fn (_ wds)
    (if (or (null? wds) (null? (rest wds)))
      (do (%stderr "ash: getopts: usage: getopts optstring name [arg ...]\n") 2)
      (let ((optstring (first wds))
            (name (first (rest wds)))
            (given (rest (rest wds))))
        (%sh-getopts-run optstring name
          (if (null? given) %sh-args given)
          (%sh-getopts-optind)
          (%sh-optstring-silent? optstring))))))

; --- Where a name would be found --------------------------------------------
;
; `command -v` and `command -V` answer what the shell would run, so they ask
; in the order the dispatch runs: a builtin, then a function, then the first
; file on PATH that could be executed.  A reserved word is asked about first,
; because it is not a command name at all, and a name with a `/` in it is
; already a path and stands for itself.
;
; Answers (kind . text), or () for a name that would find nothing.

; 0o111 -- owner, group and other.  Which of them applies is the kernel's
; question at exec time; a file with none of them is not a program.
(def %sh-exec-bits 73)

(def %sh-executable?
  (fn (_ path)
    (and (eq? (sh-path-kind path) (lit file))
         (not (= 0 (& (sh-path-mode path) %sh-exec-bits))))))

; An empty PATH entry names the current directory, which %sh-dir-of answers.
(def %sh-path-of
  (fn (self name dirs)
    (if (null? dirs)
      ()
      (let ((cand (string-append (%sh-dir-of (first dirs)) "/" name)))
        (if (%sh-executable? cand) cand (self name (rest dirs)))))))

(def %sh-where
  (fn (_ name)
    (match
      ((%sh-str-has-char? name #\/)
        (if (%sh-executable? name) (pair (lit file) name) ()))
      ((%reserved-word? name) (pair (lit keyword) name))
      ((%sh-fn-wins? name (%sh-fn-lookup name %sh-functions))
        (pair (lit function) name))
      ((%sh-builtin? name) (pair (lit builtin) name))
      (#t
        (let ((p (%sh-path-of name (%sh-split-char (%sh-var-value "PATH") #\:))))
          (if (null? p) () (pair (lit file) p)))))))

(def %sh-where-words
  (list (pair (lit keyword) "a shell keyword")
        (pair (lit builtin) "a shell builtin")
        (pair (lit function) "a shell function")))

; -V says what the name is; -v says what would run, which for anything but a
; file on PATH is the name as written.
(def %sh-where-said
  (fn (_ w)
    (let ((said (%sh-table-get (first w) %sh-where-words)))
      (if (null? said) (rest w) said))))

(def %sh-command-v
  (fn (_ name)
    (let ((w (%sh-where name)))
      (if (null? w) 1 (do (display (rest w)) (newline) 0)))))

; What NAME is, for `command -V` and for `type`.  WHO is the utility a name
; found nowhere is reported in the name of.
(def %sh-describe
  (fn (_ who name)
    (let ((w (%sh-where name)))
      (if (null? w)
        (do (%stderr "ash: " who ": " name ": not found\n") 1)
        (do (display name " is " (%sh-where-said w)) (newline) 0)))))

; `command [-v|-V] name [arg...]` -- run NAME as though no function had that
; name, or say where it would be found.  The last of -v and -V is the one that
; answers, as in both reference shells.  POSIX's -p, which would run the name
; under a PATH of the implementation's choosing, is not implemented: it is
; refused rather than ignored, since a script that asks for a trusted PATH
; must not be given the untrusted one instead.
(def %sh-command-option?
  (fn (_ w) (and (fx<? 1 (string-length w)) (= (string-ref w 0) #\-))))

(def %sh-command-letter
  (fn (_ c)
    (match ((= c #\v) (lit v)) ((= c #\V) (lit verbose)) (#t ()))))

; The letters of one option word, left to right, so `-vV` is `-v -V`.  Answers
; (ok . mode) or (bad . letter).
(def %sh-command-letters
  (fn (self w i n mode)
    (if (>= i n)
      (pair (lit ok) mode)
      (let ((m (%sh-command-letter (string-ref w i))))
        (if (null? m)
          (pair (lit bad) (substring w i (+ i 1)))
          (self w (+ i 1) n m))))))

(def %sh-command-run
  (fn (_ wds mode)
    (if (null? wds)
      0
      (match
        ((eq? mode (lit v)) (%sh-command-v (first wds)))
        ((eq? mode (lit verbose)) (%sh-describe "command" (first wds)))
        ; The redirections are already in force around this builtin, so the
        ; command inherits them rather than being given them again.
        (#t (%sh-dispatch wds () ()))))))

(def %sh-command-opts
  (fn (self wds mode)
    (if (null? wds)
      0
      (let ((w (first wds)))
        (match
          ((string=? w "--") (%sh-command-run (rest wds) mode))
          ((%sh-command-option? w)
            (let ((m (%sh-command-letters w 1 (string-length w) mode)))
              (if (eq? (first m) (lit bad))
                (do (%stderr "ash: command: -" (rest m) ": invalid option\n") 2)
                (self (rest wds) (rest m)))))
          (#t (%sh-command-run wds mode)))))))

(def %sh-command (fn (_ wds) (%sh-command-opts wds ())))

; `type NAME...` -- what each name is, as `command -V` says it, and 1 when any
; of them is found nowhere.  POSIX gives it no options, so a word that starts
; with `-` is a name like any other, which is how dash reads it.
(def %sh-type
  (fn (self wds)
    (if (null? wds)
      0
      (let ((s (%sh-describe "type" (first wds))))
        (let ((r (self (rest wds))))
          (if (= s 0) r 1))))))

; --- The builtin table ------------------------------------------------------
;
; One table, so "is this a builtin" and "what runs it" cannot diverge: the
; names are the table's keys rather than a separate list a dispatch repeats.
; `.` and `source` are the same handler under two names.  A name is found by
; walking the table, so the builtins a loop runs most come first.
(def %sh-builtin-table
  (list (pair "["      %sh-bracket)
        (pair "test"   %sh-test)
        (pair "echo"   %sh-echo)
        (pair ":"      %sh-true)
        (pair "true"   %sh-true)
        (pair "false"  %sh-false)
        (pair "read"   %sh-read)
        (pair "shift"  %sh-shift)
        (pair "set"    %sh-set)
        (pair "local"  %sh-local)
        (pair "return" %sh-return)
        (pair "break"  %sh-break)
        (pair "continue" %sh-continue)
        (pair "cd"     %sh-cd)
        (pair "export" %sh-export)
        (pair "unset"  %sh-unset)
        (pair "exit"   %sh-exit)
        (pair "eval"   %sh-eval-builtin)
        (pair "."      %sh-source)
        (pair "command" %sh-command)
        (pair "getopts" %sh-getopts-builtin)
        (pair "pwd"    %sh-pwd)
        (pair "readonly" %sh-readonly-builtin)
        (pair "exec"   %sh-exec-builtin)
        (pair "trap"   %sh-trap-builtin)
        (pair "wait"   %sh-wait-builtin)
        (pair "type"   %sh-type)
        (pair "source" %sh-source)))

(def %sh-builtin?
  (fn (_ name) (not (null? (%sh-table-get name %sh-builtin-table)))))

; A builtin under redirection: park the descriptors, run, put them back. The
; guard restores and re-raises, so a builtin that raises with fd 1 still on a
; file does not leave the shell writing there -- the way lib/x/sys/stream.x
; does it.
; The builtins whose redirections outlive them, named here rather than tested
; for inline, so a second one is a list entry rather than another branch.
(def %sh-keeps-redirs (list "exec"))

; RUN is the builtin's handler, which the dispatch has already found.
(def %sh-run-builtin-redir
  (fn (_ name run wds redirs)
    (if (null? redirs)
      (run wds)
      (if (%sh-word-in? name %sh-keeps-redirs)
        ; Set up and never put back: that is the whole of what `exec > log`
        ; means.  See %sh-exec-builtin.
        (if (%sh-setup-redirs redirs)
          (run wds)
          (%sh-redir-refused name))
        (do
          (def parked (%sh-save-fds redirs))
          (guard (e (do (%sh-restore-fds parked) (error e)))
            (do
              (def status (if (%sh-setup-redirs redirs)
                            (run wds)
                            (%sh-redir-refused name)))
              (%sh-restore-fds parked)
              status)))))))


; --- External command execution ---

(def %sh-run-external
  (fn (_ name wds redirs)
    (let ((pid (sh-fork)))
      (if (= pid 0)
        (do
          ; A fork that exists to BECOME another program: no trap of the
          ; script's can belong to it, and its 127 is not the shell exiting.
          (set! %sh-traps ())
          (%sh-in-child
            (fn (_)
              (if (not (%sh-setup-redirs redirs))
                ; Reported by the redirection itself; the program is not run.
                %sh-redir-status
                (do
                  (sh-exec name wds)
                  ; A diagnostic goes to stderr: on stdout it would be captured
                  ; by `x=$(nosuchcmd)` as the command's output and
                  ; `2>/dev/null` could not silence it. The redirections are
                  ; applied above, so a script that asked for 2>/dev/null gets
                  ; it.
                  (%stderr "ash: " name ": command not found\n")
                  127)))))
        (sh-wait pid)))))
; --- Assignment handling ---

; The utilities whose arguments are assignments, so `export V=$(cmd)` reads the
; way `V=$(cmd)` does -- unsplit and unglobbed, whatever the value holds.
(def %sh-declaration-utilities (list "export" "readonly" "local"))

(def %sh-declaration?
  (fn (_ word) (%sh-word-in? word %sh-declaration-utilities)))

; Where the word after this one stands.  `#t` is the leading run, where a word
; is an assignment while every word before it was one: `a=1 b=2 cmd x=3`
; assigns the first two and passes the third.  A declaration utility's name
; turns that into `decl`, which sticks: every argument of one is an assignment
; word however many plain names come first, so `export x y=$v` assigns y
; unsplit the way `y=$v` would.
(def %sh-next-assign?
  (fn (_ assign? tok val)
    (match
      ((eq? assign? (lit decl)) (lit decl))
      ((not (and assign? (eq? (first tok) (lit tok-word)))) ())
      ((%is-assignment? val) #t)
      ((%sh-declaration? val) (lit decl))
      (#t ()))))

; A word that is a NAME and then `=`: a letter or underscore, then letters,
; digits and underscores.  Anything else ahead of the `=` makes the word a
; command -- `a-b=1` and `1x=5` run, and are not found -- as POSIX's grammar
; has it.
;
; One scan that stops at the first character a name cannot hold, and nothing
; built: every word in assignment position is asked, the first word of every
; command among them.  The character classes are written out, not asked of
; %sh-name-start? and %sh-name-char?, which would be a call per character.
(def %sh-assign-scan
  (fn (self word i n)
    (match
      ((fx<? i n)
        (match
          ; Below `A`: the `=` that ends the name, or a digit, which a name
          ; may hold but not begin with.
          ((fx<? (string-ref word i) #\A)
            (match
              ((= (string-ref word i) #\=) (fx<? 0 i))
              ((fx<? (string-ref word i) #\0) ())
              ((fx<? #\9 (string-ref word i)) ())
              ((fx<? 0 i) (self word (fx+ i 1) n))
              (#t ())))
          ; Above `Z`: an underscore, or a lower-case letter.
          ((fx<? #\Z (string-ref word i))
            (match
              ((= (string-ref word i) #\_) (self word (fx+ i 1) n))
              ((fx<? (string-ref word i) #\a) ())
              ((fx<? #\z (string-ref word i)) ())
              (#t (self word (fx+ i 1) n))))
          (#t (self word (fx+ i 1) n))))
      (#t ()))))

(def %is-assignment?
  (fn (_ word) (%sh-assign-scan word 0 (string-length word))))

; The leading NAME=value words, and the command left after them.  Answers
; (pair assignments remaining).
(def %sh-split-assignments
  (fn (self wds assigns)
    (if (and (not (null? wds)) (%is-assignment? (first wds)))
      (self (rest wds) (pair (first wds) assigns))
      (pair (reverse assigns) wds))))

; NAME=VALUE words as ordinary assignments: what a command with no command name
; does, and what a special builtin's prefix does.
(def %sh-apply-assignments
  (fn (self assigns)
    (unless (null? assigns)
      (%sh-var-set! (%sh-assignment-name (first assigns))
                    (%sh-assignment-value (first assigns)))
      (self (rest assigns)))))

; A prefix assignment on any other command is exported to it: the variable is
; in the environment for as long as the command runs, and %sh-restore-values
; puts it back where it was.
(def %sh-apply-exported
  (fn (self assigns)
    (unless (null? assigns)
      (let ((name (%sh-assignment-name (first assigns))))
        (%sh-var-unset! name)
        (sh-setenv name (%sh-assignment-value (first assigns))))
      (self (rest assigns)))))

(def %sh-assignment-value
  (fn (_ word)
    (let ((n (string-length word)))
      (substring word (fx+ (%sh-first-eq word 0 n) 1) n))))

(def %sh-assignment-name
  (fn (_ word)
    (let ((n (string-length word)))
      (def find
        (fn (self i)
          (if (or (>= i n) (= (string-ref word i) #\=))
            (substring word 0 i)
            (self (+ i 1)))))
      (find 0))))

; Where each named variable stands now, so that what a prefix assignment
; covered can be put back exactly: (NAME WHERE VALUE), WHERE being env, shell,
; or marked for a name exported with no value, and () for an unset name.
(def %sh-save-values
  (fn (self assigns saved)
    (if (null? assigns)
      saved
      (self (rest assigns)
            (pair (%sh-var-where (%sh-assignment-name (first assigns))) saved)))))

(def %sh-var-where
  (fn (_ name)
    (let ((shell (%sh-table-get name %sh-vars)))
      (match
        ((not (null? shell)) (list name (lit shell) shell))
        ((not (null? (sh-getenv name))) (list name (lit env) (sh-getenv name)))
        ((%sh-word-in? name %sh-export-marks) (list name (lit marked) ()))
        (#t (list name () ()))))))

(def %sh-restore-values
  (fn (self saved)
    (unless (null? saved)
      (%sh-var-put-back (first saved))
      (self (rest saved)))))

(def %sh-var-put-back
  (fn (_ row)
    (let ((name (first row))
          (where (first (rest row)))
          (value (first (rest (rest row)))))
      (%sh-var-unset! name)
      (match
        ((eq? where (lit shell)) (%sh-var-set! name value))
        ((eq? where (lit env)) (sh-setenv name value))
        ((eq? where (lit marked)) (%sh-var-export! name))
        (#t ())))))

; The builtins POSIX calls special.  A prefix assignment on one of them
; outlives the command; on anything else it covers that command only.
(def %sh-special-builtins
  (list ":" "." "break" "continue" "eval" "exec" "exit" "export"
        "readonly" "return" "set" "shift" "times" "trap" "unset"))

(def %sh-special-builtin?
  (fn (_ name) (%sh-word-in? name %sh-special-builtins)))
; --- Execute collected command ---

; Every arm of the dispatch below ended `(set! %sh-status status) status`, so
; that is one function and the dispatch is one `cond`.
(def %sh-set-status
  (fn (_ status) (set! %sh-status status) status))

(def %sh-run-cmd
  (fn (_ wds redirs)
    ; Already expanded, at extraction (%collect-cmd-tokens). Re-expanding here
    ; would expand a variable's value -- `X='$Y'; echo $X` would print $Y's
    ; contents rather than the two characters it holds.
    (let ((split (%sh-split-assignments wds ())))
      (let ((assigns (first split)) (remaining (rest split)))
        (if (null? remaining)
          ; A command with no command name: bare assignments, or words that
          ; expanded to nothing.  The values it set are the shell's from here
          ; on, and its status is its last command substitution's, or 0 when
          ; it performed none.
          (do
            (%sh-apply-assignments assigns)
            (%sh-set-status
              (if (null? %sh-subst-status) 0 %sh-subst-status)))
          (do
            (unless (null? %sh-opt-xtrace)
              (%stderr (%sh-prompt "PS4") (%sh-join-args remaining) "\n"))
            (%sh-exit-on-error
             (%sh-set-status
              (%sh-run-scoped assigns remaining redirs)))))))))

; A prefix assignment covers one command: it is in the environment the command
; runs in, and the shell's own value comes back afterwards, whether the
; command returned or raised.  A special builtin keeps it instead, which is
; what POSIX asks and what makes `X=1 export Y=2` leave X set.
(def %sh-run-scoped
  (fn (_ assigns remaining redirs)
    (if (or (null? assigns) (%sh-special-builtin? (first remaining)))
      (do
        (%sh-apply-assignments assigns)
        (%sh-dispatch remaining redirs %sh-functions))
      (let ((saved (%sh-save-values assigns ())))
        (%sh-apply-exported assigns)
        (guard (e (do (%sh-restore-values saved) (error e)))
          (let ((status (%sh-dispatch remaining redirs %sh-functions)))
            (%sh-restore-values saved)
            status))))))

(def %sh-dispatch
  (fn (_ remaining redirs fns)
    (do
      (def name (first remaining))
      (def args (rest remaining))
      (def body (%sh-fn-lookup name fns))
      ; A function wins over a regular builtin and an external, and loses to
      ; a special builtin, the POSIX order.  FNS is which functions are in
      ; reach: `command` passes none, which is the whole of what it does
      ; differently.  Redirections on a function call apply for the whole
      ; body, and the shell's own descriptors must survive it -- the same
      ; save/apply/restore a builtin gets.  A builtin is looked up once, and
      ; its handler handed on.
      (if (%sh-fn-wins? name body)
        (%sh-run-fn-redir body args redirs)
        (do
          (def run (%sh-table-get name %sh-builtin-table))
          (if (null? run)
            (%sh-run-external name args redirs)
            (%sh-run-builtin-redir name run args redirs)))))))

; Whether a function found as BODY runs for NAME: it does unless NAME is a
; special builtin.  Only a name some function has is asked about the specials.
(def %sh-fn-wins?
  (fn (_ name body)
    (if (null? body) () (not (%sh-special-builtin? name)))))

; `set -e`: a failed command ends the shell, unless a condition is open.
(def %sh-exit-on-error
  (fn (_ status)
    (if (%sh-should-exit? status) (%sh-exit-shell status) status)))

; A function under redirection, on the %sh-run-builtin-redir pattern.  Same
; guard, same reason: a body that raises with fd 1 pointing at a file would
; leave the SHELL writing there.
(def %sh-run-fn-redir
  (fn (_ body wds redirs)
    (if (null? redirs)
      (%sh-call-fn body wds)
      (let ((parked (%sh-save-fds redirs)))
        (guard (e (do (%sh-restore-fds parked) (error e)))
          (let ((status (if (%sh-setup-redirs redirs)
                          (%sh-call-fn body wds)
                          %sh-redir-status)))
            (%sh-restore-fds parked)
            status))))))
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
        (if (%tok-is-keyword? tok)
          ; The keys of %sh-compound-table, so the two cannot disagree.  A `(`
          ; opens a subshell, which is punctuation rather than a word.
          (not (null? (%sh-table-get (first (rest tok)) %sh-compound-table)))
          (if (eq? (first tok) (lit tok-op))
            (string=? (first (rest tok)) "(")
            ()))))))

(def %collect-cmd-tokens ())

; Assignment position is the collector's to know -- a fact of where the word
; sits, not how it is spelt, decided on the raw token, before expansion, and
; never for a quoted one.  %sh-next-assign? carries it from word to word: the
; leading run of a command, and every argument of a declaration utility.
(set! %collect-cmd-tokens
  (fn (_ cur wds redirs assign?)
    (if (%cursor-empty? cur)
      (%sh-run-cmd (reverse wds) (reverse redirs))
      (let ((tok (%cursor-peek cur)))
        (if (%tok-is-newline? tok)
          (%sh-run-cmd (reverse wds) (reverse redirs))
          (let ((rop (%redir-op? tok)))
            (if rop
              (do
                (%cursor-advance! cur)
                (let ((fd (%default-fd rop)))
                  (if (%cursor-empty? cur)
                    (error "parse error: redirect without target")
                    ; NOT SPLIT.  `> $f` with two fields in $f is an
                    ; ambiguous redirect in POSIX, not two files; taking the
                    ; unsplit reading keeps the common case right and the
                    ; pathological one harmless.
                    (%collect-cmd-tokens
                      cur
                      wds
                      (pair (%sh-read-redir-target cur rop fd) redirs)
                      assign?))))
              (if (%tok-is-word? tok)
                ; Every word after the first is an argument, reserved or not:
                ; a command already begun is not a place a reserved word is
                ; recognized (see %sh-mark-keywords).
                (let ((val (%tok-word-val tok)))
                  (do
                    (%cursor-advance! cur)
                    ; EXPANDED HERE, not in %sh-run-cmd, because this is the
                    ; last place the token's QUOTING is still known.  `val`
                    ; above stays raw: POSIX recognises reserved words before
                    ; expansion, so a variable holding "then" must not become
                    ; one.
                    (%collect-cmd-tokens
                      cur
                      (%sh-push-fields
                        (%sh-expand-tok tok
                          (and assign?
                               (eq? (first tok) (lit tok-word))
                               (%is-assignment? val)))
                        wds)
                      redirs
                      (%sh-next-assign? assign? tok val))))
                ; `2>err`: the descriptor number the tokenizer found against
                ; the operator.
                (if (%tok-is-io? tok)
                  (do
                    (%cursor-advance! cur)
                    (%collect-cmd-tokens
                      cur wds (pair (%sh-io-redir cur tok) redirs) assign?))
                  (%sh-run-cmd (reverse wds) (reverse redirs)))))))))))

; A command's words are expanded as they are collected, so this is where the
; command's substitutions start to count.
(def %eval-simple-cmd
  (fn (_ cur)
    (set! %sh-subst-status ())
    (%collect-cmd-tokens cur () () #t)))
; --- Compound commands: parse structure, evaluate directly ---
; if cond; then body [elif cond; then body]... [else body] fi

(def %eval-if
  (fn (_ cur)
    (%cursor-advance! cur)
    ; consume 'if'

    (%skip-newlines cur)
    ; A CONDITION, so `set -e` must not fire on it -- `if false; then` and
    ; `while test ...` run commands whose failure is the point.
    (let ((cond-result (%sh-in-condition (fn (_) (%eval-list cur)))))
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

; --- Skipping a balanced token run -------------------------------------------
;
; The five skippers below were five copies of one walk: advance through tokens
; keeping a nesting count, stop at the first DEPTH-0 token the caller cares
; about.  What differed was three lines each -- which token stops it, whether
; that token is consumed, and whether running out of input is an error.  So
; that is what they pass, and the walk is written once.
;
; The cursor is left ON the stopping token; consuming it is the caller's
; business, because %skip-body-to-elif-else-fi must NOT (%eval-elif-chain runs
; next and its whole job is to look at that word).
;
; Answers the token it stopped at, or nil if the input ran out.
(def %sh-word-is?
  (fn (_ tok w)
    (and (%tok-is-keyword? tok) (string=? (%tok-word-val tok) w))))

(def %sh-word-among?
  (fn (_ tok words)
    (and (%tok-is-keyword? tok) (%sh-word-in? (%tok-word-val tok) words))))

; The nesting a token contributes.  Floored by the caller, so a stray closer in
; malformed input cannot drive the count negative and swallow the rest.
(def %sh-nest-delta
  (fn (_ tok)
    (cond
      ((%sh-word-among? tok %sh-block-openers) 1)
      ((%sh-word-among? tok %sh-block-closers) (- 0 1))
      (else 0))))

(def %sh-skip-block
  (fn (self cur depth stop?)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (and (= depth 0) (stop? tok))
          tok
          (do
            (%cursor-advance! cur)
            (let ((d (+ depth (%sh-nest-delta tok))))
              (self cur (if (< d 0) 0 d) stop?))))))))

; Skip to a depth-0 stop token and CONSUME it.  WHAT names the construct for
; the error when the input runs out first.
(def %sh-skip-past
  (fn (_ cur stop? what)
    (if (null? (%sh-skip-block cur 0 stop?))
      (error (string-append "parse error: unexpected EOF in " what))
      (%cursor-advance! cur))))

; The same, but running out of input is simply the end -- what the case
; skippers have always done.
(def %sh-skip-past-or-end
  (fn (_ cur stop?)
    (unless (null? (%sh-skip-block cur 0 stop?)) (%cursor-advance! cur))))

; Skip a false branch's body, stopping on the elif/else/fi that follows it --
; not consuming it, so %eval-elif-chain sees the terminator. Swallowing the
; `fi` would make `if false; then echo yes; fi` a parse error.
(def %sh-elif-else-fi (list "elif" "else" "fi"))

(set! %skip-body-to-elif-else-fi
  (fn (_ cur depth)
    (if (null? (%sh-skip-block cur 0
                 (fn (_ tok) (%sh-word-among? tok %sh-elif-else-fi))))
      (error "parse error: unexpected EOF in if")
      ())))
; Skip to matching fi (after we evaluated the true branch)

(set! %skip-to-fi
  (fn (_ cur depth)
    (%sh-skip-past cur (fn (_ tok) (%sh-word-is? tok "fi")) "if")))
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
            ; A CONDITION, so `set -e` must not fire on it -- `if false; then` and
    ; `while test ...` run commands whose failure is the point.
    (let ((cond-result (%sh-in-condition (fn (_) (%eval-list cur)))))
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
; --- One iteration, under the loop-control guard ----------------------------
;
; Answers (pair HOW status): HOW is `ran` when the body reached its `done`,
; `break` or `continue` when a signal aimed at THIS loop cut it short.  A
; signal aimed further out -- `break 2` from an inner loop -- passes through
; with one taken off its count, and only while there is an outer loop to take
; it: a count deeper than the nesting stops at the outermost, which is
; /bin/sh's answer too.  Anything that is not a loop signal is re-raised
; untouched, `return` included.
(def %sh-loop-signals
  (list (pair "%sh-break" (lit break)) (pair "%sh-continue" (lit continue))))

(def %sh-loop-signal-kind
  (fn (_ e)
    (if (atom? e) (%sh-table-get (symbol->str e) %sh-loop-signals) ())))

(def %sh-loop-catch
  (fn (_ e)
    (let ((kind (%sh-loop-signal-kind e)))
      (if (null? kind)
        (error e)
        (if (and (> %sh-loop-level 1) (> %sh-loop-depth 0))
          (do (set! %sh-loop-level (- %sh-loop-level 1)) (error e))
          (pair kind %sh-loop-status))))))

(def %sh-run-loop-body
  (fn (_ cur)
    (set! %sh-loop-depth (+ %sh-loop-depth 1))
    (guard (e
        (do (set! %sh-loop-depth (- %sh-loop-depth 1)) (%sh-loop-catch e)))
      (let ((result (%eval-list cur)))
        (set! %sh-loop-depth (- %sh-loop-depth 1))
        (pair (lit ran) result)))))

; Leave the cursor just past this loop's `done`.  A body that ran is standing
; on it; one cut short by a signal is somewhere inside, so walk from the
; loop's own start -- the same balanced skip the false-condition path takes.
(def %sh-loop-after-body
  (fn (_ cur start how)
    (if (eq? how (lit ran))
      (do (%skip-newlines cur) (%expect-word cur "done"))
      (do (set-first! cur start) (%skip-to-done cur 0)))))

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
    ; A CONDITION, so `set -e` must not fire on it -- `if false; then` and
    ; `while test ...` run commands whose failure is the point.
    (let ((cond-result (%sh-in-condition (fn (_) (%eval-list cur)))))
      (%skip-newlines cur)
      (%expect-word cur "do")
      (%skip-newlines cur)
      (if (= cond-result 0)
        (let ((r (%sh-run-loop-body cur)))
          (%sh-loop-after-body cur saved (first r))
          (if (eq? (first r) (lit break))
            (do (set! %sh-status (rest r)) (rest r))
            (%eval-while-body cur saved)))
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
    ; A CONDITION, so `set -e` must not fire on it -- `if false; then` and
    ; `while test ...` run commands whose failure is the point.
    (let ((cond-result (%sh-in-condition (fn (_) (%eval-list cur)))))
      (%skip-newlines cur)
      (%expect-word cur "do")
      (%skip-newlines cur)
      (if (not (= cond-result 0))
        (let ((r (%sh-run-loop-body cur)))
          (%sh-loop-after-body cur saved (first r))
          (if (eq? (first r) (lit break))
            (do (set! %sh-status (rest r)) (rest r))
            (%eval-until-body cur saved)))
        ; Condition succeeded: skip body, done

        (do (%skip-to-done cur 0) (set! %sh-status 0) 0)))))
; Skip to matching done

(set! %skip-to-done
  (fn (_ cur depth)
    (%sh-skip-past cur (fn (_ tok) (%sh-word-is? tok "done")) "while")))
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
      (let ((fs (%sh-expand-tok (%cursor-peek cur) ())))
        (%cursor-advance! cur)
        ; SPLICED, which is what makes `for f in $(cat list)` iterate once per
        ; line instead of once over the whole file.
        (%collect-for-words cur (%sh-push-fields fs ws))))))
; for var [in words...]; do body; done

(def %eval-for
  (fn (_ cur)
    (%cursor-advance! cur)
    ; consume 'for'

    (%skip-newlines cur)
    (if (%cursor-empty? cur)
      (error "parse error: for without variable")
      (let ((var (%tok-word-val (%cursor-peek cur))))
        (unless (%sh-name? var)
          (error (string-append "parse error: bad for loop variable " var)))
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
                  ; No `in` means the positional parameters as they stand when
                  ; the loop starts: `for i; do` is `for i in "$@"; do`.  A
                  ; `set --` in the body rebinds %sh-args and leaves this list
                  ; alone.
                  %sh-args)))
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
      ; No words is no iterations, and the body is still to be stepped over:
      ; the cursor stands after the `do`, where nothing has read it.
      (do (%skip-to-done cur 0) (set! %sh-status 0) 0)
      (do
        (%sh-var-set! var (first words))
        (set-first! cur body-start)
        ; reset to body

        (let ((r (%sh-run-loop-body cur)))
          (%sh-loop-after-body cur body-start (first r))
          (if (eq? (first r) (lit break))
            (do (set! %sh-status (rest r)) (rest r))
            (if (null? (rest words))
              (do (set! %sh-status 0) 0)
              (%eval-for-body cur var (rest words) body-start))))))))
; case WORD in PATTERN[|PATTERN]...) BODY;; ... esac

; case patterns are globs, matched with %sh-glob-match -- `a*)`, `*.txt)`,
; `[abc])`. This is pattern matching, not pathname expansion: it answers "does
; this word look like that", which is what `case` needs; filename globbing is a
; separate feature. Supported: `*` (any run, including empty), `?` (one
; character), `[abc]`, `[a-z]`, `[!abc]` / `[^abc]` negation, and `\` escaping
; any of them. An unterminated `[` is a literal `[`.

; POSIX's named classes, `[:alpha:]` and the rest, inside a bracket
; expression: `[[:digit:]]` is one digit, `[[:alpha:]_]` a letter or an
; underscore.  The locale is C's, so the classes are ASCII's.  A name that is
; not one of the twelve matches nothing.
(def %sh-char-class?
  (fn (_ name c)
    (match
      ((string=? name "alpha") (%sh-name-start-letter? c))
      ((string=? name "digit") (%sh-digit? c))
      ((string=? name "alnum") (match ((%sh-digit? c) #t) (#t (%sh-name-start-letter? c))))
      ((string=? name "upper") (match ((fx<? c #\A) ()) (#t (not (fx<? #\Z c)))))
      ((string=? name "lower") (match ((fx<? c #\a) ()) (#t (not (fx<? #\z c)))))
      ((string=? name "space")
        (match ((= c #\space) #t) ((fx<? c 9) ()) (#t (not (fx<? 13 c)))))
      ((string=? name "blank") (match ((= c #\space) #t) (#t (= c 9))))
      ((string=? name "print") (match ((fx<? c 32) ()) (#t (fx<? c 127))))
      ((string=? name "graph") (match ((fx<? c 33) ()) (#t (fx<? c 127))))
      ((string=? name "cntrl") (match ((fx<? c 32) #t) (#t (= c 127))))
      ((string=? name "punct")
        (match
          ((fx<? c 33) ())
          ((fx<? 126 c) ())
          ((%sh-digit? c) ())
          (#t (not (%sh-name-start-letter? c)))))
      ((string=? name "xdigit")
        (match
          ((%sh-digit? c) #t)
          ((fx<? c #\A) ())
          ((fx<? c #\G) #t)
          ((fx<? c #\a) ())
          (#t (fx<? c #\g))))
      (#t ()))))

; A letter, and only a letter: %sh-name-start? takes the underscore as well.
(def %sh-name-start-letter?
  (fn (_ c) (match ((= c #\_) ()) (#t (%sh-name-start? c)))))

; Where the `[:name:]` opened at I ends: the index just past its `:]`, or -1
; when there is none, which leaves the `[` an ordinary character.
(def %sh-glob-named-end
  (fn (self pat j hi)
    (match
      ((fx<? hi (fx+ j 2)) -1)
      ((match ((= (string-ref pat j) #\:) (= (string-ref pat (fx+ j 1)) #\])) (#t ()))
        (fx+ j 2))
      (#t (self pat (fx+ j 1) hi)))))

; A member of a class at I, and the index just past it.  A backslash makes the
; character after it the member, itself and nothing else: `[a\]]` holds `]`,
; and `[a\-z]` a literal `-` rather than the range `a` to `z`.
(def %sh-glob-escaped-at?
  (fn (_ pat i hi)
    (if (= (string-ref pat i) #\\) (fx<? (fx+ i 1) hi) ())))

(def %sh-glob-member-at
  (fn (_ pat i hi)
    (if (%sh-glob-escaped-at? pat i hi)
      (string-ref pat (fx+ i 1))
      (string-ref pat i))))

(def %sh-glob-member-end
  (fn (_ pat i hi)
    (if (%sh-glob-escaped-at? pat i hi) (fx+ i 2) (fx+ i 1))))

; The character-class helpers, taking the class body as the half-open range
; [lo, hi) -- lo just after the `[`, hi at the `]`.
(def %sh-glob-class-scan
  (fn (self pat i hi c)
    (if (>= i hi)
      ()
      (let ((e (if (and (< (+ i 1) hi)
                        (= (string-ref pat i) #\[)
                        (= (string-ref pat (+ i 1)) #\:))
                 (%sh-glob-named-end pat (+ i 2) hi)
                 -1)))
        (if (fx<? 0 e)
          ; A named class, `[:alpha:]`: the name sits between the colons.
          (if (%sh-char-class? (substring pat (+ i 2) (- e 2)) c)
            #t
            (self pat e hi c))
          (do
            (def lo (%sh-glob-member-at pat i hi))
            (def after (%sh-glob-member-end pat i hi))
            ; A range `a-b` needs its closing member inside the class.
            (if (if (fx<? (fx+ after 1) hi) (= (string-ref pat after) #\-) ())
              (do
                (def top (%sh-glob-member-at pat (fx+ after 1) hi))
                (if (if (fx<? c lo) () (not (fx<? top c)))
                  #t
                  (self pat (%sh-glob-member-end pat (fx+ after 1) hi) hi c)))
              (if (= c lo) #t (self pat after hi c)))))))))

(def %sh-glob-class-match?
  (fn (_ pat lo hi s si)
    (let ((c (string-ref s si)))
      (let ((neg (if (< lo hi)
                   (let ((f (string-ref pat lo)))
                     (or (= f #\!) (= f #\^)))
                   ())))
        (let ((hit (%sh-glob-class-scan pat (if neg (+ lo 1) lo) hi c)))
          (if neg (if hit () #t) (if hit #t ())))))))

; The index of the `]` closing a class opened at I, or -1.  A `!`/`^` and then
; a `]` immediately after the opening bracket are both literal, and a named
; class inside is stepped over whole, its own `]` being no end of this one.
(def %sh-glob-class-end
  (fn (_ pat i pn)
    (def scan
      (fn (self j)
        (match
          ((not (fx<? j pn)) (- 0 1))
          ; An escaped character is a member, a `]` included, so it closes
          ; nothing.
          ((%sh-glob-escaped-at? pat j pn) (self (fx+ j 2)))
          ((= (string-ref pat j) #\]) j)
          (#t
            (let ((e (if (and (< (+ j 1) pn)
                              (= (string-ref pat j) #\[)
                              (= (string-ref pat (+ j 1)) #\:))
                       (%sh-glob-named-end pat (+ j 2) pn)
                       -1)))
              (self (if (fx<? 0 e) e (+ j 1))))))))
    (let ((a (if (and (< i pn)
                      (let ((c (string-ref pat i)))
                        (or (= c #\!) (= c #\^))))
               (+ i 1) i)))
      (scan (if (and (< a pn) (= (string-ref pat a) #\]))
              (+ a 1) a)))))

(def %sh-glob-at ())
(def %sh-glob-star ())

; `*` -- try the rest of the pattern at every position from here to the end.
(set! %sh-glob-star
  (fn (self pat pi pn s si sn)
    (match
      ((%sh-glob-at pat pi pn s si sn) #t)
      ((fx<? si sn) (self pat pi pn s (fx+ si 1) sn))
      (#t ()))))

; Every character of every comparison comes through here -- a case pattern, a
; `${x#pat}`, a directory entry being globbed -- so the path an ordinary
; character takes is matches and the integer doors, nothing else: no `let`,
; no `and`, no `<` or `+`, each of which costs objects on every step.  The
; indices are integers throughout, which is what the doors need.
(set! %sh-glob-at
  (fn (self pat pi pn s si sn)
    (match
      ((fx<? pi pn)
        (match
          ((= (string-ref pat pi) #\*)
            (%sh-glob-star pat (fx+ pi 1) pn s si sn))
          ((= (string-ref pat pi) #\?)
            (match ((fx<? si sn) (self pat (fx+ pi 1) pn s (fx+ si 1) sn))
                   (#t ())))
          ((= (string-ref pat pi) #\[)
            (let ((e (%sh-glob-class-end pat (+ pi 1) pn)))
              (if (< e 0)
                ; Unterminated: a literal [
                (if (and (< si sn) (= (string-ref s si) #\[))
                  (self pat (+ pi 1) pn s (+ si 1) sn)
                  ())
                (if (and (< si sn) (%sh-glob-class-match? pat (+ pi 1) e s si))
                  (self pat (+ e 1) pn s (+ si 1) sn)
                  ()))))
          ; A backslash makes the next character itself.  A trailing one --
          ; which only an expansion's value can leave in a pattern -- escapes
          ; nothing, and the pattern matches nothing, as in dash and bash.
          ((= (string-ref pat pi) #\\)
            (match
              ((fx<? (fx+ pi 1) pn)
                (match
                  ((fx<? si sn)
                    (match
                      ((= (string-ref pat (fx+ pi 1)) (string-ref s si))
                        (self pat (fx+ pi 2) pn s (fx+ si 1) sn))
                      (#t ())))
                  (#t ())))
              (#t ())))
          ((fx<? si sn)
            (match
              ((= (string-ref pat pi) (string-ref s si))
                (self pat (fx+ pi 1) pn s (fx+ si 1) sn))
              (#t ())))
          (#t ())))
      ; Pattern exhausted: a match only if the word is exhausted too.
      ((fx<? si sn) ())
      (#t #t))))

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
          (if (or
                (and (eq? (first tok) (lit tok-op))
                     (string=? (first (rest tok)) "|"))
                ; The `(` a clause may open with is punctuation, not a
                ; pattern: `case "(" in (x)` matches the `x` clause for a
                ; subject that is a parenthesis, and nothing else.
                (%tok-pattern-paren? tok))
            (do
              (%cursor-advance! cur)
              (%collect-case-patterns cur pats))
            (do
              (%cursor-advance! cur)
              (%collect-case-patterns cur (pair tok pats)))))))))

; Each pattern is expanded when its turn comes, and the first that matches
; ends it: in `a|$(cmd))` the substitution runs only when `a` did not match.
(def %case-match?
  (fn (_ pats word)
    (if (null? pats)
      ()
      (if (%sh-pattern-match? (%sh-expand-pattern (first pats)) word)
        #t
        (%case-match? (rest pats) word)))))

(def %skip-case-body ())

; One clause's body: to its `;;`, or to the `esac` that ends the whole case
; when the last clause omits it.
(set! %skip-case-body
  (fn (_ cur depth)
    (%sh-skip-past-or-end cur
      (fn (_ tok)
        (or (%sh-word-is? tok "esac") (%tok-is-op? tok ";;"))))))
(def %skip-to-esac ())

(set! %skip-to-esac
  (fn (_ cur depth)
    (%sh-skip-past-or-end cur (fn (_ tok) (%sh-word-is? tok "esac")))))
(set! %eval-case-clauses
  (fn (_ cur word)
    (%skip-newlines cur)
    (if (%cursor-empty? cur)
      (do (set! %sh-status 0) 0)
      (let ((tok (%cursor-peek cur)))
        (if (and
              (%tok-is-keyword? tok)
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

      ; The case SUBJECT is expanded without field splitting (POSIX).
      (let ((word (%sh-expand-tok-1 word-tok)))
        (%skip-newlines cur)
        (%expect-word cur "in")
        (%skip-newlines cur)
        (%eval-case-clauses cur word)))))
; ( list ) — subshell

; The subshell body is collected first, in the one process, and the child
; evaluates a cursor over just those tokens. %eval-list does not stop at `)`,
; so a child forked onto the shared cursor would run every command after the
; subshell as well; collecting first bounds it, and the parent is left
; positioned past the closing paren.
(def %collect-subshell-tokens
  (fn (self cur depth toks)
    (if (%cursor-empty? cur)
      (error "parse error: expected )")
      (let ((tok (%cursor-peek cur)))
        (%cursor-advance! cur)
        (if (and (eq? (first tok) (lit tok-op)) (not (%tok-pattern-paren? tok)))
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
            (set! %sh-traps ())
            (%sh-in-child
              (fn (_)
                (do
                  (%sh-eval-body body)
                  %sh-status))))
          (let ((status (sh-wait pid)))
            (set! %sh-status status)
            status))))))

(def %skip-to-close-paren
  (fn (_ cur depth)
    (if (%cursor-empty? cur)
      (error "parse error: expected )")
      (let ((tok (%cursor-peek cur)))
        (%cursor-advance! cur)
        (if (and (eq? (first tok) (lit tok-op)) (not (%tok-pattern-paren? tok)))
          (let ((op (first (rest tok))))
            (if (string=? op "(")
              (%skip-to-close-paren cur (+ depth 1))
              (if (string=? op ")")
                (if (= depth 0) () (%skip-to-close-paren cur (- depth 1)))
                (%skip-to-close-paren cur depth))))
          (%skip-to-close-paren cur depth))))))
; --- Compound command dispatch ---

; The depth is bumped here, around the whole compound, rather than in each of
; the five parsers -- they have many return points apiece, and a counter
; decremented on all of them would drift. One place, with the guard/re-raise
; shape used for the descriptor saves.
; --- { ...; } -- the group that does NOT fork -------------------------------
;
; `{ ...; }` and `( ... )` group commands for the same reasons, and differ in
; one way: the braces run in this shell.
;
;   v=1; { v=2; }; echo $v      prints 2
;   v=1; ( v=2 );  echo $v      prints 1
;
; So `cmd | { read x; ...; }` is the idiom that needs them: a `read` in a
; subshell sets a variable nobody will see again. `{` and `}` are reserved
; words, which is why the `;` before `}` is required and why `echo {` prints a
; brace -- a reserved word is only reserved where a command could start.
(def %eval-brace-group
  (fn (_ cur)
    (%cursor-advance! cur)
    (%skip-newlines cur)
    (let ((result (%eval-list cur)))
      (%skip-newlines cur)
      (%expect-word cur "}")
      result)))

(def %eval-compound
  (fn (_ cur)
    (set! %sh-compound-depth (+ %sh-compound-depth 1))
    (guard (e
        (do (set! %sh-compound-depth (- %sh-compound-depth 1)) (error e)))
      (let ((r (%eval-compound-body cur)))
        (set! %sh-compound-depth (- %sh-compound-depth 1))
        r))))

; Which word opens which construct.  %is-compound-start? asks whether a word
; is a key of this table; %eval-compound-body asks what it maps to.  They were
; two lists of the same five words, one written as a predicate and one as a
; dispatch -- the same duplication the builtin table removed.
(def %sh-compound-table
  (list (pair "{"     %eval-brace-group)
        (pair "if"    %eval-if)
        (pair "while" %eval-while)
        (pair "until" %eval-until)
        (pair "for"   %eval-for)
        (pair "case"  %eval-case)))

(def %eval-compound-body
  (fn (_ cur)
    (let ((tok (%cursor-peek cur)))
      (if (eq? (first tok) (lit tok-op))
        (%eval-subshell cur)
        (let ((word (first (rest tok))))
          (let ((parse (%sh-table-get word %sh-compound-table)))
            (if (null? parse)
              (error (string-append "parse error: unexpected " word))
              (parse cur))))))))
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
              (%sh-move-fd write-fd 1)
              (set! %sh-traps ())
              (%sh-in-child
                (fn (_)
                  (do
                    (%eval-command (%mk-cursor left-tokens))
                    %sh-status))))
            ; Parent: stdin ← pipe, continue chain

            (do
              (sh-close write-fd)
              (%sh-move-fd read-fd 0)
              (let ((result (%sh-pipe-chain rest-cmds)))
                (%sh-pipe-status result (sh-wait pid))))))))))

; A pipeline's status is its last stage's.  Under pipefail it is the last
; stage's that failed: RIGHT is the answer for the stages after this one, and
; OWN this stage's, so a failure to the right stands and a clean right gives
; way to this stage.  `$?` is what it answers.
(def %sh-pipe-status
  (fn (_ right own)
    (match
      ((null? %sh-opt-pipefail) right)
      ((= right 0) (%sh-set-status own))
      (#t right))))
; The parent's stdin is the shell's stdin, and %sh-pipe-chain moves it. The
; chain runs its last stage in the shell process, so the parent dup2s each
; pipe's read end onto fd 0. Left there it ends a session: after
; `echo hello | grep h` at the prompt, stdin is an exhausted pipe and the next
; read is EOF. So stdin is parked first, as a redirection parks what it
; changes, and put back after, on the error path too, via the guard/re-raise
; shape lib/x/sys/stream.x uses.  A pipeline in a pipeline's last stage parks
; its own.
(def %sh-run-pipeline
  (fn (_ stages)
    (let ((parked (%sh-park-fds (list 0) ())))
      (guard (e (do (%sh-restore-fds parked) (error e)))
        (let ((result (%sh-pipe-chain stages)))
          (%sh-restore-fds parked)
          result)))))

; --- Recursive descent evaluator ---
; command: compound or simple

; --- Function definitions ----------------------------------------------------
;
;   name() compound-command [redirection...]
;
; A definition is the one command shape that cannot be recognised from its
; FIRST token: `name` is an ordinary word, and only the `()` after it says what
; this is.  So %eval-command looks three tokens ahead, before the
; compound-vs-simple split -- a reserved word is excluded, because `if()` is
; not a function definition, it is a syntax error somewhere else.
;
; The body is any compound command, not only a brace group: `f() ( ... )` runs
; in a subshell, `f() case x in ... esac` is a case.  What follows the `()` is
; the rest of this command, which is one pipeline stage -- %collect-stage
; counts both kinds of nesting, so the `;` inside the body belongs to the body
; and the one after it ends the definition.
;
; The body is stored as TOKENS, not text.  They have already been through the
; tokenizer once and re-tokenizing on every call would be both slower and a
; second chance to disagree with the first parse.  Unparsed, too: a
; redirection written after the body is expanded when the function runs, not
; when it is defined.
(def %is-fn-def?
  (fn (_ cur)
    (let ((toks (first cur)))
      (if (null? toks)
        ()
        (if (null? (rest toks))
          ()
          (if (null? (rest (rest toks)))
            ()
            (let ((a (first toks))
                  (b (first (rest toks)))
                  (c (first (rest (rest toks)))))
              ; A name is an unquoted word that is not reserved.
              (if (not (eq? (first a) (lit tok-word)))
                ()
                (if (%reserved-word? (%tok-word-val a))
                  ()
                  (if (%tok-is-op? b "(")
                    (%tok-is-op? c ")")
                    ()))))))))))

(def %eval-fn-def
  (fn (_ cur)
    (let ((name (%tok-word-val (%cursor-peek cur))))
      (unless (%sh-name? name)
        (error (string-append "parse error: bad function name " name)))
      (%cursor-advance! cur)
      ; consume name

      (%cursor-advance! cur)
      ; consume (

      (%cursor-advance! cur)
      ; consume )

      (%skip-newlines cur)
      (if (not (%is-compound-start? cur))
        (error (string-append "parse error: no compound command after "
                              name "()"))
        (let ((body (%collect-stage cur () 0 0)))
          ; A redefinition SHADOWS rather than replaces -- the lookup walks
          ; from the front, so the newest wins and the list stays
          ; append-free.
          (set! %sh-functions (pair (pair name body) %sh-functions))
          (set! %sh-status 0)
          0)))))

(def %sh-fn-lookup
  (fn (self name fns)
    (if (null? fns)
      ()
      (if (string=? (first (first fns)) name)
        (rest (first fns))
        (self name (rest fns))))))

; `return` unwinds to the call site with a non-local exit: it raises a sentinel
; symbol and %sh-call-fn catches exactly that one, re-raising anything else
; (lib/x/type/err.x). atom? guards the symbol->str, since a structured Err read
; as a symbol name would print garbage bytes.
(def %sh-signal?
  (fn (_ e name) (if (atom? e) (str=? (symbol->str e) name) ())))

(def %sh-return? (fn (_ e) (%sh-signal? e "%sh-return")))

; Everything a call is given back on the way out, however it leaves: its
; locals, its parameters and the depth it was called at.
(def %sh-leave-fn!
  (fn (_ saved saved-depth)
    (%sh-pop-locals!)
    (set! %sh-args saved)
    (set! %sh-compound-depth saved-depth)
    (set! %sh-fn-depth (- %sh-fn-depth 1))))

(def %sh-call-fn
  (fn (_ body args)
    (let ((saved %sh-args) (saved-depth %sh-compound-depth))
      (set! %sh-args args)
      (set! %sh-fn-depth (+ %sh-fn-depth 1))
      (%sh-push-locals!)
      ; A body is a fresh top level: it is one whole compound command, so
      ; nothing in these tokens closes anything outside them, and a function
      ; called from inside an `if` does not read a bare `echo done` in its
      ; body as a terminator.
      (set! %sh-compound-depth 0)
      (guard (e
          (do
            (%sh-leave-fn! saved saved-depth)
            (if (%sh-return? e) %sh-return-status (error e))))
        (%sh-eval-body body)
        (%sh-leave-fn! saved saved-depth)
        %sh-status))))

; --- A compound command's own redirections ----------------------------------
;
; `for i in ...; do ...; done > log` redirects the whole loop, and the
; redirection is written after the construct it applies to. A parser that
; evaluates as it reads would meet it too late, so the construct is skipped
; first -- read past without evaluating -- to see what follows; any
; redirections there are collected, the cursor wound back, and the construct
; evaluated with its descriptors in place. Winding a cursor back is what the
; loop bodies already do.
;
; The skip counts what the construct is made of, by the same split
; %eval-compound-body makes: a subshell counts parens, every other compound
; counts its own keywords.
(def %sh-compound-delta
  (fn (_ tok paren?)
    (if (not paren?)
      (%sh-nest-delta tok)
      (if (and (eq? (first tok) (lit tok-op)) (not (%tok-pattern-paren? tok)))
        (let ((op (first (rest tok))))
          (if (string=? op "(") 1 (if (string=? op ")") (- 0 1) 0)))
        0))))

; Read past one whole compound, leaving the cursor on whatever follows it.
; Entered ON the opening token with depth 0, so the opener takes the depth to
; 1 and the matching closer brings it back to 0 and stops.
(def %sh-skip-compound
  (fn (self cur depth paren?)
    (unless (%cursor-empty? cur)
      (let ((d (+ depth (%sh-compound-delta (%cursor-peek cur) paren?))))
        (%cursor-advance! cur)
        (when (> d 0) (self cur d paren?))))))

; The redirections written after a construct: `done > log`, and `done 2> log`,
; whose descriptor number the tokenizer hands over as a tok-io.
(def %sh-collect-trailing-redirs
  (fn (self cur redirs)
    (if (%cursor-empty? cur)
      (reverse redirs)
      (let ((tok (%cursor-peek cur)))
        (let ((rop (%redir-op? tok)))
          (if rop
            (do
              (%cursor-advance! cur)
              (self cur
                (pair (%sh-read-redir-target cur rop (%default-fd rop)) redirs)))
            (if (%tok-is-io? tok)
              (do
                (%cursor-advance! cur)
                (self cur (pair (%sh-io-redir cur tok) redirs)))
              (reverse redirs))))))))

(def %eval-compound-redir
  (fn (_ cur)
    (let ((start (first cur))
          (paren? (eq? (first (%cursor-peek cur)) (lit tok-op))))
      (%sh-skip-compound cur 0 paren?)
      (let ((redirs (%sh-collect-trailing-redirs cur ())))
        (let ((after (first cur)))
          (set-first! cur start)
          (if (null? redirs)
            (%eval-compound cur)
            (let ((parked (%sh-save-fds redirs)))
              (guard (e (do (%sh-restore-fds parked) (error e)))
                (let ((status (if (%sh-setup-redirs redirs)
                                  (%eval-compound cur)
                                  ; The construct is what sets the status when
                                  ; it runs, so a construct that does not run
                                  ; sets it here.
                                  (%sh-set-status %sh-redir-status))))
                  ; The construct stopped at its own end, or never ran; either
                  ; way, step over it and the redirections read before it.
                  (set-first! cur after)
                  (%sh-restore-fds parked)
                  status)))))))))

(set! %eval-command
  (fn (_ cur)
    (let ((status (if (%is-compound-start? cur)
                    (%eval-compound-redir cur)
                    (%eval-simple-cmd cur))))
      (%sh-refuse-leftover cur)
      status)))
; --- Pipeline stage collection ---
; Collect tokens for one stage (until | or end of command)

(def %collect-stage ())

; What ends a stage -- AT DEPTH ZERO.  The same tokens inside a construct
; belong to the construct: `for i in 1; do echo x; done | wc` has two `;` and
; a stop word in its first stage, and none of them end it.
(def %sh-stage-end?
  (fn (_ cur tok)
    (or
      (%tok-is-newline? tok)
      (%tok-is-op? tok "|")
      (%tok-is-op? tok ";")
      ; `;;` ends a command and is a distinct token from `;`, so the test above
      ; does not catch it: a case stage must not swallow the clause terminator
      ; and the clauses after it.
      (%tok-is-op? tok ";;")
      (%tok-is-op? tok "&")
      (%tok-is-op? tok "&&")
      (%tok-is-op? tok "||")
      (and (%tok-is-word? tok) (%at-stop-word? cur)))))

; A case pattern's parens are marked and counted by nothing (see
; %tok-pattern-paren?).  The floor stays under the count: malformed input can
; still hold a `)` that opens nothing, and a negative depth would cut the stage.
(def %sh-paren-depth
  (fn (_ d tok)
    (if (%tok-pattern-paren? tok)
      d
      (if (%tok-is-op? tok "(")
        (+ d 1)
        (if (and (%tok-is-op? tok ")") (> d 0)) (- d 1) d)))))

; Word nesting, floored: a stray `fi` in malformed input must not drive the
; count below zero and swallow the rest of the line.
(def %sh-stage-wdepth
  (fn (_ d tok)
    (let ((n (+ d (%sh-nest-delta tok))))
      (if (< n 0) 0 n))))

(set! %collect-stage
  (fn (self cur toks wdepth pdepth)
    (if (%cursor-empty? cur)
      (reverse toks)
      (let ((tok (%cursor-peek cur)))
        (if (and (= wdepth 0) (= pdepth 0) (%sh-stage-end? cur tok))
          (reverse toks)
          (do
            (%cursor-advance! cur)
            (self cur (pair tok toks)
              (%sh-stage-wdepth wdepth tok)
              (%sh-paren-depth pdepth tok))))))))
; Collect all pipeline stages

(def %collect-stages ())

(set! %collect-stages
  (fn (_ cur stages)
    (let ((stage (%collect-stage cur () 0 0)))
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
      ; POSIX exempts two kinds of pipeline from -e: one that starts with `!`,
      ; whose failure is what it is for, and one that is an operand of && or
      ; || other than the last.  Once the stages are collected the cursor stands
      ; after the pipeline, so the token there says which kind this is before
      ; anything runs -- and an exempt pipeline runs as a condition, which is
      ; what a subshell or a stage forked inside it inherits.
      (let ((result
              ; A definition is recognised here, beside the compounds:
              ; %collect-stages cuts the token run at the first `;` or newline,
              ; so a cursor through it never sees a function body. Hooked into
              ; %eval-command instead, `f() { echo hi; }` would reach
              ; %collect-fn-body with only `f ( ) {` in hand.
              (if (%is-fn-def? cur)
                (%eval-fn-def cur)
              ; A compound is a stage like any other, now that %collect-stage
              ; counts nesting: `( echo p ) | tr p P` and
              ; `for i in 1 2; do echo $i; done | wc -l` cut at the `|`, not at
              ; the `;` or `done` inside them. A single stage reaches
              ; %eval-command, whose compound branch applies the construct's
              ; redirections.
              (let ((stages (%collect-stages cur ())))
                (if (or negate (%sh-and-or-next? cur))
                  (%sh-in-condition (fn (_) (%sh-run-stages stages)))
                  (%sh-run-stages stages))))))
        (match
          (negate
            (let ((neg-result (if (= result 0) 1 0)))
              (set! %sh-status neg-result)
              neg-result))
          ((%sh-and-or-next? cur) result)
          (#t (%sh-exit-on-error result)))))))

(def %sh-run-stages
  (fn (_ stages)
    (if (null? (rest stages))
      (%eval-command (%mk-cursor (first stages)))
      (%sh-run-pipeline stages))))

(def %sh-and-or-ops (list "&&" "||"))

; Is the token at the cursor the && or || that makes what came before it an
; operand?
(def %sh-and-or-next?
  (fn (_ cur)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (eq? (first tok) (lit tok-op))
          (%sh-word-in? (first (rest tok)) %sh-and-or-ops)
          ())))))
; and_or: pipeline (('&&'|'||') pipeline)*

; Skip an operand without running it -- what a short-circuit does with the side
; it does not take. Recursive descent skips the evaluation, not the cursor, so
; the cursor is advanced past the operand explicitly; leaving it on the operand
; would make %eval-list find a command where it expects a separator.
; An operand ends at a list separator or the next connective, and the skip
; crosses pipes, because the operand of `&&` is a pipeline: stopping at a `|`
; would leave `grep a` behind in `false && echo a | grep a`.
(def %sh-operand-end-ops (list ";" "&" "&&" "||"))

(def %sh-operand-end?
  (fn (_ tok)
    (and (eq? (first tok) (lit tok-op))
         (%sh-word-in? (first (rest tok)) %sh-operand-end-ops))))

(def %sh-paren-delta
  (fn (_ tok)
    (cond
      ((%tok-pattern-paren? tok) 0)
      ((%tok-is-op? tok "(") 1)
      ((%tok-is-op? tok ")") (- 0 1))
      (else 0))))

(def %sh-skip-operand
  (fn (self cur depth)
    (if (%cursor-empty? cur)
      ()
      (let ((tok (%cursor-peek cur)))
        (if (and (= depth 0)
                 (or (%tok-is-newline? tok)
                     (%sh-operand-end? tok)
                     (%at-stop-word? cur)))
          ()
          (do
            (%cursor-advance! cur)
            ; Parens count too, and only here: %sh-nest-delta is the keyword
            ; nesting the skippers share, and a subshell's `(` is punctuation,
            ; not a keyword. Without it the skip stopped on the `)` of
            ; `false && (echo a)` and abandoned the list.
            (let ((d (+ depth
                        (+ (%sh-nest-delta tok) (%sh-paren-delta tok)))))
              (self cur (if (< d 0) 0 d)))))))))

; A command in an AND-OR list is exempt from `set -e` unless it is the LAST
; COMMAND RUN -- `false || echo` must not exit, `false && cmd` must not (the
; failure was not the last thing run), and a bare `false` must.  So the check
; is applied only where the loop ends having just EVALUATED an operand, never
; where it ends having skipped one.
(def %eval-and-or-loop ())

; Each pipeline applies -e itself, knowing from the token after it whether it
; is an operand; the loop only chooses which operands run.
(def %eval-and-or
  (fn (_ cur)
    (%eval-and-or-loop cur (%eval-pipeline cur))))

(set! %eval-and-or-loop
  (fn (self cur result)
    (cond
      ((%match-op cur "&&")
        (%skip-newlines cur)
        (if (= result 0)
          (self cur (%eval-pipeline cur))
          (do (%sh-skip-operand cur 0) (self cur result))))
      ((%match-op cur "||")
        (%skip-newlines cur)
        (if (= result 0)
          (do (%sh-skip-operand cur 0) (self cur result))
          (self cur (%eval-pipeline cur))))
      (else result))))

; --- Asynchronous lists ------------------------------------------------------
;
; An and-or list that ends with `&` runs in a child the shell does not wait
; for.  The child's standard input is /dev/null before its own redirections,
; since this shell has no job control; the shell carries on at once with status
; 0, and `$!` is the child's pid until the next one.  `wait` collects them.
;
; Whether a list ends with `&` has to be known before any of it runs, so the
; tokens are scanned ahead to where the list ends.

; The asynchronous lists started and not yet waited for, and the latest one.
(def %sh-bg-pids ())
(def %sh-bg-pid ())

; From a `case`, the tokens after the `esac` that closes it, or nil.  Its
; patterns' `)` are not closing parentheses, so a scan passes over it whole.
(def %sh-past-esac
  (fn (self toks depth)
    (match
      ((null? toks) ())
      ((%sh-word-is? (first toks) "case") (self (rest toks) (fx+ depth 1)))
      ((%sh-word-is? (first toks) "esac")
        (if (= depth 1) (rest toks) (self (rest toks) (- depth 1))))
      (#t (self (rest toks) depth)))))

; Where the and-or list at TOKS ends, when it ends with `&`: the tokens from
; that `&` on.  Nil when it ends any other way -- at `;`, `;;`, a newline or
; the end of the input, or at a `)` or a reserved word that belongs to a
; command around it.  DEPTH counts the compound commands and subshells inside
; the list, whose own lists do not end it.
;
; Every list is scanned before it runs, so an ordinary word costs one test of
; its kind and one of its keyword mark, and an operator is told by its first
; character; only a reserved word is looked up in the sets.
(def %sh-async-end
  (fn (self toks depth)
    (match
      ((null? toks) ())
      ((eq? (first (first toks)) (lit tok-newline))
        (if (= depth 0) () (self (rest toks) depth)))
      ((eq? (first (first toks)) (lit tok-op))
        (match
          ((= (string-ref (first (rest (first toks))) 0) #\()
            (self (rest toks) (fx+ depth 1)))
          ((= (string-ref (first (rest (first toks))) 0) #\))
            (if (= depth 0) () (self (rest toks) (- depth 1))))
          ((fx<? 0 depth) (self (rest toks) depth))
          ((= (string-ref (first (rest (first toks))) 0) #\;) ())
          ((string=? (first (rest (first toks))) "&") toks)
          (#t (self (rest toks) depth))))
      ((null? (rest (rest (first toks)))) (self (rest toks) depth))
      ((%sh-word-is? (first toks) "case") (self (%sh-past-esac toks 0) depth))
      ((%sh-word-among? (first toks) %sh-block-openers)
        (self (rest toks) (fx+ depth 1)))
      ((%sh-word-among? (first toks) %sh-block-closers)
        (if (= depth 0) () (self (rest toks) (- depth 1))))
      ((fx<? 0 depth) (self (rest toks) depth))
      ((%sh-word-among? (first toks) %sh-closing-words) ())
      (#t (self (rest toks) depth)))))

; Run the list at the cursor in a child and leave the cursor on its `&`.
(def %sh-run-async
  (fn (_ cur amp)
    (let ((pid (sh-fork)))
      (if (= pid 0)
        (do
          (set! %sh-traps ())
          (%sh-in-child
            (fn (_)
              (do
                (%sh-setup-redir (%sh-redir "<" 0 "/dev/null"))
                (%eval-and-or cur)))))
        (do
          (set-first! cur amp)
          (set! %sh-bg-pid pid)
          (set! %sh-bg-pids (pair pid %sh-bg-pids))
          (set! %sh-status 0)
          0)))))

; list: and_or ((';'|'&'|newline) and_or)*

(set! %eval-list
  (fn (_ cur)
    (%skip-newlines cur)
    (if (%at-stop-word? cur)
      (do (set! %sh-status 0) 0)
      (let ((result (let ((amp (%sh-async-end (first cur) 0)))
                      (if (null? amp)
                        (%eval-and-or cur)
                        (%sh-run-async cur amp)))))
        (if (%cursor-empty? cur)
          result
          (let ((tok (%cursor-peek cur)))
            (if (%tok-is-newline? tok)
              (do
                (%cursor-advance! cur)
                (%skip-newlines cur)
                (if (%at-stop-word? cur) result (%eval-list cur)))
              (if (or (%match-op cur ";") (%match-op cur "&"))
                (do
                  (%skip-newlines cur)
                  (if (%at-stop-word? cur) result (%eval-list cur)))
                result))))))))
; --- Here-documents ---------------------------------------------------------
;
;     cat <<EOF          the body is the LINES THAT FOLLOW, to a line that is
;     one                exactly the delimiter
;     two
;     EOF
;
; The body lives on lines the tokenizer has not reached, which is a shape
; nothing else in this reader has: every other construct is decided by the
; characters in front of it.  So here-documents are lifted out BEFORE
; tokenizing, in one pass over the raw text:
;
;   - each `<<DELIM` (or `<<-DELIM`) becomes `<<N`, where N indexes a body
;   - the body lines are removed from the text entirely
;
; after which the tokenizer and the parser see an ordinary redirection whose
; target happens to be a number, and %sh-setup-redir looks the body up.  That
; keeps the whole feature out of the reader, which cannot look ahead a line.
;
; `<<-` strips leading TABS from the body and from the terminator, which is
; what lets a here-document indent with the block it sits in.
; A QUOTED delimiter (`<<'EOF'`) means the body is literal; unquoted means it
; is expanded, exactly as a double-quoted string would be.

(def %sh-heredocs ())

(def %sh-heredoc (fn (_ text expand?) (pair text expand?)))
(def %sh-heredoc-text (fn (_ h) (first h)))
(def %sh-heredoc-expand? (fn (_ h) (rest h)))

; Cut TEXT at each CH, keeping the empty pieces: the lines of a here-document
; body, and the directories of PATH, are the same walk.
(def %sh-split-char
  (fn (_ text ch)
    (let ((n (string-length text)))
      (def go
        (fn (self i start acc)
          (if (>= i n)
            (reverse (pair (substring text start n) acc))
            (if (= (string-ref text i) ch)
              (self (+ i 1) (+ i 1) (pair (substring text start i) acc))
              (self (+ i 1) start acc)))))
      (go 0 0 ()))))

(def %sh-split-lines (fn (_ text) (%sh-split-char text #\newline)))

(def %sh-strip-tabs
  (fn (_ line)
    (let ((n (string-length line)))
      (def go
        (fn (self i)
          (if (and (< i n) (= (string-ref line i) #\tab)) (self (+ i 1)) i)))
      (substring line (go 0) n))))

; The delimiter word that follows `<<`, and where it ends: (word end expand?).
; The body ends at the word with its quoting removed, and quoting anywhere in
; it -- `'EOF'`, `"EOF"`, `\EOF`, `E"O"F` -- keeps the body from expanding.
(def %sh-hd-delim
  (fn (_ line i n)
    (let ((j (%sh-ar-skip-ws line i n)))
      (%sh-hd-delim-from line j n j () ()))))

(def %sh-quote-scan
  (fn (self line i n q)
    (if (>= i n) i (if (= (string-ref line i) q) i (self line (+ i 1) n q)))))

; A delimiter word ends at the end of the line, a blank or an operator.
(def %sh-hd-delim-end?
  (fn (_ line i n)
    (match
      ((not (fx<? i n)) #t)
      ((%sh-ws-char? (string-ref line i)) #t)
      (#t (%sh-op-start? (string-ref line i))))))

; The word from I.  PIECES holds its text so far with the quoting removed,
; latest first, and START is where the run not yet in PIECES began.
(def %sh-hd-delim-from
  (fn (self line i n start pieces quoted?)
    (if (%sh-hd-delim-end? line i n)
      (list (%ash-join "" (reverse (pair (substring line start i) pieces)))
            i
            (not quoted?))
      (let ((c (string-ref line i)))
        (match
          ; `\c` is c.
          ((= c #\\)
            (let ((e (if (fx<? (fx+ i 1) n) (fx+ i 2) n)))
              (%sh-hd-delim-piece line n start i (fx+ i 1) e e pieces)))
          ((= c #\') (%sh-hd-delim-quote line n start i c pieces))
          ((= c #\") (%sh-hd-delim-quote line n start i c pieces))
          (#t (self line (fx+ i 1) n start pieces quoted?)))))))

; A quoted run from I, which holds the quote Q, to the one that closes it.
(def %sh-hd-delim-quote
  (fn (_ line n start i q pieces)
    (let ((e (%sh-quote-scan line (fx+ i 1) n q)))
      (%sh-hd-delim-piece line n start i (fx+ i 1) e
        (if (fx<? e n) (fx+ e 1) e) pieces))))

; The word goes on at NEXT after the quoted text from FROM to TO, which follows
; the run from START to I.
(def %sh-hd-delim-piece
  (fn (_ line n start i from to next pieces)
    (%sh-hd-delim-from line next n next
      (pair (substring line from to) (pair (substring line start i) pieces))
      #t)))

; For a `$` at I that opens `$((`, the index of the `)` closing the arithmetic
; expansion on this line, or -1.
(def %sh-hd-arith-end
  (fn (_ line i n)
    (if (and (< (+ i 2) n)
             (= (string-ref line (+ i 1)) #\()
             (= (string-ref line (+ i 2)) #\())
      (%sh-cs-end line (+ i 2) n 0)
      (- 0 1))))

; The scan for here-document operators keeps its frames on a list, innermost
; first: a quote character for a quoted region, and these for a `$(` and for a
; parenthesis inside one.  An empty list is the top level.
(def %sh-hd-subst 1)
(def %sh-hd-paren 2)

; Rewrite one line, collecting the here-documents it opens.  STACK is the scan
; state the line starts in, carried over from the line before: a quoted string
; and a `$(` can both run past the end of a line, and `<<` is text inside a
; quoted string but an operator inside a `$(` inside one.  Answers (rewritten
; pending stack), where pending is a list of (delim strip? expand?) in the
; order the bodies must follow.
(def %sh-hd-scan-line
  (fn (_ line index stack)
    (%sh-hd-scan line 0 (string-length line) stack #t 0 () () index)))

; The scan from I.  START? is whether a `#` there would open a comment, FROM
; where the text not yet copied into OUT begins, and IDX the next body's
; number.
(def %sh-hd-scan
  (fn (self line i n stack start? from out pending idx)
    (if (not (fx<? i n))
      (list (%ash-join "" (reverse (pair (substring line from n) out)))
            (reverse pending)
            stack)
      (let ((c (string-ref line i)))
        (match
          ((null? stack)
            (%sh-hd-scan-bare line i n stack start? from out pending idx c))
          ((= (first stack) #\')
            (self line (fx+ i 1) n (if (= c #\') (rest stack) stack) ()
                  from out pending idx))
          ((= (first stack) #\")
            (%sh-hd-scan-dq line i n stack from out pending idx c))
          (#t (%sh-hd-scan-bare line i n stack start? from out pending idx c)))))))

; Unquoted: a quote opens a frame, a backslash takes the next character with
; it, a `#` where a word could start is a comment to the end of the line, and
; a `(` inside a `$(` opens a frame that `)` closes, as `)` closes the `$(`.
(def %sh-hd-scan-bare
  (fn (_ line i n stack start? from out pending idx c)
    (match
      ((= c #\')
        (%sh-hd-scan line (fx+ i 1) n (pair c stack) () from out pending idx))
      ((= c #\")
        (%sh-hd-scan line (fx+ i 1) n (pair c stack) () from out pending idx))
      ((= c #\\) (%sh-hd-scan line (fx+ i 2) n stack () from out pending idx))
      ((= c #\#)
        (%sh-hd-scan line (if start? n (fx+ i 1)) n stack () from out pending idx))
      ((= c #\$) (%sh-hd-scan-dollar line i n stack from out pending idx))
      ((= c #\()
        (%sh-hd-scan line (fx+ i 1) n
          (if (null? stack) stack (pair %sh-hd-paren stack)) #t
          from out pending idx))
      ((= c #\))
        (%sh-hd-scan line (fx+ i 1) n (if (null? stack) stack (rest stack)) #t
          from out pending idx))
      ((%sh-hd-op-at? line i n) (%sh-hd-scan-op line i n stack from out pending idx))
      (#t (%sh-hd-scan line (fx+ i 1) n stack (%sh-comment-may-follow? c)
            from out pending idx)))))

; Inside double quotes only the closing quote, a backslash and `$` count.
(def %sh-hd-scan-dq
  (fn (_ line i n stack from out pending idx c)
    (match
      ((= c #\") (%sh-hd-scan line (fx+ i 1) n (rest stack) () from out pending idx))
      ((= c #\\) (%sh-hd-scan line (fx+ i 2) n stack () from out pending idx))
      ((= c #\$) (%sh-hd-scan-dollar line i n stack from out pending idx))
      (#t (%sh-hd-scan line (fx+ i 1) n stack () from out pending idx)))))

; An arithmetic expansion is passed over whole, so the `<<` in `$((a<<2))`
; stays a shift; a `$(` opens a frame.
(def %sh-hd-scan-dollar
  (fn (_ line i n stack from out pending idx)
    (let ((e (%sh-hd-arith-end line i n)))
      (match
        ((fx<? i e) (%sh-hd-scan line (fx+ e 1) n stack () from out pending idx))
        ((%sh-hd-char-at? line (fx+ i 1) n #\()
          (%sh-hd-scan line (fx+ i 2) n (pair %sh-hd-subst stack) #t
            from out pending idx))
        (#t (%sh-hd-scan line (fx+ i 1) n stack () from out pending idx))))))

(def %sh-hd-char-at?
  (fn (_ line i n ch)
    (if (fx<? i n) (= (string-ref line i) ch) ())))

(def %sh-hd-op-at?
  (fn (_ line i n)
    (if (= (string-ref line i) #\<) (%sh-hd-char-at? line (fx+ i 1) n #\<) ())))

; `<<DELIM` or `<<-DELIM` at I is rewritten `<<N`, and the delimiter joins
; PENDING.
(def %sh-hd-scan-op
  (fn (_ line i n stack from out pending idx)
    (let ((strip? (%sh-hd-char-at? line (fx+ i 2) n #\-)))
      (let ((d (%sh-hd-delim line (if strip? (fx+ i 3) (fx+ i 2)) n)))
        (let ((e (first (rest d))))
          (%sh-hd-scan line e n stack () e
            (pair (string-append "<<" (convert idx %string))
                  (pair (substring line from i) out))
            (pair (list (first d) strip? (first (rest (rest d)))) pending)
            (fx+ idx 1)))))))

; Whether S, up to I, ends in a backslash that escapes the newline after it: an
; odd run of them, since each pair is one escaped backslash.
(def %sh-line-continues?
  (fn (self s i odd?)
    (if (and (fx<? 0 i) (= (string-ref s (- i 1)) #\\))
      (self s (- i 1) (not odd?))
      odd?)))

; An unquoted body is read as double-quoted text is, so a line that ends in a
; backslash joins the next one before it is compared with the delimiter: `x\`
; over `EOF` is the body line `xEOF`.  A quoted body keeps its backslashes.
(def %sh-hd-joins?
  (fn (_ line more expand?)
    (and expand?
         (not (null? more))
         (%sh-line-continues? line (string-length line) ()))))

; Take a body off the front of LINES, to the terminator.
(def %sh-hd-take
  (fn (_ lines delim strip? expand?)
    ; `remaining`, not `rest`: a parameter of that name shadows the list
    ; primitive, so the recursive step called a LIST.  Second time in this
    ; bundle -- see %sh-first-op.
    (def go
      (fn (self remaining acc)
        (if (null? remaining)
          ; Unterminated: what is left is the body, which is what a shell does
          ; at end of input.
          (list (%ash-join "" (reverse acc)) ())
          (let ((line (if strip?
                        (%sh-strip-tabs (first remaining))
                        (first remaining))))
            (match
              ((%sh-hd-joins? line (rest remaining) expand?)
                (self (pair (string-append
                              (substring line 0 (- (string-length line) 1))
                              (first (rest remaining)))
                            (rest (rest remaining)))
                      acc))
              ((string=? line delim)
                (list (%ash-join "" (reverse acc)) (rest remaining)))
              (#t
                (self (rest remaining)
                  (pair (string-append line "\n") acc))))))))
    (go lines ())))

(def %sh-hd-collect
  (fn (self lines pending bodies)
    (if (null? pending)
      (list lines bodies)
      (let ((p (first pending)))
        (let ((taken (%sh-hd-take lines (first p) (first (rest p))
                                  (first (rest (rest p))))))
          (self (first (rest taken)) (rest pending)
            (pair (%sh-heredoc (first taken) (first (rest (rest p))))
                  bodies)))))))

(def %sh-hd-walk
  (fn (self lines out bodies stack)
    (if (null? lines)
      (list (%ash-join "\n" (reverse out)) (reverse bodies))
      (let ((scanned (%sh-hd-scan-line (first lines) (length bodies) stack)))
        (let ((collected (%sh-hd-collect (rest lines)
                           (first (rest scanned)) bodies)))
          (self (first collected)
                (pair (first scanned) out)
                (first (rest collected))
                (first (rest (rest scanned)))))))))

; Lift every here-document out of INPUT, leaving `<<N` behind.  Answers the
; rewritten text; the bodies land in %sh-heredocs.
(def %sh-heredoc-extract
  (fn (_ input)
    ; Nothing to do for the overwhelming majority of input, so the cheap
    ; question is asked first.
    (if (not (%sh-str-has-heredoc-op? input))
      input
      (let ((r (%sh-hd-walk (%sh-split-lines input) () () ())))
        (set! %sh-heredocs (first (rest r)))
        (first r)))))

; Whether S holds the character A followed by B anywhere from I on.  Every text
; the shell evaluates is asked this before a pass only some text needs, so it
; builds nothing: a nested match with no `not`, which costs objects of its own.
(def %sh-has-pair?
  (fn (self s i n a b)
    (match
      ((fx<? (fx+ i 1) n)
        (match
          ((= (string-ref s i) a)
            (if (= (string-ref s (fx+ i 1)) b) #t (self s (fx+ i 1) n a b)))
          (#t (self s (fx+ i 1) n a b))))
      (#t ()))))

; `<<`, not `<`.  A single `<` is far too common to gate on -- `$((3<5))` has
; one, and every arithmetic comparison was paying for the whole line-splitting
; pass because of it.
(def %sh-str-has-heredoc-op?
  (fn (_ text) (%sh-has-pair? text 0 (string-length text) #\< #\<)))

; --- Line continuation -------------------------------------------------------
;
; A backslash before a newline joins the two lines: the pair is removed before
; the text is tokenized, wherever a backslash is an escape -- outside quotes and
; inside double quotes, but not inside single quotes or a comment (POSIX 2.2.1).
; Here-documents are lifted out first, so a quoted body keeps its backslashes
; and an unquoted one has joined its lines already (%sh-hd-take).

; A `#` opens a comment where a token could start: at the start of the text,
; or after a blank, a newline or an operator character.
(def %sh-comment-may-follow?
  (fn (_ c)
    (match
      ((%sh-ws? c) #t)
      ((= c #\newline) #t)
      (#t (%sh-op-start? c)))))

; For a `$` at I, the index of the `)` closing the `$(` it opens, or -1.
(def %sh-subst-close
  (fn (_ s i n)
    (if (and (fx<? (fx+ i 1) n) (= (string-ref s (fx+ i 1)) #\())
      (%sh-cs-end s (fx+ i 2) n 0)
      (- 0 1))))

(def %sh-mode-comment 3)

; The index of each backslash that joins its line to the next, latest first.
; MODE is bare, single-quoted, double-quoted or a comment, and START? is whether
; a `#` here would open a comment.  A command substitution is walked as text of
; its own, up to the parenthesis that closes it, so its quotes do not count
; against the ones around it.
(def %sh-continuations
  (fn (self s i n mode start? cuts)
    (if (not (fx<? i n))
      cuts
      (let ((c (string-ref s i)))
        (match
          ((= mode %sh-mode-sq)
            (self s (fx+ i 1) n (if (= c #\') %sh-mode-bare mode) () cuts))
          ((= mode %sh-mode-comment)
            (if (= c #\newline)
              (self s (fx+ i 1) n %sh-mode-bare #t cuts)
              (self s (fx+ i 1) n mode () cuts)))
          ((= c #\\)
            (match
              ((not (fx<? (fx+ i 1) n)) cuts)
              ((= (string-ref s (fx+ i 1)) #\newline)
                (self s (fx+ i 2) n mode start? (pair i cuts)))
              (#t (self s (fx+ i 2) n mode () cuts))))
          ((= c #\$)
            (let ((e (%sh-subst-close s i n)))
              (if (fx<? i e)
                ; Past the `)`, still inside the word the substitution is in.
                (self s (fx+ e 1) n mode ()
                  (self s (fx+ i 2) e %sh-mode-bare #t cuts))
                (self s (fx+ i 1) n mode () cuts))))
          ((= mode %sh-mode-dq)
            (self s (fx+ i 1) n (if (= c #\") %sh-mode-bare mode) () cuts))
          ((= c #\') (self s (fx+ i 1) n %sh-mode-sq () cuts))
          ((= c #\") (self s (fx+ i 1) n %sh-mode-dq () cuts))
          ((and (= c #\#) start?) (self s (fx+ i 1) n %sh-mode-comment () cuts))
          (#t (self s (fx+ i 1) n mode (%sh-comment-may-follow? c) cuts)))))))

; S without the backslash-newline pair at each of CUTS, latest first.
(def %sh-cut-pairs
  (fn (self s cuts end acc)
    (if (null? cuts)
      (%ash-join "" (pair (substring s 0 end) acc))
      (self s (rest cuts) (first cuts)
            (pair (substring s (fx+ (first cuts) 2) end) acc)))))

; Most text holds no backslash before a newline, quoted or not, so that is asked
; before the walk.
(def %sh-join-lines
  (fn (_ text)
    (let ((n (string-length text)))
      (if (not (%sh-has-pair? text 0 n #\\ #\newline))
        text
        (%sh-cut-pairs text
          (%sh-continuations text 0 n %sh-mode-bare #t ())
          n ())))))

; --- Public API ---

; Extraction happens once, at the top. A command substitution evaluates a
; fragment whose here-documents the outer pass already lifted; the fragment
; still carries the `<<N` markers, and running the pass again would find `N`,
; consume no body, and overwrite %sh-heredocs. So the substitution path
; evaluates already-extracted text; reading a file (`.` / source) is fresh and
; goes through the full entry.  Lines are joined there as well, after the
; extraction, so a fragment's continuations went with the text around it.
(def sh-eval-extracted
  (fn (_ input)
    (let ((tokens (%sh-mark-keywords (sh-tokenize input))))
      (if (null? tokens)
        0
        (let ((cur (%mk-cursor tokens)))
          (let ((status (%eval-list cur)))
            (%sh-refuse-leftover cur)
            status))))))

(def sh-eval
  (fn (_ input)
    (sh-eval-extracted (%sh-join-lines (%sh-heredoc-extract input)))))
