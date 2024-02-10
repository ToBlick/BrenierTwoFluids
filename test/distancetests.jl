# compute W_2 distance between two uniform distributions
using BrenierTwoFluid
using Test
using Distances
using Random
using LinearAlgebra

c = (x,y) -> 0.5 * sqeuclidean(x,y)
∇c = (x,y) -> x - y
d = 3
N = 30^2
M = 30^2
α = ones(N) / N
β = ones(M) / M

d′ = 2*Int(floor(d/2))
ε = 0.1                 # entropic regularization. √ε is a length.
q = 1.0                 # annealing parameter
Δ = 1.0                 # characteristic domain size
s = ε                   # current scale: no annealing -> equals ε
tol = 1e-8              # marginal condition tolerance
crit_it = 20            # acceleration inferrence
p_ω = 2

offset = 0.5

Random.seed!(123)
X = rand(N,d) .- 0.5
Y = rand(M,d) .- 0.5

for i in 1:2
        if i == 1 # Scaling test
                truevalue = 1/2 * d * 1/12 * offset^2 #1/2 * d * offset^2
                Y .= (rand(M,d) .- 0.5) .* (1 + offset)
        else # Shifting test
                truevalue = 1/2 * d * offset^2
                Y .= (rand(M,d) .- 0.5) .+ offset
        end

        V = SinkhornVariable(X,α)
        W = SinkhornVariable(Y,β)

        # no acc, no sym
        params = SinkhornParameters(ε=ε,q=1.0,Δ=1.0,s=s,tol=tol,crit_it=crit_it,p_ω=p_ω,sym=false,acc=false)
        S = SinkhornDivergence(V,W,c,params,true)
        initialize_potentials!(S)
        valueS = compute!(S)
        @test abs(valueS - truevalue) < (sqrt(N*M))^(-2/(d′+4))

        # no acc, no sym, no log
        params = SinkhornParameters(ε=ε,q=1.0,Δ=1.0,s=s,tol=tol,crit_it=crit_it,p_ω=p_ω,sym=false,acc=false)
        S = SinkhornDivergence(V,W,c,params,false)
        initialize_potentials!(S)
        valueS = compute!(S)
        @test abs(valueS - truevalue) < (sqrt(N*M))^(-2/(d′+4))

        # acc, no sym
        params = SinkhornParameters(ε=ε,q=1.0,Δ=1.0,s=s,tol=tol,crit_it=crit_it,p_ω=p_ω,sym=false,acc=true)
        S = SinkhornDivergence(V,W,c,params,true)
        initialize_potentials!(S)
        valueS = compute!(S)
        @test abs(valueS - truevalue) < (sqrt(N*M))^(-2/(d′+4))

        # acc, sym
        params = SinkhornParameters(ε=ε,q=1.0,Δ=1.0,s=s,tol=tol,crit_it=crit_it,p_ω=p_ω,sym=true,acc=true)
        S = SinkhornDivergence(V,W,c,params,true)
        initialize_potentials!(S)
        valueS = compute!(S)
        @test abs(valueS - truevalue) < (sqrt(N*M))^(-2/(d′+4))

        # no acc, sym
        params = SinkhornParameters(ε=ε,q=1.0,Δ=1.0,s=s,tol=tol,crit_it=crit_it,p_ω=p_ω,sym=true,acc=false)
        S = SinkhornDivergence(V,W,c,params,true)
        initialize_potentials!(S)
        valueS = compute!(S)
        @test abs(valueS - truevalue) < (sqrt(N*M))^(-2/(d′+4))
end