
# 2N low storage methods
function initialize!(integrator,cache::LowStorageRK2NConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1
  integrator.kshortsize = 1
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
end

@muladd function perform_step!(integrator,cache::LowStorageRK2NConstantCache,repeat_step=false)
  @unpack t,dt,u,f,p = integrator
  @unpack A2end,B1,B2end,c2end = cache

  # u1
  tmp = dt*integrator.fsalfirst
  u   = u + B1*tmp

  # other stages
  for i in eachindex(A2end)
    k = f(u, p, t+c2end[i]*dt)
    integrator.destats.nf += 1
    tmp = A2end[i]*tmp + dt*k
    u   = u + B2end[i]*tmp
  end

  integrator.destats.nf += 1
  integrator.k[1] = integrator.fsalfirst
  integrator.fsalfirst = f(u, p, t+dt) # For interpolation, then FSAL'd
  integrator.u = u
end

function initialize!(integrator,cache::LowStorageRK2NCache)
  @unpack k, tmp, wrapper, williamson_condition = cache
  integrator.kshortsize = 1
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = k
  if williamson_condition
    wrapper.dt = integrator.dt
    integrator.f(wrapper,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
  else
    integrator.f(k ,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
    @.. tmp += integrator.dt * k
  end
  integrator.destats.nf += 1
end

@muladd function perform_step!(integrator,cache::LowStorageRK2NCache,repeat_step=false)
  @unpack t,dt,u,f,p = integrator
  @unpack k,tmp,wrapper,williamson_condition = cache
  @unpack A2end,B1,B2end,c2end = cache.tab

  # u1
  @.. u   = u + B1*tmp
  if williamson_condition
    wrapper.dt = dt
  end
  # other stages
  for i in eachindex(A2end)
    if williamson_condition
      wrapper.coefficient = A2end[i]
      f(wrapper, u, p, t+c2end[i]*dt)
    else
      @.. tmp = A2end[i]*tmp
      f(k, u, p, t+c2end[i]*dt)
      @.. tmp += dt * k
    end
    integrator.destats.nf += 1
    @.. u   = u + B2end[i]*tmp
  end

  f(k, u, p, t+dt)
  @.. tmp = dt*k
  integrator.destats.nf += 1
end

mutable struct WilliamsonWrapper{kType, dtType, coffType}
  kref::kType
  dt::dtType
  coefficient::coffType
end

@inline Base.setindex!(a::WilliamsonWrapper, b, c) = (a.kref[c] = a.coefficient * a.kref[c] + a.dt * b)
@inline Base.size(a::WilliamsonWrapper) = size(a.kref)
@inline Base.copyto!(a::WilliamsonWrapper, b) = @.. a.kref = a.coefficient * a.kref + a.dt * b

# 2C low storage methods
function initialize!(integrator,cache::LowStorageRK2CConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1
  integrator.kshortsize = 1
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
end

@muladd function perform_step!(integrator,cache::LowStorageRK2CConstantCache,repeat_step=false)
  @unpack t,dt,u,f,p = integrator
  @unpack A2end,B1,B2end,c2end = cache

  # u1
  k = integrator.fsalfirst
  u = u + B1*dt*k

  # other stages
  for i in eachindex(A2end)
    tmp = u + A2end[i]*dt*k
    k   = f(tmp, p, t+c2end[i]*dt)
    integrator.destats.nf += 1
    u   = u + B2end[i]*dt*k
  end

  integrator.fsallast = f(u, p, t+dt) # For interpolation, then FSAL'd
  integrator.destats.nf += 1
  integrator.k[1] = integrator.fsalfirst
  integrator.u = u
end

function initialize!(integrator,cache::LowStorageRK2CCache)
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 1
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
  integrator.destats.nf += 1
end

@muladd function perform_step!(integrator,cache::LowStorageRK2CCache,repeat_step=false)
  @unpack t,dt,u,f,p = integrator
  @unpack k,fsalfirst,tmp = cache
  @unpack A2end,B1,B2end,c2end = cache.tab

  # u1
  @.. k = integrator.fsalfirst
  @.. u = u + B1*dt*k

  # other stages
  for i in eachindex(A2end)
    @.. tmp = u + A2end[i]*dt*k
    f(k, tmp, p, t+c2end[i]*dt)
    integrator.destats.nf += 1
    @.. u   = u + B2end[i]*dt*k
  end

  f(k, u, p, t+dt)
  integrator.destats.nf += 1
end



# 3S low storage methods
function initialize!(integrator,cache::LowStorageRK3SConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1
  integrator.kshortsize = 1
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
end

@muladd function perform_step!(integrator,cache::LowStorageRK3SConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack γ12end, γ22end, γ32end, δ2end, β1, β2end, c2end = cache

  # u1
  tmp = u
  u   = tmp + β1*dt*integrator.fsalfirst

  # other stages
  for i in eachindex(γ12end)
    k   = f(u, p, t+c2end[i]*dt)
    integrator.destats.nf += 1
    tmp = tmp + δ2end[i]*u
    u   = γ12end[i]*u + γ22end[i]*tmp + γ32end[i]*uprev + β2end[i]*dt*k
  end

  integrator.fsallast = f(u, p, t+dt) # For interpolation, then FSAL'd
  integrator.destats.nf += 1
  integrator.k[1] = integrator.fsalfirst
  integrator.u = u
end

function initialize!(integrator,cache::LowStorageRK3SCache)
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 1
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
  integrator.destats.nf += 1
end

@muladd function perform_step!(integrator,cache::LowStorageRK3SCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack k,fsalfirst,tmp = cache
  @unpack γ12end, γ22end, γ32end, δ2end, β1, β2end, c2end = cache.tab

  # u1
  @.. tmp = u
  @.. u   = tmp + β1*dt*integrator.fsalfirst

  # other stages
  for i in eachindex(γ12end)
    f(k, u, p, t+c2end[i]*dt)
    integrator.destats.nf += 1
    @.. tmp = tmp + δ2end[i]*u
    @.. u   = γ12end[i]*u + γ22end[i]*tmp + γ32end[i]*uprev + β2end[i]*dt*k
  end

  f(k, u, p, t+dt)
  integrator.destats.nf += 1
end



# 2R+ low storage methods
function initialize!(integrator,cache::LowStorageRK2RPConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1
  integrator.kshortsize = 1
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
end

@muladd function perform_step!(integrator,cache::LowStorageRK2RPConstantCache,repeat_step=false)
  @unpack t,dt,u,uprev,f,fsalfirst,p = integrator
  @unpack Aᵢ,Bₗ,B̂ₗ,Bᵢ,B̂ᵢ,Cᵢ = cache

  k   = fsalfirst
  integrator.opts.adaptive && (tmp = zero(uprev))

  #stages 1 to s-1
  for i in eachindex(Aᵢ)
    integrator.opts.adaptive && (tmp = tmp + (Bᵢ[i] - B̂ᵢ[i])*dt*k)
    gprev = u + Aᵢ[i]*dt*k
    u = u + Bᵢ[i]*dt*k
    k = f(gprev, p, t + Cᵢ[i]*dt)
    integrator.destats.nf += 1
  end

  #last stage
  integrator.opts.adaptive && (tmp = tmp + (Bₗ - B̂ₗ)*dt*k)
  u   = u  + Bₗ*dt*k

  #Error estimate
  if integrator.opts.adaptive
    atmp = calculate_residuals(tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  integrator.k[1] = integrator.fsalfirst
  integrator.fsallast = f(u, p, t+dt) # For interpolation, then FSAL'd
  integrator.destats.nf += 1
  integrator.u = u
end

function initialize!(integrator,cache::LowStorageRK2RPCache)
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 1
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t)
  integrator.destats.nf += 1
end

@muladd function perform_step!(integrator,cache::LowStorageRK2RPCache,repeat_step=false)
  @unpack t,dt,u,uprev,f,fsalfirst,p = integrator
  @unpack k,gprev,tmp,atmp = cache
  @unpack Aᵢ,Bₗ,B̂ₗ,Bᵢ,B̂ᵢ,Cᵢ = cache.tab

  @.. k   = fsalfirst
  integrator.opts.adaptive && (@.. tmp = zero(uprev))

  #stages 1 to s-1
  for i in eachindex(Aᵢ)
    integrator.opts.adaptive && (@.. tmp = tmp + (Bᵢ[i] - B̂ᵢ[i])*dt*k)
    @.. gprev = u + Aᵢ[i]*dt*k
    @.. u     = u + Bᵢ[i]*dt*k
    f(k, gprev, p, t + Cᵢ[i]*dt)
    integrator.destats.nf += 1
  end

  #last stage
  integrator.opts.adaptive && (@.. tmp = tmp + (Bₗ - B̂ₗ)*dt*k)
  @.. u   = u  + Bₗ*dt*k

  #Error estimate
  if integrator.opts.adaptive
    calculate_residuals!(atmp,tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  f(k, u, p, t+dt)
  integrator.destats.nf += 1
end



# 3R+ low storage methods
function initialize!(integrator,cache::LowStorageRK3RPConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 1
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
end

@muladd function perform_step!(integrator,cache::LowStorageRK3RPConstantCache,repeat_step=false)
  @unpack t,dt,u,uprev,f,fsalfirst,p = integrator
  @unpack Aᵢ₁,Aᵢ₂,Bₗ,B̂ₗ,Bᵢ,B̂ᵢ,Cᵢ = cache

  fᵢ₋₂  = zero(fsalfirst)
  k     = fsalfirst
  uᵢ₋₁  = uprev
  uᵢ₋₂  = uprev
  integrator.opts.adaptive && (tmp = zero(uprev))

  #stages 1 to s-1
  for i in eachindex(Aᵢ₁)
    integrator.opts.adaptive && (tmp = tmp + (Bᵢ[i] - B̂ᵢ[i])*dt*k)
    gprev = uᵢ₋₂ + (Aᵢ₁[i]*k+Aᵢ₂[i]*fᵢ₋₂)*dt
    u     = u + Bᵢ[i]*dt*k
    fᵢ₋₂  = k
    uᵢ₋₂  = uᵢ₋₁
    uᵢ₋₁  = u
    k     = f(gprev, p, t + Cᵢ[i]*dt)
  end

  #last stage
  integrator.opts.adaptive && (tmp = tmp + (Bₗ - B̂ₗ)*dt*k)
  u   = u  + Bₗ*dt*k

  #Error estimate
  if integrator.opts.adaptive
    atmp = calculate_residuals(tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  integrator.k[1] = integrator.fsalfirst
  integrator.fsallast = f(u, p, t+dt) # For interpolation, then FSAL'd
  integrator.u = u
end

function initialize!(integrator,cache::LowStorageRK3RPCache)
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 1
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t)
end

@muladd function perform_step!(integrator,cache::LowStorageRK3RPCache,repeat_step=false)
  @unpack t,dt,u,uprev,f,fsalfirst,p = integrator
  @unpack k,uᵢ₋₁,uᵢ₋₂,gprev,fᵢ₋₂,tmp,atmp = cache
  @unpack Aᵢ₁,Aᵢ₂,Bₗ,B̂ₗ,Bᵢ,B̂ᵢ,Cᵢ = cache.tab

  @.. fᵢ₋₂  = zero(fsalfirst)
  @.. k     = fsalfirst
  integrator.opts.adaptive && (@.. tmp = zero(uprev))
  @.. uᵢ₋₁  = uprev
  @.. uᵢ₋₂  = uprev

  #stages 1 to s-1
  for i in eachindex(Aᵢ₁)
    integrator.opts.adaptive && (@.. tmp = tmp + (Bᵢ[i] - B̂ᵢ[i])*dt*k)
    @.. gprev = uᵢ₋₂ + (Aᵢ₁[i]*k+Aᵢ₂[i]*fᵢ₋₂)*dt
    @.. u     = u + Bᵢ[i]*dt*k
    @.. fᵢ₋₂  = k
    @.. uᵢ₋₂  = uᵢ₋₁
    @.. uᵢ₋₁  = u
    f(k, gprev, p, t + Cᵢ[i]*dt)
  end

  #last stage
  integrator.opts.adaptive && (@.. tmp = tmp + (Bₗ - B̂ₗ)*dt*k)
  @.. u   = u  + Bₗ*dt*k

  #Error estimate
  if integrator.opts.adaptive
    calculate_residuals!(atmp,tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  f(k, u, p, t+dt)
end


# 4R+ low storage methods
function initialize!(integrator,cache::LowStorageRK4RPConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 1
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
end

@muladd function perform_step!(integrator,cache::LowStorageRK4RPConstantCache,repeat_step=false)
  @unpack t,dt,u,uprev,f,fsalfirst,p = integrator
  @unpack Aᵢ₁,Aᵢ₂,Aᵢ₃,Bₗ,B̂ₗ,Bᵢ,B̂ᵢ,Cᵢ = cache

  fᵢ₋₂  = zero(fsalfirst)
  fᵢ₋₃  = zero(fsalfirst)
  k     = fsalfirst
  uᵢ₋₁  = uprev
  uᵢ₋₂  = uprev
  uᵢ₋₃  = uprev
  integrator.opts.adaptive && (tmp = zero(uprev))

  #stages 1 to s-1
  for i in eachindex(Aᵢ₁)
    integrator.opts.adaptive && (tmp = tmp + (Bᵢ[i] - B̂ᵢ[i])*dt*k)
    gprev = uᵢ₋₃ + (Aᵢ₁[i]*k+Aᵢ₂[i]*fᵢ₋₂+Aᵢ₃[i]*fᵢ₋₃)*dt
    u     = u + Bᵢ[i]*dt*k
    fᵢ₋₃  = fᵢ₋₂
    fᵢ₋₂  = k
    uᵢ₋₃  = uᵢ₋₂
    uᵢ₋₂  = uᵢ₋₁
    uᵢ₋₁  = u
    k     = f(gprev, p, t + Cᵢ[i]*dt)
  end

  #last stage
  integrator.opts.adaptive && (tmp = tmp + (Bₗ - B̂ₗ)*dt*k)
  u   = u  + Bₗ*dt*k

  #Error estimate
  if integrator.opts.adaptive
    atmp = calculate_residuals(tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  integrator.k[1] = integrator.fsalfirst
  integrator.fsallast = f(u, p, t+dt) # For interpolation, then FSAL'd
  integrator.u = u
end

function initialize!(integrator,cache::LowStorageRK4RPCache)
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 1
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t)
end

@muladd function perform_step!(integrator,cache::LowStorageRK4RPCache,repeat_step=false)
  @unpack t,dt,u,uprev,f,fsalfirst,p = integrator
  @unpack k,uᵢ₋₁,uᵢ₋₂,uᵢ₋₃,gprev,fᵢ₋₂,fᵢ₋₃,tmp,atmp = cache
  @unpack Aᵢ₁,Aᵢ₂,Aᵢ₃,Bₗ,B̂ₗ,Bᵢ,B̂ᵢ,Cᵢ = cache.tab

  @.. fᵢ₋₂  = zero(fsalfirst)
  @.. fᵢ₋₃  = zero(fsalfirst)
  @.. k     = fsalfirst
  integrator.opts.adaptive && (@.. tmp = zero(uprev))
  @.. uᵢ₋₁  = uprev
  @.. uᵢ₋₂  = uprev
  @.. uᵢ₋₃  = uprev


  #stages 1 to s-1
  for i in eachindex(Aᵢ₁)
    integrator.opts.adaptive && (@.. tmp = tmp + (Bᵢ[i] - B̂ᵢ[i])*dt*k)
    @.. gprev = uᵢ₋₃ + (Aᵢ₁[i]*k+Aᵢ₂[i]*fᵢ₋₂+Aᵢ₃[i]*fᵢ₋₃)*dt
    @.. u     = u + Bᵢ[i]*dt*k
    @.. fᵢ₋₃  = fᵢ₋₂
    @.. fᵢ₋₂  = k
    @.. uᵢ₋₃  = uᵢ₋₂
    @.. uᵢ₋₂  = uᵢ₋₁
    @.. uᵢ₋₁  = u
    f(k, gprev, p, t + Cᵢ[i]*dt)
  end

  #last stage
  integrator.opts.adaptive && (@.. tmp = tmp + (Bₗ - B̂ₗ)*dt*k)
  @.. u   = u  + Bₗ*dt*k

  #Error estimate
  if integrator.opts.adaptive
    calculate_residuals!(atmp,tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  f(k, u, p, t+dt)
end


# 5R+ low storage methods
function initialize!(integrator,cache::LowStorageRK5RPConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 1
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
end

@muladd function perform_step!(integrator,cache::LowStorageRK5RPConstantCache,repeat_step=false)
  @unpack t,dt,u,uprev,f,fsalfirst,p = integrator
  @unpack Aᵢ₁,Aᵢ₂,Aᵢ₃,Aᵢ₄,Bₗ,B̂ₗ,Bᵢ,B̂ᵢ,Cᵢ = cache

  fᵢ₋₂  = zero(fsalfirst)
  fᵢ₋₃  = zero(fsalfirst)
  fᵢ₋₄  = zero(fsalfirst)
  k     = fsalfirst
  uᵢ₋₁  = uprev
  uᵢ₋₂  = uprev
  uᵢ₋₃  = uprev
  uᵢ₋₄  = uprev
  integrator.opts.adaptive && (tmp = zero(uprev))

  #stages 1 to s-1
  for i in eachindex(Aᵢ₁)
    integrator.opts.adaptive && (tmp = tmp + (Bᵢ[i] - B̂ᵢ[i])*dt*k)
    gprev = uᵢ₋₄ + (Aᵢ₁[i]*k+Aᵢ₂[i]*fᵢ₋₂+Aᵢ₃[i]*fᵢ₋₃+Aᵢ₄[i]*fᵢ₋₄)*dt
    u     = u + Bᵢ[i]*dt*k
    fᵢ₋₄  = fᵢ₋₃
    fᵢ₋₃  = fᵢ₋₂
    fᵢ₋₂  = k
    uᵢ₋₄  = uᵢ₋₃
    uᵢ₋₃  = uᵢ₋₂
    uᵢ₋₂  = uᵢ₋₁
    uᵢ₋₁  = u
    k     = f(gprev, p, t + Cᵢ[i]*dt)
  end

  #last stage
  integrator.opts.adaptive && (tmp = tmp + (Bₗ - B̂ₗ)*dt*k)
  u   = u  + Bₗ*dt*k

  #Error estimate
  if integrator.opts.adaptive
    atmp = calculate_residuals(tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  integrator.k[1] = integrator.fsalfirst
  integrator.fsallast = f(u, p, t+dt) # For interpolation, then FSAL'd
  integrator.u = u
end

function initialize!(integrator,cache::LowStorageRK5RPCache)
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 1
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t)
end

@muladd function perform_step!(integrator,cache::LowStorageRK5RPCache,repeat_step=false)
  @unpack t,dt,u,uprev,f,fsalfirst,p = integrator
  @unpack k,uᵢ₋₁,uᵢ₋₂,uᵢ₋₃,uᵢ₋₄,gprev,fᵢ₋₂,fᵢ₋₃,fᵢ₋₄,tmp,atmp = cache
  @unpack Aᵢ₁,Aᵢ₂,Aᵢ₃,Aᵢ₄,Bₗ,B̂ₗ,Bᵢ,B̂ᵢ,Cᵢ = cache.tab

  @.. fᵢ₋₂  = zero(fsalfirst)
  @.. fᵢ₋₃  = zero(fsalfirst)
  @.. fᵢ₋₄  = zero(fsalfirst)
  @.. k     = fsalfirst
  integrator.opts.adaptive && (@.. tmp = zero(uprev))
  @.. uᵢ₋₁  = uprev
  @.. uᵢ₋₂  = uprev
  @.. uᵢ₋₃  = uprev
  @.. uᵢ₋₄  = uprev


  #stages 1 to s-1
  for i in eachindex(Aᵢ₁)
    integrator.opts.adaptive && (@.. tmp = tmp + (Bᵢ[i] - B̂ᵢ[i])*dt*k)
    @.. gprev = uᵢ₋₄ + (Aᵢ₁[i]*k+Aᵢ₂[i]*fᵢ₋₂+Aᵢ₃[i]*fᵢ₋₃+Aᵢ₄[i]*fᵢ₋₄)*dt
    @.. u     = u + Bᵢ[i]*dt*k
    @.. fᵢ₋₄  = fᵢ₋₃
    @.. fᵢ₋₃  = fᵢ₋₂
    @.. fᵢ₋₂  = k
    @.. uᵢ₋₄  = uᵢ₋₃
    @.. uᵢ₋₃  = uᵢ₋₂
    @.. uᵢ₋₂  = uᵢ₋₁
    @.. uᵢ₋₁  = u
    f(k, gprev, p, t + Cᵢ[i]*dt)
  end

  #last stage
  integrator.opts.adaptive && (@.. tmp = tmp + (Bₗ - B̂ₗ)*dt*k)
  @.. u   = u  + Bₗ*dt*k

  #Error estimate
  if integrator.opts.adaptive
    calculate_residuals!(atmp,tmp, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
    integrator.EEst = integrator.opts.internalnorm(atmp,t)
  end

  f(k, u, p, t+dt)
end
