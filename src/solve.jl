function DiffEqBase.__solve(prob::Union{DiffEqBase.AbstractODEProblem,DiffEqBase.AbstractDAEProblem},
                            alg::Union{OrdinaryDiffEqAlgorithm,DAEAlgorithm}, args...;
                            kwargs...)
  integrator = DiffEqBase.__init(prob, alg, args...; kwargs...)
  solve!(integrator)
  integrator.sol
end

function DiffEqBase.__init(prob::Union{DiffEqBase.AbstractODEProblem,DiffEqBase.AbstractDAEProblem},
                           alg::Union{OrdinaryDiffEqAlgorithm,DAEAlgorithm},
                           timeseries_init = typeof(prob.u0)[],
                           ts_init = eltype(prob.tspan)[],
                           ks_init = [],
                           recompile::Type{Val{recompile_flag}} = Val{true};
                           saveat = eltype(prob.tspan)[],
                           tstops = eltype(prob.tspan)[],
                           d_discontinuities= eltype(prob.tspan)[],
                           save_idxs = nothing,
                           save_everystep = isempty(saveat),
                           save_on = true,
                           save_start = save_everystep || isempty(saveat) || saveat isa Number || prob.tspan[1] in saveat,
                           save_end = save_everystep || isempty(saveat) || saveat isa Number || prob.tspan[2] in saveat,
                           callback = nothing,
                           dense = save_everystep && !(typeof(alg) <: Union{DAEAlgorithm,FunctionMap}) && isempty(saveat),
                           calck = (callback !== nothing && callback != CallbackSet()) || # Empty callback
                                   (!isempty(setdiff(saveat,tstops)) || dense), # and no dense output
                           dt = alg isa FunctionMap && isempty(tstops) ? eltype(prob.tspan)(1) : eltype(prob.tspan)(0),
                           dtmin = nothing,
                           dtmax = eltype(prob.tspan)((prob.tspan[end]-prob.tspan[1])),
                           force_dtmin = false,
                           adaptive = isadaptive(alg),
                           gamma = gamma_default(alg),
                           abstol = nothing,
                           reltol = nothing,
                           qmin = qmin_default(alg),
                           qmax = qmax_default(alg),
                           qsteady_min = qsteady_min_default(alg),
                           qsteady_max = qsteady_max_default(alg),
                           qoldinit = 1//10^4,
                           fullnormalize = true,
                           failfactor = 2,
                           beta1 = nothing,
                           beta2 = nothing,
                           maxiters = adaptive ? 1000000 : typemax(Int),
                           internalnorm = ODE_DEFAULT_NORM,
                           internalopnorm = LinearAlgebra.opnorm,
                           isoutofdomain = ODE_DEFAULT_ISOUTOFDOMAIN,
                           unstable_check = ODE_DEFAULT_UNSTABLE_CHECK,
                           verbose = true,
                           timeseries_errors = true,
                           dense_errors = false,
                           advance_to_tstop = false,
                           stop_at_next_tstop = false,
                           initialize_save = true,
                           progress = false,
                           progress_steps = 1000,
                           progress_name = "ODE",
                           progress_message = ODE_DEFAULT_PROG_MESSAGE,
                           userdata = nothing,
                           allow_extrapolation = alg_extrapolates(alg),
                           initialize_integrator = true,
                           alias_u0 = false,
                           alias_du0 = false,
                           initializealg = BrownFullBasicInit(),
                           kwargs...) where recompile_flag

  if prob isa DiffEqBase.AbstractDAEProblem && alg isa OrdinaryDiffEqAlgorithm
    error("You cannot use an ODE Algorithm with a DAEProblem")
  end

  if prob isa DiffEqBase.AbstractODEProblem && alg isa DAEAlgorithm
    error("You cannot use an DAE Algorithm with a ODEProblem")
  end

  if typeof(prob.f)<:DynamicalODEFunction && typeof(prob.f.mass_matrix)<:Tuple
    if any(mm != I for mm in prob.f.mass_matrix)
      error("This solver is not able to use mass matrices.")
    end
  elseif !(typeof(prob)<:DiscreteProblem) &&
         !(typeof(prob)<:DiffEqBase.AbstractDAEProblem) &&
         !is_mass_matrix_alg(alg) &&
         prob.f.mass_matrix != I
    error("This solver is not able to use mass matrices.")
  end

  if !isempty(saveat) && dense
    @warn("Dense output is incompatible with saveat. Please use the SavingCallback from the Callback Library to mix the two behaviors.")
  end

  progress && @logmsg(LogLevel(-1),progress_name,_id=_id = :OrdinaryDiffEq,progress=0)

  tType = eltype(prob.tspan)
  tspan = prob.tspan
  tdir = sign(tspan[end]-tspan[1])

  t = tspan[1]

  if (((!(typeof(alg) <: OrdinaryDiffEqAdaptiveAlgorithm) && !(typeof(alg) <: OrdinaryDiffEqCompositeAlgorithm) && !(typeof(alg) <: DAEAlgorithm)) || !adaptive) && dt == tType(0) && isempty(tstops)) && !(typeof(alg) <: Union{FunctionMap,LinearExponential})
      error("Fixed timestep methods require a choice of dt or choosing the tstops")
  end

  isdae = alg isa DAEAlgorithm

  f = prob.f
  p = prob.p

  # Get the control variables

  if alias_u0
    u = prob.u0
  else
    u = recursivecopy(prob.u0)
  end

  if isdae
    if alias_du0
      du = prob.du0
    else
      du = recursivecopy(prob.u0)
    end
  end

  uType = typeof(u)
  uBottomEltype = recursive_bottom_eltype(u)
  uBottomEltypeNoUnits = recursive_unitless_bottom_eltype(u)

  ks = Vector{uType}(undef, 0)

  uEltypeNoUnits = recursive_unitless_eltype(u)
  tTypeNoUnits   = typeof(one(tType))

  if typeof(alg) <: FunctionMap
    abstol_internal = real.(zero.(u))
  elseif abstol === nothing
    if uBottomEltypeNoUnits == uBottomEltype
      abstol_internal = real(convert(uBottomEltype,oneunit(uBottomEltype)*1//10^6))
    else
      abstol_internal = real.(oneunit.(u).*1//10^6)
    end
  else
    abstol_internal = real.(abstol)
  end

  if typeof(alg) <: FunctionMap
    reltol_internal = real.(zero(first(u)/t))
  elseif reltol === nothing
    if uBottomEltypeNoUnits == uBottomEltype
      reltol_internal = real(convert(uBottomEltype,oneunit(uBottomEltype)*1//10^3))
    else
      reltol_internal = real.(oneunit.(u).*1//10^3)
    end
  else
    reltol_internal = real.(reltol)
  end

  dtmax > zero(dtmax) && tdir < 0 && (dtmax *= tdir) # Allow positive dtmax, but auto-convert
  # dtmin is all abs => does not care about sign already.

  if !isdae && isinplace(prob) && typeof(u) <: AbstractArray && eltype(u) <: Number && uBottomEltypeNoUnits == uBottomEltype # Could this be more efficient for other arrays?
    if !(typeof(u) <: ArrayPartition)
      rate_prototype = recursivecopy(u)
    else
      rate_prototype = similar(u, typeof.(oneunit.(recursive_bottom_eltype.(u.x))./oneunit(tType))...)
    end
  elseif isdae
    rate_prototype = prob.du0
  else
    if uBottomEltypeNoUnits == uBottomEltype
      rate_prototype = u
    else # has units!
      rate_prototype = u/oneunit(tType)
    end
  end
  rateType = typeof(rate_prototype) ## Can be different if united

  if isdae
    if uBottomEltype == uBottomEltypeNoUnits
      res_prototype = u
    else
      res_prototype = one(u)
    end
    resType = typeof(res_prototype)
  end

  tstops_internal, saveat_internal, d_discontinuities_internal =
    tstop_saveat_disc_handling(tstops, saveat, d_discontinuities, tspan)

  callbacks_internal = CallbackSet(callback)

  max_len_cb = DiffEqBase.max_vector_callback_length(callbacks_internal)
  if max_len_cb isa VectorContinuousCallback
    if isinplace(prob)
      callback_cache = DiffEqBase.CallbackCache(u,max_len_cb.len,uBottomEltype,uBottomEltype)
    else
      callback_cache = DiffEqBase.CallbackCache(max_len_cb.len,uBottomEltype,uBottomEltype)
    end
  else
    callback_cache = nothing
  end

  ### Algorithm-specific defaults ###
  if save_idxs === nothing
    ksEltype = Vector{rateType}
  else
    ks_prototype = rate_prototype[save_idxs]
    ksEltype = Vector{typeof(ks_prototype)}
  end

  # Have to convert incase passed in wrong.
  if save_idxs === nothing
    timeseries = convert(Vector{uType},timeseries_init)
  else
    u_initial = u[save_idxs]
    timeseries = convert(Vector{typeof(u_initial)},timeseries_init)
  end
  ts = convert(Vector{tType},ts_init)
  ks = convert(Vector{ksEltype},ks_init)
  alg_choice = Int[]

  if !adaptive && save_everystep && tspan[2]-tspan[1] != Inf
    if dt == 0
      steps = length(tstops)
    else
      dtmin === nothing && (dtmin = DiffEqBase.prob2dtmin(prob; use_end_time=true))
      abs(dt) < dtmin && throw(ArgumentError("Supplied dt is smaller than dtmin"))
      steps = ceil(Int,internalnorm((tspan[2]-tspan[1])/dt,tspan[1]))
    end
    sizehint!(timeseries,steps+1)
    sizehint!(ts,steps+1)
    sizehint!(ks,steps+1)
  elseif save_everystep
    sizehint!(timeseries,50)
    sizehint!(ts,50)
    sizehint!(ks,50)
  elseif !isempty(saveat_internal)
    sizehint!(timeseries,length(saveat_internal)+1)
    sizehint!(ts,length(saveat_internal)+1)
    sizehint!(ks,length(saveat_internal)+1)
  else
    sizehint!(timeseries,2)
    sizehint!(ts,2)
    sizehint!(ks,2)
  end

  if save_start
    saveiter = 1 # Starts at 1 so first save is at 2
    saveiter_dense = 1
    copyat_or_push!(ts,1,t)
    if save_idxs === nothing
      copyat_or_push!(timeseries,1,u)
      copyat_or_push!(ks,1,[rate_prototype])
    else
      copyat_or_push!(timeseries,1,u_initial,Val{false})
      copyat_or_push!(ks,1,[ks_prototype])
    end

    if typeof(alg) <: OrdinaryDiffEqCompositeAlgorithm
      copyat_or_push!(alg_choice,1,1)
    end
  else
    saveiter = 0 # Starts at 0 so first save is at 1
    saveiter_dense = 0
  end

  QT = tTypeNoUnits <: Integer ? typeof(qmin) : tTypeNoUnits

  k = rateType[]

  if uses_uprev(alg, adaptive) || calck
    uprev = recursivecopy(u)
  else
    # Some algorithms do not use `uprev` explicitly. In that case, we can save
    # some memory by aliasing `uprev = u`, e.g. for "2N" low storage methods.
    uprev = u
  end
  if allow_extrapolation
    uprev2 = recursivecopy(u)
  else
    uprev2 = uprev
  end

  if !isdae
    cache = alg_cache(alg,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol_internal,p,calck,Val(isinplace(prob)))
  else
    cache = alg_cache(alg,du,u,res_prototype,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol_internal,p,calck,Val(isinplace(prob)))
  end

  if typeof(alg) <: OrdinaryDiffEqCompositeAlgorithm
    id = CompositeInterpolationData(f,timeseries,ts,ks,alg_choice,dense,cache)
    beta2 === nothing && ( beta2=beta2_default(alg.algs[cache.current]) )
    beta1 === nothing && ( beta1=beta1_default(alg.algs[cache.current],beta2) )
  else
    id = InterpolationData(f,timeseries,ts,ks,dense,cache)
    beta2 === nothing && ( beta2=beta2_default(alg) )
    beta1 === nothing && ( beta1=beta1_default(alg,beta2) )
  end

  dtmin === nothing && (dtmin = DiffEqBase.prob2dtmin(prob; use_end_time=false))

  opts = DEOptions{typeof(abstol_internal),typeof(reltol_internal),QT,tType,
                   typeof(internalnorm),typeof(internalopnorm),typeof(callbacks_internal),typeof(isoutofdomain),
                   typeof(progress_message),typeof(unstable_check),typeof(tstops_internal),
                   typeof(d_discontinuities_internal),typeof(userdata),typeof(save_idxs),
                   typeof(maxiters),typeof(tstops),typeof(saveat),
                   typeof(d_discontinuities)}(
                       maxiters,save_everystep,adaptive,abstol_internal,
                       reltol_internal,QT(gamma),QT(qmax),
                       QT(qmin),QT(qsteady_max),
                       QT(qsteady_min),QT(failfactor),tType(dtmax),
                       tType(dtmin),internalnorm,internalopnorm,save_idxs,tstops_internal,saveat_internal,
                       d_discontinuities_internal,
                       tstops,saveat,d_discontinuities,
                       userdata,progress,progress_steps,
                       progress_name,progress_message,timeseries_errors,dense_errors,
                       QT(beta1),QT(beta2),QT(qoldinit),dense,
                       save_on,save_start,save_end,callbacks_internal,isoutofdomain,
                       unstable_check,verbose,
                       calck,force_dtmin,advance_to_tstop,stop_at_next_tstop)

  destats = DiffEqBase.DEStats(0)

  if typeof(alg) <: OrdinaryDiffEqCompositeAlgorithm
    sol = DiffEqBase.build_solution(prob,alg,ts,timeseries,
                      dense=dense,k=ks,interp=id,
                      alg_choice=alg_choice,
                      calculate_error = false, destats=destats)
  else
    sol = DiffEqBase.build_solution(prob,alg,ts,timeseries,
                      dense=dense,k=ks,interp=id,
                      calculate_error = false, destats=destats)
  end

  if recompile_flag == true
    FType = typeof(f)
    SolType = typeof(sol)
    cacheType = typeof(cache)
  else
    FType = Function
    if alg isa OrdinaryDiffEqAlgorithm
      SolType = DiffEqBase.AbstractODESolution
      cacheType =  OrdinaryDiffEqCache
    else
      SolType = DiffEqBase.AbstractDAESolution
      cacheType =  DAECache
    end
  end

  # rate/state = (state/time)/state = 1/t units, internalnorm drops units
  # we don't want to differentiate through eigenvalue estimation
  eigen_est = inv(one(tType))
  tprev = t
  dtcache = tType(dt)
  dtpropose = tType(dt)
  iter = 0
  kshortsize = 0
  reeval_fsal = false
  u_modified = false
  EEst = tTypeNoUnits(1)
  just_hit_tstop = false
  isout = false
  accept_step = false
  force_stepfail = false
  last_stepfail = false
  event_last_time = 0
  vector_event_last_time = 1
  last_event_error = zero(uBottomEltypeNoUnits)
  dtchangeable = isdtchangeable(alg)
  q11 = tTypeNoUnits(1)
  success_iter = 0
  erracc = tTypeNoUnits(1)
  dtacc = tType(1)

  integrator = ODEIntegrator{typeof(alg),isinplace(prob),uType,tType,typeof(p),typeof(eigen_est),
                             QT,typeof(tdir),typeof(k),SolType,
                             FType,cacheType,
                             typeof(opts),fsal_typeof(alg,rate_prototype),
                             typeof(last_event_error),typeof(callback_cache)}(
                             sol,u,k,t,tType(dt),f,p,uprev,uprev2,tprev,
                             alg,dtcache,dtchangeable,
                             dtpropose,tdir,eigen_est,EEst,QT(qoldinit),q11,
                             erracc,dtacc,success_iter,
                             iter,saveiter,saveiter_dense,cache,callback_cache,
                             kshortsize,force_stepfail,last_stepfail,
                             just_hit_tstop,event_last_time,vector_event_last_time,last_event_error,
                             accept_step,
                             isout,reeval_fsal,
                             u_modified,opts,destats)
  if initialize_integrator
    if isdae
      initialize_dae!(integrator, u, du, prob.differential_vars, initializealg, Val(isinplace(prob)))
    end
    initialize_callbacks!(integrator, initialize_save)
    initialize!(integrator,integrator.cache)
    save_start && typeof(alg) <: CompositeAlgorithm && copyat_or_push!(alg_choice,1,integrator.cache.current)
  end

  handle_dt!(integrator)

  integrator
end

function DiffEqBase.solve!(integrator::ODEIntegrator)
  @inbounds while !isempty(integrator.opts.tstops)
    while integrator.tdir * integrator.t < top(integrator.opts.tstops)
      loopheader!(integrator)
      if check_error!(integrator) != :Success
        return integrator.sol
      end
      perform_step!(integrator,integrator.cache)
      loopfooter!(integrator)
      if isempty(integrator.opts.tstops)
        break
      end
    end
    handle_tstop!(integrator)
  end
  postamble!(integrator)

  f = integrator.sol.prob.f

  if DiffEqBase.has_analytic(f)
    DiffEqBase.calculate_solution_errors!(integrator.sol;timeseries_errors=integrator.opts.timeseries_errors,dense_errors=integrator.opts.dense_errors)
  end
  if integrator.sol.retcode != :Default
    return integrator.sol
  end
  integrator.sol = DiffEqBase.solution_new_retcode(integrator.sol,:Success)
end

# Helpers

function handle_dt!(integrator)
  if iszero(integrator.dt) && integrator.opts.adaptive
    auto_dt_reset!(integrator)
    if sign(integrator.dt)!=integrator.tdir && !iszero(integrator.dt) && !isnan(integrator.dt)
      error("Automatic dt setting has the wrong sign. Exiting. Please report this error.")
    end
    if isnan(integrator.dt)
      if integrator.opts.verbose
        @warn("Automatic dt set the starting dt as NaN, causing instability.")
      end
    end
  elseif integrator.opts.adaptive && integrator.dt > zero(integrator.dt) && integrator.tdir < 0
    integrator.dt *= integrator.tdir # Allow positive dt, but auto-convert
  end
end

function tstop_saveat_disc_handling(tstops, saveat, d_discontinuities, tspan)
  t0, tf = tspan
  tType = eltype(tspan)
  tdir = sign(tf - t0)

  tdir_t0 = tdir * t0
  tdir_tf = tdir * tf

  # time stops
  tstops_internal = BinaryMinHeap{tType}()
  if isempty(d_discontinuities) && isempty(tstops) # TODO: Specialize more
    push!(tstops_internal, tdir_tf)
  else
    for t in tstops
      tdir_t = tdir * t
      tdir_t0 < tdir_t ≤ tdir_tf && push!(tstops_internal, tdir_t)
    end

    for t in d_discontinuities
      tdir_t = tdir * t
      tdir_t0 < tdir_t ≤ tdir_tf && push!(tstops_internal, tdir_t)
    end

    push!(tstops_internal, tdir_tf)
  end

  # saving time points
  saveat_internal = BinaryMinHeap{tType}()
  if typeof(saveat) <: Number
    directional_saveat = tdir * abs(saveat)
    for t in (t0 + directional_saveat):directional_saveat:tf
      push!(saveat_internal, tdir * t)
    end
  elseif !isempty(saveat)
    for t in saveat
      tdir_t = tdir * t
      tdir_t0 < tdir_t < tdir_tf && push!(saveat_internal, tdir_t)
    end
  end

  # discontinuities
  d_discontinuities_internal = BinaryMinHeap{tType}()
  sizehint!(d_discontinuities_internal.valtree, length(d_discontinuities))
  for t in d_discontinuities
    push!(d_discontinuities_internal, tdir * t)
  end

  tstops_internal, saveat_internal, d_discontinuities_internal
end

function initialize_callbacks!(integrator, initialize_save = true)
  t = integrator.t
  u = integrator.u
  callbacks = integrator.opts.callback
  integrator.u_modified = true

  u_modified = initialize!(callbacks,u,t,integrator)

  # if the user modifies u, we need to fix previous values before initializing
  # FSAL in order for the starting derivatives to be correct
  if u_modified

    if isinplace(integrator.sol.prob)
      recursivecopy!(integrator.uprev,integrator.u)
    else
      integrator.uprev = integrator.u
    end

    if alg_extrapolates(integrator.alg)
      if isinplace(integrator.sol.prob)
        recursivecopy!(integrator.uprev2,integrator.uprev)
      else
        integrator.uprev2 = integrator.uprev
      end
    end

    if initialize_save &&
      (any((c)->c.save_positions[2],callbacks.discrete_callbacks) ||
      any((c)->c.save_positions[2],callbacks.continuous_callbacks))
      savevalues!(integrator,true)
    end
  end

  # reset this as it is now handled so the integrators should proceed as normal
  integrator.u_modified = false
end
