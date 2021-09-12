using GI
using Libdl

toplevel, exprs, exports = GI.output_exprs()

ns = GINamespace(:GObject,"2.0")

## structs

# These are marked as "disguised" and what this means is not documentated AFAICT.
disguised = [:ParamSpecPool]
# These are handled specially by Gtk.GLib and are left alone here.
special = [:Object,:Value]
import_as_opaque = [:ObjectClass]
struct_skiplist=vcat(disguised, special, [:CClosure,:Closure,:ClosureNotifyData,:InterfaceInfo,:ObjectConstructParam,:ParamSpecTypeInfo,:TypeInfo,:TypeValueTable,:WeakRef])

struct_skiplist = GI.all_struct_exprs!(exprs,ns;excludelist=struct_skiplist,import_as_opaque=import_as_opaque)

## objects and interfaces

GI.all_objects!(exprs,ns;handled=[:Object])
GI.all_interfaces!(exprs,ns)

GI.write_to_file("../libs/gen/gobject_structs",toplevel)

## struct methods

toplevel, exprs, exports = GI.output_exprs()

structs=GI.get_structs(ns)

skiplist=[:init_from_instance]

filter!(x->x≠:Variant,struct_skiplist)
filter!(x->x≠:Value,struct_skiplist)

GI.all_struct_methods!(exprs,ns,skiplist=skiplist,struct_skiplist=struct_skiplist)

## object methods

skiplist=[:interface_find_property,:interface_install_property,:interface_list_properties,
:bind_property_full,:watch_closure,:add_interface,:register_enum,:register_flags,:register_type]

GI.all_object_methods!(exprs,ns;skiplist=skiplist)

GI.write_to_file("../libs/gen/gobject_methods",toplevel)

## object properties

for o in GI.get_all(ns,GI.GIObjectInfo)
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

toplevel, exprs, exports = GI.output_exprs()

skiplist=[:enum_complete_type_info,:enum_register_static,:flags_complete_type_info,
:flags_register_static,:param_type_register_static,:signal_accumulator_first_wins,
:signal_accumulator_true_handled,:signal_connect_closure,:signal_connect_closure_by_id,
:signal_handler_find,:signal_handlers_block_matched,:signal_handlers_disconnect_matched,
:signal_handlers_unblock_matched,:signal_override_class_closure,:signal_query,
:source_set_closure,:source_set_dummy_callback,:type_add_interface_static,
:type_check_class_is_a,:type_check_instance,:type_check_instance_is_a,:type_check_instance_is_fundamentally_a,
:type_default_interface_unref,:type_free_instance,:type_name_from_class,
:type_name_from_instance,:type_query,:type_register_fundamental,:type_register_static,
:signal_set_va_marshaller]

GI.all_functions!(exprs,ns,skiplist=skiplist)

GI.write_to_file("../libs/gen/gobject_functions",toplevel)
