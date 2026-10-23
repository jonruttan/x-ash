; tokens.x -- the shell's tokens, read by the platform's Lexer
; lint-known: read-str
; (read-str is sent to the lexer instance %sh-lexer, which the linter cannot see in a scoped module.)
;
; sh-tokenize reads a text into tokens through a Lexer (x/reader/lexer): the
; rules below become the types of a tokenizer base of its own, their states
; compiled by the assembler lane when it is open.  Blanks and comments are
; dropped; every other token is (label text):
;
;   tok-word     a word, raw: its quotes, escapes and substitutions as written
;   tok-sq       a word that is one single-quoted string, its text unquoted
;   tok-dq       a word that is one double-quoted string, its text unquoted
;   tok-op       an operator
;   tok-io       a descriptor's digits, read only against `<` or `>`
;   tok-newline  a newline, with no text
;
; Usage:
;   (def tokens (sh-tokenize "echo hello | grep h"))
;   ; -> ((tok-word "echo") (tok-word "hello") (tok-op "|") (tok-word "grep") (tok-word "h"))
(module ash/tokens)
(import ash/prims
  make-token-base base-make-type buffer-token char->integer string-length
  string-ref substring fx<? fx+)
(import x/reader/lexer)

; --- Helpers ---
; Predicate: is chr a shell whitespace (space or tab, NOT newline)?

(def sh-ws?
  (fn (_ c)
    (or
      (= c (char->integer #\space))
      (= c (char->integer #\tab)))))
; Predicate: is chr a shell operator start character?
; | & ; < > ( )

(def sh-op-start?
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
; whitespace, newline, operator-start, single-quote, double-quote

(def %sh-word-break?
  (fn (_ c)
    (or
      (sh-ws? c)
      (= c (char->integer #\newline))
      (sh-op-start? c)
      (= c (char->integer #\'))
      (= c (char->integer #\")))))

; A decimal digit -- the one definition; eval.x asks it too.  Its callers pass
; an integer and never nil, so the unchecked comparison is safe.
(def sh-digit?
  (fn (_ c) (match ((fx<? c #\0) ()) ((fx<? #\9 c) ()) (#t #t))))
; --- Token constructors ---

(def mk-tok-newline (fn (_) (list (lit tok-newline))))

(def mk-tok-op (fn (_ s) (list (lit tok-op) s)))

(def mk-tok-word (fn (_ s) (list (lit tok-word) s)))

(def mk-tok-sq (fn (_ s) (list (lit tok-sq) s)))

(def mk-tok-dq (fn (_ s) (list (lit tok-dq) s)))

(def mk-tok-io (fn (_ s) (list (lit tok-io) s)))

; A quoted token's text with its quotes: drop one from each end.
(def %sh-unquote (fn (_ s) (%sh-unquote-of s (string-length s))))

(def %sh-unquote-of
  (fn (_ s n) (match ((fx<? n 2) "") (#t (substring s 1 (fx+ n -1))))))

; --- The rules ----------------------------------------------------------------
; A word is read in context w, which no byte closes: a blank, newline or
; operator byte at depth 0 ends it.  Each context is (NAME CLOSE ESC OPENS);
; an opener enters a context whose close returns to the one it was entered
; from, so `"$(echo ")")"` is one span.  `#` opens a comment only where a
; token starts: there the comment reads at least as far as a word would, and
; listed first it wins a tie; inside a word `#` is a byte like any other.
; A span still open at the end of the text (`${X`, `'a'"b`, `"a`) is the word
; to the end, which the expansion reads literally: the word rule reads it, and
; a closed double-quoted string goes to the dq rule, listed first.
(def %sh-lexer-contexts
  (list
    (list (lit w) () 92
      (list (pair "\"" (lit dq)) (pair "'" (lit sq)) (pair "$(" (lit cmd))
            (pair "${" (lit brace)) (pair "`" (lit bq))))
    (list (lit dq) 34 92
      (list (pair "$(" (lit cmd)) (pair "${" (lit brace)) (pair "`" (lit bq))))
    (list (lit sq) 39 () ())
    (list (lit cmd) 41 92
      (list (pair "(" (lit cmd)) (pair "\"" (lit dq)) (pair "'" (lit sq))
            (pair "${" (lit brace)) (pair "`" (lit bq))))
    (list (lit brace) 125 92
      (list (pair "\"" (lit dq)) (pair "'" (lit sq)) (pair "$(" (lit cmd))
            (pair "${" (lit brace)) (pair "`" (lit bq))))
    (list (lit bq) 96 92
      (list (pair "'" (lit sq)) (pair "\"" (lit dq)) (pair "$(" (lit cmd))))))

(def %sh-lexer-rules
  (fn (_)
    (list
      (Lexer skip " \t")
      (Lexer until () "#" "\n")
      (Lexer table (lit tok-newline) (list "\n"))
      (Lexer run (lit tok-io) (list (pair 48 57)) (list (pair 48 57)) "<>")
      (Lexer table (lit tok-op)
        (list ";" ";;" "&" "&&" "|" "||" "(" ")" "<" ">" "<<" ">>" "<&" ">&" "<>" ">|" "<<-"))
      (Lexer quoted (lit tok-sq) 39 39 ())
      (Lexer nested (lit tok-dq) "\"" (lit dq) (rest %sh-lexer-contexts))
      (Lexer word (lit tok-word) (lit w) %sh-lexer-contexts " \t\n;&|<>()" (lit to-end)))))

; Made at load, so a boot image carries it with its cache group's entries and
; plan: after an image load the Lexer remakes its own base from what the image
; holds, with no file read and no form made.
(def %sh-lexer (Lexer make (%sh-lexer-rules) "\n"))

; --- Reading ------------------------------------------------------------------
; The Lexer's tokens are fresh lists in this heap, so a token whose label or
; text the shell reads differently is changed in place: a newline drops its
; text, a single-quoted string loses its quotes, and a double-quoted one does
; too unless a `"` stands inside it -- `"${x:+"a"}"` is a word the expansion
; reads raw.  The walk is a loop: a script's token list is as long as the
; script.
(def %sh-inner-quote?
  (fn (self s i n)
    (if (fx<? i n)
      (match
        ((= (string-ref s i) #\\) (self s (fx+ i 2) n))
        ((= (string-ref s i) #\") #t)
        (#t (self s (fx+ i 1) n)))
      #f)))

(def %sh-tok-fix!
  (fn (self toks)
    (if (null? toks) ()
      (do
        (def tok (first toks))
        (def label (first tok))
        (match
          ((eq? label (lit tok-word)) ())
          ((eq? label (lit tok-newline)) (%set-rest! tok ()))
          ((eq? label (lit tok-sq)) (%set-first! (rest tok) (%sh-unquote (first (rest tok)))))
          ((eq? label (lit tok-dq))
            (if (%sh-inner-quote? (first (rest tok)) 1 (fx+ (string-length (first (rest tok))) -1))
              (%set-first! tok (lit tok-word))
              (%set-first! (rest tok) (%sh-unquote (first (rest tok))))))
          (#t ()))
        (self (rest toks))))))

(def sh-tokenize
  (fn (_ input)
    (def toks (%sh-lexer read-str input))
    (%sh-tok-fix! toks)
    toks))

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
(def sh-hd-raw (fn (_) %sh-hd-raw))   ; read from ash/eval; the name is rebound
(def %sh-hd-cbase ())           ; roots the base
(def %sh-hd-jit-states ())
(def %sh-hd-jit (lit off))      ; off | active | failed
(def sh-hd-jit (fn (_) %sh-hd-jit))   ; likewise
(def %sh-hd-jit-bytes 0)
(def %sh-hd-jit-threshold 8192)

(def %sh-hd-jit-compile!
  (fn (_)
    (do
      (import x/tool/compile compile-asm)   ; by name: inside a module a bare import binds nothing
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

(def sh-hd-jit-tick!
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

(provide ash/tokens
  sh-tokenize mk-tok-newline mk-tok-op mk-tok-word mk-tok-sq mk-tok-dq mk-tok-io
  ; what ash/eval reads: the character classes, and the heredoc lane's state
  ; through sh-hd-jit and sh-hd-raw, since both names are rebound
  sh-digit? sh-op-start? sh-ws? sh-hd-jit sh-hd-raw sh-hd-jit-tick!)
