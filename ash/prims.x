; # x-ash -- a POSIX shell on x-lang
;
; ## ash/prims.x -- the platform layer, under the names ash was written against
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; ash reaches past x-lang in two directions -- it registers its own tokenizer
; types on an isolated base, and it forks, execs and dup2s -- and both surfaces
; moved onto classes since 2024.  Neither moved far.
;
; THE ARCHITECTURE SURVIVED INTACT, which is the headline.  ash tokenizes shell
; syntax on a SEPARATE BASE with its own type alist, so that `;` can be a
; separator rather than a comment and `#` a comment rather than a dispatch
; character.  That design needed `make-token-base` and `base-make-type`, and
; the obvious reading of their disappearance is that the platform stopped
; supporting isolated tokenizer bases.  It did not: they are (Base make-tok)
; and (Base make-type), documented in as many words --
;
;   "Create a minimal tokenizer base ... For custom tokenizer type
;    registration on an isolated base."
;
; -- so the single most unusual thing in this bundle is still first-class.
;
; ONE FILE, so the two files above this one stay readable as what they are: a
; tokenizer and a shell.

; THE DIALECT IS HELIUM, so the doors this file forwards to arrive by NAME.
; lang.xon carries the arithmetic; the operative half is here.  x/sys/posix is
; the Sys class -- fork, exec, wait, pipe, dup2, the open family, getenv and
; chdir -- and importing it at the top of the platform layer is what makes an
; unsatisfiable requirement fail at ACQUISITION rather than at the first
; pipeline.  Base, Str8, Io and List are core; only this one is an opt-in.
(import x/sys/posix)
; x/sys/file is the File class: stat (which is what `test -f` and `test -d`
; actually ask) and read-all (which is what `.` needs to source a script).
; Sys alone answers only "does this path exist", and a shell that cannot tell
; a directory from a file has no working `test`.
(import x/sys/file)

(provide ash/prims
  make-token-base base-make-type token-read-string
  first-int set-first-int! convert buffer-token
  char->integer integer->char string-length string-ref substring string-append
  string=? string? make-string list->string length reverse append map filter
  sh-fork sh-exec sh-wait sh-exit sh-getpid
  sh-open-read sh-open-write sh-open-append sh-close sh-dup2 sh-pipe
  sh-getenv sh-setenv sh-unsetenv sh-chdir sh-getcwd
  sh-path-kind sh-path-size sh-read-file sh-read-line sh-read-line-fd)

; --- The tokenizer base ------------------------------------------------------
; (Base make-tok) is the isolated, type-free tokenizer base -- the exact
; successor to 2024's make-token-base, and the reason ash's `;` can be a
; separator rather than a comment.
;
; IT SEGFAULTS ON THE FIRST CHARACTER OF ANY INPUT (x-lang#528).  This bundle
; does not work today, and that is recorded rather than dodged: the alternative
; is (Base make), which arrives with the built-in sexp types already registered
; so shell tokens compete with them by score -- `a b` tokenizes as a bare
; symbol followed by a word, `a|b` as one word, and ash's own INTEGER type
; collides with the platform's.  A shell that reports the wrong tokens is not a
; shell, and a green suite bought that way would be a lie about the port.
;
; So the faithful call stays, and the bundle is blocked.
(def make-token-base (fn (_) (Base make-tok)))

; (Base make-type TARGET NAME HANDLERS) -- cross-base registration, which is
; exactly what base-make-type was.  The name is a STRING now; ash passes
; strings already.
(def base-make-type
  (fn (_ base name handlers) (Base make-type base name handlers)))

; (prim-ref 'tok 'read-str), the same reference lib/x/repl/ansi.x and
; lib/x/reader/lit-reader.x hold -- but it takes the RAW base, and (Base
; make-tok) hands back a wrapped instance.  Pass the instance and the prim
; SEGFAULTS rather than refusing, on any input including "".  So the unwrap
; lives here, once, and the two files above never see the distinction.
; Reported as x-lang#528.
(def %token-read-str (prim-ref (lit tok) (lit read-str)))
(def token-read-string
  (fn (_ base input) (%token-read-str (Base raw-of base) input)))

; The consumed token's text, inside a reader callback.  (prim-ref 'buf 'tok)
; -- note the namespace is `buf` and the member is `tok`, not the `token` the
; 2024 name suggests.  Unbound, this raises INSIDE a tokenizer callback, which
; is a segfault rather than a message.
(def buffer-token (prim-ref (lit buf) (lit tok)))

; --- Tokenizer int cells -----------------------------------------------------
; THESE ARE REAL C CELLS, so the raw-word accessors are correct here.  The
; tokenizer's buffer and score are built by the engine, and %cell-int /
; %set-cell-int! read and write the machine word in their first slot -- which
; is what first-int / set-first-int! did.
;
; Worth being explicit, because the same two names are a heap-corrupting
; mistake when applied to an ordinary (list 0): slot 0 of a pair holds an
; object POINTER, and the next collection traces the integer as an address
; (x-lang#522).  The distinction is which object you have, and here it is the
; engine's.
(def first-int %cell-int)
(def set-first-int! %set-cell-int!)

; --- convert -----------------------------------------------------------------
; NO EXPLICIT RECEIVER: every call fills the `_` slot implicitly, `apply`
; included, so passing one by hand shifts every argument along and the
; conversion silently answers nil.
(def %cvt (prim-ref (lit convert) (lit to)))
(def convert (fn (_ v target . extra) (apply %cvt (pair v (pair target extra)))))

; The handful of Scheme-ish names ash reaches for.  It is not a Scheme -- there
; is no alias layer here -- so these are only what tokens.x and eval.x actually
; call, spelled through the classes that own them now.
; THE DIRECT PRIM, NOT THE CONVERT DISPATCHER, and the difference is a crash.
; (%cvt c %int) walks the type's from/to alists and allocates; char->integer is
; called SIX TIMES PER CHARACTER from %sh-word-break?, inside a tokenizer
; callback -- where the 2024 file's own note warns that allocation triggers a
; collection mid-token.  Adding SH-WORD to the base was enough to kill
; (sh-tokenize " ") with the dispatching version.
;
; lib/x/reader/analyser.x holds the same reference for the same reason:
;   (def %char->integer (prim-ref (lit char) (lit ->int)))
(def char->integer (prim-ref (lit char) (lit ->int)))
; NOTE THE NAMESPACE: conversions are keyed on the SOURCE type, so the pair is
; (char ->int) and (int ->char).  (char from-int) exists as a Char METHOD but
; not as a catalog member, and prim-ref answers nil for a member that is not
; there -- which reaches the reader as a garbage int rather than an error.
(def integer->char (prim-ref (lit int) (lit ->char)))
(def string-length (fn (_ s) (Str8 length s)))
(def string-ref (fn (_ s i) (Str8 ref i s)))
; Scheme's substring is [start, end); Str8 sub is (start, LENGTH).
(def substring (fn (_ s a b) (Str8 sub a (- b a) s)))
(def string-append (fn (_ . ss) (%ash-str-append ss)))
(def %ash-str-append
  (fn (self ss)
    (if (null? ss)
      ""
      (if (null? (rest ss)) (first ss) (Str8 append (first ss) (self (rest ss)))))))
(def string=? (fn (_ a b) (str=? a b)))
(def string? (fn (_ s) (str? s)))
(def make-string (fn (_ n c) (Str8 make n c)))
(def list->string (fn (_ l) (if (null? l) "" (%cvt l %string))))

; REVERSE AND list->string RUN INSIDE READER CALLBACKS, so neither may be a
; class dispatch.  lib/x/reader/analyser.x states the rule outright: reader
; context callers "must fetch them raw ... NOT (Analyser accept ...) (class
; dispatch allocates, hazardous mid-reader-callback)".
;
; (List reverse ...) is exactly such a dispatch, and ash's quoted-string
; readers call reverse and list->string at the closing quote.  With the
; dispatching version '' tokenized fine and 'a' produced (tok-sq ()) -- the
; accumulation silently became nil, with no error.  Plain recursion over the
; pair prims allocates one cons per element and dispatches nothing.
(def reverse
  (fn (self l) (%ash-rev l ())))
(def %ash-rev
  (fn (self l acc)
    (if (null? l) acc (self (rest l) (pair (first l) acc)))))

(def length (fn (_ l) (List length l)))
(def append (fn (_ a b) (List append a b)))
(def map (fn (_ f l) (List map f l)))
(def filter (fn (_ p l) (List filter p l)))
(def take (fn (_ n l) (List take n l)))
(def drop (fn (_ n l) (List drop n l)))
(def nth (fn (_ n l) (List ref n l)))
(def set-first! %set-first!)

; --- The shell's syscalls ----------------------------------------------------
; ash named these sh-* in 2024 over lib/x/posix.x's bare wrappers.  posix.x is
; lib/x/sys/posix.x now and publishes only %-private FFI handles; the public
; surface is the Sys class, which carries every one of them under a name a
; shell would recognise.  So these are one-line forwards, and the sh- prefix is
; kept because eval.x reads better for it: `(sh-dup2 fh fd)` in a redirection
; is the shell's vocabulary, not the platform's.
(def sh-fork (fn (_) (Sys fork)))
(def sh-exec (fn (_ path args) (Sys exec path args)))
(def sh-wait (fn (_ pid) (Sys wait pid)))
(def sh-exit (fn (_ status) (Sys exit status)))
(def sh-getpid (fn (_) (Sys getpid)))

(def sh-open-read (fn (_ path) (Sys open-read path)))
(def sh-open-write (fn (_ path) (Sys open-write path)))
(def sh-open-append (fn (_ path) (Sys open-append path)))
(def sh-close (fn (_ fd) (Sys close fd)))
(def sh-dup2 (fn (_ from to) (Sys dup2 from to)))

; (Sys pipe) answers a (read-fd . write-fd) pair, which is what ash's
; %sh-pipe-create expects -- the 2024 sh-pipe had the same shape.
(def sh-pipe (fn (_) (Sys pipe)))

(def sh-getenv (fn (_ name) (Sys getenv name)))
(def sh-setenv (fn (_ name value) (Sys setenv name value)))
(def sh-chdir (fn (_ dir) (Sys chdir dir)))

(def sh-unsetenv (fn (_ name) (Sys unsetenv name)))
(def sh-getcwd (fn (_) (Sys getcwd)))

; --- What `test` needs to know about a path ------------------------------
; The kind symbol ('file, 'dir, 'link, ...) or nil when the path is not there
; at all -- so one call answers -e, -f and -d, and a missing path is a nil
; rather than a raise.  File stat raises a kind-'io Err on failure, which for
; a shell test is an ANSWER, not an error.
(def sh-path-kind
  (fn (_ path) (guard (_ ()) (rest (Assoc entry (lit kind) (File stat path))))))

(def sh-path-size
  (fn (_ path) (guard (_ 0) (rest (Assoc entry (lit size) (File stat path))))))

(def sh-read-file (fn (_ path) (File read-all path)))

; --- One line from the current input, or nil at EOF ----------------------
; bytes->str, NOT list->string: the accumulator holds raw input BYTES, and the
; utf8-aware conversion would re-encode anything >= 128 and corrupt a UTF-8
; filename on its way to exec.  EOF with a partial line is still a line -- a
; script whose last line has no trailing newline must run.
;
; ONE COPY, used by both the `read` builtin and the session loop in
; ash/repl.x: they are the same question asked from two places.
(def %sh-read-char (prim-ref (lit io) (lit read-char)))

(def sh-read-line
  (fn (_)
    (def go
      (fn (self acc)
        (let ((ch (%sh-read-char)))
          (if (null? ch)
            (if (null? acc) () (bytes->str (List reverse acc)))
            (if (= ch 10)
              (bytes->str (List reverse acc))
              (self (pair (integer->char ch) acc)))))))
    (go ())))

; --- One line straight off a DESCRIPTOR ----------------------------------
; The `read` builtin cannot use the reader above, and the difference is the
; whole reason both exist.  sh-read-line goes through the ENGINE's reader,
; which is right for the session loop -- that reader is what the prompt is
; already positioned in.  But the engine's reader is bound to the stream it
; was opened on, not to whatever fd 0 currently names, so
;
;   read a b < input.txt
;
; dup2s the file onto fd 0 and the engine reader never notices: both variables
; came back empty.  A shell's `read` reads its STANDARD INPUT, redirections
; included, so it has to ask the descriptor.
;
; ONE BYTE AT A TIME, which is not the pessimisation it looks like: reading
; ahead would swallow bytes past the newline that belong to the NEXT reader of
; that descriptor -- the engine's own, when input is a script.  A shell's read
; is specified to consume exactly the line it returns, and this is what that
; costs.
(def sh-read-line-fd
  (fn (_ fd)
    (def go
      (fn (self acc)
        (let ((b (Sys fd-read fd 1)))
          (if (null? b)
            (if (null? acc) () (bytes->str (List reverse acc)))
            (let ((c (first b)))
              (if (= c 10)
                (bytes->str (List reverse acc))
                (self (pair (integer->char c) acc))))))))
    (go ())))
