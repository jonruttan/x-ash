## sh-eval word expansion in the cheapest forms

IFS is kept once found, since every unquoted expansion asks for it and a
variable is found by walking the shell's variables and then the environment.
Setting or unsetting a variable, which every change of IFS goes through,
empties what was kept.  The run of a word's plan, field splitting and the
accumulator a word is built in are written in the forms that allocate least,
with no closure made for a step of the plan.

The first four cases are pins that hold on main too; their expectations match
`/bin/sh` and `dash`.  The costs are compared rather than counted.

### IFS as each change leaves it

`a:b:c d` is two fields on the default IFS and three on `:`.

```sh
(do (sh-eval "( v='a:b:c d'; set -- $v; printf %s $#; IFS=:; set -- $v; printf %s $#; unset IFS; set -- $v; printf %s $#; f() { local IFS=' '; set -- $v; printf %s $#; }; IFS=:; f; set -- $v; printf %s $#; echo )") ())
```
---
    23223

### for one command, and for a special one

```sh
(do (sh-eval "( v='a:b:c d'; IFS=: read x y <<EOF\n1:2\nEOF\necho \"$x/$y\"; set -- $v; echo $#; IFS=: eval 'set -- $v'; echo $#; set -- $v; echo $# ) | tr '\\n' ','; echo") ())
```
---
    1/2,2,3,3,

### quoting

```sh
(do (sh-eval "( x=abc; y='a b'; z=; echo \"$x\" '$x' \\$x \"a\\\"b\" \"$y\" $y \"[$z]\" [$z] )") ())
```
---
    abc $x $x a"b a b a b [] []

### parameter operators

```sh
(do (sh-eval "( u=; x=val; p=/a/b/c.txt; echo ${u:-def} ${u-set} ${x:+alt} ${p#*/} ${p##*/} ${p%/*} ${#p} \"${x}s\" )") ())
```
---
    def alt a/b/c.txt c.txt /a/b 10 vals

### IFS asked again costs less than one comparison

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (%sh-ifs)
  (< (cost (fn (_) (%sh-ifs))) (cost (fn (_) (>= 5 1)))))
```
---
    #t

### splitting a value with nothing to split costs less than two comparisons

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (%sh-ifs)
  (< (cost (fn (_) (%sh-add-split %sh-acc-empty "5")))
     (cost (fn (_) (do (>= 5 1) (>= 5 1))))))
```
---
    #t

### expanding `$i` costs less than five comparisons

The variables are restored afterwards, so `i` is set for this case alone.  The
token is expanded once before it is measured, so it holds its plan, as a word
in a loop's body does after the first time round.

```sh
(let ((saved %sh-vars)
      (cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before))))
      (tok (first (sh-tokenize "$i"))))
  (%sh-var-set! "i" "5")
  (%sh-ifs)
  (%sh-expand-tok tok ())
  (let ((got (< (cost (fn (_) (%sh-expand-tok tok ())))
                (cost (fn (_) (do (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1) (>= 5 1)))))))
    (set! %sh-vars saved)
    got))
```
---
    #t
