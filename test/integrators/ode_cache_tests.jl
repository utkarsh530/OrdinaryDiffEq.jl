using OrdinaryDiffEq, DiffEqBase, DiffEqCallbacks, Test
using Random
Random.seed!(213)
CACHE_TEST_ALGS = [Euler(),Midpoint(),RK4(),SSPRK22(),SSPRK33(),
  CarpenterKennedy2N54(), HSLDDRK64(),
  CFRLDDRK64(), TSLDDRK74(),
  CKLLSRK43_2(),
  ParsaniKetchesonDeconinck3S32(),
  BS3(),BS5(),DP5(),DP8(),Feagin10(),Feagin12(),Feagin14(),TanYam7(),
  Tsit5(),TsitPap8(),Vern6(),Vern7(),Vern8(),Vern9(),OwrenZen3(),OwrenZen4(),OwrenZen5(),
  AutoTsit5(Rosenbrock23())]
broken_CACHE_TEST_ALGS = [ORK256(), DGLDDRK73_C(),KenCarp4()]

using InteractiveUtils

NON_IMPLICIT_ALGS = filter((x)->isconcretetype(x) && !OrdinaryDiffEq.isimplicit(x()),union(subtypes(OrdinaryDiffEq.OrdinaryDiffEqAlgorithm),subtypes(OrdinaryDiffEq.OrdinaryDiffEqAdaptiveAlgorithm)))

f = function (du,u,p,t)
  for i in 1:length(u)
    du[i] = (0.3/length(u))*u[i]
  end
end

condition = function (u,t,integrator)
  1-maximum(u)
end

affect! = function (integrator)
  u = integrator.u
  resize!(integrator,length(u)+1)
  maxidx = findmax(u)[2]
  Θ = rand()/5 + 0.25
  u[maxidx] = Θ
  u[end] = 1-Θ
  nothing
end

callback = ContinuousCallback(condition,affect!)

u0 = [0.2]
tspan = (0.0,10.0)
prob = ODEProblem(f,u0,tspan)

println("Check for stochastic errors")
for i in 1:10
  @test_nowarn sol = solve(prob,Tsit5(),callback=callback)
end

println("Check some other integrators")
sol = solve(prob,Rosenbrock23(chunk_size=1),callback=callback,dt=1/2)
@test length(sol[end]) > 1
sol = solve(prob,Rosenbrock32(chunk_size=1),callback=callback,dt=1/2)
@test length(sol[end]) > 1
@test_broken sol = solve(prob,KenCarp4(chunk_size=1),callback=callback,dt=1/2)
@test length(sol[end]) > 1
@test_broken sol = solve(prob,TRBDF2(chunk_size=1),callback=callback,dt=1/2)
@test length(sol[end]) > 1

for alg in CACHE_TEST_ALGS
  @show alg
  sol = solve(prob,alg,callback=callback,dt=1/2)
  @test length(sol[end]) > 1
end

for alg in broken_CACHE_TEST_ALGS
  @show alg
  @test_broken length(solve(prob,alg,callback=callback,dt=1/2)[end]) > 1
end


sol = solve(prob,Rodas4(chunk_size=1),callback=callback,dt=1/2)
@test length(sol[end]) > 1
sol = solve(prob,Rodas5(chunk_size=1),callback=callback,dt=1/2)
@test length(sol[end]) > 1


# Force switching

function f2(du,u,p,t)
  @assert length(u) == length(du) "length(u) = $(length(u)), length(du) = $(length(du)) at time $(t)"
  for i in 1:length(u)
    if t > 10
      du[i] = -10000*u[i]
    else
      du[i] = 0.3*u[i]
    end
  end
  return du
end

function condition2(u, t, integrator)
  1-maximum(u)
end

function affect2!(integrator)
  u = integrator.u
  resize!(integrator,length(u)+1)
  maxidx = findmax(u)[2]
  Θ = rand()
  u[maxidx] = Θ
  u[end] = 1-Θ
  nothing
end

callback = ContinuousCallback(condition2,affect2!)
u0 = [0.2]
tspan = (0.0,20.0)
prob = ODEProblem(f2,u0,tspan)
sol = solve(prob, AutoTsit5(Rosenbrock23()), callback=callback)
@test length(sol[end]) > 1
