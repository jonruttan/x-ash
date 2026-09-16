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
; is (%cvt l %string), and %cvt inside a reader callback answers nil silently
; (the same finding as x-python: build strings at load, not in a read handler),
; so an accumulated value was nil for every non-empty string. buffer-token is
; the platform's answer to "what text did this token consume", runs in the read
; handler where allocating is safe, and is what %sh-word-reader has always
; used. The analyse pass scans for the closing quote and scores; the read pass
; takes the consumed run and strips the quotes.

; The consumed run is 'text' -- quotes included, since neither reader un-reads
; the closing quote.  Drop one from each end.
(def %sh-unquote
  (fn (_ s)
    (let ((n (string-length s)))
      (if (< n 2) "" (substring s 1 (- n 1))))))

; A quoted word that does not end at its closing quote is still one word:
; `"$HOME"/bin` and `'a'"$b"` are single arguments. So the closing quote hands
; over to %sh-qword-body, which ends the token only at a real word break.
;
; The read handler then decides the token's kind: a run that is nothing but one
; quoted string keeps its tok-sq / tok-dq identity (the token vocabulary the
; specs assert), and anything mixed comes back as a tok-word carrying its raw
; text for %sh-expand-str to interpret. %sh-pure-quote? tells them apart.
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
        ; Score here even though the word may continue, so input ending at the
        ; closing quote still produces a token. If it continues, %sh-qword-body
        ; scores again at the real break and that later score wins; this is the
        ; floor, like SH-WORD's -1 analyse entry.
        (score-set score 1 buffer)
        %sh-qword-body)
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

; Quotes INSIDE the substitution hide parens from the depth count, so
; `$(echo ")")` closes where it should.
(set! %sh-cs-sq
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\')) %sh-cs-body %sh-cs-sq)))

(set! %sh-cs-dq-esc (fn (_ buffer score chr) %sh-cs-dq))

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
            ((= %sh-cs-return 2) %sh-dq-body)
            (#t %sh-qword-body))
          (do (set! %sh-cs-depth (- %sh-cs-depth 1)) %sh-cs-body)))
      ((= chr (char->integer #\')) %sh-cs-sq)
      ((= chr (char->integer #\")) %sh-cs-dq)
      (#t %sh-cs-body))))

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
          ((= %sh-cs-return 2) %sh-dq-body)
          (#t %sh-qword-body)))
      (#t %sh-bt-scan))))

; After a `$`, one character decides. Anything that is not `(` is re-dispatched
; through the state we came from -- a direct call, correct here because we want
; that character handled normally, unlike at a closing quote where the
; character has already been consumed by meaning.
(def %sh-word-dollar ())
(def %sh-dq-dollar ())
(def %sh-sq-dq-dollar ())

(set! %sh-word-dollar
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\())
      (do (set! %sh-cs-depth 0) (set! %sh-cs-return 0) %sh-cs-body)
      (%sh-qword-body buffer score chr))))

(set! %sh-dq-dollar
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\())
      (do (set! %sh-cs-depth 0) (set! %sh-cs-return 1) %sh-cs-body)
      (%sh-word-in-dq buffer score chr))))

(set! %sh-sq-dq-dollar
  (fn (_ buffer score chr)
    (if (= chr (char->integer #\())
      (do (set! %sh-cs-depth 0) (set! %sh-cs-return 2) %sh-cs-body)
      (%sh-dq-body buffer score chr))))

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
        (do (buffer-unread buffer) (score-set score 1 buffer)))
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
            ; own arm; this is the same door for the first character.
            (if (= chr (char->integer #\$))
              %sh-word-dollar
              (if (= chr #\`)
                (do (set! %sh-cs-return 0) %sh-bt-scan)
                %sh-word-body)))
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
  (fn (_ c) (if (fx<? c #\0) () (not (fx<? #\9 c)))))

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
      ((%sh-word-break? chr)
        (do (buffer-unread buffer) (score-set score 1 buffer)))
      ; Not a digit and not a break: the run is a word from here on.  The
      ; character is consumed by returning the continuation, exactly as
      ; %sh-word-body does.
      (#t %sh-int-word-body))))

(%sh-tok-type!
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

; A safety net under the parser: every predicate in eval.x opens with
; (first tok), so a token that is not a list would crash rather than raise.
; The INTEGER fallback above produces one such case; rather than trust it is
; the only one, anything that comes back not-a-pair is rendered as the word it
; stands for. One walk of the token list buys the guarantee that the parser
; only ever sees tokens.
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

; --- The base itself: made here, and made again after an image load --------
; One door, called by the load and by the image's recache hook.  The transient
; nils it in the writer's child so the walk never meets a word it cannot
; place.
(def %sh-base-reset! (fn (_) (set! %sh-base (%sh-base-make))))
(%sh-base-reset!)
(set! %image-transients (pair (lit %sh-base) %image-transients))
(set! %image-recache-hooks (pair (fn (_) (%sh-base-reset!)) %image-recache-hooks))
