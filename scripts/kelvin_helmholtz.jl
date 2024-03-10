using BrenierTwoFluid
using Distances
using Plots
using LinearAlgebra
using Random
using LaTeXStrings
using ProgressBars
using HDF5
using Dates

###
# WIP!
###


function c_periodic_x(x::VT,y::VT,D) where {T,VT <: AbstractVector{T}}
    d = 0
    for i in [1]
        if x[i] - y[i] > D[i]/2
            d += (x[i] - y[i] - D[i])^2
        elseif x[i] - y[i] < -D[i]/2
            d += (x[i] - y[i] + D[i])^2
        else
            d += (x[i] - y[i])^2
        end
    end
    d += (x[2] - y[2])^2
    0.5 * d
end

function ∇c_periodic_x(x,y,D)
    ∇c = zero(x)
    for i in [1]
        if x[i] - y[i] > D[i]/2
            ∇c[i] = x[i] - y[i] - D[i]
        elseif x[i] - y[i] < -D[i]/2
            ∇c[i] = (x[i] - y[i] + D[i])
        else
            ∇c[i] = x[i] - y[i]
        end
    end
    ∇c[2] = x[2] - y[2]
    ∇c
end

function enforce_periodicity_x!(X, D)
    for i in axes(X,1)
        if X[i,1] > D[1]/2
            X[i,1] -= D[1]
        elseif X[i,1] < -D[1]/2
            X[i,1] += D[1]
        end
    end
end

### Set output file
path = "runs/$(now()).hdf5"
###

### parameters
d = 2
D = [1,1]
c = (x,y) -> c_periodic_x(x,y,D)
∇c = (x,y) -> ∇c_periodic_x(x,y,D)

d′ = 2*floor(d/2)
ε = 0.001    # entropic regularization parameter

N = 70^2 #Int((ceil(1e-1/ε))^(d))  
#N = Int((ceil(1e-2/ε))^(d′+4))                  # particle number
M = N #Int((ceil(N^(1/d))^d))

q = 1.0         # ε-scaling rate
Δ = 1.0       # characteristic domain size
s = ε           # initial scale (ε)
tol = 1e-3      # tolerance on marginals (absolute)
max_it = 100
crit_it = 100    # when to compute acceleration
p_ω = 2         # acceleration heuristic

sym = false
acc = true

seed = 123

Δt = 1/100

Random.seed!(seed)
# initial conditions - identical
α = ones(N) / N
β = ones(M) / M
X = rand(N,d) .- 0.5;
Y = rand(M,d) .- 0.5;
#  uniform grid for background density
for k in 1:Int(sqrt(M))
    for l in 1:Int(sqrt(M))
        Y[(k-1)*Int(sqrt(M)) + l,:] .= [ k/(Int(sqrt(M))) - 1/(2*Int(sqrt(M))), l/(Int(sqrt(M))) - 1/(2*Int(sqrt(M)))] .- 1/2
    end
end
X .= Y
X .= X[sortperm(X[:,1]), :]
Y .= Y[sortperm(Y[:,1]), :];

shear(x) = 0.1 * cos(x[1]*2π*4)
color = ones(N)
for i in axes(X,1)
    if X[i,2] < shear(X[i,1]) 
        color[i] = 2
    end
end
# initial velocity
u0(x) = x[2] < shear(x[1]) ? [1.0,0] : [0.5,0] #[-cos(π*x[1])*sin(π*x[2]), sin(π*x[1])*cos(π*x[2])]
V = zero(X)
for i in axes(X)[1]
    V[i,:] .= u0(X[i,:])
end
# calculate initial distance
# Setup Sinkhorn
params = SinkhornParameters(ε=ε,q=q,Δ=Δ,s=s,tol=tol,ω=1.5,
                            crit_it=crit_it,p_ω=p_ω,max_it=max_it,sym=sym,acc=acc,tol_it=2);
S = SinkhornDivergence(SinkhornVariable(X, α),
                       SinkhornVariable(Y, β),
                       c,params,true)
initialize_potentials!(S)
∇S = zero(X)
initialize_potentials!(S)
@time valS = compute!(S)

K₀ = 0.5 * dot(V,diagm(α) * V) #0.25    # initial kinetic energy
λ² = 2 * Δt^-2 # 2*K₀/(δ^2) # 2*K₀/(δ^2 - valS)                  # relaxation to enforce dist < δ
      
t = 0
T = 0.25     # final time
nt = Int(ceil((T-t)/Δt))
p0(x) = 0.5 * (sin(π*x[1])^2 + sin(π*x[2])^2)
∇p(x) = π * [sin(π*x[1])*cos(π*x[1]), sin(π*x[2])*cos(π*x[2])]
solX = [ zero(X) for i in 1:(nt + 1) ]
solV = [ zero(V) for i in 1:(nt + 1) ]
solD = [ 0.0 for i in 1:(nt + 1) ]
sol∇S = [ zero(X) for i in 1:(nt + 1) ]
solX[1] = copy(X)
solV[1] = copy(V)
solD[1] = value(S)
sol∇S[1] = copy(x_gradient!(S, ∇c));

massvec = []
nomassvec = []
for i in 1:N
    if color[i] == 1
        push!(nomassvec, i)
    else
        push!(massvec, i)
    end
end

scatter([X[nomassvec,1]], [X[nomassvec,2]], label = false, markerstrokewidth=0, markersize = 2.5, color = :black, xlims = (-0.55,0.55), ylims = (-0.55,0.55))
scatter!([X[massvec,1]], [X[massvec,2]], label = false, markerstrokewidth=0, markersize = 2.5, color = :red, xlims = (-0.55,0.55), ylims = (-0.55,0.55))

# integrate
for it in ProgressBar(1:nt)
    X .+= 0.5 * Δt * V
    enforce_periodicity_x!(X, D)
    S.params.s = s  # if scaling is used it should be reset here
    initialize_potentials!(S)
    compute!(S)
    ∇S = x_gradient!(S, ∇c)
    V .-= Δt .* λ² .* ∇S
    X .+= 0.5 .* Δt .* V
    enforce_periodicity_x!(X, D)
    # diagnostics
    #initialize_potentials!(V1,V2,CC)
    #compute!(S)
    solX[1+it] = copy(X)
    solV[1+it] = copy(V)
    solD[1+it] = value(S)
    sol∇S[1+it] = copy(x_gradient!(S, ∇c))
end

    fid = h5open(path, "w")
    fid["X"] = [ solX[i][j,k] for i in eachindex(solX), j in axes(X,1), k in axes(X,2) ];
    fid["V"] = [ solV[i][j,k] for i in eachindex(solV), j in axes(V,1), k in axes(V,2) ];
    fid["D"] = solD
    fid["alpha"] = α
    fid["beta"] = α
    fid["grad"] = [ sol∇S[i][j,k] for i in eachindex(sol∇S), j in axes(X,1), k in axes(X,2) ];
    fid["lambda"] = sqrt(λ²)
    fid["epsilon"] = ε
    fid["tol"] = tol
    fid["crit_it"] = crit_it
    fid["p"] = p_ω
    fid["deltat"] = Δt
    close(fid)


anim = @animate for j in axes(solX,1)
    scatter([solX[j][nomassvec,1]], [solX[j][nomassvec,2]], label = false, markerstrokewidth=0, markersize = 2.5, color = :black, xlims = (-0.55,0.55), ylims = (-0.55,0.55))
    scatter!([solX[j][massvec,1]], [solX[j][massvec,2]], label = false, markerstrokewidth=0, markersize = 2.5, color = :red, xlims = (-0.55,0.55), ylims = (-0.55,0.55))
end
gif(anim, "figs/kelvin_helmholtz.gif", fps = 8)

