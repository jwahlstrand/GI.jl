using GI

toplevel, exprs, exports = GI.output_exprs()

ns = GINamespace(:Gio,"2.0")

## constants, enums, and flags, put in a "Constants" submodule

const_mod = GI.all_const_exprs(ns)
push!(exprs, Expr(:toplevel,Expr(:module, true, :Constants, const_mod)))

## export constants, enums, and flags code
GI.write_to_file("../libs/gen/gio_consts",toplevel)

## structs

toplevel, exprs, exports = GI.output_exprs()

# These are marked as "disguised" and what this means is not documentated AFAICT.
disguised = []
struct_skiplist=vcat(disguised, [:DBusInterfaceInfo,:DBusNodeInfo,:FileAttributeInfoList,:InputMessage,:IOExtension,:IOExtensionPoint,:IOModuleScope,:OutputMessage,:StaticResource])

struct_skiplist = GI.all_struct_exprs!(exprs,exports,ns;excludelist=struct_skiplist)

## objects

GI.all_objects!(exprs,exports,ns)
GI.all_interfaces!(exprs,exports,ns)

push!(exprs,exports)

GI.write_to_file("../libs/gen/gio_structs",toplevel)

## struct methods

toplevel, exprs, exports = GI.output_exprs()

skiplist=[]

GI.all_struct_methods!(exprs,ns,skiplist=skiplist,struct_skiplist=struct_skiplist)

## object methods

skiplist=[:export,:add_main_option_entries,:add_option_group,:make_pollfd,:source_new,:register_object,:get_info,:get_method_info,:get_property_info,:return_gerror,
:new_for_bus_sync,:new_sync,:get_interface_info,:set_interface_info,:writev,:writev_all,:flatten_tree,:changed_tree,:receive_messages,:send_message,:send_message_with_timeout,:send_messages,:get_context,
:return_error,:get_channel_binding_data,:lookup_certificates_issued_by,:get_default]

# skips are to avoid method name collisions
GI.all_object_methods!(exprs,ns;skiplist=skiplist,object_skiplist=[:AppInfoMonitor,:DBusConnection,:DBusMenuModel,:UnixMountMonitor])

skiplist=[:add_action_entries,:get_info,:create_source,:receive_messages,:send_messages,:get_accepted_cas,:get_channel_binding_data,:query_settable_attributes,
:query_writable_namespaces,:writev_nonblocking]
# skips are to avoid method name collisions
GI.all_interface_methods!(exprs,ns;skiplist=skiplist,interface_skiplist=[:App,:AppInfo,:DBusObjectManager,:Drive,:Mount,:NetworkMonitor,:PollableOutputStream,:ProxyResolver,:SocketConnectable,:TlsBackend,:TlsClientConnection,:Volume])

GI.write_to_file("../libs/gen/gio_methods",toplevel)

## object properties

for o in GI.get_all(ns,GI.GIObjectInfo)
    name=GI.get_name(o)
    println("object: $name")
    properties=GI.get_properties(o)
    for p in properties
        flags=GI.get_flags(p)
        tran=GI.get_ownership_transfer(p)
        println("property: ",GI.get_name(p)," ",tran)
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

skiplist=[:bus_own_name_on_connection,:bus_own_name,:bus_watch_name_on_connection,:bus_watch_name,:dbus_annotation_info_lookup,:dbus_error_encode_gerror,:dbus_error_get_remote_error,:dbus_error_is_remote_error,:dbus_error_new_for_dbus_error,
:dbus_error_strip_remote_error,:dbus_error_register_error_domain,:io_modules_load_all_in_directory_with_scope,:io_modules_scan_all_in_directory_with_scope]

GI.all_functions!(exprs,ns,skiplist=skiplist)

GI.write_to_file("../libs/gen/gio_functions",toplevel)
