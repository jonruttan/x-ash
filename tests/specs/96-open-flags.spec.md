## sh-eval a redirection's open flags

Each open a redirection makes -- to read, to write, to append, to read and
write, to create only, and to write an existing file as it is -- has its
flags ORed together once, from the platform's table `(File file-modes)`,
and hands `File open` the number.  What each open does is the redirection
specs' to show (spec 87 among them); here the flags are numbers, and an open
with the number costs less than one with the names, which `File open` folds
at every call.

### every open's flags are a number

```sh
(write (map number? (list %sh-o-read %sh-o-write %sh-o-append %sh-o-rdwr %sh-o-new %sh-o-existing)))
```
---
    (#t #t #t #t #t #t)

### an open with the number costs less than one with the names

```sh
(let ((cost (fn (_ thunk)
              (let ((before (Heap count))) (thunk) (- (Heap count) before)))))
  (< (cost (fn (_) (sh-close (sh-open-write "/dev/null"))))
     (cost (fn (_) (sh-close (%file-open File "/dev/null" (list (lit wronly) (lit creat) (lit trunc)) 438))))))
```
---
    #t
