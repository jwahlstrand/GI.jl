using G.GLib
using Test

@testset "datetime" begin

tz=GLib.TimeZone_new_local()
@test isa(tz,GLib.GBoxed)

#i=GLib.find_interval(tz,GLib.Constants.TimeType.STANDARD)
println("time zone identifier is ",GLib.get_identifier(tz))
println("time zone abbreviation is ",GLib.get_abbreviation(tz,0))

dt=GLib.DateTime_new_now_local()
@test isa(dt,GLib.GBoxed)

end
