using GI

body = Expr(:block)
toplevel = Expr(:toplevel, body)
exprs = body.args
exports = Expr(:export)

ns = GINamespace(:Gio,"2.0")

## constants, enums, and flags, put in a "Constants" submodule

const_mod = GI.all_const_exprs(ns)
push!(exprs, Expr(:toplevel,Expr(:module, true, :Constants, const_mod)))

## export constants, enums, and flags code
open("../libs/gio_consts","w") do f
    Base.println(f,"quote")
    Base.show_unquoted(f, toplevel)
    Base.println(f,"end")
end

## structs

body = Expr(:block)
toplevel = Expr(:toplevel, body)
exprs = body.args
exports = Expr(:export)

# These are marked as "disguised" and what this means is not documentated AFAICT.
disguised = []
struct_skiplist=vcat(disguised, [])

struct_skiplist = GI.all_struct_exprs!(exprs,ns;excludelist=struct_skiplist)

open("../libs/gio_structs","w") do f
    Base.println(f,"quote")
    Base.show_unquoted(f, toplevel)
    Base.println(f,"end")
end

body = Expr(:block)
toplevel = Expr(:toplevel, body)
exprs = body.args
exports = Expr(:export)

## objects

GI.all_objects!(exprs,ns)

## struct methods

skiplist=[]

GI.all_struct_methods!(exprs,ns,skiplist=skiplist,struct_skiplist=struct_skiplist)

## object methods

skiplist=[:export,:add_main_option_entries,:add_option_group,:make_pollfd,:source_new,:register_object,:get_info,:get_method_info,:get_property_info,:return_gerror,
:new_for_bus_sync,:new_sync,:get_interface_info,:set_interface_info,:writev,:writev_all,:flatten_tree,:changed_tree,:receive_messages,:send_message,:send_message_with_timeout,:send_messages,:get_context,
:return_error,:get_channel_binding_data,:lookup_certificates_issued_by]

GI.all_object_methods!(exprs,ns;skiplist=skiplist)

## functions

skiplist=[:bus_own_name_on_connection,:bus_own_name,:bus_watch_name_on_connection,:bus_watch_name,:dbus_annotation_info_lookup,:dbus_error_encode_gerror,:dbus_error_get_remote_error,:dbus_error_is_remote_error,:dbus_error_new_for_dbus_error,
:dbus_error_strip_remote_error,:dbus_error_register_error_domain,:io_modules_load_all_in_directory_with_scope,:io_modules_scan_all_in_directory_with_scope]

GI.all_functions!(exprs,ns,skiplist=skiplist)

open("gio_methods_callbacks_functions","w") do f
    Base.println(f,"quote")
    Base.show_unquoted(f, toplevel)
    println(f)
    Base.println(f,"end")
end
