const_decls(ns) = const_decls(ns,x->x)
function const_decls(ns,fmt)
    consts = get_consts(ns)
    decs = Expr[]
    for (name,val) in consts
        name = fmt(name)
        if name !== nothing
            push!(decs, :(const $(Symbol(name)) = $(val)) )
        end
    end
    decs
end
const_expr(name,val) =  :($(Symbol(name)) = $(val))

function enum_decl(enum)
    enumname=get_name(enum)
    vals = get_enum_values(enum)
    body = Expr(:block)
    for (name,val) in vals
        if match(r"^[a-zA-Z_]",string(name)) === nothing
            name = Symbol("_$name")
        end
        push!(body.args, :(const $(uppercase(name)) = $val) )
    end
    Expr(:toplevel,Expr(:module, false, Symbol(enumname), body))
end

function enum_decls(ns)
    enums = get_all(ns, GIEnumGIOrFlags)
    typedefs = Expr[]
    aliases = Expr[]
    for enum in enums
        name = get_name(enum)
        longname = enum_name(enum)
        push!(typedefs,enum_decl(enum,name))
        push!(aliases, :( const $name = _AllTypes.$longname))
    end
    (typedefs,aliases)
end
enum_name(enum) = Symbol(string(get_namespace(enum),get_name(enum)))

function full_name(info,prefix)
    name=get_name(info)
    Symbol(prefix,name)
end

function struct_decl(structinfo,prefix;force_opaque=false)
    structname=get_name(structinfo)
    fields=get_fields(structinfo)
    gstructname = Symbol(prefix,structname)
    gtype=get_g_type(structinfo)
    isboxed = GLib.g_isa(gtype,GLib.g_type_from_name(:GBoxed))
    decl = isboxed ? :($gstructname <: GBoxed) : gstructname
    fin = Expr[]
    if isboxed
        type_init = String(get_type_init(structinfo))
        #println(gstructname, " type_init is ",get_type_init(structinfo)," ",length(fields)," fields")
        libs=get_shlibs(GINamespace(get_namespace(structinfo)))
        lib=libs[findfirst(l->(nothing!=dlsym(dlopen(l),type_init)),libs)]
        slib=symbol_from_lib(lib)
        fin = quote
            GLib.g_type(::Type{T}) where {T <: $gstructname} =
                      ccall(($type_init, $slib), GType, ())
            function $gstructname(ref::Ptr{$gstructname}, own::Bool = false)
                gtype = ccall((($(QuoteNode(type_init))), $slib),GType, ())
                own || ccall((:g_boxed_copy, libgobject), Nothing, (GType, Ptr{$gstructname},), gtype, ref)
                x = new(ref)
                finalizer(x::$gstructname->begin
                        ccall((:g_boxed_free, libgobject), Nothing, (GType, Ptr{$gstructname},), gtype, x.handle)
                        #@async println("finalized ",$gstructname)
                    end, x)
            end
        end
    end
    if length(fields)>0 && !force_opaque
        fieldsexpr=Expr[]
        for field in fields
            field1=get_name(field)
            type1=extract_type(field).ctype
            push!(fieldsexpr,:($field1::$type1))
        end
        struc=quote
            struct $decl
                $(fieldsexpr...)
            end
        end
    else
        struc=quote
            mutable struct $decl
                handle::Ptr{$gstructname}
                $fin
            end
        end
    end
    struc
end

function obj_decl!(exprs,o,ns,handled)
    if in(GI.get_name(o),handled)
        return
    end
    p=GI.get_parent(o)
    if p!==nothing && !in(GI.get_name(p),handled) && GI.get_namespace(o) == GI.get_namespace(p)
        obj_decl!(exprs,p,ns,handled)
    end
    append!(exprs,GI.gobject_decl(o,GI.get_c_prefix(ns)))
    push!(handled,GI.get_name(o))
end

function gobject_decl(objectinfo,prefix)
    g_type = GI.get_g_type(objectinfo)
    oname = Symbol(GLib.g_type_name(g_type))
    type_init = GI.get_type_init(objectinfo)
    parentinfo = GI.get_parent(objectinfo)
    pg_type = GI.get_g_type(parentinfo)
    pname = Symbol(GI.GLib.g_type_name(pg_type))
    q=findfirst("_get_type",string(type_init))
    symname=Symbol(chop(string(type_init),tail=q[end]-q[1]+1))
    libs=GI.get_shlibs(GINamespace(GI.get_namespace(objectinfo)))
    lib=libs[findfirst(l->(nothing!=dlsym(dlopen(l),type_init)),libs)]
    # The call to type_init really slows things down and doesn't seem to be necessary.
    # Leaving it here because it probably is necessary.
    decl=quote
        #gtype = ccall((($(QuoteNode(type_init))), $lib),GType, ())
        abstract type $oname <: $pname end
        #gtype_decl = GLib.get_gtype_decl($oname, $lib, $symname)
        #get_type_decl(Symbol(string(:($oname), "Impl")), $oname, gtype, gtype_decl, @__MODULE__)
        #gtype_abstracts[$(QuoteNode(oname))] = $oname
    end
    exprs=Expr[]
    push!(exprs,decl)
    if !GI.get_abstract(objectinfo)
        leafname = Symbol(oname,"Leaf")
        decl=quote
            mutable struct $leafname <: $oname
                handle::Ptr{GObject}
                function $leafname(handle::Ptr{GObject})
                    if handle == C_NULL
                        error($("Cannot construct $leafname with a NULL pointer"))
                    end
                    return gobject_ref(new(handle))
                end
            end
            gtype_wrappers[$(QuoteNode(oname))] = $leafname
        end
        push!(exprs, decl)
    end
    exprs
end

function ginterface_decl(interfaceinfo,prefix)
    g_type = GI.get_g_type(interfaceinfo)
    iname = Symbol(GLib.g_type_name(g_type))
    decl=quote
        struct $iname <: GInterface
            handle::Ptr{GObject}
            gc::Any
            $iname(x::GObject) = new(unsafe_convert(Ptr{GObject}, x), x)
        end
    end
    exprs=Expr[]
    push!(exprs,decl)
    exprs
end

mutable struct NotImplementedError <: Exception
end

mutable struct UnsupportedType <: Exception
    typ
end

abstract type InstanceType end
is_pointer(::Type{InstanceType}) = true
const TypeInfo = Union{GITypeInfo,Type{InstanceType}}

struct TypeDesc{T}
    gitype::T
    jtype::Union{Expr,Symbol}    # used in Julia for arguments
    ctype::Union{Expr,Symbol}    # used in ccall's
end

# extract_type creates a TypeDesc corresponding to an argument or field
# for constructing functions and structs

# convert_from_c(name,arginfo,typeinfo) produces an expression that sets the symbol "name" from GIArgInfo

# convert_to_c...

function extract_type(info::GIArgInfo)
    typdesc = extract_type(get_type(info))
    if may_be_null(info) && typdesc.jtype !== :Any
        jtype=typdesc.jtype
        typdesc = TypeDesc(typdesc.gitype, :(Maybe($jtype)), typdesc.ctype)
    end
    typdesc
end
extract_type(info::GIFieldInfo) = extract_type(get_type(info))
function extract_type(info::GITypeInfo)
    base_type = get_base_type(info)
    extract_type(info,base_type)
end

function extract_type(info::GITypeInfo, basetype)
    typ = Symbol(string(basetype))
    if is_pointer(info)
        ptyp = :(Ptr{$typ})
    elseif typ===:Bool
        ptyp = :Cint
        typ = :Any
    else
        ptyp = typ
        typ = :Any
    end
    TypeDesc(basetype,typ,ptyp)
end

#  T<:SomeType likes to steal this:
function extract_type(info::GITypeInfo, basetype::Type{Union{}})
    TypeDesc(Union{}, :Any, :Nothing)
end

function extract_type(info::GITypeInfo, basetype::Type{String})
    @assert is_pointer(info)
    TypeDesc{Type{String}}(String,:Any,:(Ptr{UInt8}))
end
function convert_from_c(name::Symbol, arginfo::ArgInfo, typeinfo::TypeDesc{Type{String}})
    owns = get_ownership_transfer(arginfo) != GITransfer.NOTHING
    expr = :( ($name == C_NULL) ? nothing : bytestring($name, $owns))
end

function typename(info::GIStructInfo)
    g_type = GI.get_g_type(info)
    if Symbol(GLib.g_type_name(g_type))===:void  # this isn't a GType
        Symbol(get_name(info))
    else
        Symbol(GLib.g_type_name(g_type))
    end
end
function extract_type(typeinfo::TypeInfo, info::GIStructInfo)
    name = typename(info)
    if is_pointer(typeinfo)
        #TypeDesc(info,:(Ptr{$name}),:(Ptr{$name})) # use this for plain old structs?
        TypeDesc(info,typename(info),:(Ptr{$name}))
        #TypeDesc(info,:Any,:(Ptr{Nothing}))
    else
        TypeDesc(info,name,name)
    end
end

function extract_type(typeinfo::GITypeInfo,info::GIEnumGIOrFlags)
    TypeDesc{GIEnumGIOrFlags}(info,:Any, :EnumGI)
end

function convert_to_c(argname::Symbol, info::GIArgInfo, ti::TypeDesc{T}) where {T<:GIEnumGIOrFlags}
    :( enum_get($(enum_name(ti.gitype)),$argname) )
end

function extract_type(typeinfo::GITypeInfo,info::Type{GICArray})
    @assert is_pointer(typeinfo)
    elm = get_param_type(typeinfo,0)
    elmtype = extract_type(elm)
    elmctype=elmtype.ctype
    elmgitype=elmtype.gitype
    elmjtype=elmtype.jtype
    #TypeDesc{Type{GICArray}}(GICArray,:(Vector{$elmgitype}), :(Ptr{$elmctype}))
    TypeDesc{Type{GICArray}}(GICArray,:Any, :(Ptr{$elmctype}))
end
function convert_from_c(name::Symbol, arginfo::ArgInfo, typeinfo::TypeDesc{T}) where {T<:Type{GICArray}}
    if typeof(arginfo)==GIFunctionInfo
        rettypeinfo=get_return_type(arginfo)
    else
        return nothing
    end
    elm = get_param_type(rettypeinfo,0)
    elmtype = extract_type(elm)
    elmctype=elmtype.ctype
    arrlen=get_array_length(rettypeinfo)
    lensymb=nothing
    if arrlen != -1
      args=get_args(arginfo)
      lenname=get_name(args[arrlen+1])
      lensymb=Symbol(:m_,lenname)
    end

    if is_zero_terminated(rettypeinfo) && get_caller_owns(arginfo)==GITransfer.EVERYTHING
        if elmctype == :(Ptr{UInt8})
            :(_len=length_zt($name);ret2=bytestring.(unsafe_wrap(Vector{$elmctype}, $name,_len));GLib.g_strfreev($name);ret2)
        else
            return nothing
            #:(_len=length_zt($name);ret2=copy(unsafe_wrap(Vector{$elmctype}, $name,i-1));GLib.g_free($name);ret2)
        end
    elseif get_caller_owns(arginfo)==GITransfer.CONTAINER && lensymb != nothing
        :(ret2=copy(unsafe_wrap(Vector{$elmctype}, $name,$lensymb[]));GLib.g_free($name);ret2)
    else
        #throw(NotImplementedError)
        return nothing
    end
end

function convert_to_c(name::Symbol, info::GIArgInfo, ti::TypeDesc{T}) where {T<:Type{GICArray}}
    if typeof(info)==GIFunctionInfo
        return nothing
    end
    typeinfo=get_type(info)
    elm = get_param_type(typeinfo,0)
    elmtype = extract_type(elm)
    elmctype=elmtype.ctype
    if elmctype == :(Ptr{UInt8})
        return nothing
    end
    :(convert(Vector{$elmctype},$name))
end

function extract_type(typeinfo::GITypeInfo,info::Type{GArray})
    TypeDesc{Type{GArray}}(GArray,:Any, :(Ptr{GArray}))
end

function extract_type(typeinfo::GITypeInfo,info::Type{GPtrArray})
    TypeDesc{Type{GPtrArray}}(GPtrArray,:Any, :(Ptr{GPtrArray}))
end

function extract_type(typeinfo::GITypeInfo,info::Type{GByteArray})
    TypeDesc{Type{GByteArray}}(GByteArray,:Any, :(Ptr{GByteArray}))
end

function extract_type(typeinfo::GITypeInfo,listtype::Type{T}) where {T<:GLib._LList}
    @assert is_pointer(typeinfo)
    elm = get_param_type(typeinfo,0)
    elmtype = extract_type(elm).ctype
    lt = listtype == GLib._GSList ? :(GLib._GSList) : :(GLib._GList)
    #println("extract_type:",lt)
    TypeDesc{Type{GList}}(GList, :(GLib.LList{$lt{$elmtype}}), :(Ptr{$lt{$elmtype}}))
end
function convert_from_c(name::Symbol, arginfo::ArgInfo, typeinfo::TypeDesc{Type{GList}})
    #owns = get_ownership_transfer(arginfo) != GITransfer.NOTHING
    expr = :( GLib.GList($name) )
end

function extract_type(typeinfo::GITypeInfo,basetype::Type{Function})
    #throw(NotImplementedError)
    TypeDesc{Type{Function}}(Function,:Function, :(Ptr{Nothing}))
end

function convert_to_c(name::Symbol, info::GIArgInfo, ti::TypeDesc{T}) where {T<:Type{Function}}
    typeinfo=get_type(info)
    callbackinfo=get_interface(typeinfo)
    #println(get_name(callbackinfo))
    # get return type
    rettyp=get_return_type(callbackinfo)
    retctyp=extract_type(rettyp).ctype
    # get arg types
    argctypes_arr=[]
    for arg in get_args(callbackinfo)
        argtyp=get_type(arg)
        argctyp=extract_type(argtyp).ctype
        push!(argctypes_arr,argctyp)
    end
    argctypes = Expr(:tuple, argctypes_arr...)
    special=QuoteNode(Expr(:$, :name))
    expr = quote
        @cfunction($special, $retctyp, $argctypes)
    end
end

const ObjectLike = Union{GIObjectInfo, GIInterfaceInfo}

function typename(info::GIObjectInfo)
    g_type = GI.get_g_type(info)
    Symbol(GLib.g_type_name(g_type))
end

# not sure the best way to implement this given no multiple inheritance
typename(info::GIInterfaceInfo) = :GObject #FIXME

function extract_type(typeinfo::GITypeInfo, basetype::Type{T}) where {T<:GObject}
    interf_info = get_interface(typeinfo)
    ns=get_namespace(interf_info)
    prefix=get_c_prefix(ns)
    name = Symbol(prefix,string(get_name(interf_info)))
    TypeDesc{Type{GObject}}(GObject, name, :(Ptr{GObject}))
end

function extract_type(typeinfo::GITypeInfo, basetype::Type{T}) where {T<:GInterface}
    interf_info = get_interface(typeinfo)
    ns=get_namespace(interf_info)
    prefix=get_c_prefix(ns)
    name = Symbol(prefix,string(get_name(interf_info)))
    TypeDesc{Type{GInterface}}(GInterface, name, :(Ptr{GObject}))
end

function extract_type(typeinfo::GITypeInfo, basetype::Type{T}) where {T<:GBoxed}
    interf_info = get_interface(typeinfo)
    ns=get_namespace(interf_info)
    prefix=get_c_prefix(ns)
    name = Symbol(prefix,string(get_name(interf_info)))
    TypeDesc{Type{GBoxed}}(GBoxed, name, :(Ptr{$name}))
end

function convert_from_c(name::Symbol, arginfo::ArgInfo, typeinfo::TypeDesc{T}) where {T <: Type{GObject}}
    owns = get_ownership_transfer(arginfo) != GITransfer.NOTHING
    # This conversion does all the gc prevention stuff
    :(convert($(typeinfo.jtype), $name, $owns))
end

function convert_from_c(name::Symbol, arginfo::ArgInfo, typeinfo::TypeDesc{T}) where {T <: Type{GInterface}}
    owns = get_ownership_transfer(arginfo) != GITransfer.NOTHING
    # This conversion does all the gc prevention stuff
    :(convert(GObject, $name, $owns))
end

function extract_type(typeinfo::TypeInfo, info::ObjectLike)
    if is_pointer(typeinfo)
        if typename(info)===:GParam  # these are not really GObjects
            return TypeDesc(info,:GParamSpec,:(Ptr{GParamSpec}))
        end
        TypeDesc(info,typename(info),:(Ptr{GObject}))
    else
        # a GList has implicitly pointers to all elements
        TypeDesc(info,:INVALID,:GObject)
    end
end

#this should only be used for stuff that's hard to implement as cconvert
function convert_to_c(name::Symbol, info::GIArgInfo, ti::TypeDesc)
    nothing
end

function convert_from_c(name::Symbol, arginfo::ArgInfo, ti::TypeDesc{T}) where {T}
    # check transfer
    typ=GI.get_type(arginfo)

    if ti.jtype != :Any
        :(convert($(ti.jtype), $name))
    elseif ti.gitype === Bool
        :(convert(Bool, $name))
    else
        nothing
    end
end

function extract_type(typeinfo::GITypeInfo,info::Type{GError})
    TypeDesc{Type{GError}}(GError,:Any, :(Ptr{GError}))
end

function extract_type(typeinfo::GITypeInfo,info::Type{GHashTable})
    TypeDesc{Type{GHashTable}}(GHashTable,:Any, :(Ptr{GHashTable}))
end

struct Arg
    name::Symbol
    typ::Union{Expr,Symbol}
end
types(args::Array{Arg}) = [a.typ for a in args]
names(args::Array{Arg}) = [a.name for a in args]
jparams(args::Array{Arg}) = [a.typ != :Any ? :($(a.name)::$(a.typ)) : a.name for a in args]

# Map library names onto exports of *_jll
# TODO: make this more elegant
function symbol_from_lib(libname)
    if occursin("libglib",libname)
        return :libglib
    elseif occursin("libgobject",libname)
        return :libgobject
    elseif occursin("libgio",libname)
        return :libgio
    elseif occursin("libcairo-gobject",libname)
        return :libcairo_gobject
    elseif occursin("libatk",libname)
        return :libatk
    end
    libname
end

#there's probably a better way
function make_ccall(libs, id, rtype, args)
    argtypes = Expr(:tuple, types(args)...)
    # look up symbol in our possible libraries
    lib=libs[findfirst(l->(nothing!=dlsym(dlopen(l),id)),libs)]
    slib=symbol_from_lib(lib)
    c_call = :(ccall(($id, $slib), $rtype, $argtypes))
    append!(c_call.args, names(args))
    c_call
end

# with some partial-evaluation half-magic
# (or maybe just jit-compile-time macros)
# this could be simplified significantly
function create_method(info::GIFunctionInfo,prefix)
    name = get_name(info)
    flags = get_flags(info)
    args = get_args(info)
    prologue = Any[]
    epilogue = Any[]
    retvals = Symbol[]
    cargs = Arg[]
    jargs = Arg[]
    if flags & GIFunction.IS_METHOD != 0
        object = get_container(info)
        typeinfo = extract_type(InstanceType,object)
        push!(jargs, Arg(:instance, typeinfo.jtype))
        push!(cargs, Arg(:instance, typeinfo.ctype))
    end
    if flags & GIFunction.IS_CONSTRUCTOR != 0
        #FIXME: do this with other constructors too (need to check that arg lists are different)
        if name===:new
            name = Symbol("$(get_name(get_container(info)))")
        else
            name = Symbol("$(get_name(get_container(info)))_$name")
        end
    end
    rettypeinfo=get_return_type(info)
    rettype = extract_type(rettypeinfo)
    if rettype.ctype != :Nothing || skip_return(info)
        expr = convert_from_c(:ret,info,rettype)
        if expr != nothing
            push!(epilogue, :(ret2 = $expr))
            push!(retvals,:ret2)
        else
            push!(retvals,:ret)
        end
    end
    for arg in get_args(info)
        if is_skip(arg)
            continue
        end
        aname = Symbol("_$(get_name(arg))")
        typ = extract_type(arg)
        dir = get_direction(arg)
        if dir != GIDirection.OUT
            push!(jargs, Arg( aname, typ.jtype))
            expr = convert_to_c(aname,arg,typ)
            if expr != nothing
                push!(prologue, :($aname = $expr))
            elseif may_be_null(arg)
                push!(prologue, :($aname = (($aname == nothing) ? C_NULL : $aname)))
            end
        end

        if dir == GIDirection.IN
            push!(cargs, Arg(aname, typ.ctype))
        else
            ctype = typ.ctype
            wname = Symbol("m_$(get_name(arg))")
            push!(prologue, :( $wname = mutable($ctype) ))
            if dir == GIDirection.INOUT
                push!(prologue, :( $wname[] = Base.cconvert($ctype,$aname) ))
            end
            push!(cargs, Arg(wname, :(Ptr{$ctype})))
            push!(epilogue,:( $aname = $wname[] ))
            expr = convert_from_c(aname,arg,typ)
            if expr != nothing
                push!(epilogue, :($aname = $expr))
            end
            push!(retvals, aname)
        end
    end

    # go through args again, remove length jargs for array inputs, add call
    # to length() to prologue
    args=get_args(info)
    for arg in args
        if is_skip(arg)
            continue
        end
        typ = extract_type(arg)
        dir = get_direction(arg)
        aname = Symbol("_$(get_name(arg))")
        typeinfo=get_type(arg)
        arrlen=get_array_length(typeinfo)
        if typ.gitype == GICArray && arrlen >= 0
            len_name=Symbol("_",get_name(args[arrlen+1]))
            len_i=findfirst(a->(a.name === len_name),jargs)
            if len_i === nothing
                continue
            end
            deleteat!(jargs,len_i)
            push!(prologue, :($len_name = length($aname)))
        end
    end

    if flags & GIFunction.THROWS != 0
        push!(prologue, :( err = err_buf() ))
        push!(cargs, Arg(:err, :(Ptr{Ptr{GError}})))
        pushfirst!(epilogue, :( check_err(err) ))
    end

    symb = get_symbol(info)
    j_call = Expr(:call, name, jparams(jargs)... )
    libs=get_shlibs(GINamespace(get_namespace(info)))
    c_call = :( ret = $(make_ccall(libs, string(symb), rettype.ctype, cargs)))
    if length(retvals) > 1
        retstmt = Expr(:tuple, retvals...)
    elseif length(retvals) ==1
        retstmt = retvals[]
    else
        retstmt = :nothing
    end
    blk = Expr(:block)
    blk.args = vcat(prologue, c_call, epilogue, retstmt )
    fun = Expr(:function, j_call, blk)
    #println(fun)
    fun

end
