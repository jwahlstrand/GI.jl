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

function all_const_exprs!(const_mod, const_exports, ns;print_summary=true)
    c = get_consts(ns)

    for (name,val) in c
        push!(const_mod.args, const_expr("$name",val))
    end
    if print_summary
        printstyled("Generated ",length(c)," constants\n";color=:green)
    end

    es=GI.get_all(ns,GI.GIEnumGIInfo)
    for e in es
        name = Symbol(GI.get_name(e))
        push!(const_mod.args, GI.enum_decl(e))
        push!(const_exports.args, name)
    end

    if print_summary
        printstyled("Generated ",length(es)," enums\n";color=:green)
    end

    es=GI.get_all(ns,GI.GIFlagsInfo)
    for e in es
        name = Symbol(GI.get_name(e))
        push!(const_mod.args, GI.enum_decl(e))
        push!(const_exports.args, name)
    end

    if print_summary
        printstyled("Generated ",length(es)," flags\n";color=:green)
    end
end

function all_const_exprs(ns;print_summary=true)
    const_mod = Expr(:block)
    const_exports = Expr(:export)

    all_const_exprs!(const_mod,const_exports,ns;print_summary=print_summary)
    push!(const_mod.args,const_exports)

    const_mod
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
        type_init = get_type_init(structinfo)
        #println(gstructname, " type_init is ",get_type_init(structinfo)," ",length(fields)," fields")
        libs=get_shlibs(GINamespace(get_namespace(structinfo)))
        lib=libs[findfirst(l->(nothing!=dlsym(dlopen(l),type_init)),libs)]
        fin = quote
            function $gstructname(ref::Ptr{$gstructname}, own::Bool = false)
                gtype = ccall((($(QuoteNode(type_init))), $lib),GType, ())
                own || ccall((:g_boxed_copy, libgobject), Nothing, (GType, Ptr{$gstructname},), gtype, ref)
                x = new(ref)
                finalizer(x::$gstructname->begin
                        ccall((:g_boxed_free, libgobject), Nothing, (GType, Ptr{$gstructname},), gtype, x.handle)
                        #@async println("finalized ",$gstructname)
                    end, x)
            end
        end
    else
        throw(NotImplementedError)
    end
    if length(fields)>0 && !force_opaque
        throw(NotImplementedError)
        fieldsexpr=Expr[]
        for field in fields
            field1=get_name(field)
            type1=extract_type(field).ctype
            push!(fieldsexpr,:($field1::$type1))
        end
        datastructname=Symbol("_",gstructname)
        datastruc=quote
            mutable struct $datastructname
                $(fieldsexpr...)
            end
        end
    end
    struc=quote
        mutable struct $decl
            handle::Ptr{$gstructname}
            $fin
        end
    end
    if length(fields)>0 && !force_opaque
        throw(NotImplementedError)
        quote
            $(datastruc)
            $(struc)
        end
    else
        struc
    end
end

function all_struct_exprs!(exprs,ns;print_summary=true,excludelist=[],import_as_opaque=[])
    struct_skiplist=excludelist

    s=GI.get_all(ns,GI.GIStructInfo)
    ss=filter(p->∉(GI.get_name(p),struct_skiplist),s)
    imported=length(ss)
    for ssi in ss
        name=GI.get_name(ssi)
        fields=GI.get_fields(ssi)
        if GI.is_gtype_struct(ssi) # these are "class structures" and according to the documentation we probably don't need them in bindings
            push!(struct_skiplist,name)
            if print_summary
                printstyled(name," is a gtype struct, skipping\n";color=:yellow)
            end
            imported-=1
            continue
        end
        if length(fields)>0
            imported-=1
            if !in(name,import_as_opaque)
                if print_summary
                    printstyled(name," has fields, skipping\n";color=:yellow) # need to define two structs, one with fields and one without (see how GList is handled in Gtk.jl)
                end
                push!(struct_skiplist,name)
                continue
            end
        end
        name = Symbol("$name")
        try
            push!(exprs, GI.struct_decl(ssi,GI.get_c_prefix(ns);force_opaque=in(name,import_as_opaque)))
        catch NotImplementedError
            if print_summary
                printstyled(name," not implemented\n";color=:red)
            end
            push!(struct_skiplist,name)
            imported-=1
        end
        #push!(exports.args, name)
    end

    if print_summary
        println("Generated ",imported," structs out of ",length(s))
    end

    struct_skiplist
end

function all_struct_methods!(exprs,ns;skiplist=[], struct_skiplist=[])
    structs=GI.get_structs(ns)

    not_implemented=0
    skipped=0
    created=0
    for s in structs
        name=GI.get_name(s)
        methods=GI.get_methods(s)
        if in(name,struct_skiplist)
            skipped+=length(methods)
            continue
        end
        for m in methods
            if in(GI.get_name(m),skiplist)
                skipped+=1
                continue
            end
            if GI.is_deprecated(m)
                continue
            end
            try
                fun=GI.create_method(m,GI.get_c_prefix(ns))
                push!(exprs, fun)
                created+=1
            catch NotImplementedError
                not_implemented+=1
            end
        end
    end

    println(created, " methods created")
    println(skipped," methods skipped")
    println(not_implemented," methods not implemented")
end

function all_functions!(exprs,ns;skiplist=[])
    j=0
    skipped=0
    not_implemented=0
    for i in GI.get_all(ns,GI.GIFunctionInfo)
        if in(GI.get_name(i),skiplist) || occursin("cclosure",string(GI.get_name(i)))
            skipped+=1
            continue
        end
        unsupported = false # whatever we happen to unsupport
        for arg in GI.get_args(i)
            try
                bt = GI.get_base_type(GI.get_type(arg))
                if isa(bt,Ptr{GI.GIArrayType}) || isa(bt,Ptr{GI.GIArrayType{3}})
                    unsupported = true; break
                end
                if (isa(GI.get_base_type(GI.get_type(arg)), Nothing))
                    unsupported = true; break
                end
            catch NotImplementedError
                continue
            end
        end
        try
            bt = GI.get_base_type(GI.get_return_type(i))
            if isa(bt,Symbol)
                unsupported = true;
            end
            if unsupported
                #println("Skipped: ",GI.get_name(i))
                skipped+=1
                continue
            end
        catch NotImplementedError
            continue
        end
        name = GI.get_name(i)
        name = Symbol("$name")
        try
            fun=GI.create_method(i,GI.get_c_prefix(ns))
            push!(exprs, fun)
            j+=1
        catch NotImplementedError
            #println("Not implemented: ",name)
            not_implemented+=1
            continue
        end
        #push!(exports.args, name)
    end

    println("created ",j," functions")
    println("skipped ",skipped," out of ",j+skipped," functions")
    println(not_implemented," functions not implemented")
end

function obj_decl!(exprs,o,ns,handled)
    if in(GI.get_name(o),handled)
        return
    end
    p=GI.get_parent(o)
    if !in(GI.get_name(p),handled) && GI.get_namespace(o) == GI.get_namespace(p)
        obj_decl!(exprs,p,ns,handled)
    end
    append!(exprs,GI.gobject_decl(o,GI.get_c_prefix(ns)))
    push!(handled,GI.get_name(o))
end

function all_objects!(exprs,ns;handled=[])
    objects=GI.get_all(ns,GI.GIObjectInfo)

    imported=length(objects)
    for o in objects
        name=GI.get_name(o)
        if name==:Object
            imported -= 1
            continue
        end
        type_init = GI.get_type_init(o)
        if type_init==:intern  # GParamSpec and children output this
            continue
        end
        obj_decl!(exprs,o,ns,handled)
    end

    println("Imported ",imported," objects out of ",length(objects))
end

function all_object_methods!(exprs,ns;skiplist=[],object_skiplist=[])
    not_implemented=0
    skipped=0
    created=0
    objects=GI.get_all(ns,GI.GIObjectInfo)
    for o in objects
        name=GI.get_name(o)
        println("Object: ",name)
        methods=GI.get_methods(o)
        if in(name,object_skiplist)
            skipped+=length(methods)
            continue
        end
        for m in methods
            println(GI.get_name(m))
            if in(GI.get_name(m),skiplist)
                skipped+=1
                continue
            end
            if GI.is_deprecated(m)
                continue
            end
            try
                fun=GI.create_method(m,GI.get_c_prefix(ns))
                push!(exprs, fun)
                created+=1
            catch NotImplementedError
                not_implemented+=1
            #catch LoadError
            #    println("error")
            end
        end
    end
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
            #gtype_wrappers[$(QuoteNode(oname))] = $leafname
        end
        push!(exprs, decl)
    end
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
      #println("arg at arrlen is ",args[arrlen])
      #println("arg at arrlen+1 is ",args[arrlen+1])
      lenname=get_name(args[arrlen+1])
      lensymb=Symbol(:m_,lenname)
    end

    if is_zero_terminated(rettypeinfo) && get_caller_owns(arginfo)==GITransfer.EVERYTHING
        if elmctype == :(Ptr{UInt8})
            :(_len=length_zt($name);ret2=bytestring.(unsafe_wrap(Vector{$elmctype}, $name,_len));GLib.g_strfreev($name);ret2)
        else
            throw(NotImplementedError)
            #:(_len=length_zt($name);ret2=copy(unsafe_wrap(Vector{$elmctype}, $name,i-1));GLib.g_free($name);ret2)
        end
    elseif get_caller_owns(arginfo)==GITransfer.CONTAINER && lensymb != nothing
        :(ret2=copy(unsafe_wrap(Vector{$elmctype}, $name,$lensymb[]));GLib.g_free($name);ret2)
    else
        throw(NotImplementedError)
    end
end

#this should only be used for stuff that's hard to implement as cconvert
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

function extract_type(typeinfo::GITypeInfo,info::GICallbackInfo)
    throw(NotImplementedError)
    TypeDesc(info,:Function, :(Ptr{Nothing}))
end

const ObjectLike = Union{GIObjectInfo, GIInterfaceInfo}

function typename(info::GIObjectInfo)
    g_type = GI.get_g_type(info)
    Symbol(GLib.g_type_name(g_type))
end

# not sure the best way to implement this given no multiple inheritance
typename(info::GIInterfaceInfo) = :GObject #FIXME

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

function convert_from_c(argname::Symbol, arginfo::ArgInfo, ti::TypeDesc{T}) where {T}
    # check if it's a GBoxed, if so check transfer
    if ti.jtype != :Any
        :(convert($(ti.jtype), $argname))
    elseif ti.gitype === Bool
        :(convert(Bool, $argname))
    else
        nothing
    end
end

struct Arg
    name::Symbol
    typ::Union{Expr,Symbol}
end
types(args::Array{Arg}) = [a.typ for a in args]
names(args::Array{Arg}) = [a.name for a in args]
jparams(args::Array{Arg}) = [a.typ != :Any ? :($(a.name)::$(a.typ)) : a.name for a in args]
#there's probably a better way
function make_ccall(libs, id, rtype, args)
    argtypes = Expr(:tuple, types(args)...)
    # look up symbol in our possible libraries
    lib=libs[findfirst(l->(nothing!=dlsym(dlopen(l),id)),libs)]
    c_call = :(ccall(($id, $lib), $rtype, $argtypes))
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
        #FIXME: mimic the new constructor style of Gtk.jl
        name = Symbol("$(get_name(get_container(info)))_$name")
        #println("CONSTRUCTOR: ",name)
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
