using G.GLib
using Test

# GDate is a struct with fields but we force it to be imported as opaque

@testset "date" begin

d=G.GLib.Date()
@test isa(d,GLib.GBoxed)

d=G.GLib.Date_new_dmy(5,9,2021)
@test isa(d,GLib.GBoxed)

@test G.GLib.valid(d)

@test G.GLib.Constants.DateWeekday.SUNDAY == G.GLib.get_weekday(d)

@test G.GLib.is_leap_year(2020)
@test !G.GLib.is_leap_year(2019)

end
