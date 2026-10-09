; ash/line.x -- the line editor's seams, filled with the shell's own knowledge.
;
; The platform's line editor reads a line with editing, history and Tab and
; carries no grammar of its own: it asks %repl-paint how to display the line
; and (Line completer) what a word could become.  This file answers both for
; the shell, and gives the loop one reader that uses the editor when there is
; a terminal to drive and the byte reader otherwise.
;
; Colour comes from a Lexer whose tokens cover every byte of the line, each
; drawn in the colour its tag names (see "colour" below).

(import x/type/class)
(import x/type/str)
(import x/type/list)
(import x/sys/file)
(import x/sys/posix)
(import x/reader/lexer)
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
;
; A line is coloured by the tokens of a Lexer (x/reader/lexer) whose rules read
; every byte, through the platform's (Paint lexer): each token is drawn as the
; bytes it read, in the colour its tag names, so the display keeps the
; author's spacing without a scan of its own.  Blanks are a run rather than
; dropped, and a comment, a string or a word still open at the end of the
; line -- the normal state of one being typed -- is a token to the end.
;
; The lexer is made on the first paint, which is the first prompt's redraw:
; only an interactive session with colour on pays for it, and a script, a pipe
; or an image write never does.  The Lexer remakes its own states after an
; image load.

; The codes, read from the Ansi statics once per install rather than once per
; token: whether there is a terminal is a fact of the process, so the install
; runs again after a state image is loaded.
(def %ash-c-reserved-word "")
(def %ash-c-builtin "")
(def %ash-c-string "")
(def %ash-c-variable "")
(def %ash-c-comment "")

(def %ash-paint-install!
  (fn (_)
    (guard (_ ())
      (set! %ash-c-reserved-word (Str8 append (Ansi bold) (Ansi magenta)))
      (set! %ash-c-builtin (Ansi cyan))
      (set! %ash-c-string (Ansi green))
      (set! %ash-c-variable (Ansi yellow))
      (set! %ash-c-comment (Ansi dim)))))

; A word's span is read in context w, which no byte closes; each context is
; (NAME CLOSE ESC OPENS), an opener entering a context whose close returns to
; the one it was entered from, so `"$(echo ")")"` is one span.
(def %ash-paint-contexts
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

; `#` opens a comment only where a token starts: there the comment reads at
; least as far as a word would, and listed first it wins a tie.
(def %ash-paint-rules
  (fn (_)
    (list
      (Lexer run (lit blank) " \t" " \t")
      (Lexer table (lit nl) (list "\n"))
      (Lexer until (lit comment) "#" "\n" (lit to-end))
      (Lexer run (lit io) (list (pair 48 57)) (list (pair 48 57)) "<>")
      (Lexer table (lit op)
        (list ";" ";;" "&" "&&" "|" "||" "(" ")" "<" ">" "<<" ">>" "<&" ">&" "<>" ">|" "<<-"))
      (Lexer until (lit sq) "'" "'" (lit take) (lit to-end))
      (Lexer nested (lit dq) "\"" (lit dq) (rest %ash-paint-contexts) (lit to-end))
      (Lexer word (lit word) (lit w) %ash-paint-contexts " \t\n;&|<>()" (lit to-end)))))

; A word's colour: a reserved word, a builtin, a variable reference, or none.
; The builtin names are taken once, when the painter is made.
(def %ash-builtin-names ())
(def %ash-word-code
  (fn (_ text)
    (match
      ((List includes? text %sh-reserved-words) %ash-c-reserved-word)
      ((List includes? text %ash-builtin-names) %ash-c-builtin)
      ((if (> (Str8 length text) 0) (eq? (Str8 ref 0 text) #\$) #f) %ash-c-variable)
      (#t ()))))

(def %ash-painter ())

(def %ash-painter-make
  (fn (_)
    (set! %ash-builtin-names (List map first %sh-builtin-table))
    (Paint lexer (Lexer make (%ash-paint-rules) "\n")
      (list (pair (lit comment) (fn (_ t) %ash-c-comment))
            (pair (lit sq) (fn (_ t) %ash-c-string))
            (pair (lit dq) (fn (_ t) %ash-c-string))
            (pair (lit word) %ash-word-code)))))

; The seam the editor calls: (%repl-paint window marks before).  Guarded, and
; the line drawn plain, if the painter cannot be made.
(def %ash-paint
  (fn (_ s . more)
    (if (not (guard (_ #f) (Ansi enabled?))) s
      (guard (_ s)
        (do
          (if (null? %ash-painter) (set! %ash-painter (%ash-painter-make)) ())
          (%ash-painter s
            (if (null? more) () (first more))
            (if (if (null? more) #t (null? (rest more))) () (first (rest more)))))))))

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

; --- where the word stands ----------------------------------------------------
;
; What the word being completed is, read from the shell's own tokens for the
; text before it: 'command at the start of a command, 'redirect after `<`,
; `>` and the other redirection operators, and otherwise 'argument, with the
; command's name.  A command starts a line, and follows `|`, `||`, `&&`,
; `;`, `&`, `(` and the reserved words that take one: `if`, `then`, `elif`,
; `else`, `while`, `until`, `do`, `!` and `{`.  Text the tokenizer refuses,
; such as an unclosed quote, makes the word an argument.
(def %ash-command-heads (list "if" "then" "elif" "else" "while" "until" "do" "!" "{"))
(def %ash-command-ops (list "|" "||" "&&" ";" ";;" "&" "("))
(def %ash-redirect-ops (list "<" ">" ">>" "<<" "<<-" "<&" ">&" "<>" ">|"))

(def %ash-tok-text
  (fn (_ tok) (if (null? (rest tok)) "" (first (rest tok)))))

; A reserved word that a command follows, standing where a command would.
(def %ash-head?
  (fn (_ label text)
    (if (eq? label (lit tok-word)) (List includes? text %ash-command-heads) #f)))

; Answers (label . name): name is the command's, or nil at command position.
(def %ash-word-place
  (fn (_ before)
    (let ((toks (guard (_ (lit refused)) (sh-tokenize before))))
      (if (eq? toks (lit refused)) (pair (lit argument) ())
        (let ((go (fn (self toks cmd? name redirect?)
                    (if (null? toks)
                      (match
                        (redirect? (pair (lit redirect) name))
                        (cmd? (pair (lit command) ()))
                        (#t (pair (lit argument) name)))
                      (let ((label (first (first toks)))
                            (text (%ash-tok-text (first toks)))
                            (more (rest toks)))
                        (match
                          ((eq? label (lit tok-newline)) (self more #t () #f))
                          ((eq? label (lit tok-io)) (self more cmd? name redirect?))
                          ((eq? label (lit tok-op))
                            (match
                              ((List includes? text %ash-command-ops) (self more #t () #f))
                              ((List includes? text %ash-redirect-ops) (self more cmd? name #t))
                              (#t (self more cmd? name redirect?))))
                          ; A word after a redirection operator is its target,
                          ; and leaves the command where it was.
                          (redirect? (self more cmd? name #f))
                          ((if cmd? (%ash-head? label text) #f) (self more #t () #f))
                          (cmd? (self more #f text #f))
                          (#t (self more #f name #f))))))))
          (go toks #t () #f))))))

; --- paths ---------------------------------------------------------------------
;
; The names a word could become as a path, found by the shell's own globbing:
; the word, its metacharacters escaped, with `*` after it.  So what Tab offers
; is what the shell would expand -- relative to the directory `cd` last moved
; to, with a dotfile only when the word starts with a dot -- and a directory
; comes with a `/` after it, so the next Tab goes on inside it.  With
; dirs-only, as for cd, the pattern ends in `*/`, which the globber answers
; with directories alone.  A word starting `~/` is looked up under HOME and
; offered in the form it was typed.

; A match as it is offered: a directory with its `/`.
(def %ash-slashed
  (fn (_ hit)
    (if (Str8 ends? "/" hit) hit
      (if (eq? (sh-path-file-type hit) (lit dir)) (Str8 append hit "/") hit))))

; A path under home written back as `~` and the rest.
(def %ash-untilde
  (fn (_ home path)
    (if (Str8 starts? home path)
      (let ((k (Str8 length home)))
        (Str8 append "~" (Str8 sub k (- (Str8 length path) k) path)))
      path)))

(def %ash-paths
  (fn (_ word dirs-only?)
    (let ((home (if (Str8 starts? "~/" word) (%sh-var-get "HOME") ())))
      (let ((text (if (null? home) word
                    (Str8 append home (Str8 sub 1 (- (Str8 length word) 1) word))))
            (tail (if dirs-only? "*/" "*")))
        (let ((hits (%sh-glob-matches
                      (%sh-field (Str8 append (%sh-glob-escape-all text) tail) #t #t))))
          (List filter (fn (_ name) (Str8 starts? word name))
            (List map
              (fn (_ hit)
                (if (null? home) (%ash-slashed hit) (%ash-untilde home (%ash-slashed hit))))
              ; When nothing matches the globber hands the pattern back; a
              ; name that is not there is not a candidate.
              (List filter (fn (_ hit) (not (null? (sh-path-file-type hit)))) hits))))))))

; The commands a word could be: the reserved words, the builtins and the
; executables on PATH.  An empty word offers nothing rather than all of them.
(def %ash-commands
  (fn (_ word)
    (if (= 0 (Str8 length word)) ()
      (List filter (fn (_ name) (%ash-prefix? word name))
        (List append %sh-reserved-words
          (List append (%ash-builtin-names) (%ash-path-names!)))))))

; What a word could become where it stands.  At command position it is a
; command, or a path once it holds a `/`; after a redirection operator it is
; a path; as an argument it is a path, and a directory when it is cd's.
(def %ash-candidates
  (fn (_ word place)
    (match
      ((eq? (first place) (lit command))
        (if (null? (Str8 index-of "/" word)) (%ash-commands word) (%ash-paths word #f)))
      ((eq? (first place) (lit redirect)) (%ash-paths word #f))
      (#t (%ash-paths word (if (null? (rest place)) #f (str=? (rest place) "cd")))))))

(def %ash-complete
  (fn (_ ed)
    (let ((word (%ash-word-at ed)))
      (let ((before (let ((b (ed before)))
                      (Str8 sub 0 (- (Str8 length b) (Str8 length word)) b))))
        (pair word
          (List sort (fn (_ a b) (Str8 <? a b))
            (List distinct (%ash-candidates word (%ash-word-place before)))))))))

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
