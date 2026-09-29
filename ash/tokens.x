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
; The compiled base of the shell's tokens is made by the assembler lane's
; compiler, reached as x/tool/compile's own door reaches it: the cache module
; imported where it is first needed, and its function taken from the
; catalogue.  The name compile-asm is bound by no import in the dialect this
; bundle boots.
(def %sh-compile-asm
  (fn (_ form fvars)
    (import x/tool/asm-cache)
    ((prim-ref (lit compile) (lit asm-cached)) form fvars #t)))

; --- Create shell tokenizer base (bare, no sexp types) ---

; The tokenizer base is process state: (Base make-tok) puts it on a chain of
; its own that the ambient heap cannot name, so a state image cannot carry it
; and it is remade after an image load. Each type records itself in this table
; as its handlers are defined, and %sh-base-make builds a base from the table
; -- read when this file loads and again after an image load.
(def %sh-tok-types (pair () ()))    ; ((name . handlers) ...), newest first
(def %sh-tok-type!
  (fn (_ nm hs)
    (%set-first! %sh-tok-types (pair (pair nm hs) (first %sh-tok-types)))))
(def %sh-base-make
  (fn (_)
    (let ((b (make-token-base)))
      ((fn (self l)
         (if (null? l) ()
           (do (self (rest l))
               (base-make-type b (first (first l)) (rest (first l))))))
       (first %sh-tok-types))
      b)))
(def %sh-base ())
; --- Intrinsic scoring helpers ---
;
; These wrap the generic integer accessor/mutator primitives for
; the tokenizer protocol. Scripts follow the same protocol as
; C-level analysers: consume chars, un-read delimiter, set score
; and reader on p_score, return p_score.
;
; Buffer layout: (val . (read . write)) — all char pointers.
; Score layout:  (int-score . reader) — raw int + object pointer.

; The platform owns buffer-len, buffer-unread and score-set:
; lib/x/reader/intrinsics.x implements them against the same buffer layout
; ((val . (read . write)), all char pointers), so these are aliases rather than
; a second copy. They run per character inside a tokenizer callback, where the
; platform's versions are the ones the engine's own reader is tested against.
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
      (= c (char->integer #\")))))

; `#` is not in the word-break set, and deliberately: a shell starts a comment
; at `#` only where a word could start, which the SH-COMMENT type below already
; expresses (its analyse hook runs only at a token boundary). So `echo a#b`
; keeps the `#`, and `echo # note` still comments -- the space ends the word
; and `#` opens a fresh token.
; --- Token constructors ---

(def mk-tok-newline (fn (_) (list (lit tok-newline))))

(def mk-tok-op (fn (_ s) (list (lit tok-op) s)))

(def mk-tok-word (fn (_ s) (list (lit tok-word) s)))

(def mk-tok-sq (fn (_ s) (list (lit tok-sq) s)))

(def mk-tok-dq (fn (_ s) (list (lit tok-dq) s)))

(def mk-tok-io (fn (_ s) (list (lit tok-io) s)))
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

(%sh-tok-type!
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

(%sh-tok-type!
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

(%sh-tok-type!
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

(%sh-tok-type!
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

; Both quoted-string readers take their value from buffer-token in the read
; handler, not by accumulating characters in the analyse callback. list->string
; is (%cvt l %ash-string-type), and %cvt inside a reader callback answers nil
; silently (the same finding as x-python: build strings at load, not in a read
; handler), so an accumulated value was nil for every non-empty string.
; buffer-token is the platform's answer to "what text did this token
; consume", runs in the read handler where allocating is safe, and is what
; %sh-word-reader has always used. The analyse pass scans for the closing quote
; and scores; the read pass takes the consumed run and strips the quotes.

; The consumed run is 'text' -- quotes included, since neither reader un-reads
; the closing quote.  Drop one from each end.
(def %sh-unquote (fn (_ s) (%sh-unquote-of s (string-length s))))

(def %sh-unquote-of
  (fn (_ s n) (match ((fx<? n 2) "") (#t (substring s 1 (fx+ n -1))))))

; A quoted word that does not end at its closing quote is still one word:
; `"$HOME"/bin` and `'a'"$b"` are single arguments. So the closing quote hands
; over to %sh-qword-body, which ends the token only at a real word break.
;
; The read handler then decides the token's kind: a run that is nothing but one
; quoted string keeps its tok-sq / tok-dq identity (the token vocabulary the
; specs assert), and anything mixed comes back as a tok-word carrying its raw
; text for %sh-expand-str to interpret. %sh-pure-quote? tells them apart.
;
; The analyser says which, as the label of its score: %sh-label-quote where
; the opening quote's partner closes the token, %sh-label-word at every end
; the token finds after that, and %sh-label-ask where a double-quoted string
; that held a substitution or a `${...}` closes: a `"` inside one of those is
; the first the text holds, and the reader asks the text (%sh-pure-quote?),
; as it does on a platform whose score carries no label.
(def %sh-label-quote 1)
(def %sh-label-word 2)
(def %sh-label-ask 3)

(def %sh-sq-read (fn (_ . args) (%sh-quoted-read args mk-tok-sq)))

(def %sh-quoted-read
  (fn (_ args mk) (%sh-quoted-tok (buffer-token (first args)) (%read-label args) mk)))

(def %sh-quoted-tok
  (fn (_ text label mk)
    (match
      ((null? label) (%sh-quoted-asked text (%sh-pure-quote? text) mk))
      ((= label %sh-label-ask) (%sh-quoted-asked text (%sh-pure-quote? text) mk))
      ((= label %sh-label-quote) (mk (%sh-unquote text)))
      (#t (mk-tok-word text)))))

(def %sh-quoted-asked
  (fn (_ text pure? mk)
    (match (pure? (mk (%sh-unquote text))) (#t (mk-tok-word text)))))

; The character after a quoted string's closing quote: a break ends the
; token, a quoted string; any other character makes the token a word, which
; the label says at once, as the text may end before the word finds an end,
; and %sh-qword-body reads the character.  A quote is a break, and a word's
; character first.
(def %sh-quote-after
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\')) (%sh-quote-word buffer score chr))
      ((= chr (char->integer #\")) (%sh-quote-word buffer score chr))
      ((%sh-word-break? chr)
        (do (buffer-unread buffer) (score-set score 1 buffer)))
      (#t (%sh-quote-word buffer score chr)))))

(def %sh-quote-word
  (fn (_ buffer score chr)
    (%score-label! score %sh-label-word)
    (%sh-qword-body buffer score chr)))

(def %sh-sq-body ())

(set! %sh-sq-body
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\'))
      ; RETURNED, not called: the protocol applies a returned continuation to
      ; the NEXT character.  Calling it with the closing quote made
      ; %sh-qword-body read that quote as OPENING a fresh region, so the token
      ; ran on past the end of the line and swallowed the next command.
      (do
        ; Score here even though the word may continue, so input ending at the
        ; closing quote still produces a token. If it continues, %sh-qword-body
        ; scores again at the real break and that later score wins; this is the
        ; floor, like SH-WORD's -1 analyse entry.
        (%score-label! score %sh-label-quote)
        (score-set score 1 buffer)
        %sh-quote-after)
      %sh-sq-body)))

(%sh-tok-type!
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
      ; $( inside a double-quoted word: a substitution, whose own quotes and
      ; parens must not be read as this string's.

      ((= chr (char->integer #\$)) %sh-sq-dq-dollar)
      ((= chr #\`) (do (set! %sh-cs-return 2) %sh-bt-scan))
      ; Closing quote -- but the WORD may continue; see %sh-sq-read above.

      ; Closing quote: hand over to the word continuation for the NEXT
      ; character -- never call it with this one (see %sh-sq-body).
      ((= chr (char->integer #\")) (do
        ; Score here even though the word may continue, so input ending at the
        ; closing quote still produces a token. If it continues, %sh-qword-body
        ; scores again at the real break and that later score wins; this is the
        ; floor, like SH-WORD's -1 analyse entry.
        (%score-label! score %sh-label-quote)
        (score-set score 1 buffer)
        %sh-quote-after))
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

; %sh-dq-body after a substitution or a `${...}` in the string: the same
; states, which close the string with %sh-label-ask.
(def %sh-dq-rest ())

(def %sh-dq-rest-skip (fn (_ buffer score chr) %sh-dq-rest))

(def %sh-dq-rest-dollar
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\())
        (do (set! %sh-cs-depth 0) (set! %sh-cs-return 2) %sh-cs-body))
      ((= chr (char->integer #\{))
        (do (set! %sh-pe-depth 0) (set! %sh-pe-return 2) %sh-pe-body))
      (#t (%sh-dq-rest buffer score chr)))))

(set! %sh-dq-rest
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\$)) %sh-dq-rest-dollar)
      ((= chr #\`) (do (set! %sh-cs-return 2) %sh-bt-scan))
      ((= chr (char->integer #\"))
        (do
          (%score-label! score %sh-label-ask)
          (score-set score 1 buffer)
          %sh-quote-after))
      ((= chr (char->integer #\\)) %sh-dq-rest-skip)
      (#t %sh-dq-rest))))

(def %sh-dq-read (fn (_ . args) (%sh-quoted-read args mk-tok-dq)))

(%sh-tok-type!
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

; --- Command substitution: $( ... ) ------------------------------------------
;
; `$(` OPENS A REGION THAT `)` DOES NOT CLOSE A WORD IN.  `)` is an operator
; character, so without this `echo $(pwd)` tokenized as five tokens -- `echo`,
; the word `$`, the op `(`, `pwd`, the op `)` -- and the substitution was not
; expressible at all.  The whole run is one word now, raw text included, and
; %sh-expand-str runs it.
;
; THE DEPTH AND THE RETURN CONTEXT RIDE IN MODULE GLOBALS, not in closures.
; The analyse protocol's continuations take no parameters, so a nesting counter
; has nowhere else to live -- and allocating a closure per character inside a
; reader callback is the hazard this file's own notes warn about twice.  A
; `set!` of a small integer allocates nothing, and the same globals cannot
; collide across tokens: the scan is strictly sequential and %sh-cs-depth is
; re-initialised at every `$(`.
;
; The return context is where the word was when the substitution opened, so
; that `"a $(echo b) c"` stays inside its double quotes afterwards rather than
; ending at the space.
(def %sh-cs-depth 0)
(def %sh-cs-return 0)          ; 0 = bare word, 1 = "..." within a word, 2 = SH-DQ
(def %sh-cs-body ())
(def %sh-cs-sq ())
(def %sh-cs-dq ())
(def %sh-cs-dq-esc ())
(def %sh-cs-esc ())

; Quotes INSIDE the substitution hide parens from the depth count, so
; `$(echo ")")` closes where it should, and so does a backslash outside them:
; `$(echo \))`.
(set! %sh-cs-sq
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\')) %sh-cs-body %sh-cs-sq)))

(set! %sh-cs-dq-esc (fn (_ buffer score chr) %sh-cs-dq))
(set! %sh-cs-esc (fn (_ buffer score chr) %sh-cs-body))

(set! %sh-cs-dq
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\")) %sh-cs-body)
      ((= chr (char->integer #\\)) %sh-cs-dq-esc)
      (#t %sh-cs-dq))))

(set! %sh-cs-body
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\())
        (do (set! %sh-cs-depth (+ %sh-cs-depth 1)) %sh-cs-body))
      ((= chr (char->integer #\)))
        (if (= %sh-cs-depth 0)
          ; Closed.  Back to whatever the word was doing.
          (match
            ((= %sh-cs-return 1) %sh-word-in-dq)
            ((= %sh-cs-return 2) %sh-dq-rest)
            (#t %sh-qword-body))
          (do (set! %sh-cs-depth (- %sh-cs-depth 1)) %sh-cs-body)))
      ((= chr (char->integer #\')) %sh-cs-sq)
      ((= chr (char->integer #\")) %sh-cs-dq)
      ((= chr (char->integer #\\)) %sh-cs-esc)
      (#t %sh-cs-body))))

; --- Parameter expansion: ${ ... } ------------------------------------------
;
; `${` opens a region too.  POSIX reads the text from `${` to its matching `}`
; as one unit with quoting of its own, so the `"` in `"${x:-"a b"}"` opens a
; string inside the expansion rather than closing the one around it, and the
; space in `${x:-a b}` is no end of the word.  Without the region both split,
; and neither half's `${` was ever closed.
;
; Braces nest, `${x:-${y:-z}}` and `${x:-{a}}` alike; quotes and a backslash
; hide a brace from the count.  The depth and the return context ride in
; globals for the reason %sh-cs-depth does, and the return codes are the same.
(def %sh-pe-depth 0)
(def %sh-pe-return 0)
(def %sh-pe-body ())
(def %sh-pe-sq ())
(def %sh-pe-dq ())
(def %sh-pe-dq-esc ())
(def %sh-pe-esc ())

(set! %sh-pe-sq
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\')) %sh-pe-body %sh-pe-sq)))

(set! %sh-pe-dq-esc (fn (_ buffer score chr) %sh-pe-dq))
(set! %sh-pe-esc (fn (_ buffer score chr) %sh-pe-body))

(set! %sh-pe-dq
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\")) %sh-pe-body)
      ((= chr (char->integer #\\)) %sh-pe-dq-esc)
      (#t %sh-pe-dq))))

(set! %sh-pe-body
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\{))
        (do (set! %sh-pe-depth (+ %sh-pe-depth 1)) %sh-pe-body))
      ((= chr (char->integer #\}))
        (if (= %sh-pe-depth 0)
          ; Closed.  Back to whatever the word was doing.
          (match
            ((= %sh-pe-return 1) %sh-word-in-dq)
            ((= %sh-pe-return 2) %sh-dq-rest)
            (#t %sh-qword-body))
          (do (set! %sh-pe-depth (- %sh-pe-depth 1)) %sh-pe-body)))
      ((= chr (char->integer #\')) %sh-pe-sq)
      ((= chr (char->integer #\")) %sh-pe-dq)
      ((= chr (char->integer #\\)) %sh-pe-esc)
      (#t %sh-pe-body))))

; The older backtick substitution needs the same treatment as `$(`: a region
; whose spaces do not end the word.  Without it `echo `echo old`` split at the
; space into the two words "`echo" and "old`", and the expander -- which only
; ever sees one word at a time -- could not put them back together.
;
; No nesting to track (backticks do not nest without escaping), so one state
; plus an escape state.  The return context rides in %sh-cs-return, shared with
; the `$(` scanner above; the two can never be in flight at once.
(def %sh-bt-scan ())
(def %sh-bt-esc ())

(set! %sh-bt-esc (fn (_ buffer score chr) %sh-bt-scan))

(set! %sh-bt-scan
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\\)) %sh-bt-esc)
      ((= chr #\`)
        (match
          ((= %sh-cs-return 1) %sh-word-in-dq)
          ((= %sh-cs-return 2) %sh-dq-rest)
          (#t %sh-qword-body)))
      (#t %sh-bt-scan))))

; After a `$`, one character decides: `(` opens a substitution and `{` an
; expansion.  Anything else is re-dispatched through the state we came from --
; a direct call, correct here because we want that character handled
; normally, unlike at a closing quote where the character has already been
; consumed by meaning.
(def %sh-word-dollar ())
(def %sh-dq-dollar ())
(def %sh-sq-dq-dollar ())

(set! %sh-word-dollar
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\())
        (do (set! %sh-cs-depth 0) (set! %sh-cs-return 0) %sh-cs-body))
      ((= chr (char->integer #\{))
        (do (set! %sh-pe-depth 0) (set! %sh-pe-return 0) %sh-pe-body))
      (#t (%sh-qword-body buffer score chr)))))

(set! %sh-dq-dollar
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\())
        (do (set! %sh-cs-depth 0) (set! %sh-cs-return 1) %sh-cs-body))
      ((= chr (char->integer #\{))
        (do (set! %sh-pe-depth 0) (set! %sh-pe-return 1) %sh-pe-body))
      (#t (%sh-word-in-dq buffer score chr)))))

(set! %sh-sq-dq-dollar
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\())
        (do (set! %sh-cs-depth 0) (set! %sh-cs-return 2) %sh-cs-body))
      ((= chr (char->integer #\{))
        (do (set! %sh-pe-depth 0) (set! %sh-pe-return 2) %sh-pe-body))
      (#t (%sh-dq-body buffer score chr)))))

(def %sh-word-body ())
(def %sh-qword-body ())
(def %sh-word-in-sq ())
(def %sh-word-in-dq ())
(def %sh-word-dq-esc ())
(def %sh-word-esc ())
(def %sh-qword-esc ())

; A word absorbs quotes that start inside it:
;
;   X="a b"            one word, not `X=` followed by the string `a b`
;   pre"mid"post       one word
;   "$HOME"/bin        one word (from the other direction -- see %sh-sq-read)
;
; `'` and `"` are word-break characters, so a word that begins with a quote is
; SH-SQ's or SH-DQ's (the analyse entry below refuses a leading quote) and
; `echo 'hi'` tokenizes as always. A quote met mid-word applies to a region of
; the word, per POSIX: the token keeps its raw text, quotes included, and
; %sh-expand-str in eval.x interprets the regions -- the same division of
; labour as the backslash.
;
; The quote regions return to %sh-qword-body, the positive-scoring twin: a run
; that has passed through an explicit quote is not a bare word and should not
; carry SH-WORD's "let other types win" -1. A plain word keeps its -1.
(set! %sh-word-in-sq
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\'))
      (do
        ; Score here even though the word may continue, so input ending at the
        ; closing quote still produces a token. If it continues, %sh-qword-body
        ; scores again at the real break and that later score wins; this is the
        ; floor, like SH-WORD's -1 analyse entry.
        (%score-label! score %sh-label-word)
        (score-set score 1 buffer)
        %sh-qword-body)
      %sh-word-in-sq)))

; One character consumed unconditionally, so `\"` cannot close the region.
(set! %sh-word-dq-esc (fn (_ buffer score chr) %sh-word-in-dq))

; THE SAME, OUTSIDE QUOTES, and it was missing.  A backslash was an ordinary
; character to the bare-word scanner, so the space in `a\ b` was still a word
; BREAK: the input tokenized as `a\` and `b` -- two words, the first ending in
; a backslash that protects nothing.  `echo a\ b` printed two arguments, and
; the expander then hung on that trailing backslash (see %sh-expand-str).
;
; A backslash outside quotes protects ANY character, the word delimiters
; included, which is the whole of what it is for.
(set! %sh-word-esc (fn (_ buffer score chr) %sh-word-body))
(set! %sh-qword-esc (fn (_ buffer score chr) %sh-qword-body))

(set! %sh-word-in-dq
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\$)) %sh-dq-dollar)
      ((= chr #\`) (do (set! %sh-cs-return 1) %sh-bt-scan))
      ((= chr (char->integer #\")) (do
        ; Score here even though the word may continue, so input ending at the
        ; closing quote still produces a token. If it continues, %sh-qword-body
        ; scores again at the real break and that later score wins; this is the
        ; floor, like SH-WORD's -1 analyse entry.
        (%score-label! score %sh-label-word)
        (score-set score 1 buffer)
        %sh-qword-body))
      ((= chr (char->integer #\\)) %sh-word-dq-esc)
      (#t %sh-word-in-dq))))

(set! %sh-qword-body
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\$)) %sh-word-dollar)
      ((= chr #\`) (do (set! %sh-cs-return 0) %sh-bt-scan))
      ((= chr (char->integer #\')) %sh-word-in-sq)
      ((= chr (char->integer #\")) %sh-word-in-dq)
      ((= chr (char->integer #\\)) %sh-qword-esc)
      ((%sh-word-break? chr)
        (do
          (buffer-unread buffer)
          (%score-label! score %sh-label-word)
          (score-set score 1 buffer)))
      (#t %sh-qword-body))))

(set! %sh-word-body
  (fn (_ buffer score chr)
    (match
      ((= chr (char->integer #\$)) %sh-word-dollar)
      ((= chr #\`) (do (set! %sh-cs-return 0) %sh-bt-scan))
      ((= chr (char->integer #\')) %sh-word-in-sq)
      ((= chr (char->integer #\")) %sh-word-in-dq)
      ((= chr (char->integer #\\)) %sh-word-esc)
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

(%sh-tok-type!
  "SH-WORD"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (if (not (%sh-word-break? chr))
          (do
            (score-set score (- 0 1) buffer)
            ; A word may open with the substitution: `echo $(pwd)` puts the
            ; `$` first. Mid-word `$` reaches %sh-word-dollar from the body's
            ; own arm; this is the same door for the first character, and a
            ; backslash likewise protects what follows it here, so `\;` is
            ; the word `;` rather than a backslash and an operator.
            (match
              ((= chr (char->integer #\$)) %sh-word-dollar)
              ((= chr #\`) (do (set! %sh-cs-return 0) %sh-bt-scan))
              ((= chr (char->integer #\\)) %sh-word-esc)
              (#t %sh-word-body)))
          ())))
    (pair (lit read) %sh-word-reader)))
; --- INTEGER: pre-register with shell-compatible reader (positive) ---
;
; Arithmetic in analyse hooks auto-registers the INTEGER type on the
; token base. Pre-registering with a digit-matching state machine that
; produces tok-word tokens ensures digit sequences appear as shell words.
; For digit-starting mixed words (10abc), returns () to let SH-WORD handle.

; A decimal digit -- the one definition; eval.x asks it too.  The analyse
; hooks ask it of every character they are handed, which the reader passes as
; an integer and never as nil, so the unchecked comparison is safe here.
(def %sh-digit?
  (fn (_ c) (match ((fx<? c #\0) ()) ((fx<? #\9 c) ()) (#t #t))))

(def %sh-int-body ())
(def %sh-int-word-body ())

; A digit run that continues with a non-digit is a word: `50$`, `2x`, `3rd`.
; Giving up here would hand the run to the base's built-in INTEGER type, which
; produces a raw integer rather than a token list, and %tok-is-word? would then
; call `first` on an integer. Keep scanning as a word, scoring +1 so this type
; beats SH-WORD's -1; the read handler is the shared %sh-word-reader, so the
; token comes out (tok-word "50$").
(set! %sh-int-word-body %sh-qword-body)

(set! %sh-int-body
  (fn (_ buffer score chr)
    (match
      ((%sh-digit? chr) %sh-int-body)
      ; A run that meets `<` or `>` is a descriptor number: IO-NUMBER's, below.
      ((= chr (char->integer #\<)) ())
      ((= chr (char->integer #\>)) ())
      ((%sh-word-break? chr)
        (do (buffer-unread buffer) (score-set score 1 buffer)))
      ; Not a digit and not a break: the run is a word from here on, and the
      ; word's own scanner reads this character, so a `\`, `$` or backquote
      ; here does what it does anywhere in a word -- `1\;2` is one word.
      (#t (%sh-int-word-body buffer score chr)))))

; A sign opens the same run.  The base's own number reader takes `-0`,
; `+5` and `-007` otherwise, and gives each back as an integer that prints as
; `0`, `5` and `-7` -- so `kill -0 $pid` became `kill 0 $pid`, which signals
; the caller's whole process group.  Claimed here, the run is the word it is
; spelt as; a sign that a digit does not follow (`-a`, `--x`, `-`) is read on
; as a word by the same body, as a digit run that meets a letter is.
(%sh-tok-type!
  "INTEGER"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr)
        (match
          ((%sh-digit? chr) (do (score-set score 1 buffer) %sh-int-body))
          ((= chr (char->integer #\-)) (do (score-set score 1 buffer) %sh-int-body))
          ((= chr (char->integer #\+)) (do (score-set score 1 buffer) %sh-int-body))
          (#t ()))))
    (pair (lit read) %sh-word-reader)))

; --- IO-NUMBER: a descriptor number against a redirection (positive) ---
;
; `2>err` names descriptor 2 because the digits run straight into the
; operator, while `echo 2 >out` writes the word 2 to out, and so does
; `echo "$n" >out` whatever $n holds.  Only here, where the characters are,
; can the two be told apart: a digit run that meets `<` or `>` is a tok-io,
; INTEGER declining it, and any other digit run is INTEGER's.
(def %sh-io-read (fn (_ . args) (mk-tok-io (buffer-token (first args)))))

(def %sh-io-body ())

(set! %sh-io-body
  (fn (_ buffer score chr)
    (match
      ((%sh-digit? chr) %sh-io-body)
      ((= chr (char->integer #\<)) (do (buffer-unread buffer) (score-set score 1 buffer)))
      ((= chr (char->integer #\>)) (do (buffer-unread buffer) (score-set score 1 buffer)))
      (#t ()))))

(%sh-tok-type!
  "IO-NUMBER"
  (list
    (pair
      (lit analyse)
      (fn (_ buffer score chr) (if (%sh-digit? chr) %sh-io-body ())))
    (pair (lit read) %sh-io-read)))
; --- Convenience: tokenize a string ---

; A safety net under the parser: every predicate in eval.x opens with
; (first tok), so a token that is not a list would crash rather than raise.
; The INTEGER fallback above produces one such case; rather than trust it is
; the only one, anything that comes back not-a-pair is rendered as the word it
; stands for. One walk of the token list buys the guarantee that the parser
; only ever sees tokens, and that each word's token is made on this heap
; (%sh-tok-own).
;
; The walk is a loop, onto an accumulator reversed at the end: a script is a
; token list as long as the script, and a call per token nested in the last
; one's `pair` ran out of C stack at about 30,000 tokens.
(def %sh-normalize-tokens
  (fn (_ toks) (reverse (%sh-normalize-onto toks ()))))

(def %sh-normalize-onto
  (fn (self toks acc)
    (if (null? toks)
      acc
      (self (rest toks)
            (pair (let ((tok (first toks)))
                    (if (pair? tok)
                      (%sh-tok-own tok)
                      (mk-tok-word (convert tok %ash-string-type))))
                  acc)))))

; TOK, made again on this heap when it is a word the evaluator keeps a plan in
; (%sh-tok-put in eval.x).  The reader makes its tokens on the tokenizer
; base's chain, and a collect leaves its mark on a cell there, so the next
; collect stops at the cell and frees what hangs from it alone.
(def %sh-tok-own
  (fn (_ tok)
    (match
      ((eq? (first tok) (lit tok-word)) (mk-tok-word (first (rest tok))))
      ((eq? (first tok) (lit tok-dq)) (mk-tok-dq (first (rest tok))))
      (#t tok))))

; The text is read through the compiled base once it is made (%sh-jit-tick!),
; and through the interpreted one until then.
(def sh-tokenize
  (fn (_ input)
    (%sh-jit-tick! (string-length input))
    (%sh-normalize-tokens (%token-read-str %sh-active-raw input))))

; --- The base itself: made here, and made again after an image load --------
; One door, called by the load and by the image's recache hook.  The transient
; nils it in the writer's child so the walk never meets a word it cannot
; place.  The compiled base is this process's alone, so a reset forgets it.
(def %sh-active-raw ())         ; the raw base sh-tokenize reads with
(def %sh-cbase ())              ; roots the compiled base
(def %sh-jit-states ())
; The cells of the compiled states, each (NAME . CELL), and whether the
; states use them.  A cell is (STATE): it roots the state it holds.
(def %sh-jit-cells ())
(def %sh-jit-late? ())
(def %sh-jit (lit off))         ; off | active | failed
(def %sh-jit-bytes 0)
(def %sh-jit-threshold 4096)

(def %sh-base-reset!
  (fn (_)
    (set! %sh-base (%sh-base-make))
    (set! %sh-active-raw (Base raw-of %sh-base))
    (set! %sh-cbase ())
    (set! %sh-jit-states ())
    (set! %sh-jit-cells ())
    (set! %sh-jit (lit off))
    (set! %sh-jit-bytes 0)))
(%sh-base-reset!)
(set! %image-transients
  (pair (lit %sh-base) (pair (lit %sh-active-raw) (pair (lit %sh-cbase)
    (pair (lit %sh-jit-states) (pair (lit %sh-jit-cells) %image-transients))))))
(set! %image-recache-hooks (pair (fn (_) (%sh-base-reset!)) %image-recache-hooks))

; --- The compiled base ---------------------------------------------------------
;
; An interpreted analyser is a call into x for each character of each token,
; and for each type at each token's start.  The states every text goes
; through -- each type's entry, and the states that read a run of whitespace,
; a comment, an operator, a word, a number and a quoted string -- are compiled
; to native code (x/tool/compile's assembler lane) and registered on a second
; base, in the order and under the names of the first, with the read handlers
; of the first: registration is write-once, so a base's analysers cannot be
; changed.
;
; THE INTERPRETED STATES ARE THE CONTRACT, and each compiled state is one of
; them spelled in the lane's vocabulary: characters as integers, a literal
; sign and label, a loop through the state's own name.
;
; STATES THAT HAND TO EACH OTHER GO THROUGH CELLS.  A compiled state is given
; the states it hands to when it is made, so of a word's state and the state
; that reads the character after its backslash, which hand to each other, one
; is compiled before the other exists.  Where the lane lowers `first`, such a
; target is the first of a cell (%sh-jit-cell): the cell holds the
; interpreted state until the compiled one is made, and the compiled one
; from then on.  So the states a `$`, a backslash and a quote inside a word
; lead to are compiled too, and the token is read compiled to its end.
; Where the lane refuses `first`, the target is the interpreted state, whose
; successors are interpreted, and the rest of such a token is read as it
; always was.
;
; A substitution and a `${...}` are read interpreted on either: their states
; count their nesting and keep where they return to, and the lane has no
; form that writes.  A state that sets those before it hands over is
; interpreted for that reason: %sh-bt-to, %sh-cs-to and %sh-pe-to make them.
;
; The attempt comes once %sh-jit-threshold bytes have been read in the
; process, since compiling costs a few hundred milliseconds, which a short
; script would not win back; it is made in the shell's own process only, as a
; child's base ends with the child; and it runs under a guard: a refusal pins
; `failed` and the interpreted base reads on.  The compiled states are rooted
; in %sh-jit-states, since the collector cannot see an address baked into
; code.
(def %sh-bt-to
  (fn (_ back)
    (fn (_ buffer score chr)
      (set! %sh-cs-return back)
      (%sh-bt-scan buffer score chr))))

(def %sh-cs-to
  (fn (_ back)
    (fn (_ buffer score chr)
      (set! %sh-cs-depth 0)
      (set! %sh-cs-return back)
      (%sh-cs-body buffer score chr))))

(def %sh-pe-to
  (fn (_ back)
    (fn (_ buffer score chr)
      (set! %sh-pe-depth 0)
      (set! %sh-pe-return back)
      (%sh-pe-body buffer score chr))))

(def %sh-bt-word (%sh-bt-to 0))
(def %sh-bt-in-dq (%sh-bt-to 1))
(def %sh-bt-dq (%sh-bt-to 2))

; What a `$(` and a `${` open, by where each returns to: a word, a quoted
; region of a word, a quoted string.  Named here, as a compiled state holds
; the address of a state it hands to, which roots nothing.
(def %sh-opens
  (list (list (pair (lit to-cs) (%sh-cs-to 0)) (pair (lit to-pe) (%sh-pe-to 0)))
        (list (pair (lit to-cs) (%sh-cs-to 1)) (pair (lit to-pe) (%sh-pe-to 1)))
        (list (pair (lit to-cs) (%sh-cs-to 2)) (pair (lit to-pe) (%sh-pe-to 2)))))

; FORM with each of the names SYMS, a state's cell, read: `(first NAME)`.
(def %sh-jit-late
  (fn (self form syms)
    (match
      ((null? form) ())
      ((pair? form) (pair (self (first form) syms) (self (rest form) syms)))
      ((not (symbol? form)) form)
      ((%sh-jit-named? form syms) (list (lit first) form))
      (#t form))))

(def %sh-jit-named?
  (fn (self name syms)
    (match
      ((null? syms) ())
      ((eq? (first syms) name) #t)
      (#t (self name (rest syms))))))

; Whether the lane lowers `first`: asked of a state of the form the states
; below take, which is made and never called.
(def %sh-jit-cells?
  (fn (_)
    (guard (e ())
      (%sh-compile-asm
        (lit (fn (me buffer score chr) (if (= chr 32) me (first to))))
        (list (pair (lit to) (pair () ()))))
      #t)))

; NAME's cell, made holding the interpreted state WAS where there is none.
(def %sh-jit-cell
  (fn (_ name was) (%sh-jit-cell-in name was (%sh-jit-cell-at name %sh-jit-cells))))

(def %sh-jit-cell-at
  (fn (self name cells)
    (match
      ((null? cells) ())
      ((eq? (first (first cells)) name) (rest (first cells)))
      (#t (self name (rest cells))))))

(def %sh-jit-cell-in
  (fn (_ name was cell)
    (match
      ((null? cell) (%sh-jit-cell-new name (pair was ())))
      (#t cell))))

(def %sh-jit-cell-new
  (fn (_ name cell)
    (set! %sh-jit-cells (pair (pair name cell) %sh-jit-cells))
    cell))

; A word's break characters, as a test of `chr` in a compiled form: those
; %sh-word-break? names, less the quotes where QUOTES? is nil.
(def %sh-jit-break
  (fn (_ quotes?)
    (append
      (lit (or (= chr 32) (= chr 9) (= chr 10) (= chr 124) (= chr 38) (= chr 59)
               (= chr 60) (= chr 62) (= chr 40) (= chr 41)))
      (match (quotes? (lit ((= chr 39) (= chr 34)))) (#t ())))))

(def %sh-jit-digit (lit (and (>= chr 48) (<= chr 57))))

; The entries of the compiled base, by type name.
(def %sh-jit-compile!
  (fn (_)
    (set! %sh-jit-cells ())
    (set! %sh-jit-late? (%sh-jit-cells?))
    (def jc
      (fn (_ form fvars)
        (def p (%sh-compile-asm form fvars))
        (set! %sh-jit-states (pair p %sh-jit-states))
        p))
    ; A state some of whose targets are made after it.  LATES are those, each
    ; (SYM NAME WAS): the name FORM calls it by, the state's name, and the
    ; interpreted state.  With cells, FORM reads NAME's cell; without, WAS is
    ; the target.
    (def late-fvar
      (fn (_ l)
        (pair (first l)
          (match
            (%sh-jit-late? (%sh-jit-cell (first (rest l)) (first (rest (rest l)))))
            (#t (first (rest (rest l))))))))
    (def jl
      (fn (_ form fvars lates)
        (jc (match (%sh-jit-late? (%sh-jit-late form (map first lates))) (#t form))
            (append fvars (map late-fvar lates)))))
    ; STATE, in the cell of its NAME.
    (def keep
      (fn (_ name state)
        (match (%sh-jit-late? (set-first! (%sh-jit-cell name ()) state)) (#t ()))
        state))
    (def ws-body
      (jc (lit (fn (me buffer score chr)
                 (if (or (= chr 32) (= chr 9))
                   me
                   (%seq (%buffer-unread buffer) (%score-set score -1 buffer)))))
          ()))
    (def comment-body
      (jc (lit (fn (me buffer score chr)
                 (if (= chr 10)
                   (%seq (%buffer-unread buffer) (%score-set score -1 buffer))
                   me)))
          ()))
    ; What a word's state does with each character: FIRSTS its first clauses,
    ; ACCEPT what it does with a break, ON the state that reads on, and GO
    ; what is made of a state handed to.  %sh-qword-body, %sh-word-body,
    ; %sh-quote-after and %sh-word-dollar are each one.
    (def word-form
      (fn (_ firsts accept on go)
        (list (lit fn) (lit (me buffer score chr))
          (pair (lit match)
            (append firsts
              (list
                (list (lit (= chr 36)) (go (lit to-dollar)))
                (list (lit (= chr 96)) (go (lit to-bt)))
                (list (lit (= chr 39)) (go (lit to-sq)))
                (list (lit (= chr 34)) (go (lit to-dq)))
                (list (lit (= chr 92)) (go (lit to-esc)))
                (list (%sh-jit-break ())
                  (list (lit %seq) (lit (%buffer-unread buffer)) accept))
                (list #t (go on))))))))
    (def to (fn (_ state) state))
    (def word-to (fn (_ state) (list (lit %seq) (lit (%score-label! score 2)) state)))
    (def word-ends (lit (%seq (%score-label! score 2) (%score-set score 1 buffer))))
    (def word-lates
      (fn (_ esc was)
        (list (list (lit to-dollar) (lit word-dollar) %sh-word-dollar)
              (list (lit to-sq) (lit word-in-sq) %sh-word-in-sq)
              (list (lit to-dq) (lit word-in-dq) %sh-word-in-dq)
              (list (lit to-esc) esc was))))
    (def bt-word (list (pair (lit to-bt) %sh-bt-word)))
    (def qword-lates (word-lates (lit qword-esc) %sh-qword-esc))
    (def qword-body (jl (word-form () word-ends (lit me) to) bt-word qword-lates))
    (def word-body
      (jl (word-form () (lit (%score-set score -1 buffer)) (lit me) to)
          bt-word
          (word-lates (lit word-esc) %sh-word-esc)))
    (def to-qword (pair (lit to-qword) qword-body))
    (def quote-after
      (jl (word-form () (lit (%score-set score 1 buffer)) (lit to-qword) word-to)
          (pair to-qword bt-word)
          qword-lates))
    (def sq-body
      (jc (lit (fn (me buffer score chr)
                 (if (= chr 39)
                   (%seq (%score-label! score 1)
                         (%seq (%score-set score 1 buffer) to-after))
                   me)))
          (list (pair (lit to-after) quote-after))))
    ; %sh-dq-body and %sh-sq-dq-dollar: FIRSTS the first clauses, ON the
    ; state that reads on.
    (def dq-form
      (fn (_ firsts on)
        (list (lit fn) (lit (me buffer score chr))
          (pair (lit match)
            (append firsts
              (list
                (lit ((= chr 36) to-dollar))
                (lit ((= chr 96) to-bt))
                (lit ((= chr 34)
                       (%seq (%score-label! score 1)
                             (%seq (%score-set score 1 buffer) to-after))))
                (lit ((= chr 92) to-skip))
                (list #t on)))))))
    (def dq-fvars
      (list (pair (lit to-bt) %sh-bt-dq) (pair (lit to-after) quote-after)))
    (def dq-lates
      (list (list (lit to-dollar) (lit sq-dq-dollar) %sh-sq-dq-dollar)
            (list (lit to-skip) (lit dq-skip) %sh-dq-skip)))
    (def dq-body (jl (dq-form () (lit me)) dq-fvars dq-lates))
    ; The states a `$`, a backslash and a quote inside a word lead to, made
    ; where a cell can hold them.  After a `$`, a `(` or a `{` opens what is
    ; read interpreted, and any other character is read as the state the `$`
    ; stood in reads it.
    (def opens
      (lit (((= chr 40) to-cs) ((= chr 123) to-pe))))
    (def opened (fn (_ back) (nth back %sh-opens)))
    (def skip
      (fn (_ name target)
        (keep name
          (jc (lit (fn (_ buffer score chr) to)) (list (pair (lit to) target))))))
    ; %sh-word-in-dq and %sh-dq-dollar
    (def in-dq-form
      (fn (_ firsts on)
        (list (lit fn) (lit (me buffer score chr))
          (pair (lit match)
            (append firsts
              (list
                (lit ((= chr 36) to-dollar))
                (lit ((= chr 96) to-bt))
                (lit ((= chr 34)
                       (%seq (%score-label! score 2)
                             (%seq (%score-set score 1 buffer) to-qword))))
                (lit ((= chr 92) to-esc))
                (list #t on)))))))
    (def cycles!
      (fn (_)
        (skip (lit qword-esc) qword-body)
        (skip (lit word-esc) word-body)
        (skip (lit dq-skip) dq-body)
        (def in-sq
          (keep (lit word-in-sq)
            (jc (lit (fn (me buffer score chr)
                       (if (= chr 39)
                         (%seq (%score-label! score 2)
                               (%seq (%score-set score 1 buffer) to-qword))
                         me)))
                (list to-qword))))
        (def in-dq-fvars
          (list to-qword (pair (lit to-bt) %sh-bt-in-dq)))
        (def in-dq-lates
          (list (list (lit to-dollar) (lit dq-dollar) %sh-dq-dollar)
                (list (lit to-esc) (lit word-dq-esc) %sh-word-dq-esc)))
        (def in-dq
          (keep (lit word-in-dq) (jl (in-dq-form () (lit me)) in-dq-fvars in-dq-lates)))
        (skip (lit word-dq-esc) in-dq)
        (keep (lit dq-dollar)
          (jl (in-dq-form opens (lit to-in-dq))
              (append (opened 1) (pair (pair (lit to-in-dq) in-dq) in-dq-fvars))
              in-dq-lates))
        (keep (lit word-dollar)
          (jl (word-form opens word-ends (lit to-qword) to)
              (append (opened 0) (pair to-qword bt-word))
              qword-lates))
        (keep (lit sq-dq-dollar)
          (jl (dq-form opens (lit to-body))
              (append (opened 2) (pair (pair (lit to-body) dq-body) dq-fvars))
              dq-lates))))
    (match (%sh-jit-late? (cycles!)) (#t ()))
    ; The second and third characters of an operator: %sh-op-double and
    ; %sh-op-triple, a state for each operator they are made for.
    (def op-end
      (jc (lit (fn (_ buffer score chr)
                 (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))
          ()))
    (def op-dash
      (jc (lit (fn (_ buffer score chr)
                 (if (= chr 45)
                   (%score-set score 1 buffer)
                   (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
          ()))
    (def op-same
      (fn (_ c)
        (jc (list (lit fn) (lit (_ buffer score chr))
              (list (lit if) (list (lit =) (lit chr) c)
                (lit (%score-set score 1 buffer))
                (lit (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
            ())))
    (def op-less
      (jc (lit (fn (_ buffer score chr)
                 (match
                   ((= chr 60) (%seq (%score-set score 1 buffer) to-third))
                   ((or (= chr 38) (= chr 62)) (%score-set score 1 buffer))
                   (#t (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))))
          (list (pair (lit to-third) op-dash))))
    (def op-more
      (jc (lit (fn (_ buffer score chr)
                 (match
                   ((= chr 62) (%seq (%score-set score 1 buffer) to-third))
                   ((or (= chr 38) (= chr 124)) (%score-set score 1 buffer))
                   (#t (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))))
          (list (pair (lit to-third) op-end))))
    ; %sh-int-body: a character that makes the run a word is read as
    ; %sh-qword-body reads one that is no break and no quote.
    (def int-body
      (jl (list (lit fn) (lit (me buffer score chr))
            (list (lit match)
              (list %sh-jit-digit (lit me))
              (lit ((or (= chr 60) (= chr 62)) ()))
              (list (%sh-jit-break #t)
                (lit (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))
              (lit ((= chr 36) to-dollar))
              (lit ((= chr 96) to-bt))
              (lit ((= chr 92) to-esc))
              (lit (#t to-qword))))
          (pair to-qword bt-word)
          (list (list (lit to-dollar) (lit word-dollar) %sh-word-dollar)
                (list (lit to-esc) (lit qword-esc) %sh-qword-esc))))
    (def io-body
      (jc (list (lit fn) (lit (me buffer score chr))
            (list (lit match)
              (list %sh-jit-digit (lit me))
              (lit ((or (= chr 60) (= chr 62))
                     (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))
              (lit (#t ()))))
          ()))
    (list
      (pair "SH-WS"
        (jc (lit (fn (_ buffer score chr)
                   (if (or (= chr 32) (= chr 9))
                     (%seq (%score-set score -1 buffer) to-body)
                     ())))
            (list (pair (lit to-body) ws-body))))
      (pair "SH-NL"
        (jc (lit (fn (_ buffer score chr)
                   (if (= chr 10) (%score-set score 1 buffer) ())))
            ()))
      (pair "SH-COMMENT"
        (jc (lit (fn (_ buffer score chr)
                   (if (= chr 35)
                     (%seq (%score-set score -1 buffer) to-body)
                     ())))
            (list (pair (lit to-body) comment-body))))
      (pair "SH-OP"
        (jc (lit (fn (_ buffer score chr)
                   (match
                     ((or (= chr 40) (= chr 41)) (%score-set score 1 buffer))
                     ((= chr 124) (%seq (%score-set score 1 buffer) to-pipe))
                     ((= chr 38) (%seq (%score-set score 1 buffer) to-amp))
                     ((= chr 59) (%seq (%score-set score 1 buffer) to-semi))
                     ((= chr 60) (%seq (%score-set score 1 buffer) to-less))
                     ((= chr 62) (%seq (%score-set score 1 buffer) to-more))
                     (#t ()))))
            (list (pair (lit to-pipe) (op-same 124)) (pair (lit to-amp) (op-same 38))
                  (pair (lit to-semi) (op-same 59)) (pair (lit to-less) op-less)
                  (pair (lit to-more) op-more))))
      (pair "SH-SQ"
        (jc (lit (fn (_ buffer score chr) (if (= chr 39) to-body ())))
            (list (pair (lit to-body) sq-body))))
      (pair "SH-DQ"
        (jc (lit (fn (_ buffer score chr) (if (= chr 34) to-body ())))
            (list (pair (lit to-body) dq-body))))
      (pair "SH-WORD"
        (jl (list (lit fn) (lit (_ buffer score chr))
              (list (lit match)
                (list (%sh-jit-break #t) ())
                (lit (#t (%seq (%score-set score -1 buffer)
                               (match
                                 ((= chr 36) to-dollar)
                                 ((= chr 96) to-bt)
                                 ((= chr 92) to-esc)
                                 (#t to-body)))))))
            (pair (pair (lit to-body) word-body) bt-word)
            (list (list (lit to-dollar) (lit word-dollar) %sh-word-dollar)
                  (list (lit to-esc) (lit word-esc) %sh-word-esc))))
      (pair "INTEGER"
        (jc (list (lit fn) (lit (_ buffer score chr))
              (list (lit if)
                (list (lit or) %sh-jit-digit (lit (= chr 45)) (lit (= chr 43)))
                (lit (%seq (%score-set score 1 buffer) to-body))
                ()))
            (list (pair (lit to-body) int-body))))
      (pair "IO-NUMBER"
        (jc (list (lit fn) (lit (_ buffer score chr))
              (list (lit if) %sh-jit-digit (lit to-body) ()))
            (list (pair (lit to-body) io-body)))))))

; A base of the types in TYPES, newest first, each with the entry ENTRIES
; holds for its name and the read handler it has.
(def %sh-jit-base
  (fn (_ types entries)
    (def b (make-token-base))
    (%sh-jit-register b types entries)
    b))

(def %sh-jit-register
  (fn (self b types entries)
    (match
      ((null? types) ())
      (#t (%sh-jit-register-after (self b (rest types) entries) b (first types)
            entries)))))

; TYPE registered on B, after the types older than it.
(def %sh-jit-register-after
  (fn (_ older b type entries)
    (base-make-type b (first type)
      (%sh-jit-handlers (rest type) (%sh-table-entry (first type) entries)))))

(def %sh-table-entry
  (fn (self name l)
    (match
      ((str=? (first (first l)) name) (rest (first l)))
      (#t (self name (rest l))))))

; HANDLERS with ENTRY as their analyser.
(def %sh-jit-handlers
  (fn (self handlers entry)
    (match
      ((null? handlers) ())
      ((eq? (first (first handlers)) (lit analyse))
        (pair (pair (lit analyse) entry) (rest handlers)))
      (#t (pair (first handlers) (self (rest handlers) entry))))))

(def %sh-jit-adopt!
  (fn (_)
    (def b (%sh-jit-base (first %sh-tok-types) (%sh-jit-compile!)))
    (set! %sh-cbase b)
    (set! %sh-active-raw (Base raw-of b))
    (lit active)))

; N more bytes to read: the attempt is made when they reach the threshold.
(def %sh-jit-tick!
  (fn (_ n)
    (match
      ((eq? %sh-jit (lit off)) (%sh-jit-count! (+ %sh-jit-bytes n)))
      (#t ()))))

(def %sh-jit-count!
  (fn (_ bytes)
    (set! %sh-jit-bytes bytes)
    (match
      ((< bytes %sh-jit-threshold) ())
      ((= (sh-getpid) %sh-pid)
        (set! %sh-jit (guard (e (%sh-jit-refused)) (%sh-jit-adopt!))))
      (#t (set! %sh-jit (lit failed))))))

; A refused attempt leaves the interpreted base reading, and nothing rooted.
(def %sh-jit-refused
  (fn (_)
    (set! %sh-cbase ())
    (set! %sh-active-raw (Base raw-of %sh-base))
    (set! %sh-jit-states ())
    (set! %sh-jit-cells ())
    (lit failed)))

; --- The line base: here-documents -------------------------------------------
;
; A text holding a here-document is read in lines: a body is the lines up to
; the one that is its delimiter, and every other line is scanned for the `<<`
; that opens one.  This base reads a text into those lines, one token a line,
; each with its newline, and its two types say which lines the scan must see:
; a line holding none of the characters the scan looks at -- a quote, a
; backslash, `#`, `$`, a parenthesis, `<` -- comes back as its text, any other
; as its text in a list.  The two read a plain line to the same length, and
; the one registered first wins the tie.
;
; ITS STATES ARE COMPILED, and it is made only when they are: read through
; interpreted states it is slower than the walk in ash/eval.x (%sh-hd-cut),
; which answers the same and reads the lines until then.  The attempt comes
; once %sh-hd-jit-threshold bytes of text holding a here-document have been
; read in the process -- compiling costs a few tens of milliseconds, which a
; short script would not win back -- and runs under a guard: a refusal pins
; `failed` and the walk reads on.  Each type is one state, entry and body
; alike, answering itself to read on.  The compiled states are rooted in
; %sh-hd-jit-states, since the collector cannot see an address baked into
; code, and all of it is this process's alone: a transient, remade after an
; image load.
(def %sh-hd-plain-read (fn (_ . args) (buffer-token (first args))))
(def %sh-hd-line-read (fn (_ . args) (list (buffer-token (first args)))))

(def %sh-hd-raw ())             ; the raw base the lines are read with
(def %sh-hd-cbase ())           ; roots the base
(def %sh-hd-jit-states ())
(def %sh-hd-jit (lit off))      ; off | active | failed
(def %sh-hd-jit-bytes 0)
(def %sh-hd-jit-threshold 8192)

(def %sh-hd-jit-compile!
  (fn (_)
    (do
      (import x/tool/compile)
      (def jc
        (fn (_ form)
          (do
            (def p (compile-asm form () #t))
            (set! %sh-hd-jit-states (pair p %sh-hd-jit-states))
            p)))
      (def plain
        (jc (lit (fn (me buffer score chr)
          (if (= chr 10)
            (%score-set score 1 buffer)
            (if (or (= chr 39) (= chr 34) (= chr 92) (= chr 35)
                    (= chr 36) (= chr 40) (= chr 41) (= chr 60))
              ()
              me))))))
      (def line
        (jc (lit (fn (me buffer score chr)
          (if (= chr 10) (%score-set score 1 buffer) me)))))
      (def b (make-token-base))
      (base-make-type b "HD-PLAIN"
        (list (pair (lit analyse) plain) (pair (lit read) %sh-hd-plain-read)))
      (base-make-type b "HD-LINE"
        (list (pair (lit analyse) line) (pair (lit read) %sh-hd-line-read)))
      (set! %sh-hd-cbase b)
      (set! %sh-hd-raw (Base raw-of b))
      (lit active))))

(def %sh-hd-jit-tick!
  (fn (_ n)
    (if (eq? %sh-hd-jit (lit off))
      (do
        (set! %sh-hd-jit-bytes (+ %sh-hd-jit-bytes n))
        (if (< %sh-hd-jit-bytes %sh-hd-jit-threshold)
          ()
          (set! %sh-hd-jit (guard (e (lit failed)) (%sh-hd-jit-compile!)))))
      ())))

(def %sh-hd-reset!
  (fn (_)
    (do
      (set! %sh-hd-raw ())
      (set! %sh-hd-cbase ())
      (set! %sh-hd-jit-states ())
      (set! %sh-hd-jit (lit off))
      (set! %sh-hd-jit-bytes 0))))
(set! %image-transients
  (pair (lit %sh-hd-raw) (pair (lit %sh-hd-cbase)
    (pair (lit %sh-hd-jit-states) %image-transients))))
(set! %image-recache-hooks (pair (fn (_) (%sh-hd-reset!)) %image-recache-hooks))
