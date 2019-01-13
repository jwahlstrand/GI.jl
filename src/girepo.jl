abstract type GIRepository end
const girepo = ccall((:g_irepository_get_default, libgi), Ptr{GIRepository}, () )

abstract type GITypelib end

abstract type GIBaseInfo end
# a GIBaseInfo we own a reference to
mutable struct GIInfo{Typeid}
    handle::Ptr{GIBaseInfo}
end

function GIInfo(h::Ptr{GIBaseInfo},owns=true)
    if h == C_NULL
        error("Cannot constrct GIInfo from NULL")
    end
    typeid = ccall((:g_base_info_get_type, libgi), Int, (Ptr{GIBaseInfo},), h)
    info = GIInfo{typeid}(h)
    owns && finalizer(info_unref, info)
    info
end
maybeginfo(h::Ptr{GIBaseInfo}) = (h == C_NULL) ? nothing : GIInfo(h)

# don't call directly, called by gc
function info_unref(info::GIInfo)
    #core dumps on reload("GTK.jl"),
    #ccall((:g_base_info_unref, libgi), Nothing, (Ptr{GIBaseInfo},), info.handle)
    info.handle = C_NULL
end

convert(::Type{Ptr{GIBaseInfo}},w::GIInfo) = w.handle
unsafe_convert(::Type{Ptr{GIBaseInfo}},w::GIInfo) = w.handle
#convert(::Type{GIBaseInfo},w::GIInfo) = w.handle

const GIInfoTypesShortNames = (:Invalid, :Function, :Callback, :Struct, :Boxed, :EnumGI,
                               :Flags, :Object, :Interface, :Constant, :Unknown, :Union,
                               :Value, :Signal, :VFunc, :Property, :Field, :Arg, :Type, :Unresolved)

const EnumGI = Int

const GIInfoTypeNames = [ Base.Symbol("GI$(name)Info") for name in GIInfoTypesShortNames]

const GIInfoTypes = Dict{Symbol, Type}()

for (i,itype) in enumerate(GIInfoTypesShortNames)
    let lowername = Symbol(lowercase(string(itype)))
        @eval const $(GIInfoTypeNames[i]) = GIInfo{$(i-1)}
        GIInfoTypes[lowername] = GIInfo{i-1}
    end
end

const GICallableInfo = Union{GIFunctionInfo,GIVFuncInfo, GICallbackInfo, GISignalInfo}
const GIEnumGIOrFlags = Union{GIEnumGIInfo,GIFlagsInfo}
const GIRegisteredTypeInfo = Union{GIEnumGIOrFlags,GIInterfaceInfo, GIObjectInfo, GIStructInfo, GIUnionInfo}

show(io::IO, ::Type{GIInfo{Typeid}}) where Typeid = print(io, GIInfoTypeNames[Typeid+1])

function show(io::IO, info::GIInfo)
    show(io, typeof(info))
    print(io,"(:$(get_namespace(info)), :$(get_name(info)))")
end

#show(io::IO, info::GITypeInfo) = print(io,"GITypeInfo($(extract_type(info)))")
show(io::IO, info::GIArgInfo) = print(io,"GIArgInfo(:$(get_name(info)),$(extract_type(info)))")
#showcompact(io::IO, info::GIArgInfo) = show(io,info) # bug in show.jl ?

function show(io::IO, info::GIFunctionInfo)
    print(io, "$(get_namespace(info)).")
    flags = get_flags(info)
    if flags & (IS_CONSTRUCTOR | IS_METHOD) != 0
        cls = get_container(info)
        print(io, "$(get_name(cls)).")
    end
    print(io,"$(get_name(info))(")
    for arg in get_args(info)
        print(io, "$(get_name(arg))::")
        show(io, get_type(arg))
        dir = get_direction(arg)
        alloc = is_caller_allocates(arg)
        if dir == DIRECTION_OUT
            print(io, " OUT($alloc)")
        elseif dir == DIRECTION_INOUT
            print(io, " INOUT")
        end
        print(io, ", ")
    end
    print(io,")::")
    show(io, get_return_type(info))
    if flags & THROWS != 0
        print(io, " THROWS")
    end

end


struct GINamespace
    name::Symbol
    function GINamespace(namespace::Symbol, version=nothing)
        #TODO: stricter version sematics?
        gi_require(namespace, version)
        new(namespace)
    end
end
convert(::Type{Symbol}, ns::GINamespace) = ns.name
convert(::Type{Cstring}, ns::GINamespace) = ns.name
convert(::Type{Ptr{UInt8}}, ns::GINamespace) = convert(Ptr{UInt8}, ns.name)
unsafe_convert(::Type{Symbol}, ns::GINamespace) = ns.name
unsafe_convert(::Type{Ptr{UInt8}}, ns::GINamespace) = convert(Ptr{UInt8}, ns.name)

function gi_require(namespace, version=nothing)
    if version==nothing
        version = C_NULL
    end
    GError() do error_check
        typelib = ccall((:g_irepository_require, libgi), Ptr{GITypelib},
            (Ptr{GIRepository}, Ptr{UInt8}, Ptr{UInt8}, Cint, Ptr{Ptr{GError}}),
            girepo, namespace, version, 0, error_check)
        return  typelib !== C_NULL
    end
end

function gi_find_by_name(namespace, name)
    #info = ccall((:g_irepository_find_by_name, libgi), Ptr{GIBaseInfo},
    #       (Ptr{GIRepository}, Ptr{UInt8}, Ptr{UInt8}), girepo, namespace, name)

    info = ccall((:g_irepository_find_by_name, libgi), Ptr{GIBaseInfo},
                  (Ptr{GIRepository}, Cstring, Cstring), girepo, namespace.name, name)

    if info == C_NULL
        error("Name $name not found in $namespace")
    end
    GIInfo(info)
end

#GIInfo(namespace, name::Symbol) = gi_find_by_name(namespace, name)

#TODO: make ns behave more like Array and/or Dict{Symbol,GIInfo}?
length(ns::GINamespace) = Int(ccall((:g_irepository_get_n_infos, libgi), Cint,
                               (Ptr{GIRepository}, Cstring), girepo, ns))
function getindex(ns::GINamespace, i::Integer)
    GIInfo(ccall((:g_irepository_get_info, libgi), Ptr{GIBaseInfo},
              (Ptr{GIRepository}, Cstring, Cint), girepo, ns, i-1 ))
end
getindex(ns::GINamespace, name::Symbol) = gi_find_by_name(ns, name)

function get_all(ns::GINamespace, t::Type{T}) where {T<:GIInfo}
    all = GIInfo[]
    for i=1:length(ns)
        info = ns[i]
        if isa(info,t)
            push!(all,info)
        end
    end
    all
end


function get_shlibs(ns)
    names = ccall((:g_irepository_get_shared_library, libgi), Ptr{UInt8}, (Ptr{GIRepository}, Cstring), girepo, ns)
    if names != C_NULL
        [bytestring(s) for s in split(bytestring(names),",")]
    else
        String[]
    end
end
get_shlibs(info::GIInfo) = get_shlibs(get_namespace(info))

function find_by_gtype(gtypeid::Csize_t)
    GIInfo(ccall((:g_irepository_find_by_gtype, libgi), Ptr{GIBaseInfo}, (Ptr{GIRepository}, Csize_t), girepo, gtypeid))
end

GIInfoTypes[:method] = GIFunctionInfo
GIInfoTypes[:callable] = GICallableInfo
GIInfoTypes[:registered_type] = GIRegisteredTypeInfo
GIInfoTypes[:base] = GIInfo
GIInfoTypes[:enum] = GIEnumGIOrFlags

Maybe(T) = Union{T,Nothing}

rconvert(t,v) = rconvert(t,v,false)
rconvert(t::Type,val,owns) = convert(t,val)
rconvert(::Type{String}, val,owns) = bytestring(val) #,owns)
rconvert(::Type{Symbol}, val,owns) = Symbol(bytestring(val))#,owns) )
rconvert(::Type{GIInfo}, val::Ptr{GIBaseInfo},owns) = GIInfo(val,owns)
#rconvert{T}(::Type{Union(T,Nothing)}, val,owns) = (val == C_NULL) ? nothing : rconvert(T,val,owns)
# :(
for typ in [GIInfo, String, GObject]
    @eval rconvert(::Type{Union{$typ,Nothing}}, val,owns) = (val == C_NULL) ? nothing : rconvert($typ,val,owns)
end
rconvert(::Type{Nothing}, val) = error("something went wrong")

# one-> many relationships
for (owner, property) in [
    (:object, :method), (:object, :signal), (:object, :interface),
    (:object, :property), (:object, :constant), (:object, :field),
    (:interface, :method), (:interface, :signal), (:callable, :arg),
    (:enum, :value)]
    @eval function $(Symbol("get_$(property)s"))(info::$(GIInfoTypes[owner]))
        n = Int(ccall(($("g_$(owner)_info_get_n_$(property)s"), libgi), Cint, (Ptr{GIBaseInfo},), info))
        GIInfo[ GIInfo( ccall(($("g_$(owner)_info_get_$property"), libgi), Ptr{GIBaseInfo},
                      (Ptr{GIBaseInfo}, Cint), info, i)) for i=0:n-1]
    end
    if property == :method
        @eval function $(Symbol("find_$(property)"))(info::$(GIInfoTypes[owner]), name)
            ptr = ccall(($("g_$(owner)_info_find_$(property)"), libgi), Ptr{GIBaseInfo},
                            (Ptr{GIBaseInfo}, Ptr{UInt8}), info, name)
            rconvert(Maybe(GIInfo), ptr, true)
        end
    end
end
getindex(info::GIRegisteredTypeInfo, name::Symbol) = find_method(info, name)

const MaybeGIInfo = Union{GIInfo,Nothing}
# one->one
# FIXME: memory management of GIInfo:s
ctypes = Dict(GIInfo=>Ptr{GIBaseInfo},
         MaybeGIInfo=>Ptr{GIBaseInfo},
          Symbol=>Ptr{UInt8})
for (owner,property,typ) in [
    (:base, :name, Symbol), (:base, :namespace, Symbol),
    (:base, :container, MaybeGIInfo), (:registered_type, :g_type, GType), (:object, :parent, MaybeGIInfo),
    (:callable, :return_type, GIInfo), (:callable, :caller_owns, EnumGI),
    (:function, :flags, EnumGI), (:function, :Symbol, Symbol),
    (:arg, :type, GIInfo), (:arg, :direction, EnumGI), (:arg, :ownership_transfer, EnumGI),
    (:type, :tag, EnumGI), (:type, :interface, GIInfo), (:type, :array_type, EnumGI),
    (:type, :array_length, Cint), (:type, :array_fixed_size, Cint), (:constant, :type, GIInfo),
    (:value, :value, Int64) ]

    ctype = get(ctypes, typ, typ)
    @eval function $(Symbol("get_$(property)"))(info::$(GIInfoTypes[owner]))
        rconvert($typ,ccall(($("g_$(owner)_info_get_$(property)"), libgi), $ctype, (Ptr{GIBaseInfo},), info))
    end
end

get_name(info::GITypeInfo) = Symbol("<gtype>")
get_name(info::GIInvalidInfo) = Symbol("<INVALID>")

get_param_type(info::GITypeInfo,n) = rconvert(MaybeGIInfo, ccall(("g_type_info_get_param_type", libgi), Ptr{GIBaseInfo}, (Ptr{GIBaseInfo}, Cint), info, n))

#pretend that CallableInfo is a ArgInfo describing the return value
const ArgInfo = Union{GIArgInfo,GICallableInfo}
get_ownership_transfer(ai::GICallableInfo) = get_caller_owns(ai)
may_be_null(ai::GICallableInfo) = may_return_null(ai)
get_type(ai::GICallableInfo) = get_return_type(ai)

qual_name(info::GIRegisteredTypeInfo) = (get_namespace(info),get_name(info))

for (owner,flag) in [ (:type, :is_pointer), (:callable, :may_return_null), (:arg, :is_caller_allocates), (:arg, :may_be_null), (:type, :is_zero_terminated) ]
    @eval function $flag(info::$(GIInfoTypes[owner]))
        ret = ccall(($("g_$(owner)_info_$(flag)"), libgi), Cint, (Ptr{GIBaseInfo},), info)
        return ret != 0
    end
end

is_gobject(::Nothing) = false
function is_gobject(info::GIObjectInfo)
    if GLib.g_type_name(get_g_type(info)) == :GObject
        true
    else
        is_gobject(get_parent(info))
    end
end


const typetag_primitive = [
    Nothing,Bool,Int8,UInt8,
    Int16,UInt16,Int32,UInt32,
    Int64,UInt64,Cfloat,Cdouble,
    GType,
    String
    ]
const TAG_BASIC_MAX = 13
const TAG_FILENAME = 14
const TAG_ARRAY = 15
const TAG_INTERFACE = 16
const TAG_GLIST = 17
const TAG_GSLIST = 18


abstract type GIArrayType{kind} end
const GI_ARRAY_TYPE_C = 0
const GI_ARRAY_TYPE_ARRAY = 1
const GI_ARRAY_TYPE_PTR_ARRAY = 2
const GI_ARRAY_TYPE_BYTE_ARRAY =3
const GICArray = GIArrayType{GI_ARRAY_TYPE_C}

get_base_type(info::GIConstantInfo) = get_base_type(get_type(info))
function get_base_type(info::GITypeInfo)
    tag = get_tag(info)
    if tag <= TAG_BASIC_MAX
        typetag_primitive[tag+1]
    elseif tag == TAG_INTERFACE
        # Object Types n such
        get_interface(info)
    elseif tag == TAG_ARRAY
        GIArrayType{int(get_array_type(info))}
    elseif tag == TAG_GLIST
        GLib._GSList
    elseif tag == TAG_GSLIST
        GLib._GList
    elseif tag == TAG_FILENAME
        String #FIXME: on funky platforms this may not be utf8/ascii
    else
        print(tag)
        return Nothing
    end
end

get_call(info::GITypeInfo) = get_call(get_container(info))
get_call(info::GIArgInfo) = get_container(info)
get_call(info::GICallableInfo) = info

function show(io::IO,info::GITypeInfo)
    bt = get_base_type(info)
    if is_pointer(info)
        print(io,"Ptr{")
    end
    if isa(bt,Type) && bt <: GIArrayType && bt != None
        zero = is_zero_terminated(info)
        print(io,"$bt($zero,")
        fs = get_array_fixed_size(info)
        len = get_array_length(info)
        if fs >= 0
            show(io, fs)
        elseif len >= 0
            call = get_call(info)
            arg = get_args(call)[len+1]
            show(io, get_name(arg))
        end
        print(io,", ")
        param = get_param_type(info,0)
        show(io,param)
        print(io,")")
    elseif isa(bt,Type) && bt <: GLib._LList && bt != None
        print(io,"$bt{")
        param = get_param_type(info,0)
        show(io,param)
        print(io,"}")
    else
        print(io,bt)
    end
    if is_pointer(info)
        print(io,"}")
    end
end

function get_value(info::GIConstantInfo)
    typ = get_base_type(info)

    if typ <: Number
        x = Ref{Int64}(0)#Array{Int64,1}(undef,1) #or mutable
        size = ccall((:g_constant_info_get_value,libgi),Cint,(Ptr{GIBaseInfo}, Ref{Int64}), info, x)
        x[] #unsafe_load(cconvert(Ptr{typ}, x))
    elseif typ == String
        x = Array{Cstring,1}(undef,1) #or mutable
        size = ccall((:g_constant_info_get_value,libgi),Cint,(Ptr{GIBaseInfo}, Ptr{Cstring}), info, x)

        #strptr = unsafe_load(convert(Ptr{Ptr{UInt8}},x))
        #val = bytestring(strptr)

        val = unsafe_string(x[1])

        ccall((:g_constant_info_free_value,libgi), Nothing, (Ptr{GIBaseInfo}, Ptr{Nothing}), info, x)
        val
    else
        nothing#unimplemented
    end
end

function get_consts(gns)
    consts = Tuple{Symbol,Any}[]
    for c in get_all(gns,GIConstantInfo)
        name = get_name(c)
        if !occursin(r"^[a-zA-Z_]",string(name))
            name = Symbol("_$name") #FIXME: might collide
        end
        val = get_value(c)
        if val != nothing
            push!(consts, (name,val))
        end
    end
    consts
end

function get_enums(gns)
    enums = get_all(gns, GIEnumGIOrFlags)
    [(get_name(enum),get_enum_values(enum),isa(enum,GIFlagsInfo)) for enum in enums]
end

function get_enum_values(info::GIEnumGIOrFlags)
    valinfos = get_values(info)
    [(get_name(i),get_value(i)) for i in get_values(info)]
end

const IS_METHOD     = 1 << 0
const IS_CONSTRUCTOR = 1 << 1
const IS_GETTER      = 1 << 2
const IS_SETTER      = 1 << 3
const WRAPS_VFUNC    = 1 << 4
const THROWS = 1 << 5

const DIRECTION_IN = 0
const DIRECTION_OUT =1
const DIRECTION_INOUT =2

const TRANSFER_NOTHING =0
const TRANSFER_CONTAINER =1
const TRANSFER_EVERYTHING =2
