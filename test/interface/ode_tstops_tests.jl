using OrdinaryDiffEq, Test, Random
using DiffEqProblemLibrary.ODEProblemLibrary: importodeproblems; importodeproblems()
import DiffEqProblemLibrary.ODEProblemLibrary: prob_ode_linear
Random.seed!(100)

@testset "Tstops Tests on the Interval [0, 1]" begin
  prob = prob_ode_linear

  sol =solve(prob,Tsit5(),dt=1//2^(6),tstops=[1/2])
  @test 1//2 ∈ sol.t

  sol =solve(prob,RK4(),dt=1//3,tstops=[1/2], adaptive=false)
  @test sol.t == [0,1/3,1/2,1/3+1/2,1]

  sol =solve(prob,RK4(),dt=1//3,tstops=[1/2],d_discontinuities=[-1/2,1/2,3/2], adaptive=false)
  @test sol.t == [0,1/3,1/2,1/3+1/2,1]

  # TODO
  integrator = init(prob,RK4(),tstops=[1/5,1/4,1/3,1/2,3/4], adaptive=false)

  sol =solve(prob,RK4(),tstops=[1/5,1/4,1/3,1/2,3/4], adaptive=false)
  @test sol.t == [0,1/5,1/4,1/3,1/2,3/4,1]

  sol =solve(prob,RK4(),tstops=[0,1/5,1/4,1/3,1/2,3/4,1], adaptive=false)
  @test sol.t == [0,1/5,1/4,1/3,1/2,3/4,1]

  sol = solve(prob,RK4(),tstops=0:1//16:1, adaptive=false)
  @test sol.t == collect(0:1//16:1)

  sol = solve(prob,RK4(),tstops=range(0,stop=1,length=100), adaptive=false)
  @test sol.t == collect(range(0,stop=1,length=100))
end

@testset "Integrator Tstops Tests on the Interval $(["[-1, 0]", "[0, 1]"][i])" for (i, tdir) in enumerate([-1.; 1.])
  prob2 = remake(prob_ode_linear, tspan=(0.0, tdir*1.0))
  integrator = init(prob2,Tsit5())
  tstops = tdir .* [0,1/5,1/4,1/3,1/2,3/4,1]
  for tstop in tstops
    add_tstop!(integrator, tstop)
  end
  @test_throws ErrorException add_tstop!(integrator, -0.1 * tdir)
  solve!(integrator)
  for tstop in tstops
    @test tstop ∈ integrator.sol.t
  end
end
