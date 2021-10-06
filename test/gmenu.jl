using G.Gio
using G.GLib
using Test

# GMenu is a simple object with no properties

@testset "gmenu" begin

m = Gio.Menu()

@test isa(m,GObject)
@test isa(m,GMenuModel)
@test isa(m,GMenu)

Gio.insert(m,0,"test","test-action")

@test 1 == Gio.get_n_items(m)
@test Gio.is_mutable(m)

i = Gio.MenuItem("test2","test2-action")
@test isa(i,GObject)
@test isa(i,GMenuItem)



end
