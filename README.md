GI.jl
======

Julia bindings using libgobject-introspection.

This was forked from https://github.com/bfredl/GI.jl

This is a work in progress but is approaching a basic level of usefulness. Focus
is on outputting code that can simplify the creation of Julia packages that wrap
GObject-based libraries.

This package currently assumes libgirepository is installed (outside Julia).
It has only been tested on Fedora Linux. However, the generated code should work
anywhere.

## Status

Most of libgirepository is wrapped.
Information like lists of structs, methods, and functions can be extracted, as
well as argument types, struct fields, etc.
Much of this can be accomplished in other ways, but GObject introspection
includes annotations that indicate whether return values should be freed,
whether pointer arguments can be optionally NULL, whether list outputs are
NULL-terminated, which argument corresponds to the length of array inputs, etc.

Parts that are still very rough:

* Callback arguments are not at all handled correctly. I am still wrapping my
head around how signals are handled in Gtk.jl.
* Handling of GBoxed types is still being sorted out
* GInterfaces are handled awkwardly
