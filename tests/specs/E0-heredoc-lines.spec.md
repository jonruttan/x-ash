## sh-eval here-documents read in whole runs

Every line of a script holding a here-document is looked at for `<<`, and a
body is taken line by line, so both walks keep their cost per character low: a
text is cut into lines on the integer doors, a run of characters that change
nothing is passed over in one walk and a line made only of them passes whole,
a single-quoted region is passed in one scan for its quote, and a body is
joined once.

The first two cases compare a pass with the scan for `<<` that every text the
shell reads is given first: extracting the here-documents of a script of 1,000
ordinary lines costs under ten such scans (58 on main), and a body of 1,000
lines under 25 (43 on main).  They measure the walk by hand, so they hold the
compiled line base off (E1 holds that base to the walk).  The rest are pins that hold on main too, on the
states the scan keeps: a `#` in a word, a comment, a quoted `<<`, a quote over
a line end, a substitution, a pipeline, double quotes.  Expectations from
`/bin/sh` and `dash`.

### a script of 1,000 lines costs less than ten scans for `<<`

```sh
(do
  (def cost (fn (_ th) (do (def c (Heap count)) (th) (- (Heap count) c))))
  (def base (cost (fn (_) ())))
  (def script (string-append (Str8 repeat 1000 "echo hello world\n") "cat <<EOF\nx\nEOF\n"))
  (def held %sh-hd-jit-threshold)
  (set! %sh-hd-jit-threshold 100000000)
  (def scan (- (cost (fn (_) (%sh-str-has-heredoc-op? script))) base))
  (def extract (- (cost (fn (_) (%sh-heredoc-extract script))) base))
  (set! %sh-hd-jit-threshold held)
  (write (fx<? extract (fx* 10 scan)))
  ())
```
---
    #t

### a body of 1,000 lines costs less than twenty-five scans of it

```sh
(do
  (def cost (fn (_ th) (do (def c (Heap count)) (th) (- (Heap count) c))))
  (def base (cost (fn (_) ())))
  (def body (string-append "cat <<'EOF'\n" (Str8 repeat 1000 "a\n") "EOF\n"))
  (def held %sh-hd-jit-threshold)
  (set! %sh-hd-jit-threshold 100000000)
  (def scan (- (cost (fn (_) (%sh-has-pair? body 12 (string-length body) #\< #\<))) base))
  (def extract (- (cost (fn (_) (%sh-heredoc-extract body))) base))
  (set! %sh-hd-jit-threshold held)
  (write (fx<? extract (fx* 25 scan)))
  ())
```
---
    #t

### a `#` inside a word is no comment

```sh
(do (sh-eval "( printf '%s,' a#b; cat <<EOF\nbody-after-word-hash\nEOF\n)") ())
```
---
    a#b,body-after-word-hash

### a `<<` in a comment opens nothing

```sh
(do (sh-eval "( : a comment follows # <<EOF\necho not-a-body\n)") ())
```
---
    not-a-body

### a `<<` in single quotes is text

```sh
(do (sh-eval "( echo '<<EOF' | tr -d '<'; cat <<END\nquoted-op-is-text\nEND\n)") ())
```
---
    quoted-op-is-text

### a single-quoted string over a line end keeps its `<<` text

```sh
(do (sh-eval "( echo 'a\n<<EOF b' | tr '\\n' ,; echo; cat <<END\nspanning-quote\nEND\n)") ())
```
---
    spanning-quote

### a here-document inside a command substitution

```sh
(do (sh-eval "( x=$(cat <<EOF\nin-subst\nEOF\n); echo \"[$x]\"\n)") ())
```
---
    [in-subst]

### a body of plain lines into a pipeline

```sh
(do (sh-eval "( cat <<EOF | tr a-z A-Z\nplain line one\nplain line two\nEOF\n)") ())
```
---
    PLAIN LINE TWO

### a `<<` in double quotes is text

```sh
(do (sh-eval "( echo \"a <<b\" && cat <<EOF\ndq-op-is-text\nEOF\n)") ())
```
---
    dq-op-is-text
