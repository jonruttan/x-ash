## sh-eval the platform's doors, resolved once

Each platform method the shell calls -- Sys's process, descriptor and
environment doors, File's opens and stats, Assoc's entry -- is resolved once
when the shell loads, through method-of, and called directly after.  A call
through the class finds its method in the class's table every time, and
calls that alternate between two methods of one class, as a redirection's
dup2 and close do, pay for the finding at each call.

### every door resolves

```sh
((fn (self ds) (match ((null? ds) #t) ((null? (first ds)) ()) (#t (self (rest ds)))))
 (list %sys-fork %sys-exec %sys-wait %sys-exit %sys-getpid %sys-close %sys-dup2
       %sys-pipe %sys-getenv %sys-setenv %sys-unsetenv %sys-chdir %sys-getcwd
       %sys-fd-read %sys-fd-write %file-open %file-stat %file-lstat
       %file-read-all %file-list-dir %assoc-entry))
```
---
    #t

### a resolved door is the class's own method

```sh
(same? %sys-dup2 (method-of Sys (lit dup2)))
```
---
    #t
