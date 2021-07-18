using GI
using Gtk.GLib
using Libdl
ns = GI.GINamespace(:GLib)
for path=GI.get_shlibs(ns)
    dlopen(path,RTLD_GLOBAL)
end
fs = GI.get_all(ns,GI.GIFunctionInfo)

fs_good=GI.GIInfo[]
for f in fs
    lustig = false # whatever we happen to unsupport
    for arg in GI.get_args(f)
        bt = GI.get_base_type(GI.get_type(arg))
        if isa(bt,GI.GIStructInfo) || isa(bt,GI.GIEnumGIInfo) || isa(bt,GI.GIFlagsInfo) || isa(bt,Ptr{GI.GIArrayType} )
            lustig = true; break
        end
    end
    bt = GI.get_base_type(GI.get_return_type(f))
    if isa(bt,GI.GIStructInfo)  || isa(bt,GI.GIEnumGIInfo) || isa(bt,GI.GIFlagsInfo) || isa(bt,Ptr{GI.GIArrayType})
        lustig = true;
    end
    if !lustig
        #println(f)
        push!(fs_good,f)
        try
            m=GI.create_method(f,GI.dynctx)
            eval(m)
        catch LoadError
            println("error in ",f)
        end
    else
        println("skipping ",f)
    end
end
