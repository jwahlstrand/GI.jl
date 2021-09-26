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

function all_struct_exprs!(exprs,exports,ns;print_summary=true,excludelist=[],import_as_opaque=[])
    struct_skiplist=excludelist

    s=GI.get_all(ns,GI.GIStructInfo)
    ss=filter(p->∉(GI.get_name(p),struct_skiplist),s)
    imported=length(ss)
    for ssi in ss
        name=GI.get_name(ssi)
        fields=GI.get_fields(ssi)
        if occursin("Private",String(name))
            imported-=1
            continue
        end
        if GI.is_gtype_struct(ssi) # these are "class structures" and according to the documentation we probably don't need them in bindings
            push!(struct_skiplist,name)
            if print_summary
                printstyled(name," is a gtype struct, skipping\n";color=:yellow)
            end
            imported-=1
            continue
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
            continue
        end
        push!(exports.args, full_name(ssi,GI.get_c_prefix(ns)))
    end

    if print_summary
        printstyled("Generated ",imported," structs out of ",length(s),"\n";color=:green)
    end

    struct_skiplist
end

function all_struct_methods!(exprs,ns;print_summary=true,skiplist=[], struct_skiplist=[])
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

    if print_summary
        printstyled(created, " struct methods created\n";color=:green)
        printstyled(skipped," struct methods skipped\n";color=:yellow)
        if not_implemented>0
            printstyled(not_implemented," struct methods not implemented\n";color=:red)
        end
    end
end

function all_objects!(exprs,exports,ns;handled=[])
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
        push!(exports.args, full_name(o,GI.get_c_prefix(ns)))
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
        #println("Object: ",name)
        methods=GI.get_methods(o)
        if in(name,object_skiplist)
            skipped+=length(methods)
            continue
        end
        for m in methods
            #println(GI.get_name(m))
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

function all_interfaces!(exprs,exports,ns;skiplist=[])
    interfaces=GI.get_all(ns,GI.GIInterfaceInfo)

    imported=length(interfaces)
    for i in interfaces
        name=GI.get_name(i)
        type_init = GI.get_type_init(i)
        if in(name,skiplist)
            imported-=1
            continue
        end
        append!(exprs,ginterface_decl(i,GI.get_c_prefix(ns)))
        push!(exports.args, full_name(i,GI.get_c_prefix(ns)))
    end

    println("Imported ",imported," interfaces out of ",length(interfaces))
    skiplist
end

function all_interface_methods!(exprs,ns;skiplist=[],interface_skiplist=[])
    not_implemented=0
    skipped=0
    created=0
    interfaces=GI.get_all(ns,GI.GIInterfaceInfo)
    for i in interfaces
        name=GI.get_name(i)
        #println("Object: ",name)
        methods=GI.get_methods(i)
        if in(name,interface_skiplist)
            skipped+=length(methods)
            continue
        end
        for m in methods
            #println(GI.get_name(m))
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

function all_functions!(exprs,ns;print_summary=true,skiplist=[])
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

    if print_summary
        printstyled("created ",j," functions\n";color=:green)
        printstyled("skipped ",skipped," out of ",j+skipped," functions\n";color=:yellow)
        if not_implemented>0
            printstyled(not_implemented," functions not implemented\n";color=:red)
        end
    end
end

function write_to_file(filename,toplevel)
    open(filename,"w") do f
        Base.println(f,"quote")
        Base.show_unquoted(f, toplevel)
        println(f)
        Base.println(f,"end")
    end
end

function output_exprs()
    body = Expr(:block)
    toplevel = Expr(:toplevel, body)
    exprs = body.args
    exports = Expr(:export)
    toplevel, exprs, exports
end
