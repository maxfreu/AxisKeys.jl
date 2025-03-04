using NamedDims

# Abbreviations for things which have both names & keys:

NdaKa{L,T,N} = NamedDimsArray{L,T,N,<:KeyedArray{T,N}}
KaNda{L,T,N} = KeyedArray{T,N,<:NamedDimsArray{L,T,N}}

NdaKaVoM{L,T} = Union{NamedDimsArray{L,T,1,<:KeyedArray}, NamedDimsArray{L,T,2,<:KeyedArray}}
# NdaKaV{L,T} = NamedDimsArray{L,T,1,<:KeyedArray{T,1}}

# NamedDims functionality:

NamedDims.dimnames(A::KaNda{L}) where {L} = L
NamedDims.dimnames(A::KaNda{L,T,N}, d::Int) where {L,T,N} = d <= N ? L[d] : :_

NamedDims.dim(A::KaNda{L}, name) where {L} = NamedDims.dim(L, name)

Base.axes(A::KaNda{L}, s::Symbol) where {L} = axes(A, NamedDims.dim(L,s))
Base.size(A::KaNda{L,T,N}, s::Symbol) where {T,N,L} = size(A, NamedDims.dim(L,s))

NamedDims.rename(A::KaNda, names...) = KeyedArray(rename(parent(A), names...), axiskeys(A))

# Extra complication to make wrappers commutative:

hasnames(A::KaNda) = true
hasnames(A::NamedDimsArray) = true
hasnames(A) = false

NamedDims.unname(A::KaNda) = KeyedArray(unname(parent(A)), axiskeys(A))
keyless(A::NdaKa{L}) where {L} = NamedDimsArray(parent(parent(A)), L)

axiskeys(A::NdaKa) = axiskeys(parent(A))
axiskeys(A::NdaKa, d::Int) = axiskeys(parent(A), d)

axiskeys(A::NdaKa{L}, s::Symbol) where {L} = axiskeys(parent(A), NamedDims.dim(L,s))
axiskeys(A::KaNda{L}, s::Symbol) where {L} = axiskeys(A, NamedDims.dim(L,s))

haskeys(A::NdaKa) = true
haskeys(A::KeyedArray) = true
haskeys(A) = false

keys_or_axes(A) = haskeys(A) ? axiskeys(A) : axes(A)
keys_or_axes(A, d) = haskeys(A) ? axiskeys(A, d) : axes(A, d)

# Double un-wrappers:

keyless_unname(A::NdaKa) = parent(parent(A))
keyless_unname(A::KaNda) = parent(parent(A))
keyless_unname(A::NamedDimsArray) = parent(A)
keyless_unname(A::KeyedArray) = parent(A)
keyless_unname(A) = A

# Re-constructors:

function KeyedArray(A::NdaKa, r2::Tuple)
    r3 = unify_keys(axiskeys(parent(A)), r2)
    KeyedArray(keyless(A), r3)
end

function NamedDims.NamedDimsArray(A::KaNda{L}, L2::Tuple) where {L}
    L3 = NamedDims.unify_names(L, L2)
    NamedDimsArray(NamedDims.unname(A), L3)
end

# getproperty: it's useful to say for `(i,t) in enumerate(A.time)` etc.
# This will make saying ".data" slow (by 30ns), fixed in NamedDims.jl#78

Base.propertynames(A::NdaKa{L}, private::Bool=false) where {L} =
    private ? (L..., fieldnames(typeof(A))...) : L
Base.propertynames(A::KaNda{L}, private::Bool=false) where {L} =
    private ? (L..., fieldnames(typeof(A))...) : L

Base.getproperty(A::NdaKa{L}, s::Symbol) where {L} =
    Base.sym_in(s, L) ? axiskeys(A, NamedDims.dim(L, s)) : getfield(A, s)
Base.getproperty(A::KaNda{L}, s::Symbol) where {L} =
    Base.sym_in(s, L) ? axiskeys(A, NamedDims.dim(L, s)) : getfield(A, s)
Base.getproperty(A::NamedDimsArray{L}, s::Symbol) where {L} =
    Base.sym_in(s, L) ? axes(A, NamedDims.dim(L, s)) : getfield(A, s) # 🏴‍☠️?

# Keyword indexing of KeyedArray:

@inline @propagate_inbounds function Base.getindex(A::KeyedArray; kw...)
    hasnames(A) || error("must have names!")
    inds = NamedDims.order_named_inds(Val(dimnames(A)); kw...)
    getindex(A, inds...)
end
@inline @propagate_inbounds function Base.view(A::KeyedArray; kw...)
    hasnames(A) || error("must have names!")
    inds = NamedDims.order_named_inds(Val(dimnames(A)); kw...)
    view(A, inds...)
end

# Any NamedDimsArray + KeyedArray combination is callable:

@inline @propagate_inbounds (A::NdaKa)(args...) = getkey(A, args...)

@inline @propagate_inbounds (A::KaNda)(;kw...) = getkey(A; kw...)
@inline @propagate_inbounds (A::NdaKa)(;kw...) = getkey(A; kw...)

@inline @propagate_inbounds function getkey(A; kw...)
    list = dimnames(A)
    issubset(kw.itr, list) || error("some keywords not in list of names!")
    args = map(s -> Base.sym_in(s, kw.itr) ? getfield(kw.data, s) : Colon(), list)
    A(args...)
end

# Constructors, including pirate method (A; kw...)

_construc_doc = """
    KeyedArray(A; i=2:3, j=["a", "b"])
    NamedDimsArray(A; i=2:3, j=["a", "b"])

These constructors make `KeyedArray(NamedDimsArray(A, names), keys)`
or `NamedDimsArray(KeyedArray(A, keys), names)`, which should be equivalent.

These perform less sanity checking than `wrapdims(A; kw...)`.
"""
@doc _construc_doc
function KeyedArray(A::AbstractArray; kw...)
    L = keys(values(kw))
    length(L) == ndims(A) || throw(ArgumentError("number of names must match number of dimensions"))
    R = values(values(kw))
    map(x -> axes(x, 1), R) == axes(A) || throw(ArgumentError("axes of keys must match axes of array"))
    KeyedArray(NamedDimsArray(A, L), R)
end

@doc _construc_doc
function NamedDims.NamedDimsArray(A::AbstractArray; kw...)
    L = keys(values(kw))
    length(L) == ndims(A) || throw(ArgumentError("number of names must match number of dimensions"))
    R = values(values(kw))
    map(x -> axes(x, 1), R) == axes(A) || throw(ArgumentError("axes of keys must match axes of array"))
    NamedDimsArray(KeyedArray(A, R), L)
end

"""
    named_axiskeys(arr)::NamedTuple

Return the [`axiskeys`](@ref) along with their names.
If there are duplicate names or unnamed axes, an error is thrown.

```jldoctest
julia> using AxisKeys

julia> arr = KeyedArray(rand(1,3), x=[1], y=[2,3,4]);

julia> named_axiskeys(arr)
(x = [1], y = [2, 3, 4])
```
"""
function named_axiskeys(A::AbstractArray)
    NT = NamedTuple{dimnames(A)}
    NT(axiskeys(A))
end
