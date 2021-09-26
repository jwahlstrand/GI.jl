module Gio

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@optlevel"))
    @eval Base.Experimental.@optlevel 1
end

using ..GLib

using Glib_jll

import Base: convert

export GInputStream, GOutputStream, GCancellable, GMenuModel, GMenu
export GAppLaunchContext, GApplication, GMountOperation, GEmblemedIcon

eval(include("gen/gio_consts"))
eval(include("gen/gio_structs"))

eval(include("gen/gio_methods"))
eval(include("gen/gio_functions"))

end
