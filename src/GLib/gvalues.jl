### Getting and Setting Properties

struct GValue
    g_type::GType
    field2::UInt64
    field3::UInt64
    GValue() = new(0, 0, 0)
end
const GV = Union{Mutable{GValue}, Ptr{GValue}}
Base.zero(::Type{GValue}) = GValue()
function gvalue(::Type{T}) where T
    v = mutable(GValue())
    v[] = T
    v
end
function gvalue(x)
    T = typeof(x)
    v = gvalue(T)
    v[T] = x
    v
end
function gvalues(xs...)
    v = zeros(GValue, length(xs))
    for (i, x) in enumerate(xs)
        T = typeof(x)
        gv = mutable(v, i)
        gv[] = T  # init type
        gv[T] = x # init value
    end
    finalizer((v) -> for i = 1:length(v)
            ccall((:g_value_unset, libgobject), Nothing, (Ptr{GValue},), pointer(v, i))
        end, v)
    v
end

function setindex!(dest::GV, src::GV)
    ccall((:g_value_transform, libgobject), Cint, (Ptr{GValue}, Ptr{GValue}), src, dest) != 0
    src
end

convert(::Type{GValue}, p::Ptr{GValue}) = unsafe_load(p)

setindex!(::Type{Nothing}, v::GV) = v
setindex!(v::GLib.GV, x) = setindex!(v, x, typeof(x))
setindex!(gv::GV, x, i::Int) = setindex!(mutable(gv, i), x)

getindex(gv::GV, i::Int, ::Type{T}) where {T} = getindex(mutable(gv, i), T)
getindex(gv::GV, i::Int) = getindex(mutable(gv, i))
getindex(v::GV, i::Int, ::Type{Nothing}) = nothing

macro make_gvalue(pass_x, as_ctype, to_gtype, with_id, opt...)
    esc(:(make_gvalue($pass_x, $as_ctype, $to_gtype, $with_id, $__module__, $(opt...))))
end

const gboxed_types = Any[]

function getindex(gv::GV, ::Type{Any})
    gtyp = unsafe_load(gv).g_type
    if gtyp == 0
        error("Invalid GValue type")
    end
    if gtyp == g_type(Nothing)
        return nothing
    end
    # first pass: fast loop for fundamental types
    for (i, id) in enumerate(fundamental_ids)
        if id == gtyp  # if g_type == id
            return fundamental_fns[i](gv)
        end
    end
    # second pass: GBoxed types
    for typ in subtypes(GBoxed)
        if gtyp == g_type(typ)
            return getindex(gv,typ)
        end
    end
    # third pass: user defined (sub)types
    for (typ, typefn, getfn) in gvalue_types
        if g_isa(gtyp, typefn())
            return getfn(gv)
        end
    end
    # last pass: check for derived fundamental types (which have not been overridden by the user)
    for (i, id) in enumerate(fundamental_ids)
        if g_isa(gtyp, id)
            return fundamental_fns[i](gv)
        end
    end
    typename = g_type_name(gtyp)
    error("Could not convert GValue of type $typename to Julia type")
end
#end
