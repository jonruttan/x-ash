## sh-tokenize reads through the platform's Lexer

ash/tokens.x reads a text with a Lexer (x/reader/lexer): the shell's rules,
compiled when the assembler lane is open.  A word that is one quoted string
is a tok-sq or tok-dq with its quotes gone; a word that holds more, or a
double-quoted string with a `"` inside a substitution, is a tok-word, raw.  A
span still open at the end of the text is the word to the end.

### a quoted string, and a word that holds one, to the end of the text

```sh
(map sh-tokenize
  (list "'a'" "'a' " "'a'b" "\"a\"" "\"a\"b c" "a'b'" "'a''b'" "'a'\\'" "'a'\"b'"
        "\"a\"'b" "'a'$(b '" "'a'`b" "\"a $(b \"c\") d\"" "\"a $(b) d\"" "\"a\\\"b\"" "''" "\"\"x"))
```
---
    (((tok-sq "a")) ((tok-sq "a")) ((tok-word "'a'b")) ((tok-dq "a")) ((tok-word "\"a\"b") (tok-word "c")) ((tok-word "a'b'")) ((tok-word "'a''b'")) ((tok-word "'a'\\'")) ((tok-word "'a'\"b'")) ((tok-word "\"a\"'b")) ((tok-word "'a'$(b '")) ((tok-word "'a'`b")) ((tok-word "\"a $(b \"c\") d\"")) ((tok-dq "a $(b) d")) ((tok-dq "a\\\"b")) ((tok-sq "")) ((tok-word "\"\"x")))

### words, operators, descriptors, comments and open spans

A descriptor is digits read only against `<` or `>`; `#` opens a comment
where a token starts and is a byte inside a word.

```sh
(map sh-tokenize
  (list "" " " "a" "a b" ": a b c; x=1; echo x >/dev/null\n"
    "echo 'q' \"d\" $x ${y:-a b} $(sub 'z' \")\") `bt x` $((1+2))\n"
    "a'b'c \"d\"e f\"g h\"i 'j k'l\n" "x=\"a $y\" z='1 2'\n"
    "a\\ b \; \\$x \"e\\\"f\" 'g'\\''h'\n" "# comment\necho a#b # c\n"
    "a|b||c&d&&e;f;;g<h<<i<<-j>k>>l<&m>&n<>o>|p(q)r>>-s<|t\n"
    "2>err 1<in 10>>x echo 2 >out 12abc 3rd -0 +5 -007 -a --x - -lt 50$ 7'q' 8\"r\"\n"
    "if [ $i -lt 50 ]; then i=$((i+1)); fi\nfor f in a b; do echo $f; done\n"
    "case $x in a*) y=1;; *) y=2;; esac\nf() { local v=$1; }\n"
    "\"unterminated" "'unterminated" "$(unterminated" "${unterminated" "`unterminated"
    "a\\" "\"a $(b \"c\" 'd') e\" \"${f:-\"g\"}\" \"`h`\" \"$$ $\"\n"
    "tab\tsep\t\tx\n\n\n  lead" "a$" "$" "$b$c" "1$" "1`x`" "1\;2" "<" ">>" "<<-" "&" "("))
```
---
    (() () ((tok-word "a")) ((tok-word "a") (tok-word "b")) ((tok-word ":") (tok-word "a") (tok-word "b") (tok-word "c") (tok-op ";") (tok-word "x=1") (tok-op ";") (tok-word "echo") (tok-word "x") (tok-op ">") (tok-word "/dev/null") (tok-newline)) ((tok-word "echo") (tok-sq "q") (tok-dq "d") (tok-word "$x") (tok-word "${y:-a b}") (tok-word "$(sub 'z' \")\")") (tok-word "`bt x`") (tok-word "$((1+2))") (tok-newline)) ((tok-word "a'b'c") (tok-word "\"d\"e") (tok-word "f\"g h\"i") (tok-word "'j k'l") (tok-newline)) ((tok-word "x=\"a $y\"") (tok-word "z='1 2'") (tok-newline)) ((tok-word "a\\ b") (tok-word "\\;") (tok-word "\\$x") (tok-dq "e\\\"f") (tok-word "'g'\\''h'") (tok-newline)) ((tok-newline) (tok-word "echo") (tok-word "a#b") (tok-newline)) ((tok-word "a") (tok-op "|") (tok-word "b") (tok-op "||") (tok-word "c") (tok-op "&") (tok-word "d") (tok-op "&&") (tok-word "e") (tok-op ";") (tok-word "f") (tok-op ";;") (tok-word "g") (tok-op "<") (tok-word "h") (tok-op "<<") (tok-word "i") (tok-op "<<-") (tok-word "j") (tok-op ">") (tok-word "k") (tok-op ">>") (tok-word "l") (tok-op "<&") (tok-word "m") (tok-op ">&") (tok-word "n") (tok-op "<>") (tok-word "o") (tok-op ">|") (tok-word "p") (tok-op "(") (tok-word "q") (tok-op ")") (tok-word "r") (tok-op ">>") (tok-word "-s") (tok-op "<") (tok-op "|") (tok-word "t") (tok-newline)) ((tok-io "2") (tok-op ">") (tok-word "err") (tok-io "1") (tok-op "<") (tok-word "in") (tok-io "10") (tok-op ">>") (tok-word "x") (tok-word "echo") (tok-word "2") (tok-op ">") (tok-word "out") (tok-word "12abc") (tok-word "3rd") (tok-word "-0") (tok-word "+5") (tok-word "-007") (tok-word "-a") (tok-word "--x") (tok-word "-") (tok-word "-lt") (tok-word "50$") (tok-word "7'q'") (tok-word "8\"r\"") (tok-newline)) ((tok-word "if") (tok-word "[") (tok-word "$i") (tok-word "-lt") (tok-word "50") (tok-word "]") (tok-op ";") (tok-word "then") (tok-word "i=$((i+1))") (tok-op ";") (tok-word "fi") (tok-newline) (tok-word "for") (tok-word "f") (tok-word "in") (tok-word "a") (tok-word "b") (tok-op ";") (tok-word "do") (tok-word "echo") (tok-word "$f") (tok-op ";") (tok-word "done") (tok-newline)) ((tok-word "case") (tok-word "$x") (tok-word "in") (tok-word "a*") (tok-op ")") (tok-word "y=1") (tok-op ";;") (tok-word "*") (tok-op ")") (tok-word "y=2") (tok-op ";;") (tok-word "esac") (tok-newline) (tok-word "f") (tok-op "(") (tok-op ")") (tok-word "{") (tok-word "local") (tok-word "v=$1") (tok-op ";") (tok-word "}") (tok-newline)) ((tok-word "\"unterminated")) ((tok-word "'unterminated")) ((tok-word "$(unterminated")) ((tok-word "${unterminated")) ((tok-word "`unterminated")) ((tok-word "a\\")) ((tok-word "\"a $(b \"c\" 'd') e\"") (tok-word "\"${f:-\"g\"}\"") (tok-dq "`h`") (tok-dq "$$ $") (tok-newline)) ((tok-word "tab") (tok-word "sep") (tok-word "x") (tok-newline) (tok-newline) (tok-newline) (tok-word "lead")) ((tok-word "a$")) ((tok-word "$")) ((tok-word "$b$c")) ((tok-word "1$")) ((tok-word "1`x`")) ((tok-word "1\\;2")) ((tok-op "<")) ((tok-op ">>")) ((tok-op "<<-")) ((tok-op "&")) ((tok-op "(")))

### a script runs through it

```sh
(do
  (def script "g8_out=$( g8_n=0; for g8_i in 1 2 3; do g8_n=$((g8_n+g8_i)); done; g8_f() { echo \"$1:$g8_n\" 'q r' ${g8_u:-d e} `echo bt`; }; g8_f a | tr a A; if [ \"$g8_n\" = 6 ]; then echo six; fi; [ $g8_n -lt 7 ] && echo less >&2 2>/dev/null; echo done )")
  (sh-eval script)
  (%sh-var-get "g8_out"))
```
---
    "A:6 q r d e bt\nsix\ndone"

### a child reads with the lexer its parent made

```sh
(do
  (sh-tokenize "x")
  (def pid (sh-fork))
  (if (= pid 0)
    (guard (e (do (display "error: ") (write e) (newline) (sh-exit 5)))
      (write (sh-tokenize "a 'b' 2>c"))
      (newline)
      (sh-exit 7))
    (sh-wait pid))
  ())
```
---
    ((tok-word "a") (tok-sq "b") (tok-io "2") (tok-op ">") (tok-word "c"))
