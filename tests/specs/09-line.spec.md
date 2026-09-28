## ash/line -- the line editor's seams

The editor carries no grammar. The shell fills its two seams: `%ash-paint`
displays a line with the tokenizer's own verdicts on words, operators and
strings, and `%ash-complete` answers a word by where it stands: a command from
the reserved words, the builtins and the executables on PATH, and an argument
or a redirection target as a path, by the shell's own globbing.

### with no terminal, painting returns the line unchanged

```sh
(do (import ash/line) (let ((s "if true; then echo \"a b\"; fi # c")) (Str8 =? (%ash-paint s) s)))
```
---
    #t

The completer reads the buffer through one method, `before`, the text to the
left of the cursor; a stand-in with that method is enough to test it, and
lets these cases run on a platform that has no editor to build a buffer with.

### the word being completed ends at the cursor and starts after a separator

```sh
(do (import ash/line)
    (def-class %spec-buf () text (method before (self) (member (lit text))))
    (%ash-word-at (new %spec-buf text "echo one | gre")))
```
---
    "gre"

### a reserved word and a builtin complete from their own tables

```sh
(do (import ash/line)
    (let ((r (%ash-complete (new %spec-buf text "whi"))))
      (list (first r) (List includes? "while" (rest r)))))
```
---
    ("whi" #t)

### an empty word offers nothing

```sh
(do (import ash/line)
    (%ash-complete (new %spec-buf text "")))
```
---
    ("")

### where the word stands: a command, an argument to one, or a redirection target

The shell's own tokens for the text before the word decide it, so a reserved
word counts only where a command would stand.

```sh
(do (import ash/line)
    (List map (fn (_ s) (let ((p (%ash-word-place s))) (list (symbol->str (first p)) (rest p))))
      (list "" "ls " "echo a | " "if " "cat < " "echo if " "cd " "(cd a; ")))
```
---
    (("command" ()) ("argument" "ls") ("command" ()) ("command" ()) ("redirect" "cat") ("argument" "echo") ("argument" "cd") ("command" ()))

The path cases complete inside a directory made for this file alone: `sfile`,
`.hidden`, and the directories `src` and `sub`.  Its random name is cut from
each answer so the expectations do not depend on it.

### an argument completes as a file or a directory, and a directory ends in /

```sh
(do (import ash/line) (import x/sys/file)
    (def %spec-tmp (File temp "/tmp/x-ash-complete-"))
    (File close (first %spec-tmp))
    (File unlink (rest %spec-tmp))
    (def %spec-dir (rest %spec-tmp))
    (File mkdir %spec-dir)
    (File mkdir (Str8 append %spec-dir "/src"))
    (File mkdir (Str8 append %spec-dir "/sub"))
    (File write-all (Str8 append %spec-dir "/sfile") "")
    (File write-all (Str8 append %spec-dir "/.hidden") "")
    (def %spec-cut
      (fn (_ r) (List map (fn (_ n) (Str8 sub (Str8 length %spec-dir) (Str8 length n) n)) (rest r))))
    (%spec-cut (%ash-complete (new %spec-buf text (Str8 append "ls " (Str8 append %spec-dir "/s"))))))
```
---
    ("/sfile" "/src/" "/sub/")

### cd's argument completes as a directory only

```sh
(%spec-cut (%ash-complete (new %spec-buf text (Str8 append "cd " (Str8 append %spec-dir "/s")))))
```
---
    ("/src/" "/sub/")

### a dotfile is offered only to a word that starts with a dot

```sh
(list (%spec-cut (%ash-complete (new %spec-buf text (Str8 append "ls " (Str8 append %spec-dir "/")))))
      (%spec-cut (%ash-complete (new %spec-buf text (Str8 append "ls " (Str8 append %spec-dir "/."))))))
```
---
    (("/sfile" "/src/" "/sub/") ("/.hidden"))

### a redirection target completes as a path, and so does a command holding a /

```sh
(list (%spec-cut (%ash-complete (new %spec-buf text (Str8 append "echo x > " (Str8 append %spec-dir "/sf")))))
      (%spec-cut (%ash-complete (new %spec-buf text (Str8 append %spec-dir "/sf")))))
```
---
    (("/sfile") ("/sfile"))

### a word with nothing to match offers nothing

```sh
(null? (rest (%ash-complete (new %spec-buf text (Str8 append "ls " (Str8 append %spec-dir "/zz"))))))
```
---
    #t

### a relative word completes from the directory cd moved to

```sh
(do (sh-eval (Str8 append "cd " %spec-dir))
    (let ((r (%ash-complete (new %spec-buf text "ls s"))))
      (sh-eval "cd - >/dev/null")
      r))
```
---
    ("s" "sfile" "src/" "sub/")

### a word starting ~/ is looked up under HOME and offered as typed

```sh
(let ((home (%sh-var-get "HOME")))
  (sh-eval (Str8 append "HOME=" %spec-dir))
  (let ((r (%ash-complete (new %spec-buf text "ls ~/s"))))
    (sh-eval (Str8 append "HOME=" home))
    r))
```
---
    ("~/s" "~/sfile" "~/src/" "~/sub/")

### the directory made for these cases is removed

```sh
(do (File unlink (Str8 append %spec-dir "/sfile"))
    (File unlink (Str8 append %spec-dir "/.hidden"))
    (File rmdir (Str8 append %spec-dir "/src"))
    (File rmdir (Str8 append %spec-dir "/sub"))
    (File rmdir %spec-dir)
    (File exists? %spec-dir))
```
---
    #f
