using OrdinaryDiffEq, Test
using DiffEqProblemLibrary.ODEProblemLibrary: importodeproblems; importodeproblems()
import DiffEqProblemLibrary.ODEProblemLibrary: prob_ode_linear, prob_ode_2Dlinear

prob_forward = prob_ode_linear
prob_reverse = remake(prob_forward,tspan=(1.0,0.0))

for prob in [prob_forward,prob_reverse]
  tdir = sign(prob.tspan[2] - prob.tspan[1])

  sol =solve(prob,DP5(),dt=1//2^(2),save_everystep=false)
  sol2=solve(prob,DP5(),dt=1//2^(2),save_everystep=false,saveat=[1/2])

  @test sort!(symdiff(sol.t,sol2.t)) == [0.0,1/2,1.0]

  sol2=solve(prob,DP5(),dt=1//2^(2),save_everystep=false,saveat=[0.0,1/2,1.0])

  @test symdiff(sol.t,sol2.t) == [1/2]

  sol2=solve(prob,DP5(),dt=1//2^(2),save_everystep=false,saveat=1/2)

  @test sort!(symdiff(sol.t,sol2.t)) == [1/2]

  sol3=solve(prob,DP5(),dt=1//2^(2),save_everystep=false,saveat=[1/2],tstops=[1/2])

  @test sol3.t == [1/2]

  sol3=solve(prob,DP5(),dt=1//2^(2),saveat=[0.0,1/2,1.0],tstops=[1/2])

  @test tdir>0 ? sol3.t == [0.0,1/2,1.0] : sol3.t == [1.0,1/2,0.0]

  sol3=solve(prob,DP5(),dt=1//2^(2),saveat=1/10,tstops=[1/2])

  @show tdir>0
  @test tdir>0 ? sol3.t == collect(0.0:0.1:1.00) : sol3.t == collect(1.0:-0.1:0.00)

end

sol =solve(prob_forward,RK4(),dt=1/2^(2),save_everystep=true,adaptive=false)
sol2=solve(prob_forward,RK4(),dt=1/2^(2),save_everystep=true,adaptive=false,saveat=[.125,.6,.61,.8])

@test symdiff(sol.t,sol2.t) == [.125,.6,.61,.8]

sol =solve(prob_forward,Rosenbrock32(),dt=1/2^(2),save_everystep=true)
sol2=solve(prob_forward,Rosenbrock32(),dt=1/2^(2),save_everystep=true,saveat=[.125,.6,.61,.8])

@test symdiff(sol.t,sol2.t) == [.125,.6,.61,.8]

sol =solve(prob_forward,Trapezoid(),dt=1/2^(2),save_everystep=true)
sol2=solve(prob_forward,Trapezoid(),dt=1/2^(2),save_everystep=true,saveat=[.125,.6,.61,.8])

@test symdiff(sol.t,sol2.t) == [.125,.6,.61,.8]

sol =solve(prob_reverse,RK4(),dt=1/2^(2),save_everystep=true,adaptive=false)
sol2=solve(prob_reverse,RK4(),dt=1/2^(2),save_everystep=true,adaptive=false,saveat=[0.8,0.61,0.6,0.125])

@test symdiff(sol.t,sol2.t) == [0.8,0.61,0.6,0.125]

sol =solve(prob_reverse,Rosenbrock32(),dt=1/2^(2),save_everystep=true)
sol2=solve(prob_reverse,Rosenbrock32(),dt=1/2^(2),save_everystep=true,saveat=[0.8,0.61,0.6,0.125])

@test symdiff(sol.t,sol2.t) == [0.8,0.61,0.6,0.125]

sol =solve(prob_reverse,Trapezoid(),dt=1/2^(2),save_everystep=true)
sol2=solve(prob_reverse,Trapezoid(),dt=1/2^(2),save_everystep=true,saveat=[0.8,0.61,0.6,0.125])

@test symdiff(sol.t,sol2.t) == [0.8,0.61,0.6,0.125]

prob = prob_ode_2Dlinear

sol =solve(prob,DP5(),dt=1//2^(2),save_everystep=true)
sol2=solve(prob,DP5(),dt=1//2^(2),save_everystep=true,saveat=[0.0,1/2,1.0])

@test symdiff(sol.t,sol2.t) == [1/2]

sol =solve(prob,RK4(),dt=1/2^(2),save_everystep=true,adaptive=false)
sol2=solve(prob,RK4(),dt=1/2^(2),save_everystep=true,adaptive=false,saveat=[0.0,.125,.6,.61,.8,1.0])

@test symdiff(sol.t,sol2.t) == [.125,.6,.61,.8]

sol =solve(prob,Rosenbrock32(),dt=1/2^(2),save_everystep=true)
sol2=solve(prob,Rosenbrock32(),dt=1/2^(2),save_everystep=true,saveat=[.125,.6,.61,.8])

@test symdiff(sol.t,sol2.t) == [.125,.6,.61,.8]

sol =solve(prob,Trapezoid(),dt=1/2^(2),save_everystep=false)
sol2=solve(prob,Trapezoid(),dt=1/2^(2),saveat=[.125,.6,.61,.8])

@test sort!(symdiff(sol.t,sol2.t)) == [0.0,.125,.6,.61,.8,1.0]

sol=solve(prob,Trapezoid(),dt=1/2^(2),save_everystep=true,dense=false,saveat=[0,.125,.6,.61,.8])

@test !(sol.t[2] ≈ 0)

# Test Iterators

sol2=solve(prob,DP5(),dt=1//2^(2),save_everystep=false,dense=false,saveat=0:1//100:1)

@test sol2.t ≈ collect(0:1//100:1)

sol2=solve(prob,DP5(),dt=1//2^(2),save_everystep=false,dense=false,saveat=range(0,stop=1,length=100))

@test sol2.t ≈ range(0,stop=1,length=100)

f = (du,u,p,t) -> prob.f(du,u,p,t)
prob2 = ODEProblem(f,vec(prob.u0),prob.tspan,1.01)

sol2=solve(prob2,DP5(),dt=1//2^(2),saveat=.1,save_idxs=1:2:5)

for u in sol2.u
  @test length(u) == 3
end

sol2=solve(prob2,DP5(),dt=1//2^(2),saveat=.1,save_idxs=1:2:5,save_everystep=true)

sol=solve(prob2,DP5(),dt=1//2^(2),save_start=false)

@test sol.t[1] == 1//2^(2)

# Test save_on switch
sol = solve(prob, DP5(), save_on=false, save_start=false, save_end=false)
@test isempty(sol.t) && isempty(sol.u)
sol = solve(prob, DP5(), saveat=0.2, save_on=false, save_start=false, save_end=false)
@test isempty(sol.t) && isempty(sol.u)

small_f(u,p,t)= u
u0 = 1.
tspan = (0.0, 15.0)
prob = ODEProblem(small_f,u0,tspan)
sol = solve(prob, Tsit5(), saveat=4.)
@test sol.t == [0.0,4,8,12,15]
