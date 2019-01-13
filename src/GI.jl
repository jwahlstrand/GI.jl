module GI
    import Gtk
    using Gtk.GLib
    using Gtk.GLib.MutableTypes
    import Base: convert, cconvert, show, length, getindex, setindex!, uppercase, unsafe_convert
    import Gtk.GLib: libgobject, libglib, bytestring
    using Libdl

    uppercase(s::Symbol) = Symbol(uppercase(string(s)))
    # gimport interface (not final in any way)
    export @gimport

    export GINamespace
    export extract_type, ensure_name, ensure_method

    include(joinpath("..","deps","ext.jl"))
    include("girepo.jl")
    include("giimport.jl")
    include("gencache.jl")
end
