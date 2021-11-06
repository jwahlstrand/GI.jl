# functions that output expressions for a library in bulk

function all_const_exprs!(const_mod, const_exports, ns;print_summary=true)
    c = get_consts(ns)

    for (name,val) in c
        push!(const_mod.args, const_expr("$name",val))
    end
    if print_summary && length(c)>0
        printstyled("Generated ",length(c)," constants\n";color=:green)
    end

    es=get_all(ns,GIEnumGIInfo)
    for e in es
        name = Symbol(get_name(e))
        push!(const_mod.args, enum_decl(e))
        push!(const_exports.args, name)
    end

    if print_summary && length(es)>0
        printstyled("Generated ",length(es)," enums\n";color=:green)
    end

    es=get_all(ns,GIFlagsInfo)
    for e in es
        name = Symbol(get_name(e))
        push!(const_mod.args, enum_decl(e))
        push!(const_exports.args, name)
    end

    if print_summary && length(es)>0
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

function struct_exprs!(exprs,exports,ns,structs;print_summary=true,excludelist=[],import_as_opaque=[])
    struct_skiplist=excludelist

    imported=length(structs)
    for ss in structs
        ssi=gi_find_by_name(ns,ss)
        name=get_name(ssi)
        fields=get_fields(ssi)
        if occursin("Private",String(name))
            imported-=1
            continue
        end
        if is_gtype_struct(ssi) # these are "class structures" and according to the documentation we probably don't need them in bindings
            push!(struct_skiplist,name)
            imported-=1
            continue
        end
        name = Symbol("$name")
        try
            push!(exprs, struct_decl(ssi,get_c_prefix(ns);force_opaque=in(name,import_as_opaque)))
        catch NotImplementedError
            if print_summary
                printstyled(name," not implemented\n";color=:red)
            end
            push!(struct_skiplist,name)
            imported-=1
            continue
        end
        push!(exports.args, full_name(ssi,get_c_prefix(ns)))
    end

    if print_summary
        printstyled("Generated ",imported," structs out of ",length(structs),"\n";color=:green)
    end

    struct_skiplist
end

function all_struct_exprs!(exprs,exports,ns;print_summary=true,excludelist=[],import_as_opaque=[])
    struct_skiplist=excludelist

    s=get_all(ns,GIStructInfo)
    ss=filter(p->∉(get_name(p),struct_skiplist),s)
    imported=length(ss)
    for ssi in ss
        name=get_name(ssi)
        fields=get_fields(ssi)
        if occursin("Private",String(name))
            imported-=1
            continue
        end
        if is_gtype_struct(ssi) # these are "class structures" and according to the documentation we probably don't need them in bindings
            push!(struct_skiplist,name)
            #if print_summary
            #    printstyled(name," is a gtype struct, skipping\n";color=:yellow)
            #end
            imported-=1
            continue
        end
        name = Symbol("$name")
        push!(exprs, struct_decl(ssi,get_c_prefix(ns);force_opaque=in(name,import_as_opaque)))
        push!(exports.args, full_name(ssi,get_c_prefix(ns)))
    end

    if print_summary
        printstyled("Generated ",imported," structs out of ",length(s),"\n";color=:green)
    end

    struct_skiplist
end

function all_struct_methods!(exprs,ns;print_summary=true,skiplist=[], struct_skiplist=[])
    structs=get_structs(ns)

    not_implemented=0
    skipped=0
    created=0
    for s in structs
        name=get_name(s)
        methods=get_methods(s)
        if in(name,struct_skiplist)
            skipped+=length(methods)
            continue
        end
        for m in methods
            if in(get_name(m),skiplist)
                skipped+=1
                continue
            end
            if is_deprecated(m)
                continue
            end
            fun=create_method(m,get_c_prefix(ns))
            push!(exprs, fun)
            created+=1
        end
    end

    if print_summary
        printstyled(created, " struct methods created\n";color=:green)
        if skipped>0
            printstyled(skipped," struct methods skipped\n";color=:yellow)
        end
        if not_implemented>0
            printstyled(not_implemented," struct methods not implemented\n";color=:red)
        end
    end
end

function all_objects!(exprs,exports,ns;print_summary=true,handled=[],skiplist=[])
    objects=get_all(ns,GIObjectInfo)

    imported=length(objects)
    # precompilation prevents adding directly to GLib's gtype_wrapper cache here
    # so we add to a package local cache and merge with GLib's cache in __init__()
    gtype_cache = quote
        gtype_wrapper_cache = Dict{Symbol, Type}()
    end
    push!(exprs,gtype_cache)
    for o in objects
        name=get_name(o)
        if name==:Object
            imported -= 1
            continue
        end
        if in(name, skiplist)
            imported -= 1
            continue
        end
        type_init = get_type_init(o)
        if type_init==:intern  # GParamSpec and children output this
            continue
        end
        obj_decl!(exprs,o,ns,handled)
        push!(exports.args, full_name(o,get_c_prefix(ns)))
    end
    gtype_cache_init = quote
        gtype_wrapper_cache_init() = merge!(GLib.gtype_wrappers,gtype_wrapper_cache)
    end
    push!(exprs,gtype_cache_init)

    if print_summary
        printstyled("Created ",imported," objects out of ",length(objects),"\n";color=:green)
    end
end

function all_object_methods!(exprs,ns;skiplist=[],object_skiplist=[])
    not_implemented=0
    skipped=0
    created=0
    objects=get_all(ns,GIObjectInfo)
    for o in objects
        name=get_name(o)
        methods=get_methods(o)
        if in(name,object_skiplist)
            skipped+=length(methods)
            continue
        end
        for m in methods
            if in(get_name(m),skiplist)
                skipped+=1
                continue
            end
            if is_deprecated(m)
                continue
            end
            try
                fun=create_method(m,get_c_prefix(ns))
                push!(exprs, fun)
                created+=1
            catch NotImplementedError
                println("$name method not implemented: ",get_name(m))
                not_implemented+=1
            end
        end
    end
end

function all_interfaces!(exprs,exports,ns;print_summary=true,skiplist=[])
    interfaces=get_all(ns,GIInterfaceInfo)

    imported=length(interfaces)
    for i in interfaces
        name=get_name(i)
        # could use the following to narrow the type
        #p=get_prerequisites(i)
        type_init = get_type_init(i)
        if in(name,skiplist)
            imported-=1
            continue
        end
        append!(exprs,ginterface_decl(i,get_c_prefix(ns)))
        push!(exports.args, full_name(i,get_c_prefix(ns)))
    end

    if print_summary && imported>0
        printstyled("Created ",imported," interfaces out of ",length(interfaces),"\n";color=:green)
    end
    skiplist
end

function all_interface_methods!(exprs,ns;skiplist=[],interface_skiplist=[])
    not_implemented=0
    skipped=0
    created=0
    interfaces=get_all(ns,GIInterfaceInfo)
    for i in interfaces
        name=get_name(i)
        methods=get_methods(i)
        if in(name,interface_skiplist)
            skipped+=length(methods)
            continue
        end
        for m in methods
            if in(get_name(m),skiplist)
                skipped+=1
                continue
            end
            if is_deprecated(m)
                continue
            end
            try
                fun=create_method(m,get_c_prefix(ns))
                push!(exprs, fun)
                created+=1
            catch NotImplementedError
                println("$name method not implemented: ",get_name(m))
                not_implemented+=1
            end
        end
    end
end

function all_functions!(exprs,ns;print_summary=true,skiplist=[])
    j=0
    skipped=0
    not_implemented=0
    for i in get_all(ns,GIFunctionInfo)
        if in(get_name(i),skiplist) || occursin("cclosure",string(get_name(i)))
            skipped+=1
            continue
        end
        unsupported = false # whatever we happen to unsupport
        for arg in get_args(i)
            try
                bt = get_base_type(get_type(arg))
                if isa(bt,Ptr{GIArrayType}) || isa(bt,Ptr{GIArrayType{3}})
                    unsupported = true; break
                end
                if (isa(get_base_type(get_type(arg)), Nothing))
                    unsupported = true; break
                end
            catch NotImplementedError
                continue
            end
        end
        try
            bt = get_base_type(get_return_type(i))
            if isa(bt,Symbol)
                unsupported = true;
            end
            if unsupported
                skipped+=1
                continue
            end
        catch NotImplementedError
            continue
        end
        name = get_name(i)
        name = Symbol("$name")
        try
            fun=create_method(i,get_c_prefix(ns))
            push!(exprs, fun)
            j+=1
        catch NotImplementedError
            println("Function not implemented: ",name)
            not_implemented+=1
            continue
        end
        #push!(exports.args, name)
    end

    if print_summary
        printstyled("created ",j," functions\n";color=:green)
        if skipped>0
            printstyled("skipped ",skipped," out of ",j+skipped," functions\n";color=:yellow)
        end
        if not_implemented>0
            printstyled(not_implemented," functions not implemented\n";color=:red)
        end
    end
end

function write_to_file(filename,toplevel)
    open(filename,"w") do f
        Base.println(f,"quote")
        Base.remove_linenums!(toplevel)
        Base.show_unquoted(f, toplevel)
        println(f)
        Base.println(f,"end")
    end
end

write_to_file(path,filename,toplevel)=write_to_file(joinpath(path,filename),toplevel)

function output_exprs()
    body = Expr(:block)
    toplevel = Expr(:toplevel, body)
    exprs = body.args
    exports = Expr(:export)
    toplevel, exprs, exports
end
