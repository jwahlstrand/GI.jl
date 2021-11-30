module GI
    using Glib_jll
    using Pkg.Artifacts

    include("GLib/GLib.jl")
    using .GLib
    import .GLib: libgobject, libglib, bytestring
    import .GLib:
      unsafe_convert,
      AbstractStringLike, bytestring

    import Base: convert, cconvert, show, length, getindex, setindex!, uppercase, unsafe_convert
    using Libdl

    uppercase(s::Symbol) = Symbol(uppercase(string(s)))

    export GINamespace
    export const_expr
    export extract_type

    include(joinpath("..","deps","ext.jl"))
    include("girepo.jl")
    include("giimport.jl")
    include("giexport.jl")
end
