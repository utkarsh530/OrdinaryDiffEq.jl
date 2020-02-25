using OrdinaryDiffEq, StaticArrays, Test

f = function (out,du,u,p,t)
  out[1] = - 0.04u[1]              + 1e4*u[2]*u[3] - du[1]
  out[2] = + 0.04u[1] - 3e7*u[2]^2 - 1e4*u[2]*u[3] - du[2]
  out[3] = u[1] + u[2] + u[3] - 1.0
end

u₀ = [1.0, 0, 0]
du₀ = [0.0, 0.0, 0.0]
tspan = (0.0,100000.0)
differential_vars = [true,true,false]
prob = DAEProblem(f,du₀,u₀,tspan,differential_vars=differential_vars)
integrator = init(prob, DABDF2())

@test integrator.cache.du[1] ≈ -0.04 atol=1e-9
@test integrator.cache.du[2] ≈  0.04 atol=1e-9
@test integrator.u[3] ≈ 0.0 atol=1e-9

integrator = init(prob, DImplicitEuler())

@test integrator.cache.du[1] ≈ -0.04 atol=1e-9
@test integrator.cache.du[2] ≈  0.04 atol=1e-9
@test integrator.u[3] ≈ 0.0 atol=1e-9

# Need to be able to find the consistent solution of this problem, broken right now
# analytical solution:
# 	u[1](t) ->  cos(t)
#	u[2](t) -> -sin(t)
#	u[3](t) -> 2cos(t)
f = function (out,du,u,p,t)
	out[1] = du[1] - u[2]
	out[2] = du[2] + u[3] - cos(t)
	out[3] = u[1] - cos(t)
end

u₀ = [1.0, 0.0, 0.0]
du₀ = [0.0, 0.0, 0.0]
tspan = (0.0,1.0)
differential_vars = [true, true, false]
prob = DAEProblem(f,du₀,u₀,tspan,differential_vars=differential_vars)
integrator = init(prob, DABDF2())

@test integrator.cache.du[1] ≈ 0.0 atol=1e-9
@test_broken integrator.cache.du[2] ≈ -1.0 atol=1e-9
@test_broken integrator.u[3] ≈ 2.0 atol=1e-9

f = function (du,u,p,t)
	du - u
end

u₀ = 1.0
du₀ = 0.0
tspan = (0.0,1.0)
differential_vars = [true]
prob = DAEProblem(f,du₀,u₀,tspan,differential_vars=differential_vars)
integrator = init(prob, DABDF2())

@test integrator.cache.du ≈ 1.0 atol=1e-9

f = function (du,u,p,t)
	du .- u
end

u₀ = SA[1.0, 1.0]
du₀ = SA[0.0, 0.0]
tspan = (0.0,1.0)
differential_vars = [true, true]
prob = DAEProblem(f,du₀,u₀,tspan,differential_vars=differential_vars)
integrator = init(prob, DABDF2())

@test integrator.cache.du[1] ≈ 1.0 atol=1e-9
@test integrator.cache.du[2] ≈ 1.0 atol=1e-9
