; # x-ash -- a POSIX shell on x-lang
;
; ## ash/syntax.x -- the sh highlighting grammar
;
; @description The grammar x/tool/syntax colours shell scripts with: comments,
;   quoted strings, parameter expansions inside and outside them, assigned
;   names, numbers, and the reserved words and builtins as keywords.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; lang.xon's (grammar sh ...) form names this module, and x/tool/syntax
; imports it the first time a file needs the grammar, in whatever process is
; colouring: vi's, a REPL's, an HTML renderer's.  So it imports x-lang
; libraries and never the shell, and the words it colours are its own copy of
; the shell's tables.  A spec holds the two to the same words.
;
; Tokens are lexical, as a highlighter's are.  A double-quoted string is one
; string token, whose class function answers the expansions inside it as
; names, and a here-document's body is read as shell.  Outside a string,
; $NAME, $1, $? and ${...} are each an expansion, and $( and ` are operators
; whose commands are read as any other.

(module ash/syntax)
(import x/type/list)
(import x/reader/lexer)
(import x/tool/syntax)

; The reserved words and the builtins, as ash/eval.x's sh-reserved-words and
; sh-builtin-table name them.
(def sh-syntax-reserved-words
  (list "if" "then" "elif" "else" "fi"
        "while" "until" "for" "do" "done"
        "case" "in" "esac" "!" "{" "}"))

(def sh-syntax-builtins
  (list "[" "test" "echo" ":" "true" "false" "read" "shift" "set" "local"
        "return" "break" "continue" "cd" "export" "unset" "exit" "eval" "."
        "command" "getopts" "pwd" "readonly" "exec" "trap" "wait" "type"
        "source" "alias" "unalias" "hash"))

; A word is a run of the bytes no other token starts with: not a blank, an
; operator byte, a quote, $ or a backslash.  # starts a comment, not a word,
; and is a word's byte after its first.  A byte above 127 is a word's, read
; with either sign.
(def %sh-syntax-word-rest
  (list (pair 1 8) (pair 11 12) (pair 14 31) 33 35 37 (pair 42 58) 61
        (pair 63 91) (pair 93 95) (pair 97 123) (pair 125 255) (pair -128 -1)))
(def %sh-syntax-word-first
  (list (pair 1 8) (pair 11 12) (pair 14 31) 33 37 (pair 42 58) 61
        (pair 63 91) (pair 93 95) (pair 97 123) (pair 125 255) (pair -128 -1)))

(def %sh-syntax-name-first (list (pair 65 90) (pair 97 122) 95))
(def %sh-syntax-name-rest (list (pair 48 57) (pair 65 90) (pair 97 122) 95))

; The spans a double-quoted string or a ${...} holds, each
; (NAME CLOSE ESC OPENS), as ash/tokens.x reads them.
(def %sh-syntax-contexts
  (list
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
      (list (pair "'" (lit sq)) (pair "\"" (lit dq)) (pair "$(" (lit cmd))))
    (list (lit dsq) 39 92 ())))

; A number is a word of digits alone, listed before the word to win the tie.
(def %sh-syntax-rules
  (list
    (Lexer run (lit blank) " \t\r\n" " \t\r\n")
    (Lexer until (lit comment) "#" "\n" (lit to-end))
    (Lexer until (lit string) "'" "'" (lit take) (lit to-end))
    (Lexer nested (lit string) "$'" (lit dsq) %sh-syntax-contexts (lit to-end))
    (Lexer nested (lit string) "\"" (lit dq) %sh-syntax-contexts (lit to-end))
    (Lexer nested (lit expand) "${" (lit brace) %sh-syntax-contexts (lit to-end))
    (Lexer pattern (lit expand)
      (list (list "$" 1 1) (list %sh-syntax-name-first 1 1) (list %sh-syntax-name-rest 0 ())))
    (Lexer pattern (lit expand) (list (list "$" 1 1) (list "0123456789?#@*$!-" 1 1)))
    (Lexer escape (lit escape) 92)
    (Lexer table (lit op)
      (list ";" ";;" "&" "&&" "|" "||" "(" ")" "<" ">" "<<" ">>" "<&" ">&" "<>"
            ">|" "<<-" "$(" "$((" "`"))
    (Lexer run (lit number) (list (pair 48 57)) (list (pair 48 57)))
    (Lexer run (lit word) %sh-syntax-word-first %sh-syntax-word-rest)
    (Lexer any (lit other))))

(import x/core/doors str-byte-ref char->int str-byte-len int+ int-)

; The byte at i of s, or -1 past its end.
(def %sh-syntax-byte
  (fn (_ s i) (if (< i (str-byte-len s)) (char->int (str-byte-ref s i)) -1)))

(def %sh-syntax-name-byte?
  (fn (_ b)
    (match
      ((eq? b 95) #t)
      ((if (>= b 65) (<= b 90) #f) #t)
      (#t (if (>= b 97) (<= b 122) #f)))))

(def %sh-syntax-digit? (fn (_ b) (if (>= b 48) (<= b 57) #f)))

; Where the name starting at i of s ends.
(def %sh-syntax-name-end
  (fn (self s i)
    (let ((b (%sh-syntax-byte s i)))
      (if (if (%sh-syntax-name-byte? b) #t (%sh-syntax-digit? b))
        (self s (int+ i 1))
        i))))

; Where the } closing the ${ before i ends, or () when none does.
(def %sh-syntax-brace-end
  (fn (self s i depth)
    (let ((b (%sh-syntax-byte s i)))
      (match
        ((< b 0) ())
        ((eq? b 92) (self s (int+ i 2) depth))
        ((eq? b 123) (self s (int+ i 1) (int+ depth 1)))
        ((eq? b 125) (if (eq? depth 0) (int+ i 1) (self s (int+ i 1) (int- depth 1))))
        (#t (self s (int+ i 1) depth))))))

; Where the expansion at the $ at i of s ends: $NAME, $1, $? and the other
; specials, or ${...}.  () when the $ starts none.
(def %sh-syntax-expansion-end
  (fn (_ s i)
    (let ((b (%sh-syntax-byte s (int+ i 1))))
      (match
        ((%sh-syntax-name-byte? b) (%sh-syntax-name-end s (int+ i 2)))
        ((List includes? b (list 48 49 50 51 52 53 54 55 56 57 63 35 64 42 36 33 45))
          (int+ i 2))
        ((eq? b 123) (%sh-syntax-brace-end s (int+ i 2) 0))
        (#t ())))))

; acc with the string run from..to of the token on it, when it holds a byte.
(def %sh-syntax-run
  (fn (_ from to acc)
    (if (> to from) (pair (list from (int- to from) (lit string)) acc) acc)))

; A double-quoted string's pieces, reversed onto acc: the expansions in it
; are names, and the runs between them strings.  An escaped $ is the
; string's; a $ starting no expansion, $( among them, is too.
(def %sh-syntax-dq-walk
  (fn (self s i n from acc)
    (if (>= i n) (%sh-syntax-run from n acc)
      (let ((b (%sh-syntax-byte s i)))
        (match
          ((eq? b 92) (self s (int+ i 2) n from acc))
          ((eq? b 36)
            (let ((e (%sh-syntax-expansion-end s i)))
              (if (null? e) (self s (int+ i 1) n from acc)
                (self s e n e
                  (pair (list i (int- e i) (lit name)) (%sh-syntax-run from i acc))))))
          (#t (self s (int+ i 1) n from acc)))))))

; A double-quoted string with an expansion in it answers its pieces; any
; other string is one.
(def %sh-syntax-string-class
  (fn (_ text)
    (if (eq? (%sh-syntax-byte text 0) 34)
      (let ((ps (%sh-syntax-dq-walk text 0 (str-byte-len text) 0 ())))
        (if (null? (rest ps)) (lit string) (List reverse ps)))
      (lit string))))

; A word is a keyword when the shell reserves it or a builtin names it.  A
; word starting name= is an assignment, its name coloured and the rest of
; the word left plain.
(def %sh-syntax-word-class
  (fn (_ text)
    (match
      ((List includes? text sh-syntax-reserved-words) (lit keyword))
      ((List includes? text sh-syntax-builtins) (lit keyword))
      ((not (%sh-syntax-name-byte? (%sh-syntax-byte text 0))) ())
      (#t
        (let ((e (%sh-syntax-name-end text 1)))
          (if (eq? (%sh-syntax-byte text e) 61) (list (list 0 e (lit name))) ()))))))

; A line starting with a name, a comment or a closing brace is taken to start
; outside any string, so spans need not read the script from its top.  A
; multi-line quoted string with such a line in it colours inverted from that
; line to the end of the window, as other editors' shell grammars do.

(def %sh-syntax-sync
  (fn (_ s ls)
    (if (>= ls (str-byte-len s)) #f
      (let ((b (char->int (str-byte-ref s ls))))
        (match
          ((List includes? b (list 35 95 125)) #t)
          ((if (>= b 65) (<= b 90) #f) #t)
          (#t (if (>= b 97) (<= b 122) #f)))))))

(Syntax register!
  (let ((g (Syntax make (lit sh) %sh-syntax-rules
             (list (pair (lit comment) (lit comment))
                   (pair (lit string) %sh-syntax-string-class)
                   (pair (lit expand) (lit name))
                   (pair (lit escape) (lit escape))
                   (pair (lit op) (lit operator))
                   (pair (lit number) (lit number))
                   (pair (lit word) %sh-syntax-word-class)))))
    (g sync %sh-syntax-sync)
    g))

(provide ash/syntax sh-syntax-reserved-words sh-syntax-builtins)
