module BrenierTwoFluid

using Distances
using Base.Threads
using Plots
using LaTeXStrings
using LinearAlgebra

include("costs.jl")
export LazyCost, CostCollection, c_periodic, ∇c_periodic

include("sinkhornvariable.jl")
export SinkhornVariable, initialize_potentials_nolog!, initialize_potentials_log!

include("sinkhornparameters.jl")
export SinkhornParameters

include("sinkhorndivergence.jl")
export SinkhornDivergence, softmin, sinkhorn_step!, value, compute!, x_gradient!, x_gradient, y_gradient, y_gradient!
export scale, maxit, tol, acceleration, marginal_error
export initialize_potentials!

include("barycenter.jl")
export SinkhornBarycenter, compute!

include("transportplans.jl")
export TransportPlan, transportmatrix

include("plotting.jl")
export plot

end
