using G.Gio
using G.GLib
using Test

# for testing handling of GInterfaces

@testset "gfile" begin

path=GLib.get_home_dir()
f=Gio.new_for_path(path)
path2=Gio.get_path(f)

@test path==path2

f2=Gio.dup(f)

@test path==Gio.get_path(f2)

@test Gio.query_exists(f,nothing)

end
