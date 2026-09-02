; tokens.x -- Shell token types for ash personality
;
; Each type is registered on a separate base via base-make-type.
; The shell base has its own type-alist, isolating shell token types
; from sexp types (which would conflict: ; is sexp comment vs shell
; separator, # is sexp dispatch vs shell comment, etc.).
;
; Token types: sh-whitespace, sh-newline, sh-comment, sh-operator,
;              sh-sq-string, sh-dq-string, sh-word
;
; Usage:
;   (def tokens (sh-tokenize "echo hello | grep h"))
;   ; -> ((tok-word "echo") (tok-word "hello") (tok-op "|") (tok-word "grep") (tok-word "h"))
; --- Create shell tokenizer base (bare, no sexp types) ---

(def %sh-base (make-token-base))
; --- Intrinsic scoring helpers ---
;
; These wrap the generic integer accessor/mutator primitives for
; the tokenizer protocol. Scripts follow the same protocol as
; C-level analysers: consume chars, un-read delimiter, set score
; and reader on p_score, return p_score.
;
; Buffer layout: (val . (read . write)) — all char pointers.
; Score layout:  (int-score . reader) — raw int + object pointer.

; THE PLATFORM OWNS THESE NOW.  The 2024 file reimplemented buffer-len,
; buffer-unread and score-set over the raw int-cell accessors, with a comment
; describing the buffer layout it assumed: "(val . (read . write)) -- all char
; pointers".  That layout is unchanged, and lib/x/reader/intrinsics.x
; implements exactly the same three functions against it -- so the
; reimplementation is now a second copy of a contract someone else maintains.
;
; Aliasing the platform's is not just tidier: these run per character inside a
; tokenizer callback, where the platform's versions are the ones the engine's
; own reader is tested against.
(def buffer-len %buffer-len)
(def buffer-unread %buffer-unread)
(def score-set %score-set)

; --- Helpers ---
; Predicate: is chr a shell whitespace (space or tab, NOT newline)?

(def %sh-ws?
  (fn (_ c)
    (or
      (= c (char->integer #\space))
      (= c (char->integer #\tab)))))
; Predicate: is chr a shell operator start character?
; | & ; < > ( )

(def %sh-op-start?
  (fn (_ c)
    (or
      (= c (char->integer #\|))
      (= c (char->integer #\&))
      (= c (char->integer #\;))
      (= c (char->integer #\<))
      (= c (char->integer #\>))
      (= c (char->integer #\())
      (= c (char->integer #\))))))
; Predicate: is chr a word-break character?
; whitespace, newline, operator-start, single-quote, double-quote, #

(def %sh-word-break?
  (fn (_ c)
    (or
      (%sh-ws? c)
      (= c (char->integer #\newline))
      (%sh-op-start? c)
      (= c (char->integer #\'))
      (= c (char->integer #\"))
      (= c (char->integer #\#)))))
; --- Token constructors ---

(def mk-tok-newline (fn (_) (list (lit tok-newline))))

(def mk-tok-op (fn (_ s) (list (lit tok-op) s)))

(def mk-tok-word (fn (_ s) (list (lit tok-word) s)))

(def mk-tok-sq (fn (_ s) (list (lit tok-sq) s)))

(def mk-tok-dq (fn (_ s) (list (lit tok-dq) s)))
; --- Shared reader: extract consumed text as word token ---

(def %sh-word-reader
  (fn (_ . args) (mk-tok-word (buffer-token (first args)))))
; --- sh-whitespace: spaces/tabs (discarded, negative/greedy) ---

(def %sh-ws-continue ())

(set! %sh-ws-continue
  (fn (_ buffer score chr)
    (if (%sh-ws? chr)
      %sh-ws-continue
      (do
        (buffer-unread buffer)
        (score-set score (- 0 1) buffer)))))

(base-make-type
  %sh-base
  "SH-WS"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (%sh-ws? chr)
          (do (score-set score (- 0 1) buffer) %sh-ws-continue)
          ())))))
; --- sh-newline: \n as a token (positive/deterministic) ---

(def %sh-nl-read (fn (_ . args) (mk-tok-newline)))

(base-make-type
  %sh-base
  "SH-NL"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr (char->integer #\newline))
          (score-set score 1 buffer)
          ())))
    (pair (lit read) %sh-nl-read)))
; --- sh-comment: # to end of line (discarded, negative/greedy) ---

(def %sh-comment-body ())

(set! %sh-comment-body
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\newline))
      (do
        (buffer-unread buffer)
        (score-set score (- 0 1) buffer))
      %sh-comment-body)))

(base-make-type
  %sh-base
  "SH-COMMENT"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr (char->integer #\#))
          (do (score-set score (- 0 1) buffer) %sh-comment-body)
          ())))))
; --- sh-operator: single and multi-character operators (positive) ---
;
; Single: | & ; < > ( )
; Double: || && ;; << >> <& >& <> >|
; Triple: <<-
;
; Uses buffer-token to extract the operator string.

(def %sh-op-reader
  (fn (_ . args) (mk-tok-op (buffer-token (first args)))))
; Check for triple operator <<-

(def %sh-op-triple
  (fn (_ c1 c2)
    (fn (_ buffer score chr)
      (if (and
            (= c1 (char->integer #\<))
            (= c2 (char->integer #\<))
            (= chr (char->integer #\-)))
        (score-set score 1 buffer)
        (do (buffer-unread buffer) (score-set score 1 buffer))))))
; Check for double operators

(def %sh-op-double
  (fn (_ c1)
    (fn (_ buffer score chr)
      (match
        ; Same char doubled: ||, &&, ;;, <<, >>

        ((= chr c1)
          (if (or (= c1 (char->integer #\<)) (= c1 (char->integer #\>)))
            ; < or > can extend to triple

            (do
              (score-set score 1 buffer)
              (%sh-op-triple c1 (+ chr 0)))
            (score-set score 1 buffer)))
        ; <& or >&

        ((and
           (or (= c1 (char->integer #\<)) (= c1 (char->integer #\>)))
           (= chr (char->integer #\&)))
          (score-set score 1 buffer))
        ; <> (c1 = <, chr = >)

        ((and
           (= c1 (char->integer #\<))
           (= chr (char->integer #\>)))
          (score-set score 1 buffer))
        ; >| (c1 = >, chr = |)

        ((and
           (= c1 (char->integer #\>))
           (= chr (char->integer #\|)))
          (score-set score 1 buffer))
        ; Not a double — un-read, score the single

        (#t (do (buffer-unread buffer) (score-set score 1 buffer)))))))

(base-make-type
  %sh-base
  "SH-OP"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (%sh-op-start? chr)
          ; ( and ) are always single-char

          (if (or
                (= chr (char->integer #\())
                (= chr (char->integer #\))))
            (score-set score 1 buffer)
            (do (score-set score 1 buffer) (%sh-op-double (+ chr 0))))
          ())))
    (pair (lit read) %sh-op-reader)))
; --- sh-sq-string: single-quoted strings (positive) ---
;
; Everything between ' and ' is literal (no escapes).
; Accumulates chars into a list; score is computed from bufferlen.

; THE ACCUMULATOR NEVER SURVIVED, AND THE GLOBAL WAS NOT THE REASON.  Both
; quoted-string readers used to build the value character by character in the
; analyse callback -- a list of chars threaded through a closure per character
; -- and hand it to the read handler through a module-level global.  '' worked
; and 'a' answered (tok-sq ()), which reads like a global that does not
; survive and is not: the closure threading is correct, and the empty case
; only worked because prims' list->string short-circuits (null? l) to "" and
; never reaches the conversion.
;
; The conversion is what fails.  list->string is (%cvt l %string), and %cvt
; inside a reader callback ANSWERS NIL -- silently, with no error -- which is
; the x-python finding too ("%cvt is nil inside read handlers; build code-point
; strings at load").  Every non-empty string was therefore nil, and the two
; entries in tests/contract/known-failures.txt were one line of allocation in
; the wrong place.
;
; So don't accumulate.  BUFFER-TOKEN IS THE PLATFORM'S ANSWER to "what text did
; this token consume", it is what %sh-word-reader has always used, and it runs
; in the READ handler where allocating is safe.  The analyse pass now only
; scans for the closing quote and scores; the read pass takes the consumed run
; and strips the quotes off it.  No global, no per-character cons, and the
; unusual thing about this tokenizer stays unusual for the right reason.

; The consumed run is 'text' -- quotes included, since neither reader un-reads
; the closing quote.  Drop one from each end.
(def %sh-unquote
  (fn (_ s)
    (let ((n (string-length s)))
      (if (< n 2) "" (substring s 1 (- n 1))))))

; A QUOTED WORD THAT DOES NOT END AT ITS CLOSING QUOTE IS STILL ONE WORD.
; `"$HOME"/bin` and `'a'"$b"` are single arguments, and scoring at the closing
; quote made them two and three -- the mirror of the mid-word case handled in
; %sh-word-body below, from the other side.  So the closing quote hands over to
; %sh-qword-body, which ends the token only at a real word break.
;
; The READ handler then decides what kind of token this was: a run that is
; nothing but one quoted string keeps its tok-sq / tok-dq identity (which is
; the bundle's token vocabulary, and what the specs assert), and anything
; MIXED comes back as a tok-word carrying its raw text for %sh-expand-str to
; interpret.  %sh-pure-quote? is what tells them apart.
(def %sh-sq-read
  (fn (_ . args)
    (let ((text (buffer-token (first args))))
      (if (%sh-pure-quote? text)
        (mk-tok-sq (%sh-unquote text))
        (mk-tok-word text)))))

(def %sh-sq-body ())

(set! %sh-sq-body
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\'))
      ; RETURNED, not called: the protocol applies a returned continuation to
      ; the NEXT character.  Calling it with the closing quote made
      ; %sh-qword-body read that quote as OPENING a fresh region, so the token
      ; ran on past the end of the line and swallowed the next command.
      (do
        ; SCORED HERE AND STILL CONTINUING.  The score marks a valid token end
        ; so that input ENDING at the closing quote produces a token at all --
        ; without it `'a'` scored nothing and vanished.  If the word does carry
        ; on, %sh-qword-body scores again at the real break and that later
        ; score wins; this one is the floor, exactly as SH-WORD's analyse entry
        ; scores -1 before its body has seen anything.
        (score-set score 1 buffer)
        %sh-qword-body)
      %sh-sq-body)))

(base-make-type
  %sh-base
  "SH-SQ"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr (char->integer #\')) %sh-sq-body ())))
    (pair (lit read) %sh-sq-read)))
; --- sh-dq-string: double-quoted strings (positive) ---
;
; Phase 1: treat $expansions as literal text (no expansion).
; Handles backslash escapes for: $ ` " \ newline

; Same rewrite as SH-SQ above, and the same reason -- see the note there.  The
; extra work here is the ESCAPES, and they move with the value: analyse only
; needs to know that a backslash makes the next character non-terminating (so
; "a\"b" does not end at the middle quote), and the actual unescaping happens
; in the read handler, where string allocation is safe.

(def %sh-dq-body ())
(def %sh-dq-skip ())

; One character consumed literally, whatever it is -- the analyse pass is only
; locating the closing quote, not interpreting.
(set! %sh-dq-skip (fn (_ buffer score chr) %sh-dq-body))

(set! %sh-dq-body
  (fn (_ buffer score chr)
    (match
      ; Closing quote -- but the WORD may continue; see %sh-sq-read above.

      ; Closing quote: hand over to the word continuation for the NEXT
      ; character -- never call it with this one (see %sh-sq-body).
      ((= chr (char->integer #\")) (do
        ; SCORED HERE AND STILL CONTINUING.  The score marks a valid token end
        ; so that input ENDING at the closing quote produces a token at all --
        ; without it `'a'` scored nothing and vanished.  If the word does carry
        ; on, %sh-qword-body scores again at the real break and that later
        ; score wins; this one is the floor, exactly as SH-WORD's analyse entry
        ; scores -1 before its body has seen anything.
        (score-set score 1 buffer)
        %sh-qword-body))
      ; Backslash: the next character cannot close the string

      ((= chr (char->integer #\\)) %sh-dq-skip)
      ; Regular character (including $, `, etc. -- literal in Phase 1)

      (#t %sh-dq-body))))

; THE ESCAPES ARE NOT UNDONE HERE, and that is a layering decision the first
; version got wrong.  Unescaping in the reader made `"esc \$X"` print the value
; of X: `\$` became a bare `$`, and the expander -- which runs later and cannot
; tell an escaped dollar from a real one -- then expanded it.  A backslash is
; how the user says "not that", so the mark has to survive until the pass that
; would otherwise act on it.
;
; So the token carries the RAW inner text, backslashes and all, and
; %sh-expand-str in eval.x handles escaping and expansion in ONE left-to-right
; pass -- which is the only way to get `"\$X"` and `"$X"` both right.

(def %sh-dq-read
  (fn (_ . args)
    (let ((text (buffer-token (first args))))
      (if (%sh-pure-quote? text)
        (mk-tok-dq (%sh-unquote text))
        (mk-tok-word text)))))

(base-make-type
  %sh-base
  "SH-DQ"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr (char->integer #\")) %sh-dq-body ())))
    (pair (lit read) %sh-dq-read)))
; --- sh-word: unquoted words (catch-all, negative/greedy) ---
;
; Accumulates characters until a word-break character.
; Uses negative score so other types take priority.
; Uses buffer-token to extract the word text.

(def %sh-word-body ())
(def %sh-qword-body ())
(def %sh-word-in-sq ())
(def %sh-word-in-dq ())
(def %sh-word-dq-esc ())

; A WORD ABSORBS QUOTES THAT START INSIDE IT, which is what makes
;
;   X="a b"            one word, not `X=` followed by the string `a b`
;   pre"mid"post       one word
;   "$HOME"/bin        one word (from the other direction -- see %sh-sq-read)
;
; `'` and `"` are word-BREAK characters, so a run used to end at the quote:
; %process-assignments then set X to the empty string and tried to run `a b` as
; a command.  Every quoted assignment in every script did this.
;
; A word that BEGINS with a quote is still SH-SQ's or SH-DQ's -- the analyse
; entry below refuses a leading quote -- so `echo 'hi'` tokenizes as it always
; has.  What changes is only a quote met MID-word, where POSIX says the
; quoting applies to a REGION of the word rather than to the word.  The token
; keeps its raw text, quotes included, and %sh-expand-str in eval.x interprets
; the regions -- the same division of labour as the backslash.
;
; THE QUOTE REGIONS RETURN TO %sh-qword-body, the positive-scoring twin, and
; that is deliberate: a run that has passed through an explicit quote is not a
; bare word any more, and should not carry SH-WORD's "let other types win"
; -1.  A plain word never enters these states and keeps its -1 exactly.
(set! %sh-word-in-sq
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\'))
      (do
        ; SCORED HERE AND STILL CONTINUING.  The score marks a valid token end
        ; so that input ENDING at the closing quote produces a token at all --
        ; without it `'a'` scored nothing and vanished.  If the word does carry
        ; on, %sh-qword-body scores again at the real break and that later
        ; score wins; this one is the floor, exactly as SH-WORD's analyse entry
        ; scores -1 before its body has seen anything.
        (score-set score 1 buffer)
        %sh-qword-body)
      %sh-word-in-sq)))

; One character consumed unconditionally, so `\"` cannot close the region.
(set! %sh-word-dq-esc (fn (_ buffer score chr) %sh-word-in-dq))

(set! %sh-word-in-dq
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\")) (do
        ; SCORED HERE AND STILL CONTINUING.  The score marks a valid token end
        ; so that input ENDING at the closing quote produces a token at all --
        ; without it `'a'` scored nothing and vanished.  If the word does carry
        ; on, %sh-qword-body scores again at the real break and that later
        ; score wins; this one is the floor, exactly as SH-WORD's analyse entry
        ; scores -1 before its body has seen anything.
        (score-set score 1 buffer)
        %sh-qword-body))
      ((= chr (char->integer #\\)) %sh-word-dq-esc)
      (#t %sh-word-in-dq))))

(set! %sh-qword-body
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\')) %sh-word-in-sq)
      ((= chr (char->integer #\")) %sh-word-in-dq)
      ((%sh-word-break? chr)
        (do (buffer-unread buffer) (score-set score 1 buffer)))
      (#t %sh-qword-body))))

(set! %sh-word-body
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\')) %sh-word-in-sq)
      ((= chr (char->integer #\")) %sh-word-in-dq)
      ((%sh-word-break? chr)
        (do
          (buffer-unread buffer)
          (score-set score (- 0 1) buffer)))
      (#t %sh-word-body))))

; --- Was this consumed run nothing but ONE quoted string? -------------------
;
; The question the two quoted READ handlers ask.  `'a'` and `"a b"` keep their
; tok-sq / tok-dq identity -- the bundle's token vocabulary, and what the specs
; assert -- while `'a'"$b"` and `"$HOME"/bin` come back as tok-word carrying
; raw text, because their quoting is per-region and only the expander can
; resolve it.  The test is simply whether the opening quote's partner is the
; last character.
(def %sh-quote-close
  (fn (self text q i n)
    (if (>= i n)
      (- 0 1)
      (let ((c (char->integer (string-ref text i))))
        ; Inside "..." a backslash protects the next character, including a
        ; quote -- so "a\"b" is not closed at the middle one.
        (if (and (= q (char->integer #\")) (= c (char->integer #\\)))
          (self text q (+ i 2) n)
          (if (= c q) i (self text q (+ i 1) n)))))))

(def %sh-pure-quote?
  (fn (_ text)
    (let ((n (string-length text)))
      (if (< n 2)
        ()
        (let ((q (char->integer (string-ref text 0))))
          (= (%sh-quote-close text q 1 n) (- n 1)))))))

(base-make-type
  %sh-base
  "SH-WORD"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (not (%sh-word-break? chr))
          (do (score-set score (- 0 1) buffer) %sh-word-body)
          ())))
    (pair (lit read) %sh-word-reader)))
; --- INTEGER: pre-register with shell-compatible reader (positive) ---
;
; Arithmetic in analyse hooks auto-registers the INTEGER type on the
; token base. Pre-registering with a digit-matching state machine that
; produces tok-word tokens ensures digit sequences appear as shell words.
; For digit-starting mixed words (10abc), returns () to let SH-WORD handle.

(def %sh-digit?
  (fn (_ c)
    (and (>= c (char->integer #\0)) (<= c (char->integer #\9)))))

(def %sh-int-body ())
(def %sh-int-word-body ())

; A DIGIT RUN THAT TURNS INTO A WORD IS A WORD, and giving up here was a
; SEGFAULT rather than a fallback.  The `(#t ())` this replaces meant "this
; type no longer matches", and on an isolated base carrying the engine's own
; INTEGER type that hands the run to the built-in reader -- which produces a
; RAW INTEGER, not a token list.  So
;
;   echo 50$        ->  ((tok-word "echo") 50 (tok-word "$"))
;
; and %tok-is-word? then called `first` on the integer 50 and the shell died
; with no message.  Any word starting with digits and continuing with a
; non-digit, non-break character did it: `50$`, `2x`, `3rd`.  Verified on the
; pre-change tree, so the crash is older than the file it is fixed in.
;
; The fix is to keep scanning as a word, which is what the run IS.  Scoring
; stays +1 so this type still beats SH-WORD's -1 and the read handler is the
; shared %sh-word-reader either way -- so the token comes out (tok-word "50$").
(set! %sh-int-word-body %sh-qword-body)

(set! %sh-int-body
  (fn (_ buffer score chr)
    (match
      ((%sh-digit? chr) %sh-int-body)
      ((%sh-word-break? chr)
        (do (buffer-unread buffer) (score-set score 1 buffer)))
      ; Not a digit and not a break: the run is a word from here on.  The
      ; character is consumed by returning the continuation, exactly as
      ; %sh-word-body does.
      (#t %sh-int-word-body))))

(base-make-type
  %sh-base
  "INTEGER"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (%sh-digit? chr)
          (do (score-set score 1 buffer) %sh-int-body)
          ())))
    (pair (lit read) %sh-word-reader)))
; --- Convenience: tokenize a string ---

; A SAFETY NET UNDER THE PARSER, because a token that is not a list is a
; segfault and not an error: every predicate in eval.x opens with (first tok).
; The INTEGER fallback above was one way to produce one; rather than trust that
; it was the only way, anything that comes back not-a-pair is rendered as the
; word it stands for.  Costs one walk of a token list; buys the guarantee that
; the parser only ever sees tokens.
(def %sh-normalize-tokens
  (fn (self toks)
    (if (null? toks)
      ()
      (pair
        (let ((tok (first toks)))
          (if (pair? tok) tok (mk-tok-word (convert tok %string))))
        (self (rest toks))))))

(def sh-tokenize
  (fn (_ input) (%sh-normalize-tokens (token-read-string %sh-base input))))
