module GLib

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@optlevel"))
    @eval Base.Experimental.@optlevel 1
end

# Import `libglib` and `libgobject`
using Glib_jll

import Base: convert, copy, show, size, length, getindex, setindex!, get,
             iterate, eltype, isempty, ndims, stride, strides, popfirst!,
             empty!, append!, reverse!, pushfirst!, pop!, push!, splice!, insert!, deleteat!,
             sigatomic_begin, sigatomic_end, Sys.WORD_SIZE, unsafe_convert,
             getproperty, getindex, setindex!, print

using Libdl

using ..MutableTypes

export Maybe

export GList, glist_iter, _GSList, _GList, GError, GVariant, GType, GBoxed
export GObject, GInitiallyUnowned, GInterface
export g_timeout_add, g_idle_add, @idle_add
export @sigatom, cfunction_
export gobject_ref, signal_connect

export bytestring

export gtype_abstracts, gtype_wrappers, GVariantDict, GBytes, GVariantType

export GValue,GParamSpec, GTypeModule

Maybe(T) = Union{T,Nothing}

cfunction_(@nospecialize(f), r, a::Tuple) = cfunction_(f, r, Tuple{a...})

@generated function cfunction_(f, R::Type{rt}, A::Type{at}) where {rt, at<:Tuple}
    quote
        @cfunction($(Expr(:$,:f)), $rt, ($(at.parameters...),))
    end
end


# local function, handles Symbol and makes UTF8-strings easier
const AbstractStringLike = Union{AbstractString, Symbol}
bytestring(s) = String(s)
bytestring(s::Symbol) = s
function bytestring(s::Ptr{UInt8}, own::Bool=false)
    str=unsafe_string(s)
    if own
        g_free(s)
    end
    str
end

g_malloc(s::Integer) = ccall((:g_malloc, libglib), Ptr{Nothing}, (Csize_t,), s)
g_free(p::Ptr) = ccall((:g_free, libglib), Nothing, (Ptr{Nothing},), p)
g_strfreev(p) = ccall((:g_strfreev, libglib), Nothing, (Ptr{Ptr{Nothing}},), p)

# related to array handling
function length_zt(arr::Ptr)
    i=1
    while unsafe_load(arr,i)!=C_NULL
        i+=1
    end
    i-1
end

include("glist.jl")
include("gvariant.jl")
include("gtype.jl")
include("hashtable.jl")
include("arrays.jl")

eval(include("gen/glib_consts"))
eval(include("gen/glib_structs"))

include("gvalues.jl")
include("gerror.jl")

function err_buf()
    err = mutable(Ptr{GError});
    err.x = C_NULL
    err
end
function check_err(err::Mutable{Ptr{GError}})
    if err[] != C_NULL
        gerror = GError(err[])
        emsg = bytestring(gerror.message)
        ccall((:g_clear_error,libglib),Nothing,(Ptr{Ptr{GError}},),err)
        error(emsg)
    end
end

include("signals.jl")

eval(include("gen/glib_methods"))
eval(include("gen/glib_functions"))

eval(include("gen/gobject_structs"))
eval(include("gen/gobject_methods"))
eval(include("gen/gobject_functions"))

function init_main_loop()
    main_loop = GLib.MainLoop_new(nothing, true)

    g_main() = GLib.g_sigatom() do
        GLib.run(main_loop)
    end

    # if g_main_depth > 0, a glib main-loop is already running,
    # so we don't need to start a new one
    if ccall((:g_main_depth, GLib.libglib), Cint, ()) == 0
        global g_main_task = schedule(Task(g_main))
    end
end

end
