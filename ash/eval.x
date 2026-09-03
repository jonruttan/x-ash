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

; --- Word sets --------------------------------------------------------------
;
; A set of words is a LIST of words.  Written as a chain of string=? it reads
; as logic when it is data, and every addition means editing the shape rather
; than the contents.
(def %sh-word-in?
  (fn (_ word words) (not (null? (List index-of word words)))))

; A TABLE is an alist of (key . value) keyed by string; %sh-table-get is the
; only thing that knows that.  Dispatch throughout this file is a table plus
; this lookup, rather than a `match` welding each key to its handler -- so the
; set of keys and what they do stay one fact instead of two.
(def %sh-table-get
  (fn (self key table)
    (if (null? table)
      ()
      (if (string=? key (first (first table)))
        (rest (first table))
        (self key (rest table))))))

(def %sh-reserved-words
  (list "if" "then" "elif" "else" "fi"
        "while" "until" "for" "do" "done"
        "case" "in" "esac" "!" "{" "}"))

; The subset that CLOSES a construct.  %sh-reserved-words is the full sixteen
; and is right for asking "could this word be syntax"; these are the ones that
; may terminate a command already in progress.  `if`, `while`, `for`, `case`,
; `in`, `!` and `{` are all OPENERS -- no compound parser looks for one as a
; terminator, so treating them as arguments costs nothing and is what a shell
; does.
(def %sh-closing-words
  (list "then" "elif" "else" "fi" "do" "done" "esac" "}"))

; The operators that end a command list the same way a closing word does.
(def %sh-stop-ops (list ")" ";;"))

; What NESTS, for the skip walks.  Every compound opens with one of these and
; closes with one of those, and the five skippers each carried their own copy
; of both lists -- three copies that had drifted: %skip-to-fi's openers were
; missing `until` and `case` and its closers were missing `esac`, so an
; `until` loop inside a skipped if-branch put the parser out by one.
(def %sh-block-openers (list "if" "while" "until" "for" "case"))
(def %sh-block-closers (list "fi" "done" "esac"))

(def %reserved-word?
  (fn (_ word) (%sh-word-in? word %sh-reserved-words)))
; The reserved words that CLOSE a construct.  %reserved-word? is the full
; fifteen and is right for asking "could this word be syntax"; this is the
; subset that may terminate a command already in progress.  `if`, `while`,
; `for`, `case`, `in`, `!` and `{` are all OPENERS -- no compound parser looks
; for one as a terminator, so treating them as arguments costs nothing and is
; what a shell does.
; HOW DEEP INSIDE A COMPOUND THE PARSER IS.  `done` only closes something when
; there is something open: at the top level it is an ordinary word, and
; treating it as a terminator did real damage --
;
;   echo done      printed a blank line, AND
;   echo end       (and everything after it) never ran
;
; -- because the abandoned `done` then satisfied %at-stop-word?, which ended
; the enclosing %eval-list and silently discarded the rest of the script.
; Bumped for the whole of any compound (see %eval-compound), so the closers
; keep their power exactly where a construct is waiting for them.
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
          ((eq? (first tok) (lit tok-word)) (%closing-word? (first (rest tok))))
          ((eq? (first tok) (lit tok-op))
            (%sh-word-in? (first (rest tok)) %sh-stop-ops))
          (else ()))))))

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

(def %sh-digit? (fn (_ c) (and (>= c #\0) (<= c #\9))))

(def %sh-name-start?
  (fn (_ c)
    (or (and (>= c #\A) (<= c #\Z))
        (and (>= c #\a) (<= c #\z))
        (= c #\_))))

(def %sh-name-char?
  (fn (_ c) (or (%sh-name-start? c) (%sh-digit? c))))

; `set -u`: a plain `$X` on an unset name is an error.  ONLY the plain form --
; `${X:-default}` and `${X+alt}` exist precisely to ask about an unset
; parameter, and POSIX exempts them, so they go through %sh-var-value directly.
(def %sh-var-value-checked
  (fn (_ name)
    (if (and (not (null? %sh-opt-nounset)) (%sh-param-unset? name))
      (error (string-append name ": parameter not set"))
      (%sh-var-value name))))

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
; `-x` trace commands to stderr.  `set +e` and friends turn them off, which is
; why each is a cell rather than a flag set once.
(def %sh-opt-errexit ())
(def %sh-opt-nounset ())
(def %sh-opt-xtrace ())

; ERREXIT MUST NOT FIRE IN A CONDITION.  `if false; then`, `false || echo`,
; `! cmd` and a `while` test all run commands whose failure is the POINT, and a
; shell that exited on them would be unusable.  POSIX lists those contexts
; explicitly; this counts them, and %sh-should-exit? asks whether any is open.
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
(def %sh-return-status 0)

(def %sh-join-args
  (fn (self args)
    (if (null? args)
      ""
      (if (null? (rest args))
        (first args)
        (string-append (first args)
          (string-append " " (self (rest args))))))))

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
        (pair "#" (fn (_) (convert (length %sh-args) %string)))
        ; $@ and $* differ only under field splitting of the RESULT, which
        ; ash does not do -- so they are the same string here.
        (pair "@" (fn (_) (%sh-join-args %sh-args)))
        (pair "*" (fn (_) (%sh-join-args %sh-args)))))

(def %sh-var-value
  (fn (_ name)
    (let ((special (%sh-table-get name %sh-special-vars)))
      (cond
        ((not (null? special)) (special))
        ((%all-digits? name) (%sh-arg-at (convert name %int)))
        ; An unset variable expands to the empty string, which is POSIX
        ; default -- there is no `set -u` here to make it an error.
        (else (let ((v (sh-getenv name))) (if (null? v) "" v)))))))

; The end of the name run starting at I.
(def %sh-name-end
  (fn (self s i n)
    (if (>= i n)
      i
      (if (%sh-name-char? (string-ref s i))
        (self s (+ i 1) n)
        i))))

; The index of the closing brace at or after I, or -1.
; The `}` closing a `${` opened before I, or -1.  Depth-aware, so a default
; that is itself an expansion -- `${X:-${Y}}` -- closes where it should.
(def %sh-brace-end
  (fn (self s i n depth)
    (if (>= i n)
      (- 0 1)
      (let ((c (string-ref s i)))
        (cond
          ((= c #\{) (self s (+ i 1) n (+ depth 1)))
          ((= c #\}) (if (= depth 0) i (self s (+ i 1) n (- depth 1))))
          (else (self s (+ i 1) n depth)))))))

; Inside double quotes a backslash is literal EXCEPT before one of $ ` " \ and
; newline -- so `"a\db"` keeps its backslash and `"a\$b"` does not.  Outside
; quotes a backslash escapes whatever follows it.
(def %sh-dq-escapable?
  (fn (_ c)
    (or (= c #\$) (= c #\`) (= c #\")
        (= c #\\) (= c #\newline))))

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
; --- Command substitution ----------------------------------------------------
;
; `$(...)` and the older backtick form.  Both run the text as a shell script in
; a CHILD whose stdout is a pipe, and both answer what it printed with trailing
; newlines removed -- which is the whole of what POSIX asks for, and the reason
; `X=$(pwd)` is the single most-reached-for thing a shell does that ash could
; not express at all.
;
; THE STATUS IS NOT PROPAGATED, and that is a deliberate limit rather than an
; oversight: expansion happens while the command's words are being COLLECTED,
; and %sh-run-cmd overwrites %sh-status with the command's own status
; afterwards.  So `echo $(false)` correctly reports echo's 0, and
; `X=$(false); echo $?` reports 0 where a POSIX shell says 1.  Recording it
; here would be recording a value that is about to be overwritten.

; The index of the `)` closing a substitution opened before I, or -1.  Quoted
; regions hide their parens, matching the tokenizer's own scan.
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

(def %sh-cmd-subst
  (fn (_ src)
    (let ((p (%sh-pipe-create)))
      (let ((read-fd (first p)) (write-fd (rest p)))
        (let ((pid (sh-fork)))
          (if (= pid 0)
            (do
              (sh-close read-fd)
              (sh-dup2 write-fd 1)
              (sh-close write-fd)
              ; The substituted text is its own script, so it starts at the
              ; top level however deep the expansion was reached from.
              (set! %sh-compound-depth 0)
              ; A failing substitution answers what it managed to print, the
              ; way a shell does -- the error has already gone to stderr.
              (guard (e ()) (sh-eval-extracted src))
              (sh-exit %sh-status))
            ; READ BEFORE WAIT.  A child whose output exceeds the pipe buffer
            ; blocks in write() until someone drains it, so waiting first would
            ; deadlock on any substitution bigger than a pipe.
            (do
              (sh-close write-fd)
              (let ((out (sh-read-all-fd read-fd)))
                (sh-close read-fd)
                (sh-wait pid)
                (%sh-rstrip-newlines out)))))))))

; --- FIELD SPLITTING -------------------------------------------------------
;
; The expander answers a LIST OF FIELDS, not a string, and that is the whole
; of this section.  A word is split on whitespace AFTER it expands, and only
; the expanded part is split:
;
;   X="a b"; cmd $X          two arguments
;   X="a b"; cmd "$X"        one
;   for f in $(cat list)     once per line, not once for the whole file
;   cmd $EMPTY               NO argument at all, not an empty one
;   cmd "$EMPTY"             one empty argument
;
; Until this existed every one of those was one field, which is the single
; behaviour scripts lean on hardest without noticing.
;
; The walker carries (fields cur started).  `started` is what separates "an
; empty field" from "no field": literal text and quote marks set it, expanded
; text sets it only for the characters it actually contributes.  That is why
; `cmd "$EMPTY"` yields an empty argument -- the quotes started a field -- and
; `cmd $EMPTY` yields none.
;
; IFS IS THE DEFAULT SET, space/tab/newline, and is not configurable: `set` is
; not implemented, so there is nowhere to change it from.

(def %sh-ws-char?
  (fn (_ c) (or (= c #\space) (= c #\tab) (= c #\newline))))

(def %sh-lead-ws?
  (fn (_ text)
    (if (= (string-length text) 0)
      ()
      (%sh-ws-char? (string-ref text 0)))))

(def %sh-trail-ws?
  (fn (_ text)
    (let ((n (string-length text)))
      (if (= n 0)
        ()
        (%sh-ws-char? (string-ref text (- n 1)))))))

; The non-empty runs between whitespace, in order.
; --- IFS ---------------------------------------------------------------------
;
; The default is space/tab/newline, and until `set` existed there was nowhere
; to change it from -- so this was hard-coded.  POSIX gives IFS two kinds of
; character and they behave differently:
;
;   WHITESPACE in IFS   a run of them is ONE delimiter, and leading or trailing
;                       runs produce no field:  `a  b` is two fields
;   anything else       EACH occurrence delimits, so adjacent ones make empty
;                       fields:  IFS=: over `a::b` is three
;
; and a non-whitespace delimiter may have IFS whitespace either side of it,
; which belongs to it rather than delimiting again.
;
; IFS set but EMPTY means no splitting at all -- the one case people reach for
; deliberately, to read a whole line into one field.

(def %sh-ifs-default " \t\n")

(def %sh-ifs
  (fn (_)
    (let ((v (sh-getenv "IFS")))
      (if (null? v) %sh-ifs-default v))))

(def %sh-in-ifs? (fn (_ c ifs) (%sh-str-has-char? ifs c)))

(def %sh-str-has-char?
  (fn (_ text c)
    (let ((n (string-length text)))
      (def go
        (fn (self i)
          (if (>= i n) () (if (= (string-ref text i) c) #t (self (+ i 1))))))
      (go 0))))

; How far a run of IFS WHITESPACE reaches from I.
(def %sh-ifs-ws-end
  (fn (self text i n ifs)
    (if (and (< i n)
             (and (%sh-ws-char? (string-ref text i))
                  (%sh-in-ifs? (string-ref text i) ifs)))
      (self text (+ i 1) n ifs)
      i)))

(def %sh-ifs-split
  (fn (_ text)
    (let ((ifs (%sh-ifs)))
      (if (= (string-length ifs) 0)
        ; IFS="" -- no splitting.  An empty text is still no fields.
        (if (= (string-length text) 0) () (list text))
        (let ((n (string-length text)))
          (def go
            (fn (self i cur started acc)
              (if (>= i n)
                (reverse (if started (pair cur acc) acc))
                (let ((c (string-ref text i)))
                  (if (not (%sh-in-ifs? c ifs))
                    (self (+ i 1)
                      (string-append cur (substring text i (+ i 1))) #t acc)
                    ; A delimiter.  Take any IFS whitespace around it, and at
                    ; most ONE non-whitespace delimiter with it.
                    (let ((after-ws (%sh-ifs-ws-end text i n ifs)))
                      (let ((hard? (and (< after-ws n)
                                        (and (%sh-in-ifs?
                                               (string-ref text after-ws) ifs)
                                             (not (%sh-ws-char?
                                                    (string-ref text after-ws))))))
                        )
                        (let ((j (%sh-ifs-ws-end text
                                   (if hard? (+ after-ws 1) after-ws) n ifs)))
                          ; A whitespace-only delimiter never makes an empty
                          ; field; a non-whitespace one does.
                          (if (or hard? started)
                            (self j "" (and hard? (< j n))
                              (pair cur acc))
                            (self j "" () acc))))))))))
          ; A leading run of IFS whitespace is skipped rather than delimiting.
          (go (%sh-ifs-ws-end text 0 n ifs) "" () ()))))))

; --- The word being built ---------------------------------------------------
;
; Three values travel together through the whole of the expansion walk: the
; FIELDS finished so far (reversed), the field CURrently being built, and
; whether anything has STARTED that field.  They were passed as three
; positional parameters and returned as a bare (list a b c), read back with
; (first (rest (rest r))) -- which is not a data structure, it is a dare.
;
; Named constructor and accessors instead.  The representation is still a
; list, because that is what the language offers; what changes is that no
; caller has to know it.
; THE FIELD IN HAND IS A LIST OF PIECES, not a string.  It was a string, grown
; with (string-append cur here) once per character -- which copies the whole
; accumulated field every time, so building an n-character word cost O(n^2) and
; two allocations per character.  With the per-snippet collect off (this
; bundle's runner turns it off; see tests/spec-runner.sh) a batched spec run
; accumulates all of that and died on the interpreter's allocation ceiling.
;
; Pieces are pushed in reverse and joined ONCE, when the field closes.  Per
; character that is one cons; the copying happens exactly once per field.
(def %sh-acc (fn (_ fields pieces started) (list fields pieces started)))
(def %sh-acc-fields  (fn (_ a) (first a)))
(def %sh-acc-pieces  (fn (_ a) (first (rest a))))
(def %sh-acc-started (fn (_ a) (first (rest (rest a)))))

(def %sh-acc-empty (%sh-acc () () ()))

; The field in hand, materialized.  Only the two closers below need it.
(def %sh-acc-cur
  (fn (_ a) (Str8 join "" (List reverse (%sh-acc-pieces a)))))

; Anything literal starts a field, which is what makes `cmd ""` an empty
; argument.
(def %sh-acc-add
  (fn (_ a text)
    (%sh-acc (%sh-acc-fields a) (pair text (%sh-acc-pieces a)) #t)))

; Mark the field open without adding to it -- what a quote mark does.
(def %sh-acc-open
  (fn (_ a) (%sh-acc (%sh-acc-fields a) (%sh-acc-pieces a) #t)))

; Close the field in hand and begin the next one.
(def %sh-acc-break
  (fn (_ a)
    (%sh-acc (pair (%sh-acc-cur a) (%sh-acc-fields a)) () ())))

; Close the word: the field in hand becomes one iff anything started it.
(def %sh-acc-finish
  (fn (_ a)
    (reverse
      (if (%sh-acc-started a)
        (pair (%sh-acc-cur a) (%sh-acc-fields a))
        (%sh-acc-fields a)))))

; --- Keeping quoted glob characters literal ---------------------------------
;
; Pathname expansion happens AFTER the word is built, by which point `"*"` and
; `*` are the same character -- so the accumulator has to carry the difference.
; It carries it as a BACKSLASH: text that was quoted or escaped goes in with
; its glob metacharacters escaped, which is exactly the notation %sh-glob-at
; already understands and %sh-glob-unescape takes back off at the end.
;
; A backslash is escaped too, so the unescape is exact: every backslash in a
; finished field is one this put there (an unquoted one was consumed by the
; walk as an escape and never reached here).
(def %sh-glob-meta (list #\* #\? #\[ #\\))

(def %sh-char-in?
  (fn (self c chars)
    (if (null? chars)
      ()
      (if (= c (first chars)) #t (self c (rest chars))))))

; SCAN FIRST, BUILD ONLY IF NEEDED.  This runs on every literal character of
; every word; almost none is a metacharacter, so the almost-always path
; allocates nothing.
(def %sh-has-glob-meta?
  (fn (_ text)
    (let ((n (string-length text)))
      (def go
        (fn (self i)
          (if (>= i n)
            ()
            (if (%sh-char-in? (string-ref text i) %sh-glob-meta)
              #t
              (self (+ i 1))))))
      (go 0))))

(def %sh-glob-escape
  (fn (_ text)
    (if (not (%sh-has-glob-meta? text))
      text
      (let ((n (string-length text)))
        (def go
          (fn (self i out)
            (if (>= i n)
              (Str8 join "" (List reverse out))
              (let ((here (substring text i (+ i 1))))
                (self (+ i 1)
                  (pair (if (%sh-char-in? (string-ref text i) %sh-glob-meta)
                          (string-append "\\" here)
                          here)
                        out))))))
        (go 0 ())))))

(def %sh-acc-add-literal
  (fn (_ a text) (%sh-acc-add a (%sh-glob-escape text))))

; --- Splicing expanded text in --------------------------------------------
;
; Every piece after the first STARTS a field, so the one in hand is closed
; ahead of it.
(def %sh-add-pieces
  (fn (self a pieces)
    (if (null? pieces)
      a
      (self (%sh-acc-add (%sh-acc-break a) (first pieces)) (rest pieces)))))

; Splice expanded TEXT into the accumulator, splitting it on IFS whitespace.
;
; Leading whitespace closes the field in hand; the first piece JOINS whatever
; is left of it (`p${X}s` is one word made of three); each later piece starts
; its own; trailing whitespace closes the last.
(def %sh-add-split
  (fn (_ a text)
    (let ((pieces (%sh-ifs-split text)))
      (cond
        ; Nothing at all changes nothing; all-whitespace still closes a field
        ; that has content.
        ((null? pieces)
          (if (and (> (string-length text) 0) (%sh-acc-started a))
            (%sh-acc-break a)
            a))
        (else
          (let ((opened (if (and (%sh-lead-ws? text) (%sh-acc-started a))
                          (%sh-acc-break a)
                          a)))
            (let ((filled (%sh-add-pieces
                            (%sh-acc-add opened (first pieces))
                            (rest pieces))))
              (if (%sh-trail-ws? text) (%sh-acc-break filled) filled))))))))

; One expansion's worth of text.  Split only when splitting is on AND we are
; outside quotes -- inside `"..."` a value keeps its spaces, which is the
; entire point of quoting it.
(def %sh-add-expansion
  (fn (_ a mode text split?)
    (if (= mode %sh-mode-bare)
      ; An unquoted expansion's RESULT is subject to both splitting and
      ; globbing -- `X='*'; echo $X` globs, `echo "$X"` does not.
      (if split? (%sh-add-split a text) (%sh-acc-add a text))
      (%sh-acc-add-literal a text))))

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
; and the already-expanded word.
(def %sh-param-default
  (fn (_ name val fired? word) (if fired? word val)))

(def %sh-param-assign
  (fn (_ name val fired? word)
    (if fired? (do (sh-setenv name word) word) val)))

(def %sh-param-error
  (fn (_ name val fired? word)
    (if fired?
      (error (string-append name ": "
               (if (= (string-length word) 0) "parameter not set" word)))
      val)))

; `+` fires on the opposite condition to the other three: it wants the word
; when the parameter IS set.  The caller inverts before calling, so this stays
; the same shape as its neighbours.
(def %sh-param-alt
  (fn (_ name val fired? word) (if fired? word "")))

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

; The leading parameter NAME: a run of name characters, or a single special
; ($?, $#, $1...), or empty when the braces open with an operator.
(def %sh-param-name
  (fn (_ inner)
    (let ((n (string-length inner)))
      (if (= n 0)
        ""
        (let ((c (string-ref inner 0)))
          (if (%sh-name-start? c)
            (substring inner 0 (%sh-name-end inner 0 n))
            (if (null? (%sh-table-get (substring inner 0 1) %sh-special-vars))
              (if (%sh-digit? c) (substring inner 0 1) "")
              (substring inner 0 1))))))))

; Is the parameter unset?  A special is always set; a positional is set when it
; is within range; anything else asks the environment.
(def %sh-param-unset?
  (fn (_ name)
    (cond
      ((not (null? (%sh-table-get name %sh-special-vars))) ())
      ((%all-digits? name) (> (convert name %int) (length %sh-args)))
      (else (null? (sh-getenv name))))))

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
                  (%sh-expand-word word))))))))))

; ${...} in full.  Answers the expanded text.
(def %sh-brace-expand
  (fn (_ inner)
    (let ((n (string-length inner)))
      (cond
        ((= n 0) "")
        ; ${#X} is a length; ${#} alone is the parameter COUNT, which
        ; %sh-var-value already knows as the special "#".
        ((and (> n 1) (= (string-ref inner 0) #\#))
          (convert
            (string-length (%sh-var-value (substring inner 1 n)))
            %string))
        (else
          (let ((name (%sh-param-name inner)))
            (let ((tail (substring inner (string-length name) n)))
              (if (= (string-length tail) 0)
                (%sh-var-value name)
                (let ((op (%sh-first-op tail %sh-param-op-names)))
                  (if (null? op)
                    ; Not an operator we know -- the whole of it is a name.
                    (%sh-var-value inner)
                    (%sh-param-apply name op
                      (substring tail (string-length op)
                        (string-length tail)))))))))))))

; How far the ORDINARY text starting at I runs: up to the next character the
; walk has an arm for.  In single quotes only the closing quote is special, so
; a `'...'` region is one run.
(def %sh-plain-char?
  (fn (_ c mode)
    (if (= mode %sh-mode-sq)
      (not (= c #\'))
      (not (or (= c #\') (= c #\") (= c #\\) (= c #\`) (= c #\$))))))

(def %sh-plain-run-end
  (fn (self s i n mode)
    (if (>= i n)
      i
      (if (%sh-plain-char? (string-ref s i) mode)
        (self s (+ i 1) n mode)
        i))))

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
(def %sh-ar-levels
  (list (list "||")
        (list "&&")
        (list "==" "!=")
        (list "<=" ">=" "<" ">")
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
                       (error "ash: arithmetic: division by 0")
                       (convert (/ a b) %int))))
        (pair "%"  (fn (_ a b)
                     (if (= b 0) (error "ash: arithmetic: division by 0") (% a b))))))

(def %sh-ar-skip-ws
  (fn (self s i n)
    (if (and (< i n) (%sh-ws-char? (string-ref s i)))
      (self s (+ i 1) n)
      i)))

; Which of this level's operators the text at I begins with, or nil.  The level
; lists put `<=` before `<` so the longer match is found first.
(def %sh-ar-match-op
  (fn (self s i n ops)
    (if (null? ops)
      ()
      (if (%sh-str-starts? (substring s i n) (first ops))
        (first ops)
        (self s i n (rest ops))))))

(def %sh-ar-digits-end
  (fn (self s i n)
    (if (and (< i n) (%sh-digit? (string-ref s i))) (self s (+ i 1) n) i)))

; An unset or non-numeric name is 0, which is POSIX.  `convert` ANSWERS NIL
; for both rather than raising, so a guard alone does not catch it -- that nil
; reached `+` as an operand and the whole expansion died.
(def %sh-ar-num
  (fn (_ text)
    (let ((v (guard (_ ()) (convert text %int))))
      (if (null? v) 0 v))))

(def %sh-ar-level ())
(def %sh-ar-level-loop ())
(def %sh-ar-primary ())

(set! %sh-ar-primary
  (fn (_ s i0 n)
    (let ((i (%sh-ar-skip-ws s i0 n)))
      (if (>= i n)
        (%sh-ar 0 i)
        (let ((c (string-ref s i)))
          (cond
            ((= c #\()
              (let ((inner (%sh-ar-level s (+ i 1) n %sh-ar-levels)))
                ; Step over the closing paren if it is there.
                (let ((e (%sh-ar-skip-ws s (%sh-ar-pos inner) n)))
                  (%sh-ar (%sh-ar-val inner)
                          (if (and (< e n) (= (string-ref s e) #\))) (+ e 1) e)))))
            ((= c #\-)
              (let ((r (%sh-ar-primary s (+ i 1) n)))
                (%sh-ar (- 0 (%sh-ar-val r)) (%sh-ar-pos r))))
            ((= c #\+) (%sh-ar-primary s (+ i 1) n))
            ((= c #\!)
              (let ((r (%sh-ar-primary s (+ i 1) n)))
                (%sh-ar (%sh-bool-int (not (%sh-truthy? (%sh-ar-val r))))
                        (%sh-ar-pos r))))
            ((%sh-digit? c)
              (let ((e (%sh-ar-digits-end s i n)))
                (%sh-ar (%sh-ar-num (substring s i e)) e)))
            ((%sh-name-start? c)
              (let ((e (%sh-name-end s i n)))
                (%sh-ar (%sh-ar-num (%sh-var-value (substring s i e))) e)))
            ; Anything else is not arithmetic; step over it rather than loop.
            (else (%sh-ar 0 (+ i 1)))))))))

(set! %sh-ar-level
  (fn (_ s i n levels)
    (if (null? levels)
      (%sh-ar-primary s i n)
      (%sh-ar-level-loop s (%sh-ar-level s i n (rest levels)) n levels))))

; Left-associative: fold each further operator of this level onto what is
; already built.
(set! %sh-ar-level-loop
  (fn (_ s left n levels)
    (let ((i (%sh-ar-skip-ws s (%sh-ar-pos left) n)))
      (let ((op (%sh-ar-match-op s i n (first levels))))
        (if (null? op)
          (%sh-ar (%sh-ar-val left) i)
          (let ((right (%sh-ar-level s (+ i (string-length op)) n (rest levels))))
            (%sh-ar-level-loop s
              (%sh-ar ((%sh-table-get op %sh-ar-ops)
                        (%sh-ar-val left) (%sh-ar-val right))
                      (%sh-ar-pos right))
              n levels)))))))

(def %sh-arith-eval
  (fn (_ text)
    (let ((n (string-length text)))
      (convert (%sh-ar-val (%sh-ar-level text 0 n %sh-ar-levels)) %string))))

; Is this `$(` inner text an arithmetic expansion rather than a command one?
(def %sh-arith?
  (fn (_ inner)
    (let ((n (string-length inner)))
      (and (>= n 2)
           (and (= (string-ref inner 0) #\()
                (= (string-ref inner (- n 1)) #\)))))))

; --- The walk ---------------------------------------------------------------
;
; MODE says which kind of region the scan is in.  A word is not uniformly
; quoted: `X="a b"` and `pre'lit'$X` are each several regions in one word, and
; the mode is which one the scan is inside right now.
(def %sh-mode-bare 0)          ; outside quotes
(def %sh-mode-sq 1)            ; inside '...'
(def %sh-mode-dq 2)            ; inside "..."

; SPLIT? is off for the two places POSIX does not split: a `case` subject, and
; a redirection target (where more than one field is an ambiguous redirect).
;
; A tok-word starts bare.  A tok-dq starts in mode 2 -- its outer quotes were
; already stripped by the reader, so there is no opening quote left to switch
; on, and the field must start open or `cmd ""` passes no argument at all.
(def %sh-expand-str
  (fn (_ s mode0 split?)
    (let ((n (string-length s)))
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
                    (let ((e (%sh-plain-run-end s i n mode)))
                      (self e mode
                        (%sh-acc-add-literal a (substring s i e))))))
                ; A quote mark switches region and starts a field.
                ((and (= mode %sh-mode-bare) (= c #\'))
                  (self (+ i 1) %sh-mode-sq (%sh-acc-open a)))
                ((and (= mode %sh-mode-bare) (= c #\"))
                  (self (+ i 1) %sh-mode-dq (%sh-acc-open a)))
                ((and (= mode %sh-mode-dq) (= c #\"))
                  (self (+ i 1) %sh-mode-bare (%sh-acc-open a)))
                ; A backslash emits what it protects and resumes PAST it, so a
                ; `$` it protected stays a `$`.
                ((and (= c #\\) (< (+ i 1) n))
                  (let ((d (string-ref s (+ i 1))))
                    (self (+ i 2) mode
                      (%sh-acc-add-literal a
                        (if (or (= mode %sh-mode-bare) (%sh-dq-escapable? d))
                          (substring s (+ i 1) (+ i 2))
                          (substring s i (+ i 2)))))))
                ; The older backtick substitution.
                ((= c #\`)
                  (let ((e (%sh-bt-end s (+ i 1) n)))
                    (if (< e 0)
                      (self (+ i 1) mode (%sh-acc-add a (substring s i (+ i 1))))
                      (self (+ e 1) mode
                        (%sh-add-expansion a mode
                          (%sh-cmd-subst (substring s (+ i 1) e)) split?)))))
                ((= c #\$) (%sh-expand-dollar self s i n mode a split?))
                ; ORDINARY TEXT GOES IN A RUN AT A TIME.  One character per
                ; step meant one substring allocation per character of every
                ; word; a plain word is now one substring, which is what took
                ; a batched spec run back under the interpreter's allocation
                ; ceiling.
                ;
                ; A bare `*` IS the glob; the same character inside quotes is
                ; not -- so the run is escaped or not by the mode it was read
                ; in, exactly as a single character was.
                (else
                  (let ((e (%sh-plain-run-end s i n mode)))
                    (let ((run (substring s i e)))
                      (self e mode
                        (if (= mode %sh-mode-bare)
                          (%sh-acc-add a run)
                          (%sh-acc-add-literal a run)))))))))))
      (go 0 mode0
        (if (= mode0 %sh-mode-dq) (%sh-acc-open %sh-acc-empty) %sh-acc-empty)))))

; The `$` arm, lifted out so the walk above stays readable.  CONT is the
; walker's own continuation, resumed at an index with an accumulator.
(def %sh-expand-dollar
  (fn (_ cont s i n mode a split?)
    ; Two local helpers, in a `let` so they stay local: this file already has
    ; more module-level %-names than it needs, and neither is meaningful
    ; outside these fifteen lines.
    (let ((literal-dollar
            (fn (_) (cont (+ i 1) mode (%sh-acc-add a "$"))))
          (substitute
            (fn (_ next text)
              (cont next mode (%sh-add-expansion a mode text split?)))))
    ; A `$` at the very end is a literal `$`.
    (if (>= (+ i 1) n)
      (%sh-acc-finish (%sh-acc-add a "$"))
      (let ((d (string-ref s (+ i 1))))
        (cond
          ; $( ... ) -- a command substitution.
          ((= d #\()
            (let ((e (%sh-cs-end s (+ i 2) n 0)))
              (if (< e 0)
                (literal-dollar)
                (let ((inner (substring s (+ i 2) e)))
                  (substitute (+ e 1)
                    (if (%sh-arith? inner)
                      (%sh-arith-eval (substring inner 1 (- (string-length inner) 1)))
                      (%sh-cmd-subst inner)))))))
          ; ${NAME}
          ((= d #\{)
            (let ((e (%sh-brace-end s (+ i 2) n 0)))
              (if (< e 0)
                (literal-dollar)
                (substitute (+ e 1)
                  (%sh-brace-expand (substring s (+ i 2) e))))))
          ; The one-character specials: $? $$ $# $@ $* and $1..$9.
          ;
          ; A SINGLE DIGIT ONLY, which is POSIX and surprises people: `$10` is
          ; $1 followed by a literal 0, and ${10} is how the tenth is spelled.
          ((or (= d #\?) (= d #\$) (= d #\#)
               (= d #\@) (= d #\*) (%sh-digit? d))
            (substitute (+ i 2) (%sh-var-value (substring s (+ i 1) (+ i 2)))))
          ; $NAME
          ((%sh-name-start? d)
            (let ((e (%sh-name-end s (+ i 1) n)))
              (substitute e (%sh-var-value-checked (substring s (+ i 1) e)))))
          ; $ followed by anything else is a literal $.
          (else (literal-dollar))))))))

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
              (Str8 join "" (List reverse out))
              (if (and (= (string-ref text i) #\\) (< (+ i 1) n))
                (self (+ i 2) (pair (substring text (+ i 1) (+ i 2)) out))
                (self (+ i 1) (pair (substring text i (+ i 1)) out))))))
        (go 0 ())))))

; Does this text hold a glob character the user meant AS one?  Escaped ones do
; not count, which is the whole point of the escaping.
(def %sh-glob-pattern?
  (fn (_ text)
    (let ((n (string-length text)))
      (def go
        (fn (self i)
          (if (>= i n)
            ()
            (let ((c (string-ref text i)))
              (if (= c #\\)
                (self (+ i 2))
                (if (or (= c #\*) (= c #\?) (= c #\[)) #t (self (+ i 1))))))))
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

(def %sh-glob-field
  (fn (_ field)
    (if (not (%sh-glob-pattern? field))
      (list (%sh-glob-unescape field))
      (let ((absolute? (= (string-ref field 0) #\/))
            (segments (%sh-glob-split field)))
        (let ((hits (%sh-glob-walk
                      (if absolute? (rest segments) segments)
                      (list (if absolute? "/" "")))))
          (let ((final (if (%sh-trailing-slash? segments)
                         (%sh-dirs-only hits)
                         hits)))
            ; No match: the pattern stands, with its escapes removed.
            (if (null? final) (list (%sh-glob-unescape field)) final)))))))

(def %sh-glob-fields
  (fn (self fields)
    (if (null? fields)
      ()
      (List append (%sh-glob-field (first fields)) (self (rest fields))))))

; --- What the callers see ----------------------------------------------------
;
; A tok-sq is one field, always: single quotes suppress everything, splitting
; included, and `''` is an empty argument rather than none.
(def %sh-tok-mode
  (fn (_ tok)
    (if (eq? (first tok) (lit tok-dq)) %sh-mode-dq %sh-mode-bare)))

(def %sh-expand-tok
  (fn (_ tok)
    (if (eq? (first tok) (lit tok-sq))
      ; Single quotes suppress everything, globbing included.
      (list (%tok-word-val tok))
      (%sh-glob-fields
        (%sh-expand-str (%tok-word-val tok) (%sh-tok-mode tok) #t)))))

; The unsplit reading, for a `case` subject and a redirection target.
(def %sh-expand-tok-1
  (fn (_ tok)
    (if (eq? (first tok) (lit tok-sq))
      (%tok-word-val tok)
      (let ((fs (%sh-expand-str (%tok-word-val tok) (%sh-tok-mode tok) ())))
        ; Not globbed, but the escapes still come off -- a redirection target
        ; and a case subject are literal strings.
        (if (null? fs) "" (%sh-glob-unescape (first fs)))))))

; Still string-in, string-out, for the sites that hold a value rather than a
; token.  Unsplit by construction.
(def %sh-expand-word
  (fn (_ word)
    (if (not (string? word))
      word
      (let ((fs (%sh-expand-str word %sh-mode-bare ())))
        (if (null? fs) "" (first fs))))))

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
          (let ((c (string-ref s i)))
            (if (and (>= c (convert #\0 %int)) (<= c (convert #\9 %int)))
              (%check (+ i 1) len)
              ())))))
    (if (= (string-length s) 0)
      ()
      (%check 0 (string-length s)))))

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
; FD arrives as a string when the script wrote one (`2> log`) and as an int
; from %default-fd otherwise; %sh-redir-fd is where that is reconciled, once.
(def %sh-redir (fn (_ op fd target) (list (lit sh-redir) op fd target)))
(def %sh-redir-op     (fn (_ r) (first (rest r))))
(def %sh-redir-target (fn (_ r) (first (rest (rest (rest r))))))
(def %sh-redir-fd
  (fn (_ r)
    (let ((fd (first (rest (rest r)))))
      (if (string? fd) (convert fd %int) fd))))

; A here-document's body reaches the command down a pipe.
;
; THE WRITER IS A FORKED CHILD, not this process.  Writing the body here and
; then reading it back would deadlock on any body larger than the pipe buffer
; (64 KB on the usual boxes): nothing is draining the other end yet.  The child
; writes and exits; the parent keeps only the read end.
;
; It is not waited for.  Waiting would be the same deadlock from the other
; side -- the reader has not run yet -- so the writer is reaped when the shell
; exits, which is what a shell using a temp file avoids and what this trades
; for having no temp file at all.
(def %sh-setup-heredoc
  (fn (_ index fd)
    (let ((h (%sh-heredoc-at (convert index %int))))
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
                    (sh-dup2 r fd)
                    (sh-close r)))))))))))

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
    (let ((fs (%sh-expand-str text %sh-mode-dq ())))
      (if (null? fs) "" (%sh-glob-unescape (first fs))))))

(def %sh-setup-redir
  (fn (_ redir)
    (let ((op (%sh-redir-op redir))
           ; Expanded at collection, with its quoting in hand.
           (target (%sh-redir-target redir)))
      (let ((fd (%sh-redir-fd redir)))
        (if (or (string=? op "<<") (string=? op "<<-"))
          (%sh-setup-heredoc target fd)
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
                    ())))))))))))

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
              (if (= (string-ref word i) (convert #\= %int))
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

; A shell's truth is INVERTED: 0 is true.  %sh-bool turns a predicate's answer
; into that, once, instead of every arm spelling `(if p 0 1)`.
(def %sh-bool (fn (_ p) (if p 0 1)))

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
; The operator tables.  A test operator is a NAME and a PREDICATE, and the
; shell's inverted truth (0 is true) is applied once, by the caller, rather
; than by every arm.
(def %sh-file-ops
  (list (pair "-e" (fn (_ kind path) (not (null? kind))))
        (pair "-f" (fn (_ kind path) (eq? kind (lit file))))
        (pair "-d" (fn (_ kind path) (eq? kind (lit dir))))
        (pair "-s" (fn (_ kind path)
                     (and (not (null? kind)) (> (sh-path-size path) 0))))))

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

(def %sh-test-num
  (fn (_ l op r)
    (let ((p (%sh-table-get op %sh-num-ops)))
      (if (null? p)
        ()
        (%sh-bool (p (convert l %int) (convert r %int)))))))

(def %sh-test-1
  (fn (_ word) (%sh-bool (> (string-length word) 0))))

(def %sh-test-2
  (fn (_ op val)
    (match
      ((string=? op "-n") (%sh-bool (> (string-length val) 0)))
      ((string=? op "-z") (%sh-bool (= (string-length val) 0)))
      ((string=? op "!")  (%sh-bool (not (= (%sh-test (list val)) 0))))
      (#t
        (let ((r (%sh-test-file op val)))
          ; An unknown unary operator is a usage error (2), not a false --
          ; `test -q x` should complain, not quietly fail.
          (if (null? r)
            (do (%stderr "ash: test: " op ": unary operator expected\n") 2)
            r))))))

(def %sh-test-3
  (fn (_ left op right)
    (match
      ((string=? op "=")  (%sh-bool (string=? left right)))
      ((string=? op "!=") (%sh-bool (not (string=? left right))))
      (#t
        (let ((r (%sh-test-num left op right)))
          (if (null? r)
            (do (%stderr "ash: test: " op ": binary operator expected\n") 2)
            r))))))

; A plain def: %sh-test-2 calls back into this for `!`, but a body's references
; resolve when it RUNS, so no forward declaration is needed.  The (def x ())
; then (set! x ...) dance this replaces is what let the declaration be deleted
; with the block above it and turned every spec red at load.
(def %sh-test
  (fn (_ wds)
    (let ((n (length wds)))
      (cond
        ((= n 0) 1)
        ; `! EXPR` at any length, so `test ! -f x` works.  Checked before the
        ; arities so the negation composes with all of them.
        ((and (> n 1) (string=? (first wds) "!"))
          (%sh-bool (not (= (%sh-test (rest wds)) 0))))
        ((= n 1) (%sh-test-1 (first wds)))
        ((= n 2) (%sh-test-2 (first wds) (first (rest wds))))
        ((= n 3) (%sh-test-3 (first wds) (first (rest wds))
                             (first (rest (rest wds)))))
        (else 1)))))

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
      (let ((c (string-ref s i)))
        (if (or (= c #\space) (= c #\tab)) (self s (+ i 1) n) i)))))

(def %sh-read-word-end
  (fn (self s i n)
    (if (>= i n)
      i
      (let ((c (string-ref s i)))
        (if (or (= c #\space) (= c #\tab)) i (self s (+ i 1) n))))))

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

(def %sh-return
  (fn (_ wds)
    (let ((n (if (null? wds) %sh-status (convert (first wds) %int))))
      (if (= %sh-fn-depth 0)
        ; Outside a function POSIX leaves this unspecified; report and carry
        ; on rather than unwinding to somewhere there is no frame for.
        (do (%stderr "ash: return: can only `return' from a function\n") 1)
        (do (set! %sh-return-status n) (error (lit %sh-return)))))))

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
(def %sh-set-opts
  (list (pair "e" (fn (_ on?) (set! %sh-opt-errexit on?)))
        (pair "u" (fn (_ on?) (set! %sh-opt-nounset on?)))
        (pair "x" (fn (_ on?) (set! %sh-opt-xtrace on?)))))

; One `-abc` or `+abc` cluster.
(def %sh-set-flags
  (fn (self word on? i)
    (if (>= i (string-length word))
      0
      (let ((f (%sh-table-get (substring word i (+ i 1)) %sh-set-opts)))
        (if (null? f)
          (do (%stderr "ash: set: " (substring word i (+ i 1))
                       ": unknown option\n") 2)
          (do (f on?) (self word on? (+ i 1))))))))

(def %sh-set
  (fn (self wds)
    (if (null? wds)
      0
      (let ((w (first wds)))
        (cond
          ((string=? w "--") (do (set! %sh-args (rest wds)) 0))
          ((%sh-str-starts? w "-")
            (let ((r (%sh-set-flags w #t 1)))
              (if (= r 0) (self (rest wds)) r)))
          ((%sh-str-starts? w "+")
            (let ((r (%sh-set-flags w () 1)))
              (if (= r 0) (self (rest wds)) r)))
          ; A bare operand: POSIX treats `set a b` as setting the parameters.
          (else (do (set! %sh-args wds) 0)))))))

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
; The three builtins that were written inline in the dispatch.  A table holds
; functions, so they have to BE functions -- which is no loss: `:` and `true`
; differing only in name is clearer as two bindings to one function than as two
; arms of a case.
(def %sh-true  (fn (_ wds) 0))
(def %sh-false (fn (_ wds) 1))

(def %sh-exit
  (fn (_ wds)
    (sh-exit (if (null? wds) %sh-status (convert (first wds) %int)))))

; `[ ... ]` is `test` with the closing bracket dropped.
(def %sh-bracket
  (fn (_ wds)
    (%sh-test
      (if (null? wds)
        wds
        (if (string=? (last wds) "]") (take (- (length wds) 1) wds) wds)))))

; --- The builtin table ------------------------------------------------------
;
; ONE table, not a list of names beside a dispatch that repeats them.  Those
; were two structures obliged to agree with nothing making them agree: adding a
; builtin to one and forgetting the other gives a name that %sh-builtin? claims
; and %sh-run-builtin answers 1 to -- a command that silently fails instead of
; running.  Now the names ARE the table's keys, so the question "is this a
; builtin" and the question "what runs it" cannot diverge.
;
; `.` and `source` are the same handler under two names, which a table says
; directly and a dispatch could only say twice.
(def %sh-builtin-table
  (list (pair "echo"   %sh-echo)
        (pair "cd"     %sh-cd)
        (pair "pwd"    %sh-pwd)
        (pair "export" %sh-export)
        (pair "unset"  %sh-unset)
        (pair "read"   %sh-read)
        (pair "return" %sh-return)
        (pair "shift"  %sh-shift)
        (pair "set"    %sh-set)
        (pair "test"   %sh-test)
        (pair "["      %sh-bracket)
        (pair "."      %sh-source)
        (pair "source" %sh-source)
        (pair "exit"   %sh-exit)
        (pair "true"   %sh-true)
        (pair "false"  %sh-false)
        (pair ":"      %sh-true)))

(def %sh-builtin?
  (fn (_ name) (not (null? (%sh-table-get name %sh-builtin-table)))))

(def %sh-run-builtin
  (fn (_ name wds)
    (let ((run (%sh-table-get name %sh-builtin-table)))
      ; Unreachable in practice -- %sh-run-cmd asks %sh-builtin? first, and
      ; both read this table -- but a missing handler must not be a crash.
      (if (null? run) 1 (run wds)))))

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
          (if (= (string-ref word i) (convert #\= %int))
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

; Every arm of the dispatch below ended `(set! %sh-status status) status`, so
; that is one function and the dispatch is one `cond`.
(def %sh-set-status
  (fn (_ status) (set! %sh-status status) status))

(def %sh-run-cmd
  (fn (_ wds redirs)
    ; ALREADY EXPANDED, at extraction (%collect-cmd-tokens).  Re-expanding here
    ; would expand a variable's VALUE -- `X='$Y'; echo $X` would print $Y's
    ; contents rather than the two characters it holds.
    (let ((remaining (%process-assignments wds)))
      (if (null? remaining)
        ; A bare assignment is a command that did nothing and succeeded.
        (%sh-set-status 0)
        (let ((name (first remaining))
              (args (rest remaining)))
          (unless (null? %sh-opt-xtrace)
            (%stderr "+ " (%sh-join-args remaining) "\n"))
          (let ((body (%sh-fn-lookup name %sh-functions)))
            (%sh-exit-on-error
             (%sh-set-status
              (cond
                ; A FUNCTION WINS OVER AN EXTERNAL AND LOSES TO A BUILTIN,
                ; which is the POSIX order.
                ((%sh-builtin? name) (%sh-run-builtin-redir name args redirs))
                ; Redirections on a function call apply for the whole body, and
                ; the shell's own descriptors must survive it -- the same
                ; save/apply/restore a builtin gets.
                ((not (null? body)) (%sh-run-fn-redir body args redirs))
                (else (%sh-run-external name args redirs)))))))))))

; `set -e`: a failed command ends the shell, unless a condition is open.
(def %sh-exit-on-error
  (fn (_ status)
    (if (%sh-should-exit? status) (sh-exit status) status)))

; A function under redirection, on the %sh-run-builtin-redir pattern.  Same
; guard, same reason: a body that raises with fd 1 pointing at a file would
; leave the SHELL writing there.
(def %sh-run-fn-redir
  (fn (_ body wds redirs)
    (if (null? redirs)
      (%sh-call-fn body wds)
      (do
        (%sh-save-fds redirs)
        (guard (e (do (%sh-restore-fds redirs) (error e)))
          (%sh-setup-redirs redirs)
          (let ((status (%sh-call-fn body wds)))
            (%sh-restore-fds redirs)
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
        (if (eq? (first tok) (lit tok-word))
          ; The keys of %sh-compound-table, so the two cannot disagree.  A `(`
          ; opens a subshell, which is punctuation rather than a word.
          (not (null? (%sh-table-get (first (rest tok)) %sh-compound-table)))
          (if (eq? (first tok) (lit tok-op))
            (string=? (first (rest tok)) "(")
            ()))))))

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
                    ; NOT SPLIT.  `> $f` with two fields in $f is an
                    ; ambiguous redirect in POSIX, not two files; taking the
                    ; unsplit reading keeps the common case right and the
                    ; pathological one harmless.
                    (let ((target (%sh-expand-tok-1 (%cursor-peek cur))))
                      (%cursor-advance! cur)
                      (%collect-cmd-tokens
                        cur
                        wds
                        (pair (%sh-redir rop fd target) redirs))))))
              (if (%tok-is-word? tok)
                (let ((val (%tok-word-val tok)))
                  ; A RESERVED WORD IN ARGUMENT POSITION IS AN ARGUMENT.  This
                  ; used to end the command at ANY of the fifteen, so
                  ;
                  ;   echo done      printed a blank line
                  ;   echo if        printed a blank line
                  ;
                  ; -- the word was dropped and `echo` ran with none.  POSIX
                  ; recognises a reserved word only as the FIRST word of a
                  ; command, and that position is already handled before this
                  ; loop by %is-compound-start?.
                  ;
                  ; Only the STOP words keep their power here, and only those
                  ; that close a construct: a body written without its `;`
                  ; (`do echo x done`) still ends at `done` rather than
                  ; swallowing it.  bash errors on that input; ending the
                  ; command is the friendlier of two answers to a script that
                  ; is wrong either way, and it is what the compound parsers
                  ; below already assume.
                  (if (and
                        (not (null? wds))
                        (eq? (first tok) (lit tok-word))
                        (%closing-word? val))
                    (%sh-run-cmd (reverse wds) (reverse redirs))
                    (do
                      (%cursor-advance! cur)
                      ; EXPANDED HERE, not in %sh-run-cmd, because this is the
                      ; last place the token's QUOTING is still known.  `val`
                      ; above stays raw: POSIX recognises reserved words before
                      ; expansion, so a variable holding "then" must not become
                      ; one.
                      (%collect-cmd-tokens
                        cur (%sh-push-fields (%sh-expand-tok tok) wds)
                        redirs))))
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

; Skip a false branch's body, stopping ON the elif/else/fi that follows it.
;
; NOT CONSUMED, and that is the whole of the bug this once had: swallowing the
; `fi` left %eval-elif-chain looking at the token after it, so
; `if false; then echo yes; fi` -- an else-less if whose condition is false --
; was a parse error on every version of this bundle.
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
    ; A CONDITION, so `set -e` must not fire on it -- `if false; then` and
    ; `while test ...` run commands whose failure is the point.
    (let ((cond-result (%sh-in-condition (fn (_) (%eval-list cur)))))
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
      (let ((fs (%sh-expand-tok (%cursor-peek cur))))
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
               (= (string-ref pat (+ i 1)) #\-))
        (if (and (>= c (string-ref pat i))
                 (<= c (string-ref pat (+ i 2))))
          #t
          (self pat (+ i 3) hi c))
        (if (= c (string-ref pat i))
          #t
          (self pat (+ i 1) hi c))))))

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
; a `]` immediately after the opening bracket are both literal.
(def %sh-glob-class-end
  (fn (_ pat i pn)
    (def scan
      (fn (self j)
        (if (>= j pn)
          (- 0 1)
          (if (= (string-ref pat j) #\]) j (self (+ j 1))))))
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
    (if (%sh-glob-at pat pi pn s si sn)
      #t
      (if (>= si sn) () (self pat pi pn s (+ si 1) sn)))))

(set! %sh-glob-at
  (fn (self pat pi pn s si sn)
    (if (>= pi pn)
      ; Pattern exhausted: a match only if the word is exhausted too.
      (if (>= si sn) #t ())
      (let ((pc (string-ref pat pi)))
        (match
          ((= pc #\*) (%sh-glob-star pat (+ pi 1) pn s si sn))
          ((= pc #\?)
            (if (>= si sn) () (self pat (+ pi 1) pn s (+ si 1) sn)))
          ((= pc #\[)
            (let ((e (%sh-glob-class-end pat (+ pi 1) pn)))
              (if (< e 0)
                ; Unterminated: a literal [
                (if (and (< si sn) (= (string-ref s si) #\[))
                  (self pat (+ pi 1) pn s (+ si 1) sn)
                  ())
                (if (and (< si sn) (%sh-glob-class-match? pat (+ pi 1) e s si))
                  (self pat (+ e 1) pn s (+ si 1) sn)
                  ()))))
          ((and (= pc #\\) (< (+ pi 1) pn))
            (if (and (< si sn)
                     (= (string-ref pat (+ pi 1))
                        (string-ref s si)))
              (self pat (+ pi 2) pn s (+ si 1) sn)
              ()))
          (#t
            (if (and (< si sn) (= pc (string-ref s si)))
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

      ; The case SUBJECT is expanded without field splitting (POSIX).
      (let ((word (%sh-expand-tok-1 word-tok)))
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

; THE DEPTH IS BUMPED HERE, around the whole compound, rather than in each of
; the five parsers: they have many return points apiece and a skip path each,
; and a counter that has to be decremented on all of them would be wrong within
; a week.  One place, with the guard/re-raise shape used for the descriptor
; saves, cannot drift.
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
  (list (pair "if"    %eval-if)
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

; --- Function definitions ----------------------------------------------------
;
;   name() { body; }
;
; A definition is the one command shape that cannot be recognised from its
; FIRST token: `name` is an ordinary word, and only the `()` after it says what
; this is.  So %eval-command looks three tokens ahead, before the
; compound-vs-simple split -- a reserved word is excluded, because `if()` is
; not a function definition, it is a syntax error somewhere else.
;
; The body is stored as TOKENS, not text.  They have already been through the
; tokenizer once and re-tokenizing on every call would be both slower and a
; second chance to disagree with the first parse.
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
              (if (not (%tok-is-keyword? a))
                ()
                (if (%reserved-word? (%tok-word-val a))
                  ()
                  (if (%tok-is-op? b "(")
                    (%tok-is-op? c ")")
                    ()))))))))))

(def %collect-fn-body
  (fn (self cur depth toks)
    (if (%cursor-empty? cur)
      (error "parse error: unexpected EOF in function body")
      (let ((tok (%cursor-peek cur)))
        (%cursor-advance! cur)
        (if (%tok-is-keyword? tok)
          (let ((w (%tok-word-val tok)))
            (if (string=? w "{")
              (self cur (+ depth 1) (pair tok toks))
              (if (string=? w "}")
                (if (= depth 0)
                  (reverse toks)
                  (self cur (- depth 1) (pair tok toks)))
                (self cur depth (pair tok toks)))))
          (self cur depth (pair tok toks)))))))

(def %eval-fn-def
  (fn (_ cur)
    (let ((name (%tok-word-val (%cursor-peek cur))))
      (%cursor-advance! cur)
      ; consume name

      (%cursor-advance! cur)
      ; consume (

      (%cursor-advance! cur)
      ; consume )

      (%skip-newlines cur)
      (if (%cursor-empty? cur)
        (error (string-append "parse error: no body for function " name))
        (let ((tok (%cursor-peek cur)))
          (if (not (if (%tok-is-keyword? tok)
                     (string=? (%tok-word-val tok) "{")
                     ()))
            (error (string-append "parse error: expected { after " name "()"))
            (do
              (%cursor-advance! cur)
              ; consume {

              (%skip-newlines cur)
              (let ((body (%collect-fn-body cur 0 ())))
                ; A redefinition SHADOWS rather than replaces -- the lookup
                ; walks from the front, so the newest wins and the list stays
                ; append-free.
                (set! %sh-functions (pair (pair name body) %sh-functions))
                (set! %sh-status 0)
                0))))))))

(def %sh-fn-lookup
  (fn (self name fns)
    (if (null? fns)
      ()
      (if (string=? (first (first fns)) name)
        (rest (first fns))
        (self name (rest fns))))))

; `return` unwinds to the call site, which needs a non-local exit -- so it
; raises a sentinel symbol and %sh-call-fn catches exactly that one, the shape
; lib/x/type/err.x documents ("re-raise what we don't handle").  atom? guards
; the symbol->str: reading a structured Err's memory as a symbol name is how
; the REPL used to print garbage bytes.
(def %sh-return?
  (fn (_ e) (if (atom? e) (str=? (symbol->str e) "%sh-return") ())))

(def %sh-call-fn
  (fn (_ body args)
    (let ((saved %sh-args) (saved-depth %sh-compound-depth))
      (set! %sh-args args)
      (set! %sh-fn-depth (+ %sh-fn-depth 1))
      ; A BODY IS A FRESH TOP LEVEL.  %collect-fn-body already took the closing
      ; `}` off, so nothing in these tokens closes anything outside them -- and
      ; a function called from inside an `if` would otherwise inherit that
      ; depth and read a bare `echo done` in its body as a terminator.
      (set! %sh-compound-depth 0)
      (guard (e
          (do
            (set! %sh-args saved)
            (set! %sh-compound-depth saved-depth)
            (set! %sh-fn-depth (- %sh-fn-depth 1))
            (if (%sh-return? e) %sh-return-status (error e))))
        (unless (null? body) (%eval-list (%mk-cursor body)))
        (set! %sh-args saved)
        (set! %sh-compound-depth saved-depth)
        (set! %sh-fn-depth (- %sh-fn-depth 1))
        %sh-status))))

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
              ; `;;` ENDS A COMMAND, and it was missing here.  It is a distinct
              ; token from `;`, so the test above does not catch it, and a
              ; stage therefore swallowed the clause terminator and everything
              ; after it -- which is why a `case` whose FIRST clause matched
              ; ran the remaining clauses' patterns as commands the moment a
              ; newline followed the `;;`.
              (%tok-is-op? tok ";;")
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
      ; `! cmd` inverts the status, so cmd's failure is expected -- and the
      ; left operand of && / || is not the list's final command either.  POSIX
      ; exempts both from -e.
      ; Compound commands (if/while/for) contain internal ';' delimiters

      ; that %collect-stage would incorrectly split on. Handle directly.

      (let ((result
              ; A DEFINITION IS RECOGNISED HERE, beside the compounds, and for
              ; the same reason they are: %collect-stages below cuts the token
              ; run at the first `;` or newline, so a cursor that has been
              ; through it can never see a function BODY.  Hooked into
              ; %eval-command instead, `f() { echo hi; }` reached
              ; %collect-fn-body with only `f ( ) {` in hand and died with
              ; "unexpected EOF in function body".
              (if (%is-fn-def? cur)
                (%eval-fn-def cur)
              (if (%is-compound-start? cur)
                (%eval-compound cur)
                (let ((stages (%collect-stages cur ())))
                  (if (null? (rest stages))
                    (let ((cur (%mk-cursor (first stages))))
                      (%eval-command cur))
                    (%sh-run-pipeline stages)))))))
        (if negate
          (let ((neg-result (if (= result 0) 1 0)))
            (set! %sh-status neg-result)
            neg-result)
          result)))))
; and_or: pipeline (('&&'|'||') pipeline)*

; Skip an operand without running it -- what a short-circuit must do with the
; side it does not take.
;
; RECURSIVE DESCENT DOES NOT SKIP TOKENS BY ITSELF, and the old code's comment
; said it did: "since we use recursive descent, the right side won't be
; evaluated if we just return".  True of the EVALUATION and false of the
; CURSOR, which was left sitting on the skipped operand -- so %eval-list found
; a command where it expected a separator, gave up, and silently discarded the
; whole rest of the script:
;
;   false && echo no; echo after      printed nothing at all
;   true  || echo no; echo after      printed nothing at all
;
; Pre-existing since 2024, and invisible for as long as nothing followed the
; short-circuit on the same line.
; An operand ends at a list separator OR at the next connective -- skipping
; through `||` swallowed the alternative, so `false && a || b` ran nothing.
; `|` is NOT here: the operand of `&&` is a PIPELINE, so the skip has to cross
; pipes.  Stopping at one left `grep a` behind in `false && echo a | grep a`
; and abandoned the rest of the list all over again.
(def %sh-operand-end-ops (list ";" "&" "&&" "||"))

(def %sh-operand-end?
  (fn (_ tok)
    (and (eq? (first tok) (lit tok-op))
         (%sh-word-in? (first (rest tok)) %sh-operand-end-ops))))

(def %sh-paren-delta
  (fn (_ tok)
    (cond
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
            ; PARENS COUNT TOO, and only here: %sh-nest-delta is the keyword
            ; nesting the compound skippers share, and a subshell's `(` is
            ; punctuation rather than a keyword.  Without it the skip stopped
            ; on the `)` of `false && (echo a)` -- %at-stop-word? treats one as
            ; a terminator -- and abandoned the list again.
            (let ((d (+ depth
                        (+ (%sh-nest-delta tok) (%sh-paren-delta tok)))))
              (self cur (if (< d 0) 0 d)))))))))

; A command in an AND-OR list is exempt from `set -e` unless it is the LAST
; COMMAND RUN -- `false || echo` must not exit, `false && cmd` must not (the
; failure was not the last thing run), and a bare `false` must.  So the check
; is applied only where the loop ends having just EVALUATED an operand, never
; where it ends having skipped one.
(def %eval-and-or-loop ())

(def %eval-and-or
  (fn (_ cur)
    (%eval-and-or-loop cur
      (%sh-in-condition (fn (_) (%eval-pipeline cur))) #t)))

(set! %eval-and-or-loop
  (fn (self cur result evaluated-last?)
    (cond
      ((%cursor-empty? cur)
        (if evaluated-last? (%sh-exit-on-error result) result))
      ((%match-op cur "&&")
        (%skip-newlines cur)
        (if (= result 0)
          (self cur (%sh-in-condition (fn (_) (%eval-pipeline cur))) #t)
          (do (%sh-skip-operand cur 0) (self cur result ()))))
      ((%match-op cur "||")
        (%skip-newlines cur)
        (if (= result 0)
          (do (%sh-skip-operand cur 0) (self cur result ()))
          (self cur (%sh-in-condition (fn (_) (%eval-pipeline cur))) #t)))
      (else (if evaluated-last? (%sh-exit-on-error result) result)))))

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

(def %sh-split-lines
  (fn (_ text)
    (let ((n (string-length text)))
      (def go
        (fn (self i start acc)
          (if (>= i n)
            (reverse (pair (substring text start n) acc))
            (if (= (string-ref text i) #\newline)
              (self (+ i 1) (+ i 1) (pair (substring text start i) acc))
              (self (+ i 1) start acc)))))
      (go 0 0 ()))))

(def %sh-strip-tabs
  (fn (_ line)
    (let ((n (string-length line)))
      (def go
        (fn (self i)
          (if (and (< i n) (= (string-ref line i) #\tab)) (self (+ i 1)) i)))
      (substring line (go 0) n))))

; The delimiter word that follows `<<`, and where it ends.  A quoted one is
; taken literally and marks the body as unexpanded.
(def %sh-hd-delim
  (fn (_ line i n)
    (let ((j (%sh-ar-skip-ws line i n)))
      (if (>= j n)
        (list "" j #t)
        (let ((q (string-ref line j)))
          (if (or (= q #\') (= q #\"))
            (let ((e (%sh-quote-scan line (+ j 1) n q)))
              (list (substring line (+ j 1) e) (+ e 1) ()))
            (let ((e (%sh-word-scan line j n)))
              (list (substring line j e) e #t))))))))

(def %sh-quote-scan
  (fn (self line i n q)
    (if (>= i n) i (if (= (string-ref line i) q) i (self line (+ i 1) n q)))))

(def %sh-word-scan
  (fn (self line i n)
    (if (>= i n)
      i
      (let ((c (string-ref line i)))
        (if (or (%sh-ws-char? c) (or (= c #\;) (or (= c #\<) (= c #\>))))
          i
          (self line (+ i 1) n))))))

; Rewrite one line, collecting the here-documents it opens.  Answers
; (rewritten pending), where pending is a list of (delim strip? expand?) in the
; order the bodies must follow.
(def %sh-hd-scan-line
  (fn (_ line index)
    (let ((n (string-length line)))
      (def go
        (fn (self i mode out pending idx)
          (if (>= i n)
            (list (Str8 join "" (List reverse out)) (reverse pending))
            (let ((c (string-ref line i)))
              (cond
                ; Quoted regions are copied through; `<<` inside them is text.
                ((not (= mode 0))
                  (self (+ i 1) (if (= c mode) 0 mode)
                        (pair (substring line i (+ i 1)) out) pending idx))
                ((or (= c #\') (= c #\"))
                  (self (+ i 1) c (pair (substring line i (+ i 1)) out)
                        pending idx))
                ; `<<` but not `<<<`, and not `<&`
                ((and (= c #\<)
                      (and (< (+ i 1) n) (= (string-ref line (+ i 1)) #\<)))
                  (let ((strip? (and (< (+ i 2) n)
                                     (= (string-ref line (+ i 2)) #\-))))
                    (let ((d (%sh-hd-delim line (if strip? (+ i 3) (+ i 2)) n)))
                      (self (first (rest d)) 0
                        (pair (string-append "<<" (convert idx %string)) out)
                        (pair (list (first d) strip?
                                    (first (rest (rest d)))) pending)
                        (+ idx 1)))))
                (else
                  (self (+ i 1) 0 (pair (substring line i (+ i 1)) out)
                        pending idx)))))))
      (go 0 0 () () index))))

; Take a body off the front of LINES, to the terminator.
(def %sh-hd-take
  (fn (_ lines delim strip?)
    ; `remaining`, not `rest`: a parameter of that name shadows the list
    ; primitive, so the recursive step called a LIST.  Second time in this
    ; bundle -- see %sh-first-op.
    (def go
      (fn (self remaining acc)
        (if (null? remaining)
          ; Unterminated: what is left is the body, which is what a shell does
          ; at end of input.
          (list (Str8 join "" (List reverse acc)) ())
          (let ((line (if strip?
                        (%sh-strip-tabs (first remaining))
                        (first remaining))))
            (if (string=? line delim)
              (list (Str8 join "" (List reverse acc)) (rest remaining))
              (self (rest remaining)
                (pair (string-append line "\n") acc)))))))
    (go lines ())))

(def %sh-hd-collect
  (fn (self lines pending bodies)
    (if (null? pending)
      (list lines bodies)
      (let ((p (first pending)))
        (let ((taken (%sh-hd-take lines (first p) (first (rest p)))))
          (self (first (rest taken)) (rest pending)
            (pair (%sh-heredoc (first taken) (first (rest (rest p))))
                  bodies)))))))

(def %sh-hd-walk
  (fn (self lines out bodies)
    (if (null? lines)
      (list (Str8 join "\n" (List reverse out)) (reverse bodies))
      (let ((scanned (%sh-hd-scan-line (first lines) (length bodies))))
        (let ((collected (%sh-hd-collect (rest lines)
                           (first (rest scanned)) bodies)))
          (self (first collected)
                (pair (first scanned) out)
                (first (rest collected))))))))

; Lift every here-document out of INPUT, leaving `<<N` behind.  Answers the
; rewritten text; the bodies land in %sh-heredocs.
(def %sh-heredoc-extract
  (fn (_ input)
    ; Nothing to do for the overwhelming majority of input, so ask the cheap
    ; question first -- but ask it by SCANNING.  The first version built a list
    ; of every character to hand to List index-of, which allocated a cons per
    ; character of every command the shell ever runs: more than the pass it was
    ; avoiding, and enough to take the spec suite over its allocation ceiling.
    (if (not (%sh-str-has-heredoc-op? input))
      input
      (let ((r (%sh-hd-walk (%sh-split-lines input) () ())))
        (set! %sh-heredocs (first (rest r)))
        (first r)))))

; `<<`, not `<`.  A single `<` is far too common to gate on -- `$((3<5))` has
; one, and every arithmetic comparison was paying for the whole line-splitting
; pass because of it.
(def %sh-str-has-heredoc-op?
  (fn (_ text)
    (let ((n (string-length text)))
      (def go
        (fn (self i)
          (if (>= (+ i 1) n)
            ()
            (if (and (= (string-ref text i) #\<)
                     (= (string-ref text (+ i 1)) #\<))
              #t
              (self (+ i 1))))))
      (go 0))))

; --- Public API ---

; EXTRACTION HAPPENS ONCE, at the top.  A command substitution evaluates a
; FRAGMENT of text whose here-documents the outer pass already lifted -- the
; fragment still carries the `<<N` markers, and running the pass again over it
; would find `N` as a delimiter, consume no body (there is none left), and
; overwrite %sh-heredocs with the result.  `X=$(cat <<EOF ... )` came back
; empty for exactly that.
;
; So the substitution path evaluates already-extracted text.  Reading a FILE
; (`.` / source) is fresh text and goes through the full entry.
(def sh-eval-extracted
  (fn (_ input)
    (let ((tokens (sh-tokenize input)))
      (if (null? tokens)
        0
        (let ((cur (%mk-cursor tokens))) (%eval-list cur))))))

(def sh-eval
  (fn (_ input) (sh-eval-extracted (%sh-heredoc-extract input))))
