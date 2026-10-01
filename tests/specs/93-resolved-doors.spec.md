## sh-eval the platform's doors, resolved once

Each platform method the shell calls -- Sys's process, descriptor and
environment doors, File's stats, Assoc's entry -- is resolved once when the
shell loads, through method-of, and called directly after.  A call through
the class finds its method in the class's table every time, and calls that
alternate between two methods of one class pay for the finding at each call.
A redirection's open and the shell's close go through the syscall doors File
makes those calls through, resolved once the same way.

### every door resolves

```sh
((fn (self ds) (match ((null? ds) #t) ((null? (first ds)) ()) (#t (self (rest ds)))))
 (list %sys-fork %sys-exec %sys-wait %sys-exit %sys-getpid %sys-dup2
       %sys-pipe %sys-getenv %sys-setenv %sys-unsetenv %sys-chdir %sys-getcwd
       %sys-fd-read %sys-fd-write %file-stat %file-lstat
       %file-read-all %file-list-dir %assoc-entry %sh-sys-open %sh-sys-close))
```
---
    #t

### a resolved door is the class's own method

```sh
(same? %sys-dup2 (method-of Sys (lit dup2)))
```
---
    #t
