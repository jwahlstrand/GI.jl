struct GArray <: GBoxed
    data::Ptr{UInt8}
    len::UInt32
end

struct GByteArray <: GBoxed
    data::Ptr{UInt8}
    len::UInt32
end

struct GPtrArray <: GBoxed
    pdata::Ptr{Nothing}
    len::UInt32
end
