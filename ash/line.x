; ash/line.x -- the line editor's seams, filled with the shell's own knowledge.
;
; The platform's line editor reads a line with editing, history and Tab and
; carries no grammar of its own: it asks %repl-paint how to display the line
; and (Line completer) what a word could become.  This file answers both for
; the shell, and gives the loop one reader that uses the editor when there is
; a terminal to drive and the byte reader otherwise.
;
; Colour comes from the shell's own tokenizer: sh-tokenize decides what is a
; word, an operator or a quoted string, and this file only locates each
; token's bytes in the line so the display keeps the author's spacing.  The
; one thing it scans for itself is the extent of a quoted string, since the
; tokenizer answers a string's contents rather than its span.

(import x/type/class)
(import x/type/str)
(import x/type/list)
(import x/sys/file)
(import x/sys/posix)
; The editor, when the platform has one.  Imported here rather than left to
; the launcher so that its Line class exists when the completer is installed
; below; a platform without it leaves the guard to answer.
(guard (_ ()) (import x/repl/line))

; --- reading one line ---------------------------------------------------------
;
; Answers the line as a string, nil at end of input, and 'cancel for ctrl-c,
; which abandons the entry being typed.  Without a terminal, or on a platform
; without the editor, the prompt is displayed and the byte reader is used.
(def %ash-editor?
  (fn (_) (guard (_ #f) (Line available?))))

; --- is this a session? -------------------------------------------------------
;
; A shell is interactive when its own input and its reports are both
; terminals, and only then is there anyone to prompt: a script arriving down a
; pipe gets no prompt and no banner, and stdout carries what the commands
; wrote and nothing else.
;
; x.sh parks the user's stdin on fd 3 while the boot stream holds fd 0, and
; %ash-repl takes it back before the first read, so whichever of the two is a
; terminal is the shell's own input -- the question is asked on both sides of
; that swap.
(def %ash-interactive?
  (fn (_)
    (guard (_ ())
      (and (or (Sys isatty 0) (Sys isatty 3)) (Sys isatty 2)))))

; POSIX writes PS1 and PS2 to standard error.  On stdout they would land in
; whatever a session's output was piped or redirected into.
(def %ash-show-prompt
  (fn (_ prompt) (when (%ash-interactive?) (%stderr prompt))))

(def %ash-read-line
  (fn (_ prompt)
    (if (%ash-editor?)
      (let ((r (Line read prompt)))
        (match
          ((eq? r (lit eof)) ())
          ((eq? r (lit cancel)) (lit cancel))
          (#t r)))
      (do (%ash-show-prompt prompt) (sh-read-line)))))

; --- colour -------------------------------------------------------------------

; The codes, read from the Ansi statics once per install rather than once per
; token: whether there is a terminal is a fact of the process, so the install
; runs again after a state image is loaded.
(def %ash-c-keyword "")
(def %ash-c-builtin "")
(def %ash-c-string "")
(def %ash-c-variable "")
(def %ash-c-comment "")
(def %ash-c-reset "")

(def %ash-paint-install!
  (fn (_)
    (guard (_ ())
      (set! %ash-c-keyword (Str8 append (Ansi bold) (Ansi magenta)))
      (set! %ash-c-builtin (Ansi cyan))
      (set! %ash-c-string (Ansi green))
      (set! %ash-c-variable (Ansi yellow))
      (set! %ash-c-comment (Ansi dim))
      (set! %ash-c-reset (Ansi reset)))))

; One coloured piece onto the reversed segment list; an empty code pushes the
; bare text, so nothing emits a stray reset.
(def %ash-seg
  (fn (_ segs code text)
    (if (= 0 (Str8 length text)) segs
      (if (= 0 (Str8 length code)) (pair text segs)
        (pair %ash-c-reset (pair text (pair code segs)))))))

; The bytes between the last token and the next, uncoloured.
(def %ash-gap
  (fn (_ s from to segs)
    (if (>= from to) segs (pair (Str8 sub from (- to from) s) segs))))

; Where `text` next occurs at or after `from`, or nil.
(def %ash-find
  (fn (_ s text from n)
    (if (>= from n) ()
      (let ((i (Str8 index-of text (Str8 sub from (- n from) s))))
        (if (null? i) () (+ from i))))))

; The first quote character at or after `from`, or nil.
(def %ash-quote-from
  (fn (self s from n)
    (if (>= from n) ()
      (let ((c (Str8 ref from s)))
        (if (if (eq? c #\") #t (eq? c #\')) from (self s (+ from 1) n))))))

; The offset just past the string opened by the quote at `q`, or n when it
; is not closed.  A backslash inside double quotes escapes the next byte.
(def %ash-quote-end
  (fn (_ s q n)
    (let ((open (Str8 ref q s)))
      (let ((go (fn (self i)
                  (if (>= i n) n
                    (let ((c (Str8 ref i s)))
                      (match
                        ((eq? c open) (+ i 1))
                        ((if (eq? open #\") (eq? c #\\) #f) (self (+ i 2)))
                        (#t (self (+ i 1)))))))))
        (go (+ q 1))))))

(def %ash-builtin-names
  (fn (_) (List map first %sh-builtin-table)))

; The code for a word: a reserved word, a builtin, a variable reference, or
; nothing.
(def %ash-word-code
  (fn (_ kind text)
    (if (not (eq? kind (lit tok-word))) ""
      (match
        ((List includes? text %sh-reserved-words) %ash-c-keyword)
        ((List includes? text (%ash-builtin-names)) %ash-c-builtin)
        ((if (> (Str8 length text) 0) (eq? (Str8 ref 0 s-dollar) (Str8 ref 0 text)) #f) %ash-c-variable)
        (#t "")))))
(def s-dollar "$")

; What is left after the last token: a comment from its `#`, an unclosed
; string from its quote, or plain bytes.
(def %ash-paint-tail
  (fn (_ s from n segs)
    (if (>= from n) segs
      (let ((hash (%ash-find s "#" from n))
            (q (%ash-quote-from s from n)))
        (match
          ((if (null? hash) #f (if (null? q) #t (< hash q)))
            (%ash-seg (%ash-gap s from hash segs) %ash-c-comment (Str8 sub hash (- n hash) s)))
          ((not (null? q))
            (%ash-seg (%ash-gap s from q segs) %ash-c-string (Str8 sub q (- n q) s)))
          (#t (%ash-gap s from n segs)))))))

(def %ash-paint
  (fn (_ s)
    (if (not (guard (_ #f) (Ansi enabled?))) s
      (guard (_ s)
        (let ((n (Str8 length s)))
          (let ((go (fn (self toks at segs)
                      (if (null? toks) (%ash-paint-tail s at n segs)
                        (let ((kind (first (first toks)))
                              (text (if (null? (rest (first toks))) "" (first (rest (first toks))))))
                          (match
                            ((eq? kind (lit tok-newline)) (self (rest toks) at segs))
                            ((if (eq? kind (lit tok-dq)) #t (eq? kind (lit tok-sq)))
                              (let ((q (%ash-quote-from s at n)))
                                (if (null? q) (%ash-paint-tail s at n segs)
                                  (let ((e (%ash-quote-end s q n)))
                                    (self (rest toks) e
                                          (%ash-seg (%ash-gap s at q segs) %ash-c-string
                                                    (Str8 sub q (- e q) s)))))))
                            (#t
                              (let ((p (%ash-find s text at n)))
                                (if (null? p) (%ash-paint-tail s at n segs)
                                  (let ((e (+ p (Str8 length text))))
                                    (self (rest toks) e
                                          (%ash-seg (%ash-gap s at p segs)
                                                    (%ash-word-code kind text)
                                                    (Str8 sub p (- e p) s)))))))))))))
            (Str8 join "" (List reverse (go (sh-tokenize s) 0 ())))))))))

; --- completion ---------------------------------------------------------------

; The word being typed: the bytes from the last space, tab, `|`, `;`, `&`,
; `(` or `<`/`>` before the cursor.
(def %ash-word-at
  (fn (_ ed)
    (let ((before (ed before)))
      (let ((n (Str8 length before)))
        (let ((go (fn (self i)
                    (if (<= i 0) 0
                      (let ((c (Str8 ref (- i 1) before)))
                        (if (List includes? c (list #\space #\tab #\| #\; #\& #\( #\< #\>))
                          i (self (- i 1))))))))
          (Str8 sub (go n) (- n (go n)) before))))))

; Executables on PATH, listed once per session on the first Tab: that Tab
; takes about two seconds on a PATH of a few thousand names, and the ones
; after it a fifth of a second.
(def %ash-path-names ())
(def %ash-path-names!
  (fn (_)
    (when (null? %ash-path-names)
      (let ((path (Sys getenv "PATH")))
        (set! %ash-path-names
          (list (List flat-map
                  (fn (_ dir) (guard (_ ()) (File list-dir dir)))
                  (if (null? path) () (Str8 split ":" path)))))))
    (first %ash-path-names)))

; Whether `name` starts with `word`, tested with the byte primitives: this
; runs once per name on PATH for every Tab, and a class door per name costs
; seconds where the primitives cost tenths.
(def %ash-bsub (prim-ref (lit str) (lit byte-sub)))
(def %ash-blen (prim-ref (lit str) (lit byte-len)))
(def %ash-prefix?
  (fn (_ word name)
    (let ((k (%ash-blen word)))
      (if (> k (%ash-blen name)) #f
        (str=? word (%ash-bsub name 0 k))))))

(def %ash-complete
  (fn (_ ed)
    (let ((word (%ash-word-at ed)))
      (pair word
        (if (= 0 (Str8 length word)) ()
          (List sort (fn (_ a b) (Str8 <? a b))
            (List distinct
              (List filter (fn (_ name) (%ash-prefix? word name))
                (List append %sh-reserved-words
                  (List append (%ash-builtin-names) (%ash-path-names!)))))))))))

; --- installation -------------------------------------------------------------

(def %ash-line-install!
  (fn (_)
    (%ash-paint-install!)
    (guard (_ ()) (set! %repl-paint %ash-paint))
    (guard (_ ()) (Line completer %ash-complete))))

(%ash-line-install!)
(guard (_ ())
  (set! %image-recache-hooks (pair (fn (_) (%ash-line-install!)) %image-recache-hooks)))

(provide ash/line %ash-read-line %ash-interactive? %ash-show-prompt %ash-paint
  %ash-complete %ash-word-at)
