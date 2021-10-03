using GI

toplevel, exprs, exports = GI.output_exprs()

ns = GINamespace(:GLib, "2.0")
ns2 = GINamespace(:GObject, "2.0")

# This exports constants, structs, functions, etc. from the glib library. Most
# of the functionality overlaps what can be done in Julia, but it is a
# good starting point for getting GI.jl working fully.

## constants, enums, and flags, put in a "Constants" submodule

const_mod = Expr(:block)
const_exports = Expr(:export)

GI.all_const_exprs!(const_mod, const_exports, ns)
GI.all_const_exprs!(const_mod, const_exports, ns2)

push!(const_mod.args,const_exports)

push!(exprs, Expr(:toplevel,Expr(:module, true, :Constants, const_mod)))

## export constants, enums, and flags code
mkpath("../libs/gen/")
GI.write_to_file("../libs/gen/glib_consts",toplevel)

## structs

toplevel, exprs, exports = GI.output_exprs()

# These are marked as "disguised" and what this means is not documentated AFAICT.
disguised = [:AsyncQueue, :BookmarkFile, :Data, :Dir, :Hmac, :Iconv,
            :OptionContext, :PatternSpec, :Rand, :Sequence, :SequenceIter,
            :SourcePrivate, :StatBuf, :StringChunk, :StrvBuilder, :TestCase,
            :TestSuite, :Timer, :TreeNode]

# These are handled specially by Gtk.GLib and are left alone here.
special = [:List,:SList,:Error,:Variant] # add Hashtable?
# Treat these as opaque even though there are fields
import_as_opaque = [:Date,:Source]

# These include callbacks or are otherwise currently problematic
struct_skiplist=vcat(disguised, special, [:ByteArray,:Cond,:HashTableIter,:Hook,
    :HookList,:IOChannel,:IOFuncs,:MarkupParseContext,
    :MarkupParser,:MemVTable,:Node,:Once,:OptionGroup,:PollFD,:Private,:Queue,:RWLock,
    :RecMutex,:Scanner,:Source,:SourceCallbackFuncs,:SourceFuncs,
    :TestLogBuffer,:TestLogMsg,:Thread,:ThreadPool,:Tree,:UriParamsIter])

GI.all_struct_exprs!(exprs,exports,ns;excludelist=struct_skiplist, import_as_opaque=import_as_opaque)

push!(exprs,exports)

GI.write_to_file("../libs/gen/glib_structs",toplevel)

## struct methods

toplevel, exprs, exports = GI.output_exprs()

name_issues=[:end]

# some of these are skipped because they involve callbacks
skiplist=vcat(name_issues,[:error_quark,:compare,:ref,:copy,:unref_to_array,
:new_literal,:parse_error_print_context,:find_source_by_funcs_user_data,:find_source_by_id,
:new_from_data,:add_poll,:remove_poll,:check,:find_source_by_user_data,:query])

filter!(x->x≠:Variant,struct_skiplist)

GI.all_struct_methods!(exprs,ns,skiplist=skiplist,struct_skiplist=struct_skiplist)

GI.write_to_file("../libs/gen/glib_methods",toplevel)

## functions

toplevel, exprs, exports = GI.output_exprs()

# many of these are skipped because they involve callbacks
skiplist=[:atomic_rc_box_release_full,:child_watch_add,:datalist_foreach,:dataset_foreach,:file_get_contents,:io_add_watch,:log_set_handler,:log_set_writer_func,:rc_box_release_full,:spawn_async,:spawn_async_with_fds,:spawn_async_with_pipes,:spawn_async_with_pipes_and_fds,:spawn_sync,:test_add_data_func,:test_add_data_func_full,:test_add_func,:test_queue_destroy,:unix_fd_add_full,:unix_signal_add, :byte_array_new,:byte_array_free_to_bytes,:datalist_get_data, :datalist_get_flags, :datalist_id_get_data, :datalist_set_flags, :datalist_unset_flags,:hook_destroy,:hook_destroy_link,:hook_free,:hook_insert_before, :hook_prepend,:hook_unref,:io_channel_error_from_errno,:poll, :sequence_get,:sequence_move,:sequence_move_range,:sequence_remove,:sequence_remove_range,:sequence_set,:sequence_swap,:shell_parse_argv,:source_remove_by_funcs_user_data,:test_run_suite, :assertion_message_error,:byte_array_free,:byte_array_new_take,:byte_array_steal,:byte_array_unref,:hash_table_add,:hash_table_contains,:hash_table_destroy,:hash_table_insert,:hash_table_lookup,:hash_table_lookup_extended,:hash_table_remove,:hash_table_remove_all,:hash_table_replace,:hash_table_size,:hash_table_steal,:hash_table_steal_all,:hash_table_steal_extended,:hash_table_unref,:uri_parse_params, :propagate_error,:set_error_literal,:pattern_match,:pattern_match_string,:log_structured_array,:log_writer_default,:log_writer_format_fields,:log_writer_journald,:log_writer_standard_streams,:parse_debug_string,:variant_parse_error_print_context]

GI.all_functions!(exprs,ns,skiplist=skiplist)

GI.write_to_file("../libs/gen/glib_functions",toplevel)
