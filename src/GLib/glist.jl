# Gtk linked list

## Type hierarchy information

### an _LList is expected to have a data::Ptr{T} and next::Ptr{_LList{T}} element
### they are expected to be allocated and freed by GLib (e.g. with malloc/free)
abstract type _LList{T} end

struct _GSList{T} <: _LList{T}
    data::Ptr{T}
    next::Ptr{_GSList{T}}
end
struct _GList{T} <: _LList{T}
    data::Ptr{T}
    next::Ptr{_GList{T}}
    prev::Ptr{_GList{T}}
end

eltype(::Type{_LList{T}}) where {T} = T
eltype(::Type{L}) where {L <: _LList} = eltype(supertype(L))

mutable struct GList{L <: _LList, T} <: AbstractVector{T}
    handle::Ptr{L}
    transfer_full::Bool
    function GList{L,T}(handle, transfer_full::Bool) where {L<:_LList,T}
        # if transfer_full == true, then also free the elements when finalizing the list
        # this function assumes the caller will take care of holding a pointer to the returned object
        # until it wants to be garbage collected
        @assert T == eltype(L)
        l = new{L,T}(handle, transfer_full)
        finalizer(empty!, l)
        return l
    end
end
GList(t::Type{T}) where {T} = GList(convert(Ptr{_GList{T}}, C_NULL), true) # constructor for a particular type
GList(list::Ptr{L}, transfer_full::Bool = false) where {L <: _LList} = GList{L, eltype(L)}(list, transfer_full)

const  LList{L <: _LList} = Union{Ptr{L}, GList{L}}
eltype(::LList{L}) where {L <: _LList} = eltype(L)

_listdatatype(::Type{_LList{T}}) where {T} = T
_listdatatype(::Type{L}) where {L <: _LList} = _listdatatype(supertype(L))
deref(item::Ptr{L}) where {L <: _LList} = deref_to(L, unsafe_load(item).data) # extract something from the glist (automatically determine type)
deref_to(::Type{T}, x::Ptr) where {T} = unsafe_pointer_to_objref(x)::T # helper for extracting something from the glist (to type T)
deref_to(::Type{L}, x::Ptr) where {L <: _LList} = convert(eltype(L), deref_to(_listdatatype(L), x))
ref_to(::Type{T}, x) where {T} = gc_ref(x) # create a reference to something for putting in the glist
ref_to(::Type{L}, x) where {L <: _LList} = ref_to(_listdatatype(L), x)
empty!(li::Ptr{_LList}) = gc_unref(deref(li)) # delete an item in a glist
empty!(li::Ptr{L}) where {L <: _LList} = empty!(convert(Ptr{supertype(L)}, li))

## Standard Iteration protocol
start_(list::LList{L}) where {L} = unsafe_convert(Ptr{L}, list)
next_(::LList, s) = (deref(s), unsafe_load(s).next) # return (value, state)
done_(::LList, s) = (s == C_NULL)
iterate(list::LList, s=start_(list)) = done_(list, s) ? nothing : next_(list, s)


const  LListPair{L} = Tuple{LList, Ptr{L}}
function glist_iter(list::Ptr{L}, transfer_full::Bool = false) where L <: _LList
    # this function pairs every list element with the list head, to forestall garbage collection
    return (GList(list, transfer_full), list)
end
function next_(::LList, s::LListPair{L}) where L <: _LList
    return (deref(s[2]), (s[1], unsafe_load(s[2]).next))
end
done_(::LList, s::LListPair{L}) where {L <: _LList} = done_(s[1], s[2])

## Standard Array-like declarations
show(io::IO, ::MIME"text/plain", list::GList{L, T}) where {L, T} = show(io, list)
show(io::IO, list::GList{L, T}) where {L, T} = print(io, "GList{$L => $T}(length = $(length(list)), transfer_full = $(list.transfer_full))")

unsafe_convert(::Type{Ptr{L}}, list::GList) where {L <: _LList} = list.handle
endof(list::LList) = length(list)
ndims(list::LList) = 1
strides(list::LList) = (1,)
stride(list::LList, k::Integer) = (k > 1 ? length(list) : 1)
size(list::LList) = (length(list),)
isempty(list::LList{L}) where {L} = (unsafe_convert(Ptr{L}, list) == C_NULL)
Base.IteratorSize(::Type{L}) where {L <: LList} = Base.HasLength()

popfirst!(list::GList) = splice!(list, nth_first(list))
pop!(list::GList) = splice!(list, nth_last(list))
deleteat!(list::GList, i::Integer) = deleteat!(list, nth(list, i))

function splice!(list::GList, item::Ptr)
    x = deref(item)
    deleteat!(list, item)
    x
end

setindex!(list::GList, x, i::Real) = setindex!(list, x, nth(list, i))
