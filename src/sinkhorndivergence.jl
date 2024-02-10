mutable struct SinkhornParameters{SAFE, SYM, ACC, T}
    Δ::T #diameter
    q::T #scaling parameter

    ω::T #acceleration parameter
    crit_it::Int #iteration number when ω is inferred
    p_ω::Int # ω is inferred comparing the residual at crit_it to that at crit_it - p_ω

    s::T #current scale
    ε::T #minimum scale

    p::T #ε ∼ x^p
    tol::T #tolerance
    max_it::Int

    function SinkhornParameters(Δ::T, q::T, ω::T, crit_it::Int, p_ω::Int, s::T, ε::T, p::T, tol::T, max_it, sym, acc) where {T}
        if tol == Inf
            SAFE = false
        else
            SAFE = true
        end
        new{SAFE, sym, acc, T}(Δ, q, ω, crit_it, p_ω, s, ε, p, tol, max_it)
    end
end

function SinkhornParameters(;
    Δ = 1.0,
    q = 1.0,
    ω = 1.0,
    crit_it = 20,
    p_ω = 2,
    ε = 1e-2,
    s = ε,
    p = 2.0,
    tol = 1e-6,
    max_it = Int(ceil(10 * Δ/ε)),
    sym = false,
    acc = true)
SinkhornParameters(Δ, q, ω, crit_it, p_ω, s, ε, p, tol, max_it, sym, acc)
end

"""
SinkhornDivergence

Struct that holds two SinkhornVariables, a CostCollection, and SinkhornParameters. This is what most functions operate and dispatch on.
"""
struct SinkhornDivergence{LOG, SAFE, SYM, ACC, T, d, AT, VT, CT}
    V1::SinkhornVariable{T,d,AT,VT} #X, α, log(α), f, f₋, h, h₋
    V2::SinkhornVariable{T,d,AT,VT}
    CC::CostCollection{T,CT}        #C_xy, C_yx, C_xx, C_yy
    params::SinkhornParameters{SAFE, SYM, ACC, T}

    function SinkhornDivergence(V::SinkhornVariable{T,d,AT,VT}, 
                                W::SinkhornVariable{T,d,AT,VT}, 
                                CC::CostCollection{T,CT}, 
                                params::SinkhornParameters{SAFE, SYM, ACC, T},
                                log) where {SAFE, SYM, ACC, T, d, AT, VT, CT}
        new{log, SAFE, SYM, ACC, T, d, AT, VT, CT}(V, W, CC, params)
    end
end

function SinkhornDivergence(V::SinkhornVariable, W::SinkhornVariable, c::FT, params::SinkhornParameters, log) where {FT<:Base.Callable}
    CC = CostCollection(V.X, W.X, c)
    SinkhornDivergence(V, W, CC, params, log)
end


#
# Aliases
#

const LogSinkhornDivergence = SinkhornDivergence{true}
const NologSinkhornDivergence = SinkhornDivergence{false}

const SafeSinkhornDivergence = SinkhornDivergence{LOG, true} where {LOG}
const UnsafeSinkhornDivergence = SinkhornDivergence{LOG, false} where {LOG}

const SymmetricSinkhornDivergence = SinkhornDivergence{LOG, SAFE, true} where {LOG, SAFE}
const AsymmetricSinkhornDivergence = SinkhornDivergence{LOG, SAFE, false} where {LOG, SAFE}

const LogSymmetricSinkhornDivergence = SinkhornDivergence{true, SAFE, true} where {SAFE}
const NologSymmetricSinkhornDivergence = SinkhornDivergence{false, SAFE, true} where {SAFE}
const LogAsymmetricSinkhornDivergence = SinkhornDivergence{true, SAFE, false} where {SAFE}
const NologAsymmetricSinkhornDivergence = SinkhornDivergence{false, SAFE, false} where {SAFE}

const AcceleratedSinkhornDivergence = SinkhornDivergence{LOG, SAFE, SYM, true} where {LOG, SAFE, SYM}

#
# Convenience
#

islog(S::SinkhornDivergence{LOG}) where LOG = LOG
issafe(S::SinkhornDivergence{LOG, SAFE}) where {LOG, SAFE} = SAFE
issymmetric(S::SinkhornDivergence{LOG, SAFE, SYM}) where {LOG, SAFE, SYM} = SYM
isaccelerated(S::SinkhornDivergence{LOG, SAFE, SYM, ACC}) where {LOG, SAFE, SYM, ACC} = ACC
scale(S::SinkhornDivergence) = S.params.s
max_it(S::SinkhornDivergence) = S.params.max_it
tol(S::SinkhornDivergence) = S.params.tol
minscale(S::SinkhornDivergence) = S.params.ε
acceleration(S::SinkhornDivergence) = S.params.ω

function initialize_potentials!(S::LogSinkhornDivergence)
    initialize_potentials_log!(S.V1, S.V2, S.CC)
end

function initialize_potentials!(S::NologSinkhornDivergence)
    initialize_potentials_nolog!(S.V1, S.V2, S.CC)
end

"""
softmin

[Streaming log-sum-exp calculation](https://www.nowozin.net/sebastian/blog/streaming-log-sum-exp-computation.html)
"""
function softmin(j, C::AbstractMatrix{T}, f::AbstractVector{T}, log_α::AbstractVector{T}, ε::T) where T
    M = -Inf
    r = 0.0
    # this is serial for now 
    @inbounds for i in eachindex(f)
        v = (f[i] - C[i,j])/ε + log_α[i]
        if v <= M
            r += exp(v-M)
        else
            r *= exp(M-v)
            r += 1
            M = v
        end
    end
    return (- ε * (log(r) + M))
end

"""
sinkhorn_step!

One iteration of the Sinkhorn algorithm.
"""
function sinkhorn_step!(S::LogSymmetricSinkhornDivergence)
    @threads for i in eachindex(S.V1.f)
        @inbounds S.V1.f[i] = 1/2 * S.V1.f₋[i] + 1/2 * softmin(i, S.CC.C_yx, S.V2.f₋, S.V2.log_α, scale(S))
        @inbounds S.V1.h[i] = 1/2 * S.V1.h₋[i] + 1/2 * softmin(i, S.CC.C_xx, S.V1.h₋, S.V1.log_α, scale(S))
        if isaccelerated(S) # the symmetric problem is never accelerated
            @inbounds S.V1.f[i] = (1 - acceleration(S)) * S.V1.f₋[i] + acceleration(S) * S.V1.f[i]
        end
    end
    @threads for j in eachindex(S.V2.f)
        @inbounds S.V2.f[j] = 1/2 * S.V2.f₋[j] + 1/2 * softmin(j, S.CC.C_xy, S.V1.f₋, S.V1.log_α, scale(S))
        @inbounds S.V2.h[j] = 1/2 * S.V2.h[j] + 1/2 * softmin(j, S.CC.C_yy, S.V2.h₋, S.V2.log_α, scale(S))
        if isaccelerated(S)
            @inbounds S.V2.f[j] = (1 - acceleration(S)) * S.V2.f₋[j] + acceleration(S) * S.V2.f[j]
        end
    end
end

function sinkhorn_step!(S::LogAsymmetricSinkhornDivergence)
    @threads for i in eachindex(S.V1.f)
        @inbounds S.V1.f[i] = softmin(i, S.CC.C_yx, S.V2.f₋, S.V2.log_α, scale(S))
        @inbounds S.V1.h[i] = 1/2 * S.V1.h₋[i] + 1/2 * softmin(i, S.CC.C_xx, S.V1.h₋, S.V1.log_α, scale(S))
        if isaccelerated(S) # the symmetric problem is never accelerated
            @inbounds S.V1.f[i] = (1 - acceleration(S)) * S.V1.f₋[i] + acceleration(S) * S.V1.f[i]
        end
    end
    @threads for j in eachindex(S.V2.f)
        @inbounds S.V2.f[j] = softmin(j, S.CC.C_xy, S.V1.f, S.V1.log_α, scale(S)) # note that we are using the 'new' S.V1.f here
        @inbounds S.V2.h[j] = 1/2 * S.V2.h[j] + 1/2 * softmin(j, S.CC.C_yy, S.V2.h₋, S.V2.log_α, scale(S))
        if isaccelerated(S)
            @inbounds S.V2.f[j] = (1 - acceleration(S)) * S.V2.f₋[j] + acceleration(S) * S.V2.f[j]
        end
    end
end

function sinkhorn_step!(S::NologAsymmetricSinkhornDivergence)
    ε = scale(S)
    S.V1.f .= S.V1.α ./ ( exp.( -1 .* S.CC.C_yx ./ ε) * S.V2.f₋ )
    S.V1.h .= sqrt.( S.V1.h₋ .* S.V1.α ./ ( exp.( -1 .* S.CC.C_xx ./ ε) * S.V1.h₋ ) )
    if isaccelerated(S) # the symmetric problem is never accelerated
        S.V1.f .= S.V1.f₋.^(1 - acceleration(S)) .* S.V1.f.^acceleration(S)
    end
    S.V2.f .= S.V2.α ./ ( exp.( -1 .* S.CC.C_xy ./ ε) * S.V1.f )
    S.V2.h .= sqrt.( S.V2.h₋ .* S.V2.α ./ ( exp.( -1 .* S.CC.C_yy ./ ε) * S.V2.h₋ ) )
    if isaccelerated(S) # the symmetric problem is never accelerated
        S.V2.f .= S.V2.f₋.^(1 - acceleration(S)) .* S.V2.f.^acceleration(S)
    end
end

"""
compute!

Solve the OT problem, i.e. do a bunch of Sinkhorn interations. Unsafe version.
"""
function compute!(S::UnsafeSinkhornDivergence)
    it = 1
    r_p = 0
    while scale(S) >= minscale(S)
        # do one sinkhorn iteration
        sinkhorn_step!(S)
        S.V1.f₋ .= S.V1.f
        S.V2.f₋ .= S.V2.f
        S.V1.h₋ .= S.V1.h
        S.V2.h₋ .= S.V2.h # perhaps these updates can be avoided in some cases
        
        # lower the scale
        S.params.s = scale(S) * S.params.q
        
        if isaccelerated(S)
            if it == S.params.crit_it - S.params.p_ω
                r_p = marginal_error(S)
            elseif it == S.params.crit_it
                θ²_est = (marginal_error(S)/r_p)^(1/S.params.p_ω)
                if θ²_est >= 1
                    θ²_est = 0.95 # θ² can be larger than one if the estimate is bad, which would lead to complex ω
                end
                S.params.ω = 2 / (1 + sqrt(1 - θ²_est))
            end
        end
        it += 1
    end
    return value(S)
end

"""
compute!

Solve the OT problem, i.e. do a bunch of Sinkhorn interations. Safe version.
"""
function compute!(S::SafeSinkhornDivergence)
    r_p = 0
    for it in 1:max_it(S)
        # do one sinkhorn step
        sinkhorn_step!(S)

        # tolerance criterion: marginal violation
        if it % 5 == 0 # TODO: make this 5 a parameter
            # we check only one marginal because there is no reason they should be different. When using no acceleration and no symmetrization, π1_err == 0 anyway
            if marginal_error(S) < tol(S)
                break
            end
        end
        S.V1.f₋ .= S.V1.f
        S.V2.f₋ .= S.V2.f
        S.V1.h₋ .= S.V1.h
        S.V2.h₋ .= S.V2.h # perhaps these updates can be avoided in some cases

        # lower the scale
        if S.params.q != 1
            S.params.s = maximum((scale(S) * S.params.q, minscale(S)))
        end
        
        if isaccelerated(S)
            if it == S.params.crit_it - S.params.p_ω
                r_p = marginal_error(S)
            elseif it == S.params.crit_it
                θ²_est = (marginal_error(S)/r_p)^(1/S.params.p_ω)
                if θ²_est >= 1
                    θ²_est = 0.95 # θ² can be larger than one if the estimate is bad, which would lead to complex ω
                end
                S.params.ω = 2 / (1 + sqrt(1 - θ²_est))
            end
        end
        it += 1
    end
    return value(S)
end

function marginal_errors(S::LogSinkhornDivergence)
    π1_err = 0.0
    π2_err = 0.0
    # serial for now
    @inbounds for i in eachindex(S.V1.f)
        sm_i = softmin(i, S.CC.C_yx, S.V2.f, S.V2.log_α, scale(S))
        r = abs( exp( (S.V1.f[i] - sm_i) / scale(S) ) - 1 )
        # Linf
        if r > π2_err
            π2_err = r
        end
        # L1
        # π2_err += r * S.V1.α[i]
    end
    @inbounds for j in eachindex(S.V2.f)
        sm_j = softmin(j, S.CC.C_xy, S.V1.f, S.V1.log_α, scale(S))
        π1_err += abs( exp( (S.V2.f[j] - sm_j) / scale(S) ) - 1 ) * S.V2.α[j]
    end
    return π1_err, π2_err
end

function marginal_error(S::NologSinkhornDivergence)
    return sum(abs.( S.V1.α .- S.V1.f .* ( exp.( -1 .* S.CC.C_yx ./ scale(S)) * S.V2.f ) ))
end

function marginal_error(S::LogSinkhornDivergence)
    π2_err = 0.0
    # serial for now
    @inbounds for i in eachindex(S.V1.f)
        sm_i = softmin(i, S.CC.C_yx, S.V2.f, S.V2.log_α, scale(S))
        r = abs( exp( (S.V1.f[i] - sm_i) / scale(S) ) - 1 )
        # Linf
        if r > π2_err
            π2_err = r
        end
        # L1
        # π2_err += r * S.V1.α[i]
    end
    return π2_err
end

function value(S::LogSinkhornDivergence)
    return (S.V1.f - S.V1.h)' * S.V1.α + (S.V2.f - S.V2.h)' * S.V2.α
end

function value(S::NologSinkhornDivergence)
    return scale(S) * ( (log.(S.V1.f) - log.(S.V1.h))' * S.V1.α + (log.(S.V2.f) .- log.(S.V2.h))' * S.V2.α )
end

function x_gradient!(S::LogSinkhornDivergence, ∇c)
    X = S.V1.X
    Y = S.V2.X
    g = S.V2.f
    f = S.V1.f
    ε = scale(S)
    ∇S = S.V1.∇fh
    ∇S .= 0
    for i in eachindex(f)
        # W(α,β) term
        for j in eachindex(g)
            v = exp((g[j] + f[i] - S.CC.C_xy[i,j])/ε) * S.V2.α[j]
            ∇S[i,:] .+= v .* ∇c(X[i,:],Y[j,:])
        end
        # W(α,α) term
        for k in eachindex(S.V1.h)
            v = exp((S.V1.h[k] + S.V1.h[i] - S.CC.C_xx[i,k])/ε) * S.V1.α[k]
            ∇S[i,:] .-= v .* ∇c(X[i,:],X[k,:])
        end
    end
    ∇S
end

function y_gradient!(S::LogSinkhornDivergence, ∇c)
    X = S.V1.X
    Y = S.V2.X
    g = S.V2.f
    f = S.V1.f
    ε = scale(S)
    ∇S = S.V2.∇fh
    ∇S .= 0
    for j in eachindex(g)
        # W(α,β) term
        for i in eachindex(f)
            v = exp((g[j] + f[i] - S.CC.C_yx[j,i])/ε) * S.V1.α[i]
            ∇S[j,:] .+= v .* ∇c(Y[j,:],X[i,:])
        end
        # W(β,β) term
        for k in eachindex(S.V2.h)
            v = exp((S.V2.h[k] + S.V2.h[j] - S.CC.C_yy[j,k])/ε) * S.V2.α[k]
            ∇S[j,:] .-= v .* ∇c(Y[j,:],Y[k,:])
        end
    end
    ∇S
end