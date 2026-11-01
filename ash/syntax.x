; # x-ash -- a POSIX shell on x-lang
;
; ## ash/syntax.x -- the sh highlighting grammar
;
; @description The grammar x/tool/syntax colours shell scripts with: comments,
;   quoted strings, parameter expansions, numbers, and the reserved words and
;   builtins as keywords.
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
; string token with the expansions inside it, and a here-document's body is
; read as shell.  Outside a string, $NAME, $1, $? and ${...} are each an
; expansion, and $( and ` are operators whose commands are read as any other.

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

(def %sh-syntax-word-class
  (fn (_ text)
    (if (if (List includes? text sh-syntax-reserved-words) #t
          (List includes? text sh-syntax-builtins))
      (lit keyword)
      ())))

; A line starting with a name, a comment or a closing brace is taken to start
; outside any string, so spans need not read the script from its top.  A
; multi-line quoted string with such a line in it colours inverted from that
; line to the end of the window, as other editors' shell grammars do.
(def %sh-syntax-bref (prim-ref (lit str) (lit byte-ref)))
(def %sh-syntax-cint (prim-ref (lit char) (lit ->int)))
(def %sh-syntax-blen (prim-ref (lit str) (lit byte-len)))

(def %sh-syntax-sync
  (fn (_ s ls)
    (if (>= ls (%sh-syntax-blen s)) #f
      (let ((b (%sh-syntax-cint (%sh-syntax-bref s ls))))
        (match
          ((List includes? b (list 35 95 125)) #t)
          ((if (>= b 65) (<= b 90) #f) #t)
          (#t (if (>= b 97) (<= b 122) #f)))))))

(Syntax register!
  (let ((g (Syntax make (lit sh) %sh-syntax-rules
             (list (pair (lit comment) (lit comment))
                   (pair (lit string) (lit string))
                   (pair (lit expand) (lit name))
                   (pair (lit escape) (lit escape))
                   (pair (lit op) (lit operator))
                   (pair (lit number) (lit number))
                   (pair (lit word) %sh-syntax-word-class)))))
    (g sync %sh-syntax-sync)
    g))

(provide ash/syntax sh-syntax-reserved-words sh-syntax-builtins)
