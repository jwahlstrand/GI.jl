using GI
using Libdl

body = Expr(:block)
toplevel = Expr(:toplevel, body)
exprs = body.args
exports = Expr(:export)

ns = GINamespace(:GObject,"2.0")

## structs

# These are marked as "disguised" and what this means is not documentated AFAICT.
disguised = [:ParamSpecPool]
# These are handled specially by Gtk.GLib and are left alone here.
special = [:Object,:Value]
import_as_opaque = [:ObjectClass]
struct_skiplist=vcat(disguised, special, [:CClosure,:Closure,:ClosureNotifyData,:InterfaceInfo,:ObjectConstructParam,:ParamSpecTypeInfo,:TypeInfo,:TypeValueTable,:WeakRef])

struct_skiplist = GI.all_struct_exprs!(exprs,ns;excludelist=struct_skiplist,import_as_opaque=import_as_opaque)

open("../libs/gobject_structs","w") do f
    Base.println(f,"quote")
    Base.show_unquoted(f, toplevel)
    Base.println(f,"end")
end

body = Expr(:block)
toplevel = Expr(:toplevel, body)
exprs = body.args
exports = Expr(:export)

## objects

objects=GI.get_all(ns,GI.GIObjectInfo)

imported=length(objects)
for o in objects
    name=GI.get_name(o)
    if name==:Object
        global imported -= 1
        continue
    end
    println(name)
    type_init = GI.get_type_init(o)
    if type_init==:intern  # GParamSpec and children output this
        continue
    end
    append!(exprs,GI.gobject_decl(o,GI.get_c_prefix(ns)))
end

println("Imported ",imported," objects out of ",length(objects))

## struct methods

structs=GI.get_structs(ns)

skiplist=[]

filter!(x->x≠:Variant,struct_skiplist)

GI.all_struct_methods!(exprs,ns,skiplist=skiplist,struct_skiplist=struct_skiplist)

## object methods

skiplist=[:interface_find_property,:interface_install_property,:interface_list_properties,
:bind_property_full,:watch_closure,:add_interface,:register_enum,:register_flags,:register_type]

not_implemented=0
skipped=0
created=0
for o in objects
    name=GI.get_name(o)
    println("Object: ",name)
    methods=GI.get_methods(o)
    #if in(name,object_skiplist)
    #    if name != :Object
    #        global skipped+=length(methods)
    #        continue
    #    end
    #end
    for m in methods
        println(GI.get_name(m))
        if in(GI.get_name(m),skiplist)
            global skipped+=1
            continue
        end
        if GI.is_deprecated(m)
            continue
        end
        try
            fun=GI.create_method(m,GI.get_c_prefix(ns))
            push!(exprs, fun)
            global created+=1
        catch NotImplementedError
            global not_implemented+=1
        #catch LoadError
        #    println("error")
        end
    end
end

## object properties

for o in objects
    name=GI.get_name(o)
    properties=GI.get_properties(o)
    for p in properties
        if in(GI.get_name(o),skiplist)
            global skipped+=1
            continue
        end
        if GI.is_deprecated(p)
            continue
        end
        typ=GI.get_type(p)
        btyp=GI.get_base_type(typ)
        println(GI.get_name(p)," ",btyp)
        #try
            #fun=GI.create_method(m,GI.get_c_prefix(ns))
            #push!(exprs, fun)
            #global created+=1
        #catch NotImplementedError
        #    global not_implemented+=1
        #catch LoadError
        #    println("error")
        #end
    end
end


## functions

skiplist=[:enum_complete_type_info,:enum_register_static,:flags_complete_type_info,
:flags_register_static,:param_type_register_static,:signal_accumulator_first_wins,
:signal_accumulator_true_handled,:signal_connect_closure,:signal_connect_closure_by_id,
:signal_handler_find,:signal_handlers_block_matched,:signal_handlers_disconnect_matched,
:signal_handlers_unblock_matched,:signal_override_class_closure,:signal_query,
:source_set_closure,:source_set_dummy_callback,:type_add_interface_static,
:type_check_class_is_a,:type_check_instance,:type_check_instance_is_a,:type_check_instance_is_fundamentally_a,
:type_default_interface_unref,:type_free_instance,:type_name_from_class,
:type_name_from_instance,:type_query,:type_register_fundamental,:type_register_static]

GI.all_functions!(exprs,ns,skiplist=skiplist)

open("gobject_methods_callbacks_functions","w") do f
    Base.println(f,"quote")
    Base.show_unquoted(f, toplevel)
    println(f)
    Base.println(f,"end")
end
