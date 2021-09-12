using G.GLib
using Test

@testset "date" begin

d=G.GLib.Date()
@test isa(d,GLib.GBoxed)

d=G.GLib.Date_new_dmy(5,9,2021)
@test isa(d,GLib.GBoxed)

@test G.GLib.Constants.DateWeekday.SUNDAY == G.GLib.get_weekday(d)

@test G.GLib.valid(d)

end
