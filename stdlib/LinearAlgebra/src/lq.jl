# This file is a part of Julia. License is MIT: https://julialang.org/license

# LQ Factorizations
"""
    LQ <: Factorization

Matrix factorization type of the `LQ` factorization of a matrix `A`. The `LQ`
decomposition is the [`QR`](@ref) decomposition of `transpose(A)`. This is the return
type of [`lq`](@ref), the corresponding matrix factorization function.

If `S::LQ` is the factorization object, the lower triangular component can be
obtained via `S.L`, and the orthogonal/unitary component via `S.Q`, such that
`A ≈ S.L*S.Q`.

Iterating the decomposition produces the components `S.L` and `S.Q`.

# Examples
```jldoctest
julia> A = [5. 7.; -2. -4.]
2×2 Matrix{Float64}:
  5.0   7.0
 -2.0  -4.0

julia> S = lq(A)
LQ{Float64, Matrix{Float64}, Vector{Float64}}
L factor:
2×2 Matrix{Float64}:
 -8.60233   0.0
  4.41741  -0.697486
Q factor:
2×2 LinearAlgebra.LQPackedQ{Float64, Matrix{Float64}, Vector{Float64}}:
 -0.581238  -0.813733
 -0.813733   0.581238

julia> S.L * S.Q
2×2 Matrix{Float64}:
  5.0   7.0
 -2.0  -4.0

julia> l, q = S; # destructuring via iteration

julia> l == S.L &&  q == S.Q
true
```
"""
struct LQ{T,S<:AbstractMatrix{T},C<:AbstractVector{T}} <: Factorization{T}
    factors::S
    τ::C

    function LQ{T,S,C}(factors, τ) where {T,S<:AbstractMatrix{T},C<:AbstractVector{T}}
        require_one_based_indexing(factors)
        new{T,S,C}(factors, τ)
    end
end
LQ(factors::AbstractMatrix{T}, τ::AbstractVector{T}) where {T} =
    LQ{T,typeof(factors),typeof(τ)}(factors, τ)
LQ{T}(factors::AbstractMatrix, τ::AbstractVector) where {T} =
    LQ(convert(AbstractMatrix{T}, factors), convert(AbstractVector{T}, τ))
# backwards-compatible constructors (remove with Julia 2.0)
@deprecate(LQ{T,S}(factors::AbstractMatrix{T}, τ::AbstractVector{T}) where {T,S},
           LQ{T,S,typeof(τ)}(factors, τ), false)

# iteration for destructuring into components
Base.iterate(S::LQ) = (S.L, Val(:Q))
Base.iterate(S::LQ, ::Val{:Q}) = (S.Q, Val(:done))
Base.iterate(S::LQ, ::Val{:done}) = nothing

struct LQPackedQ{T,S<:AbstractMatrix{T},C<:AbstractVector{T}} <: AbstractMatrix{T}
    factors::S
    τ::C
end


"""
    lq!(A) -> LQ

Compute the [`LQ`](@ref) factorization of `A`, using the input
matrix as a workspace. See also [`lq`](@ref).
"""
lq!(A::StridedMatrix{<:BlasFloat}) = LQ(LAPACK.gelqf!(A)...)
"""
    lq(A) -> S::LQ

Compute the LQ decomposition of `A`. The decomposition's lower triangular
component can be obtained from the [`LQ`](@ref) object `S` via `S.L`, and the
orthogonal/unitary component via `S.Q`, such that `A ≈ S.L*S.Q`.

Iterating the decomposition produces the components `S.L` and `S.Q`.

The LQ decomposition is the QR decomposition of `transpose(A)`, and it is useful
in order to compute the minimum-norm solution `lq(A) \\ b` to an underdetermined
system of equations (`A` has more columns than rows, but has full row rank).

# Examples
```jldoctest
julia> A = [5. 7.; -2. -4.]
2×2 Matrix{Float64}:
  5.0   7.0
 -2.0  -4.0

julia> S = lq(A)
LQ{Float64, Matrix{Float64}, Vector{Float64}}
L factor:
2×2 Matrix{Float64}:
 -8.60233   0.0
  4.41741  -0.697486
Q factor:
2×2 LinearAlgebra.LQPackedQ{Float64, Matrix{Float64}, Vector{Float64}}:
 -0.581238  -0.813733
 -0.813733   0.581238

julia> S.L * S.Q
2×2 Matrix{Float64}:
  5.0   7.0
 -2.0  -4.0

julia> l, q = S; # destructuring via iteration

julia> l == S.L &&  q == S.Q
true
```
"""
lq(A::AbstractMatrix{T}) where {T} = lq!(copy_similar(A, lq_eltype(T)))
lq(x::Number) = lq!(fill(convert(lq_eltype(typeof(x)), x), 1, 1))

lq_eltype(::Type{T}) where {T} = typeof(zero(T) / sqrt(abs2(one(T))))

copy(A::LQ) = LQ(copy(A.factors), copy(A.τ))

LQ{T}(A::LQ) where {T} = LQ(convert(AbstractMatrix{T}, A.factors), convert(Vector{T}, A.τ))
Factorization{T}(A::LQ) where {T} = LQ{T}(A)

AbstractMatrix(A::LQ) = A.L*A.Q
AbstractArray(A::LQ) = AbstractMatrix(A)
Matrix(A::LQ) = Array(AbstractArray(A))
Array(A::LQ) = Matrix(A)

adjoint(A::LQ) = Adjoint(A)
Base.copy(F::Adjoint{T,<:LQ{T}}) where {T} =
    QR{T,typeof(F.parent.factors),typeof(F.parent.τ)}(copy(adjoint(F.parent.factors)), copy(F.parent.τ))

function getproperty(F::LQ, d::Symbol)
    m, n = size(F)
    if d === :L
        return tril!(getfield(F, :factors)[1:m, 1:min(m,n)])
    elseif d === :Q
        return LQPackedQ(getfield(F, :factors), getfield(F, :τ))
    else
        return getfield(F, d)
    end
end

Base.propertynames(F::LQ, private::Bool=false) =
    (:L, :Q, (private ? fieldnames(typeof(F)) : ())...)

getindex(A::LQPackedQ, i::Integer, j::Integer) =
    lmul!(A, setindex!(zeros(eltype(A), size(A, 2)), 1, j))[i]

function show(io::IO, mime::MIME{Symbol("text/plain")}, F::LQ)
    summary(io, F); println(io)
    println(io, "L factor:")
    show(io, mime, F.L)
    println(io, "\nQ factor:")
    show(io, mime, F.Q)
end

LQPackedQ{T}(Q::LQPackedQ) where {T} = LQPackedQ(convert(AbstractMatrix{T}, Q.factors), convert(Vector{T}, Q.τ))
AbstractMatrix{T}(Q::LQPackedQ) where {T} = LQPackedQ{T}(Q)
Matrix{T}(A::LQPackedQ) where {T} = convert(Matrix{T}, LAPACK.orglq!(copy(A.factors),A.τ))
Matrix(A::LQPackedQ{T}) where {T} = Matrix{T}(A)
Array{T}(A::LQPackedQ{T}) where {T} = Matrix{T}(A)
Array(A::LQPackedQ) = Matrix(A)

size(F::LQ, dim::Integer) = size(getfield(F, :factors), dim)
size(F::LQ)               = size(getfield(F, :factors))

# size(Q::LQPackedQ) yields the shape of Q's square form
function size(Q::LQPackedQ)
    n = size(Q.factors, 2)
    return n, n
end
function size(Q::LQPackedQ, dim::Integer)
    if dim < 1
        throw(BoundsError())
    elseif dim <= 2 # && 1 <= dim
        return size(Q.factors, 2)
    else # 2 < dim
        return 1
    end
end


## Multiplication by LQ
function lmul!(A::LQ, B::StridedVecOrMat)
    lmul!(LowerTriangular(A.L), view(lmul!(A.Q, B), 1:size(A,1), axes(B,2)))
    return B
end
function *(A::LQ{TA}, B::AbstractVecOrMat{TB}) where {TA,TB}
    TAB = promote_type(TA, TB)
    _cut_B(lmul!(convert(Factorization{TAB}, A), copy_similar(B, TAB)), 1:size(A,1))
end

## Multiplication by Q
### QB
lmul!(A::LQPackedQ{T}, B::StridedVecOrMat{T}) where {T<:BlasFloat} = LAPACK.ormlq!('L','N',A.factors,A.τ,B)
function (*)(A::LQPackedQ, B::StridedVecOrMat)
    TAB = promote_type(eltype(A), eltype(B))
    lmul!(AbstractMatrix{TAB}(A), copymutable_oftype(B, TAB))
end

### QcB
lmul!(adjA::Adjoint{<:Any,<:LQPackedQ{T}}, B::StridedVecOrMat{T}) where {T<:BlasReal} =
    (A = adjA.parent; LAPACK.ormlq!('L', 'T', A.factors, A.τ, B))
lmul!(adjA::Adjoint{<:Any,<:LQPackedQ{T}}, B::StridedVecOrMat{T}) where {T<:BlasComplex} =
    (A = adjA.parent; LAPACK.ormlq!('L', 'C', A.factors, A.τ, B))

function *(adjA::Adjoint{<:Any,<:LQPackedQ}, B::StridedVecOrMat)
    A = adjA.parent
    TAB = promote_type(eltype(A), eltype(B))
    if size(B,1) == size(A.factors,2)
        lmul!(adjoint(AbstractMatrix{TAB}(A)), copymutable_oftype(B, TAB))
    elseif size(B,1) == size(A.factors,1)
        lmul!(adjoint(AbstractMatrix{TAB}(A)), [B; zeros(TAB, size(A.factors, 2) - size(A.factors, 1), size(B, 2))])
    else
        throw(DimensionMismatch("first dimension of B, $(size(B,1)), must equal one of the dimensions of A, $(size(A))"))
    end
end

### QBc/QcBc
function *(A::LQPackedQ, adjB::Adjoint{<:Any,<:StridedVecOrMat})
    B = adjB.parent
    TAB = promote_type(eltype(A), eltype(B))
    BB = similar(B, TAB, (size(B, 2), size(B, 1)))
    adjoint!(BB, B)
    return lmul!(A, BB)
end
function *(adjA::Adjoint{<:Any,<:LQPackedQ}, adjB::Adjoint{<:Any,<:StridedVecOrMat})
    B = adjB.parent
    TAB = promote_type(eltype(adjA.parent), eltype(B))
    BB = similar(B, TAB, (size(B, 2), size(B, 1)))
    adjoint!(BB, B)
    return lmul!(adjA, BB)
end

# in-place right-application of LQPackedQs
# these methods require that the applied-to matrix's (A's) number of columns
# match the number of columns (nQ) of the LQPackedQ (Q) (necessary for in-place
# operation, and the underlying LAPACK routine (ormlq) treats the implicit Q
# as its (nQ-by-nQ) square form)
rmul!(A::StridedMatrix{T}, B::LQPackedQ{T}) where {T<:BlasFloat} =
    LAPACK.ormlq!('R', 'N', B.factors, B.τ, A)
rmul!(A::StridedMatrix{T}, adjB::Adjoint{<:Any,<:LQPackedQ{T}}) where {T<:BlasReal} =
    (B = adjB.parent; LAPACK.ormlq!('R', 'T', B.factors, B.τ, A))
rmul!(A::StridedMatrix{T}, adjB::Adjoint{<:Any,<:LQPackedQ{T}}) where {T<:BlasComplex} =
    (B = adjB.parent; LAPACK.ormlq!('R', 'C', B.factors, B.τ, A))

# out-of-place right application of LQPackedQs
#
# LQPackedQ's out-of-place multiplication behavior is context dependent. specifically,
# if the inner dimension in the multiplication is the LQPackedQ's second dimension,
# the LQPackedQ behaves like its square form. if the inner dimension in the
# multiplication is the LQPackedQ's first dimension, the LQPackedQ behaves like either
# its square form or its truncated form depending on the shape of the other object
# involved in the multiplication. we treat these cases separately.
#
# (1) the inner dimension in the multiplication is the LQPackedQ's second dimension.
# in this case, the LQPackedQ behaves like its square form.
#
function *(A::StridedVecOrMat, adjQ::Adjoint{<:Any,<:LQPackedQ})
    Q = adjQ.parent
    TR = promote_type(eltype(A), eltype(Q))
    return rmul!(copymutable_oftype(A, TR), adjoint(AbstractMatrix{TR}(Q)))
end
function *(adjA::Adjoint{<:Any,<:StridedMatrix}, adjQ::Adjoint{<:Any,<:LQPackedQ})
    A, Q = adjA.parent, adjQ.parent
    TR = promote_type(eltype(A), eltype(Q))
    C = adjoint!(similar(A, TR, reverse(size(A))), A)
    return rmul!(C, adjoint(AbstractMatrix{TR}(Q)))
end
#
# (2) the inner dimension in the multiplication is the LQPackedQ's first dimension.
# in this case, the LQPackedQ behaves like either its square form or its
# truncated form depending on the shape of the other object in the multiplication.
#
# these methods: (1) check whether the applied-to matrix's (A's) appropriate dimension
# (columns for A_*, rows for Ac_*) matches the number of columns (nQ) of the LQPackedQ (Q),
# and if so effectively apply Q's square form to A without additional shenanigans; and
# (2) if the preceding dimensions do not match, check whether the appropriate dimension of
# A instead matches the number of rows of the matrix of which Q is a factor (i.e.
# size(Q.factors, 1)), and if so implicitly apply Q's truncated form to A by zero extending
# A as necessary for check (1) to pass (if possible) and then applying Q's square form
#
function *(A::StridedVecOrMat, Q::LQPackedQ)
    TR = promote_type(eltype(A), eltype(Q))
    if size(A, 2) == size(Q.factors, 2)
        C = copymutable_oftype(A, TR)
    elseif size(A, 2) == size(Q.factors, 1)
        C = zeros(TR, size(A, 1), size(Q.factors, 2))
        copyto!(C, 1, A, 1, length(A))
    else
        _rightappdimmismatch("columns")
    end
    return rmul!(C, AbstractMatrix{TR}(Q))
end
function *(adjA::Adjoint{<:Any,<:StridedMatrix}, Q::LQPackedQ)
    A = adjA.parent
    TR = promote_type(eltype(A), eltype(Q))
    if size(A, 1) == size(Q.factors, 2)
        C = adjoint!(similar(A, TR, reverse(size(A))), A)
    elseif size(A, 1) == size(Q.factors, 1)
        C = zeros(TR, size(A, 2), size(Q.factors, 2))
        adjoint!(view(C, :, 1:size(A, 1)), A)
    else
        _rightappdimmismatch("rows")
    end
    return rmul!(C, AbstractMatrix{TR}(Q))
end
_rightappdimmismatch(rowsorcols) =
    throw(DimensionMismatch(string("the number of $(rowsorcols) of the matrix on the left ",
        "must match either (1) the number of columns of the (LQPackedQ) matrix on the right ",
        "or (2) the number of rows of that (LQPackedQ) matrix's internal representation ",
        "(the factorization's originating matrix's number of rows)")))

# With a real lhs and complex rhs with the same precision, we can reinterpret
# the complex rhs as a real rhs with twice the number of columns
function (\)(F::LQ{T}, B::VecOrMat{Complex{T}}) where T<:BlasReal
    require_one_based_indexing(B)
    X = zeros(T, size(F,2), 2*size(B,2))
    X[1:size(B,1), 1:size(B,2)] .= real.(B)
    X[1:size(B,1), size(B,2)+1:size(X,2)] .= imag.(B)
    ldiv!(F, X)
    return reshape(copy(reinterpret(Complex{T}, copy(transpose(reshape(X, div(length(X), 2), 2))))),
                           isa(B, AbstractVector) ? (size(F,2),) : (size(F,2), size(B,2)))
end


function ldiv!(A::LQ, B::StridedVecOrMat)
    require_one_based_indexing(B)
    m, n = size(A)
    m ≤ n || throw(DimensionMismatch("LQ solver does not support overdetermined systems (more rows than columns)"))

    ldiv!(LowerTriangular(A.L), view(B, 1:size(A,1), axes(B,2)))
    return lmul!(adjoint(A.Q), B)
end

function ldiv!(Fadj::Adjoint{<:Any,<:LQ}, B::StridedVecOrMat)
    require_one_based_indexing(B)
    m, n = size(Fadj)
    m >= n || throw(DimensionMismatch("solver does not support underdetermined systems (more columns than rows)"))

    F = parent(Fadj)
    lmul!(F.Q, B)
    ldiv!(UpperTriangular(adjoint(F.L)), view(B, 1:size(F,1), axes(B,2)))
    return B
end

# In LQ factorization, `Q` is expressed as the product of the adjoint of the
# reflectors.  Thus, `det` has to be conjugated.
det(Q::LQPackedQ) = conj(_det_tau(Q.τ))
