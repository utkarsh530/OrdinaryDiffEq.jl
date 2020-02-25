function initialize!(integrator,cache::AitkenNevilleCache)
  integrator.kshortsize = 2
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # For the interpolation, needs k at the updated point
  integrator.destats.nf += 1

  cache.step_no = 1
  cache.cur_order = max(integrator.alg.init_order, integrator.alg.min_order)
end

function perform_step!(integrator,cache::AitkenNevilleCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack k,fsalfirst,T,utilde,atmp,dtpropose,cur_order,A = cache
  @unpack u_tmps, k_tmps = cache

  max_order = min(size(T, 1), cur_order + 1)

  if !integrator.alg.threading
    for i in 1:max_order
      dt_temp = dt/(2^(i-1))
      # Solve using Euler method
      @muladd @.. u = uprev + dt_temp*fsalfirst
      f(k, u, p, t+dt_temp)
      integrator.destats.nf += 1
      for j in 2:2^(i-1)
        @muladd @.. u = u + dt_temp*k
        f(k, u, p, t+j*dt_temp)
        integrator.destats.nf += 1
      end
      @.. T[i,1] = u
    end
  else
    let max_order=max_order, uprev=uprev, dt=dt, fsalfirst=fsalfirst, p=p, t=t,
        u_tmps=u_tmps, k_tmps=k_tmps , T=T
      # Balance workload of threads by computing T[1,1] with T[max_order,1] on
      # same thread, T[2,1] with T[max_order-1,1] on same thread. Similarly fill
      # first column of T matrix
      Threads.@threads for i in 1:2
        startIndex = (i == 1) ? 1 : max_order
        endIndex = (i == 1) ? max_order - 1 : max_order
        for index in startIndex:endIndex
          dt_temp = dt/(2^(index-1))
          # Solve using Euler method
          @muladd @.. u_tmps[Threads.threadid()] = uprev + dt_temp*fsalfirst
          f(k_tmps[Threads.threadid()], u_tmps[Threads.threadid()], p, t+dt_temp)
          for j in 2:2^(index-1)
            @muladd @.. u_tmps[Threads.threadid()] = u_tmps[Threads.threadid()] + dt_temp*k_tmps[Threads.threadid()]
            f(k_tmps[Threads.threadid()], u_tmps[Threads.threadid()], p, t+j*dt_temp)
          end
          @.. T[index,1] = u_tmps[Threads.threadid()]
        end
      end
    end
    integrator.destats.nf += 2^max_order - 1
  end

  # Richardson extrapolation
  tmp = 1
  for j in 2:max_order
    tmp *= 2
    for i in j:max_order
      @.. T[i, j] = (tmp * T[i, j - 1] - T[i - 1, j - 1]) / (tmp - 1)
    end
  end

  if integrator.opts.adaptive
      minimum_work = Inf
      if isone(cache.step_no)
        range_start = 2
      else
        range_start = max(2, cur_order - 1)
      end

      for i in range_start:max_order
          A = 2^(i-1)
          @.. utilde = T[i,i] - T[i,i-1]
          atmp = calculate_residuals(utilde, uprev, T[i,i], integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
          EEst = integrator.opts.internalnorm(atmp,t)

          beta1 = integrator.opts.beta1
          e = integrator.EEst
          qold = integrator.qold

          integrator.opts.beta1 = 1/(i+1)
          integrator.EEst = EEst
          dtpropose = step_accept_controller!(integrator,integrator.alg,stepsize_controller!(integrator,integrator.alg))
          integrator.EEst = e
          integrator.opts.beta1 = beta1
          integrator.qold = qold

          work = A/dtpropose

          if work < minimum_work
              integrator.opts.beta1 = 1/(i+1)
              cache.dtpropose = dtpropose
              cache.cur_order = i
              minimum_work = work
              integrator.EEst = EEst
          end
      end
  end

  # using extrapolated value of u
  @.. u = T[cache.cur_order, cache.cur_order]
  cache.step_no = cache.step_no + 1
  f(k, u, p, t+dt)
  integrator.destats.nf += 1
end

function initialize!(integrator,cache::AitkenNevilleConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.destats.nf += 1

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  cache.step_no = 1
  cache.cur_order = max(integrator.alg.init_order, integrator.alg.min_order)
end

function perform_step!(integrator,cache::AitkenNevilleConstantCache,repeat_step=false)
  @unpack t,dt,uprev,f,p = integrator
  @unpack dtpropose, T, cur_order, work, A = cache

  max_order = min(size(T, 1), cur_order + 1)

  if !integrator.alg.threading
    for i in 1:max_order
      dt_temp = dt/(2^(i-1)) # Romberg sequence

      # Solve using Euler method with dt_temp = dt/n_{i}
      @muladd u = @.. uprev + dt_temp*integrator.fsalfirst
      k = f(u, p, t+dt_temp)
      integrator.destats.nf += 1

      for j in 2:2^(i-1)
        @muladd u = @.. u + dt_temp*k
        k = f(u, p, t+j*dt_temp)
        integrator.destats.nf += 1
      end
      T[i,1] = u
    end
  else
    let max_order=max_order, dt=dt, uprev=uprev, integrator=integrator, p=p, t=t, T=T
      # Balance workload of threads by computing T[1,1] with T[max_order,1] on
      # same thread, T[2,1] with T[max_order-1,1] on same thread. Similarly fill
      # first column of T matrix
      Threads.@threads for i in 1:2
        startIndex = (i == 1) ? 1 : max_order
        endIndex = (i == 1) ? max_order - 1 : max_order

        for index in startIndex:endIndex
          dt_temp = dt/2^(index - 1)
          @muladd u = @.. uprev + dt_temp*integrator.fsalfirst
          k_temp = f(u, p, t+dt_temp)
          for j in 2:2^(index-1)
            @muladd u = @.. u + dt_temp*k_temp
            k_temp = f(u, p, t+j*dt_temp)
          end
          T[index,1] = u
        end
      end
    end

    integrator.destats.nf += 2^max_order - 1
  end

  # Richardson extrapolation
  tmp = 1
  for j in 2:max_order
    tmp *= 2
    for i in j:max_order
      T[i, j] = (tmp * T[i, j - 1] - T[i - 1, j - 1]) / (tmp - 1)
    end
  end

  if integrator.opts.adaptive
      minimum_work = Inf
      if isone(cache.step_no)
        range_start = 2
      else
        range_start = max(2, cur_order - 1)
      end

      for i in range_start:max_order
          A = 2^(i-1)
          utilde = T[i,i] - T[i,i-1]
          atmp = calculate_residuals(utilde, uprev, T[i,i], integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
          EEst = integrator.opts.internalnorm(atmp,t)

          beta1 = integrator.opts.beta1
          e = integrator.EEst
          qold = integrator.qold

          integrator.opts.beta1 = 1/(i+1)
          integrator.EEst = EEst
          dtpropose = step_accept_controller!(integrator,integrator.alg,stepsize_controller!(integrator,integrator.alg))
          integrator.EEst = e
          integrator.opts.beta1 = beta1
          integrator.qold = qold

          work = A/dtpropose

          if work < minimum_work
              integrator.opts.beta1 = 1/(i+1)
              cache.dtpropose = dtpropose
              cache.cur_order = i
              minimum_work = work
              integrator.EEst = EEst
          end
      end
  end

  cache.step_no = cache.step_no + 1

  # Use extrapolated value of u
  integrator.u = T[cache.cur_order,cache.cur_order]

  k = f(integrator.u, p, t+dt)
  integrator.destats.nf += 1
  integrator.fsallast = k
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function initialize!(integrator,cache::ImplicitEulerExtrapolationCache)
  integrator.kshortsize = 2

  integrator.fsalfirst = zero(first(cache.k_tmps))
  integrator.f(integrator.fsalfirst, integrator.u, integrator.p, integrator.t)
  integrator.fsallast = zero(integrator.fsalfirst)
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.destats.nf += 1

  cache.step_no = 1
  cache.cur_order = max(integrator.alg.init_order, integrator.alg.min_order)
end

function perform_step!(integrator,cache::ImplicitEulerExtrapolationCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack T,utilde,atmp,dtpropose,cur_order,A = cache
  @unpack J,W,uf,tf,jac_config = cache
  @unpack u_tmps, k_tmps, linsolve_tmps = cache

  max_order = min(size(T, 1), cur_order + 1)

  if !integrator.alg.threading
    for index in 1:max_order
      dt_temp = dt/(2^(index-1)) # Romberg sequence
      calc_W!(W[1], integrator, nothing, cache, dt_temp, repeat_step)
      @.. k_tmps[1] = integrator.fsalfirst
      @.. u_tmps[1] = uprev

      for j in 1:2^(index-1)
        @.. linsolve_tmps[1] = dt_temp*k_tmps[1]
        cache.linsolve[1](vec(k_tmps[1]), W[1], vec(linsolve_tmps[1]), !repeat_step)
        integrator.destats.nsolve += 1
        @.. k_tmps[1] = -k_tmps[1]
        @.. u_tmps[1] = u_tmps[1] + k_tmps[1]
        f(k_tmps[1], u_tmps[1],p,t+j*dt_temp)
        integrator.destats.nf += 1
      end

      @.. T[index,1] = u_tmps[1]
    end
  else
    let max_order=max_order, uprev=uprev, dt=dt, p=p, t=t, T=T, W=W,
        integrator=integrator, cache=cache, repeat_step = repeat_step,
        k_tmps=k_tmps, u_tmps=u_tmps
      Threads.@threads for i in 1:2
        startIndex = (i == 1) ? 1 : max_order
        endIndex = (i == 1) ? max_order - 1 : max_order
        for index in startIndex:endIndex
          dt_temp = dt/(2^(index-1)) # Romberg sequence
          calc_W!(W[Threads.threadid()], integrator, nothing, cache, dt_temp, repeat_step)
          @.. k_tmps[Threads.threadid()] = integrator.fsalfirst
          @.. u_tmps[Threads.threadid()] = uprev
          for j in 1:2^(index-1)
              @.. linsolve_tmps[Threads.threadid()] = dt_temp*k_tmps[Threads.threadid()]
              cache.linsolve[Threads.threadid()](vec(k_tmps[Threads.threadid()]), W[Threads.threadid()], vec(linsolve_tmps[Threads.threadid()]), !repeat_step)
              @.. k_tmps[Threads.threadid()] = -k_tmps[Threads.threadid()]
              @.. u_tmps[Threads.threadid()] = u_tmps[Threads.threadid()] + k_tmps[Threads.threadid()]
              f(k_tmps[Threads.threadid()], u_tmps[Threads.threadid()],p,t+j*dt_temp)
          end

          @.. T[index,1] = u_tmps[Threads.threadid()]
        end
      end
    end

    nevals = 2^max_order - 1
    integrator.destats.nf += nevals
    integrator.destats.nsolve += nevals
  end

  # Richardson extrapolation
  tmp = 1
  for j in 2:max_order
    tmp *= 2
    for i in j:max_order
      @.. T[i, j] = (tmp * T[i, j - 1] - T[i - 1, j - 1]) / (tmp - 1)
    end
  end

  integrator.dt = dt

  if integrator.opts.adaptive
    minimum_work = Inf
    if isone(cache.step_no)
      range_start = 2
    else
      range_start = max(2, cur_order - 1)
    end

    for i in range_start:max_order
        A = 2^(i-1)
        @.. utilde = T[i,i] - T[i,i-1]
        atmp = calculate_residuals(utilde, uprev, T[i,i], integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
        EEst = integrator.opts.internalnorm(atmp,t)

        beta1 = integrator.opts.beta1
        e = integrator.EEst
        qold = integrator.qold

        integrator.opts.beta1 = 1/(i+1)
        integrator.EEst = EEst
        dtpropose = step_accept_controller!(integrator,integrator.alg,stepsize_controller!(integrator,integrator.alg))
        integrator.EEst = e
        integrator.opts.beta1 = beta1
        integrator.qold = qold

        work = A/dtpropose

        if work < minimum_work
            integrator.opts.beta1 = 1/(i+1)
            cache.dtpropose = dtpropose
            cache.cur_order = i
            minimum_work = work
            integrator.EEst = EEst
        end
    end
  end

  @.. integrator.u = T[cache.cur_order,cache.cur_order]
  cache.step_no = cache.step_no + 1
  f(integrator.fsallast, integrator.u, p, t+dt)
  integrator.destats.nf += 1
end


function initialize!(integrator,cache::ImplicitEulerExtrapolationConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::ImplicitEulerExtrapolationConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack dtpropose, T, cur_order, work, A, tf, uf = cache

  max_order = min(size(T, 1), cur_order+1)

  if !integrator.alg.threading
    for index in 1:max_order
      dt_temp = dt/(2^(index-1)) # Romberg sequence
      W = calc_W(integrator, cache, dt_temp, repeat_step)
      k_copy = integrator.fsalfirst
      u_tmp = uprev

      for j in 1:2^(index-1)
        k = _reshape(W\-_vec(dt_temp*k_copy), axes(uprev))
        integrator.destats.nsolve += 1
        u_tmp = u_tmp + k
        k_copy = f(u_tmp, p, t+j*dt_temp)
        integrator.destats.nf += 1
      end

      T[index,1] = u_tmp
    end
  else
    let max_order=max_order, dt=dt, integrator=integrator, cache=cache, repeat_step=repeat_step,
      uprev=uprev, T=T
      Threads.@threads for i in 1:2
        startIndex = (i==1) ? 1 : max_order
        endIndex = (i==1) ? max_order-1 : max_order
        for index in startIndex:endIndex
          dt_temp = dt/(2^(index-1)) # Romberg sequence
          W = calc_W(integrator, cache, dt_temp, repeat_step)
          k_copy = integrator.fsalfirst
          u_tmp = uprev
          for j in 1:2^(index-1)
              k = _reshape(W\-_vec(dt_temp*k_copy), axes(uprev))
              u_tmp = u_tmp + k
              k_copy = f(u_tmp, p, t+j*dt_temp)
          end
          T[index,1] = u_tmp
        end
      end
    end

    nevals = 2^max_order - 1
    integrator.destats.nf += nevals
    integrator.destats.nsolve += nevals
  end

  # Richardson extrapolation
  tmp = 1
  for j in 2:max_order
    tmp *= 2
    for i in j:max_order
      T[i, j] = (tmp * T[i, j - 1] - T[i - 1, j - 1]) / (tmp - 1)
    end
  end

  integrator.dt = dt

  if integrator.opts.adaptive
      minimum_work = Inf
      if isone(cache.step_no)
        range_start = 2
      else
        range_start = max(2, cur_order - 1)
      end

      for i in range_start:max_order
          A = 2^(i-1)
          utilde = T[i,i] - T[i,i-1]
          atmp = calculate_residuals(utilde, uprev, T[i,i], integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
          EEst = integrator.opts.internalnorm(atmp,t)

          beta1 = integrator.opts.beta1
          e = integrator.EEst
          qold = integrator.qold

          integrator.opts.beta1 = 1/(i+1)
          integrator.EEst = EEst
          dtpropose = step_accept_controller!(integrator,integrator.alg,stepsize_controller!(integrator,integrator.alg))
          integrator.EEst = e
          integrator.opts.beta1 = beta1
          integrator.qold = qold

          work = A/dtpropose

          if work < minimum_work
              integrator.opts.beta1 = 1/(i+1)
              cache.dtpropose = dtpropose
              cache.cur_order = i
              minimum_work = work
              integrator.EEst = EEst
          end
      end
  end


  # Use extrapolated value of u
  integrator.u = T[cache.cur_order, cache.cur_order]
  k_temp = f(integrator.u, p, t+dt)
  integrator.destats.nf += 1
  integrator.fsallast = k_temp
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function initialize!(integrator,cache::ExtrapolationMidpointDeuflhardCache)
  # cf. initialize! of MidpointCache
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 2
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
end

function perform_step!(integrator, cache::ExtrapolationMidpointDeuflhardCache, repeat_step = false)
  # Unpack all information needed
  @unpack t, uprev, dt, f, p = integrator
  @unpack n_curr, u_temp1, u_temp2, utilde, res, T, fsalfirst,k  = cache
  @unpack u_temp3, u_temp4, k_tmps = cache

  # Coefficients for obtaining u
  @unpack extrapolation_weights, extrapolation_scalars = cache.coefficients
  # Coefficients for obtaining utilde
  @unpack extrapolation_weights_2, extrapolation_scalars_2 = cache.coefficients
  # Additional constant information
  @unpack subdividing_sequence = cache.coefficients
  @unpack stage_number = cache

  fill!(cache.Q, zero(eltype(cache.Q)))
  tol = integrator.opts.internalnorm(integrator.opts.reltol, t) # Used by the convergence monitor

  if integrator.opts.adaptive
    # Set up the order window
    win_min = max(integrator.alg.n_min, n_curr - 1)
    win_max = min(integrator.alg.n_max, n_curr + 1)

    # Set up the current extrapolation order
    cache.n_old = n_curr # Save the suggested order for step_*_controller!
    n_curr = win_min # Start with smallest order in the order window

  end

  #Compute the internal discretisations
  if !integrator.alg.threading
    for i in 0:n_curr
      j_int = 4 * subdividing_sequence[i+1]
      dt_int = dt / j_int # Stepsize of the ith internal discretisation
      @.. u_temp2 = uprev
      @.. u_temp1 = u_temp2 + dt_int * fsalfirst # Euler starting step
      for j in 2:j_int
        f(k, cache.u_temp1, p, t + (j-1) * dt_int)
        @.. T[i+1] = u_temp2 + 2 * dt_int * k # Explicit Midpoint rule
        @.. u_temp2 = u_temp1
        @.. u_temp1 = T[i+1]
      end
    end
  else
    if integrator.alg.sequence == :romberg
      # Compute solution by using maximum two threads for romberg sequence
      # One thread will fill T matrix till second last element and another thread will
      # fill last element of T matrix.
      # Romberg sequence --> 1, 2, 4, 8, ..., 2^(i)
      # 1 + 2 + 4 + ... + 2^(i-1) = 2^(i) - 1
      let n_curr=n_curr,subdividing_sequence=subdividing_sequence,uprev=uprev,dt=dt,u_temp3=u_temp3,
          u_temp4=u_temp4,k_tmps=k_tmps,p=p,t=t,T=T
        Threads.@threads for i = 1 : 2
          startIndex = (i == 1) ? 0 : n_curr
          endIndex = (i == 1) ? n_curr - 1 : n_curr
          for index = startIndex : endIndex
            j_int_temp = 4 * subdividing_sequence[index+1]
            dt_int_temp = dt / j_int_temp # Stepsize of the ith internal discretisation
            @.. u_temp4[Threads.threadid()] = uprev
            @.. u_temp3[Threads.threadid()] = u_temp4[Threads.threadid()] + dt_int_temp * fsalfirst # Euler starting step
            for j in 2:j_int_temp
              f(k_tmps[Threads.threadid()], cache.u_temp3[Threads.threadid()], p, t + (j-1) * dt_int_temp)
              @.. T[index+1] = u_temp4[Threads.threadid()] + 2 * dt_int_temp * k_tmps[Threads.threadid()] # Explicit Midpoint rule
              @.. u_temp4[Threads.threadid()] = u_temp3[Threads.threadid()]
              @.. u_temp3[Threads.threadid()] = T[index+1]
            end
          end
        end
      end
    else
      let n_curr=n_curr,subdividing_sequence=subdividing_sequence,uprev=uprev,dt=dt,u_temp3=u_temp3,
          u_temp4=u_temp4,k_tmps=k_tmps,p=p,t=t,T=T
        Threads.@threads for i in 0:(n_curr ÷ 2)
          indices = (i, n_curr-i)
          for index in indices
            j_int_temp = 4 * subdividing_sequence[index+1]
            dt_int_temp = dt / j_int_temp # Stepsize of the ith internal discretisation
            @.. u_temp4[Threads.threadid()] = uprev
            @.. u_temp3[Threads.threadid()] = u_temp4[Threads.threadid()] + dt_int_temp * fsalfirst # Euler starting step
            for j in 2:j_int_temp
              f(k_tmps[Threads.threadid()], u_temp3[Threads.threadid()], p, t + (j-1) * dt_int_temp)
              @.. T[index+1] = u_temp4[Threads.threadid()] + 2 * dt_int_temp * k_tmps[Threads.threadid()] # Explicit Midpoint rule
              @.. u_temp4[Threads.threadid()] = u_temp3[Threads.threadid()]
              @.. u_temp3[Threads.threadid()] = T[index+1]
            end
            if indices[2] <= indices[1]
                break
            end
          end
        end
      end
    end
  end



  if integrator.opts.adaptive
    # Compute all information relating to an extrapolation order ≦ win_min
    for i = integrator.alg.n_min:n_curr

      #integrator.u .= extrapolation_scalars[i+1] * sum( broadcast(*, cache.T[1:(i+1)], extrapolation_weights[1:(i+1), (i+1)]) ) # Approximation of extrapolation order i
      #cache.utilde .= extrapolation_scalars_2[i] * sum( broadcast(*, cache.T[2:(i+1)], extrapolation_weights_2[1:i, i]) ) # and its internal counterpart

      u_temp1 .= false
      u_temp2 .= false
      for j in 1:(i+1)
        @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (i+1)]
      end
      for j in 2:i+1
        @.. u_temp2 += cache.T[j] * extrapolation_weights_2[j-1, i]
      end
      @.. integrator.u = extrapolation_scalars[i+1] * u_temp1
      @.. cache.utilde = extrapolation_scalars_2[i] * u_temp2

      calculate_residuals!(cache.res, integrator.u, cache.utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(cache.res, t)
      cache.n_curr = i # Update chache's n_curr for stepsize_controller_internal!
      stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
    end

    # Check if an approximation of some order in the order window can be accepted
    while n_curr <= win_max
      if integrator.EEst <= 1.0
        # Accept current approximation u of order n_curr
        break
      elseif integrator.EEst <= tol^(stage_number[n_curr - integrator.alg.n_min + 1] / stage_number[win_max - integrator.alg.n_min + 1] - 1)
        # Reject current approximation order but pass convergence monitor
        # Compute approximation of order (n_curr + 1)
        n_curr = n_curr + 1
        cache.n_curr = n_curr

        # Update cache.T
        j_int = 4 * subdividing_sequence[n_curr + 1]
        dt_int = dt / j_int # Stepsize of the new internal discretisation
        @.. u_temp2 = uprev
        @.. u_temp1 = u_temp2 + dt_int * fsalfirst # Euler starting step
        for j in 2:j_int
          f(k, cache.u_temp1, p, t + (j-1) * dt_int)
          @.. T[n_curr+1] = u_temp2 + 2 * dt_int * k
          @.. u_temp2 = u_temp1
          @.. u_temp1 = T[n_curr+1]
        end

        # Update u, integrator.EEst and cache.Q
        #integrator.u .= extrapolation_scalars[n_curr+1] * sum( broadcast(*, cache.T[1:(n_curr+1)], extrapolation_weights[1:(n_curr+1), (n_curr+1)]) ) # Approximation of extrapolation order n_curr
        #cache.utilde .= extrapolation_scalars_2[n_curr] * sum( broadcast(*, cache.T[2:(n_curr+1)], extrapolation_weights_2[1:n_curr, n_curr]) ) # and its internal counterpart

        u_temp1 .= false
        u_temp2 .= false
        for j in 1:n_curr+1
          @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (n_curr+1)]
        end
        for j in 2:n_curr+1
          @.. u_temp2 += cache.T[j] * extrapolation_weights_2[j-1, n_curr]
        end
        @.. integrator.u = extrapolation_scalars[n_curr+1] * u_temp1
        @.. cache.utilde  = extrapolation_scalars_2[n_curr]* u_temp2

        calculate_residuals!(cache.res, integrator.u, cache.utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
        integrator.EEst = integrator.opts.internalnorm(cache.res, t)
        stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
      else
          # Reject the current approximation and not pass convergence monitor
          break
      end
    end
  else

    #integrator.u .= extrapolation_scalars[n_curr+1] * sum( broadcast(*, cache.T[1:(n_curr+1)], extrapolation_weights[1:(n_curr+1), (n_curr+1)]) ) # Approximation of extrapolation order n_curr
    u_temp1 .= false
    for j in 1:n_curr+1
      @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (n_curr+1)]
    end
    @.. integrator.u = extrapolation_scalars[n_curr+1] * u_temp1

  end

  f(cache.k, integrator.u, p, t+dt) # Update FSAL
end

function initialize!(integrator,cache::ExtrapolationMidpointDeuflhardConstantCache)
  # cf. initialize! of MidpointConstantCache
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::ExtrapolationMidpointDeuflhardConstantCache, repeat_step=false)
  # Unpack all information needed
  @unpack t, uprev, dt, f, p = integrator
  @unpack n_curr = cache
  # Coefficients for obtaining u
  @unpack extrapolation_weights, extrapolation_scalars = cache.coefficients
  # Coefficients for obtaining utilde
  @unpack extrapolation_weights_2, extrapolation_scalars_2 = cache.coefficients
  # Additional constant information
  @unpack subdividing_sequence = cache.coefficients
  @unpack stage_number = cache

  # Create auxiliary variables
  u_temp1, u_temp2 = copy(uprev), copy(uprev) # Auxiliary variables for computing the internal discretisations
  u, utilde = copy(uprev), copy(uprev) # Storage for the latest approximation and its internal counterpart
  tol = integrator.opts.internalnorm(integrator.opts.reltol, t) # Used by the convergence monitor
  T = fill(zero(uprev), integrator.alg.n_max + 1) # Storage for the internal discretisations obtained by the explicit midpoint rule
  fill!(cache.Q, zero(eltype(cache.Q)))

  # Start computation
  if integrator.opts.adaptive
    # Set up the order window
    win_min = max(integrator.alg.n_min, n_curr - 1)
    win_max = min(integrator.alg.n_max, n_curr + 1)

    # Set up the current extrapolation order
    cache.n_old = n_curr # Save the suggested order for step_*_controller!
    n_curr = win_min # Start with smallest order in the order window
  end

  # Compute the internal discretisations
  if !integrator.alg.threading
    for i = 0:n_curr
      j_int = 4 * subdividing_sequence[i+1]
      dt_int = dt / j_int # Stepsize of the ith internal discretisation
      u_temp2 = uprev
      u_temp1 = u_temp2 + dt_int*integrator.fsalfirst # Euler starting step
      for j in 2:j_int
        T[i+1] = u_temp2 + 2 * dt_int * f(u_temp1, p, t + (j-1) * dt_int) # Explicit Midpoint rule
        u_temp2 = u_temp1
        u_temp1 = T[i+1]
      end
    end
  else
    if integrator.alg.sequence == :romberg
      # Compute solution by using maximum two threads for romberg sequence
      # One thread will fill T matrix till second last element and another thread will
      # fill last element of T matrix.
      # Romberg sequence --> 1, 2, 4, 8, ..., 2^(i)
      # 1 + 2 + 4 + ... + 2^(i-1) = 2^(i) - 1
      let n_curr=n_curr,subdividing_sequence=subdividing_sequence,uprev=uprev,dt=dt,
          integrator=integrator,p=p,t=t,T=T
        Threads.@threads for i = 1 : 2
          startIndex = (i == 1) ? 0 : n_curr
          endIndex = (i == 1) ? n_curr - 1 : n_curr
          for index = startIndex : endIndex
            j_int_temp = 4 * subdividing_sequence[index+1]
            dt_int_temp = dt / j_int_temp # Stepsize of the ith internal discretisation
            u_temp4 = uprev
            u_temp3 = u_temp4 + dt_int_temp*integrator.fsalfirst # Euler starting step
            for j in 2:j_int_temp
              T[index+1] = u_temp4 + 2 * dt_int_temp * f(u_temp3, p, t + (j-1) * dt_int_temp) # Explicit Midpoint rule
              u_temp4 = u_temp3
              u_temp3 = T[index+1]
            end
          end
        end
      end
    else
      let n_curr=n_curr, subdividing_sequence=subdividing_sequence, dt=dt, uprev=uprev,
              p=p, t=t, T=T
        Threads.@threads for i in 0:(n_curr ÷ 2)
          indices = (i, n_curr-i)
          for index in indices
            j_int_temp = 4 * subdividing_sequence[index+1]
            dt_int_temp = dt / j_int_temp # Stepsize of the ith internal discretisation
            u_temp4 = uprev
            u_temp3 = u_temp4 + dt_int_temp * integrator.fsalfirst # Euler starting step
            for j in 2:j_int_temp
              T[index+1] = u_temp4 + 2 * dt_int_temp * f(u_temp3, p, t + (j-1) * dt_int_temp) # Explicit Midpoint rule
              u_temp4 = u_temp3
              u_temp3 = T[index+1]
            end
            if indices[2] <= indices[1]
                break
            end
          end
        end
      end
    end
  end


  if integrator.opts.adaptive
    # Compute all information relating to an extrapolation order ≦ win_min
    for i = integrator.alg.n_min:n_curr
      u = eltype(uprev).(extrapolation_scalars[i+1]) * sum( broadcast(*, T[1:(i+1)], eltype(uprev).(extrapolation_weights[1:(i+1), (i+1)])) ) # Approximation of extrapolation order i
      utilde = eltype(uprev).(extrapolation_scalars_2[i]) * sum( broadcast(*, T[2:(i+1)], eltype(uprev).(extrapolation_weights_2[1:i, i])) ) # and its internal counterpart
      res = calculate_residuals(u, utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(res, t)
      cache.n_curr = i # Update chache's n_curr for stepsize_controller_internal!
      stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
    end

    # Check if an approximation of some order in the order window can be accepted
    while n_curr <= win_max
      if integrator.EEst <= 1.0
        # Accept current approximation u of order n_curr
        break
      elseif integrator.EEst <= tol^(stage_number[n_curr - integrator.alg.n_min + 1] / stage_number[win_max - integrator.alg.n_min + 1] - 1)
        # Reject current approximation order but pass convergence monitor
        # Compute approximation of order (n_curr + 1)
        n_curr = n_curr + 1
        cache.n_curr = n_curr

        # Update T
        j_int = 4 * subdividing_sequence[n_curr + 1]
        dt_int = dt / j_int # Stepsize of the new internal discretisation
        u_temp2 = uprev
        u_temp1 = u_temp2 + dt_int * integrator.fsalfirst # Euler starting step
        for j in 2:j_int
          T[n_curr+1] = u_temp2 + 2 * dt_int * f(u_temp1, p, t + (j-1) * dt_int)
          u_temp2 = u_temp1
          u_temp1 = T[n_curr+1]
        end

        # Update u, integrator.EEst and cache.Q
        u = eltype(uprev).(extrapolation_scalars[n_curr+1]) * sum( broadcast(*, T[1:(n_curr+1)], eltype(uprev).(extrapolation_weights[1:(n_curr+1), (n_curr+1)])) ) # Approximation of extrapolation order n_curr
        utilde = eltype(uprev).(extrapolation_scalars_2[n_curr]) * sum( broadcast(*, T[2:(n_curr+1)], eltype(uprev).(extrapolation_weights_2[1:n_curr, n_curr])) ) # and its internal counterpart
        res = calculate_residuals(u, utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
        integrator.EEst = integrator.opts.internalnorm(res, t)
        stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
      else
          # Reject the current approximation and not pass convergence monitor
          break
      end
    end
  else
    u = eltype(uprev).(extrapolation_scalars[n_curr+1]) * sum( broadcast(*, T[1:(n_curr+1)], eltype(uprev).(extrapolation_weights[1:(n_curr+1), (n_curr+1)])) ) # Approximation of extrapolation order n_curr
  end

  # Save the latest approximation and update FSAL
  integrator.u = u
  integrator.fsallast = f(u, p, t + dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function initialize!(integrator,cache::ImplicitDeuflhardExtrapolationCache)
  # cf. initialize! of MidpointCache
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 2
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
end

function perform_step!(integrator, cache::ImplicitDeuflhardExtrapolationCache, repeat_step = false)
  # Unpack all information needed
  @unpack t, uprev, dt, f, p = integrator
  @unpack n_curr, u_temp1, u_temp2, utilde, res, T, fsalfirst,k  = cache
  @unpack u_temp3, u_temp4, k_tmps = cache

  # Coefficients for obtaining u
  @unpack extrapolation_weights, extrapolation_scalars = cache.coefficients
  # Coefficients for obtaining utilde
  @unpack extrapolation_weights_2, extrapolation_scalars_2 = cache.coefficients
  # Additional constant information
  @unpack subdividing_sequence = cache.coefficients
  @unpack stage_number = cache

  @unpack J,W,uf,tf,linsolve_tmp,jac_config = cache

  fill!(cache.Q, zero(eltype(cache.Q)))
  tol = integrator.opts.internalnorm(integrator.opts.reltol, t) # Used by the convergence monitor

  if integrator.opts.adaptive
    # Set up the order window
    win_min = max(integrator.alg.n_min, n_curr - 1)
    win_max = min(integrator.alg.n_max, n_curr + 1)

    # Set up the current extrapolation order
    cache.n_old = n_curr # Save the suggested order for step_*_controller!
    n_curr = win_min # Start with smallest order in the order window

  end

  #Compute the internal discretisations
  for i in 0:n_curr
    j_int = 4 * subdividing_sequence[i+1]
    dt_int = dt / j_int # Stepsize of the ith internal discretisation
    calc_W!(W, integrator, nothing, cache, dt_int, repeat_step)
    @.. u_temp2 = uprev
    @.. linsolve_tmp = dt_int*fsalfirst
    cache.linsolve(vec(k), W, vec(linsolve_tmp), !repeat_step)
    @.. k = -k
    @.. u_temp1 = u_temp2 + k # Euler starting step
    for j in 2:j_int
      f(k, cache.u_temp1, p, t + (j-1) * dt_int)
      @.. linsolve_tmp = dt_int * k - (u_temp1 - u_temp2)
      cache.linsolve(vec(k), W, vec(linsolve_tmp), !repeat_step)
      @.. k = -k
      @.. T[i+1] = 2 * u_temp1 - u_temp2 + 2 * k # Explicit Midpoint rule
      @.. u_temp2 = u_temp1
      @.. u_temp1 = T[i+1]
    end
  end

  if integrator.opts.adaptive
    # Compute all information relating to an extrapolation order ≦ win_min
    for i = integrator.alg.n_min:n_curr

      #integrator.u .= extrapolation_scalars[i+1] * sum( broadcast(*, cache.T[1:(i+1)], extrapolation_weights[1:(i+1), (i+1)]) ) # Approximation of extrapolation order i
      #cache.utilde .= extrapolation_scalars_2[i] * sum( broadcast(*, cache.T[2:(i+1)], extrapolation_weights_2[1:i, i]) ) # and its internal counterpart

      u_temp1 .= false
      u_temp2 .= false
      for j in 1:(i+1)
        @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (i+1)]
      end
      for j in 2:i+1
        @.. u_temp2 += cache.T[j] * extrapolation_weights_2[j-1, i]
      end
      @.. integrator.u = extrapolation_scalars[i+1] * u_temp1
      @.. cache.utilde = extrapolation_scalars_2[i] * u_temp2

      calculate_residuals!(cache.res, integrator.u, cache.utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(cache.res, t)
      cache.n_curr = i # Update chache's n_curr for stepsize_controller_internal!
      stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
    end

    # Check if an approximation of some order in the order window can be accepted
    while n_curr <= win_max
      if integrator.EEst <= 1.0
        # Accept current approximation u of order n_curr
        break
      elseif integrator.EEst <= tol^(stage_number[n_curr - integrator.alg.n_min + 1] / stage_number[win_max - integrator.alg.n_min + 1] - 1)
        # Reject current approximation order but pass convergence monitor
        # Compute approximation of order (n_curr + 1)
        n_curr = n_curr + 1
        cache.n_curr = n_curr

        # Update cache.T
        j_int = 4 * subdividing_sequence[n_curr + 1]
        dt_int = dt / j_int # Stepsize of the new internal discretisation
        @.. u_temp2 = uprev
        @.. u_temp1 = u_temp2 + dt_int * fsalfirst # Euler starting step
        for j in 2:j_int
          f(k, cache.u_temp1, p, t + (j-1) * dt_int)
          @.. T[n_curr+1] = u_temp2 + 2 * dt_int * k
          @.. u_temp2 = u_temp1
          @.. u_temp1 = T[n_curr+1]
        end

        # Update u, integrator.EEst and cache.Q
        #integrator.u .= extrapolation_scalars[n_curr+1] * sum( broadcast(*, cache.T[1:(n_curr+1)], extrapolation_weights[1:(n_curr+1), (n_curr+1)]) ) # Approximation of extrapolation order n_curr
        #cache.utilde .= extrapolation_scalars_2[n_curr] * sum( broadcast(*, cache.T[2:(n_curr+1)], extrapolation_weights_2[1:n_curr, n_curr]) ) # and its internal counterpart

        u_temp1 .= false
        u_temp2 .= false
        for j in 1:n_curr+1
          @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (n_curr+1)]
        end
        for j in 2:n_curr+1
          @.. u_temp2 += cache.T[j] * extrapolation_weights_2[j-1, n_curr]
        end
        @.. integrator.u = extrapolation_scalars[n_curr+1] * u_temp1
        @.. cache.utilde  = extrapolation_scalars_2[n_curr]* u_temp2

        calculate_residuals!(cache.res, integrator.u, cache.utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
        integrator.EEst = integrator.opts.internalnorm(cache.res, t)
        stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
      else
          # Reject the current approximation and not pass convergence monitor
          break
      end
    end
  else

    #integrator.u .= extrapolation_scalars[n_curr+1] * sum( broadcast(*, cache.T[1:(n_curr+1)], extrapolation_weights[1:(n_curr+1), (n_curr+1)]) ) # Approximation of extrapolation order n_curr
    u_temp1 .= false
    for j in 1:n_curr+1
      @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (n_curr+1)]
    end
    @.. integrator.u = extrapolation_scalars[n_curr+1] * u_temp1

  end

  f(cache.k, integrator.u, p, t+dt) # Update FSAL
end

function initialize!(integrator,cache::ImplicitDeuflhardExtrapolationConstantCache)
  # cf. initialize! of MidpointConstantCache
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::ImplicitDeuflhardExtrapolationConstantCache, repeat_step=false)
  # Unpack all information needed
  @unpack t, uprev, dt, f, p = integrator
  @unpack n_curr = cache
  # Coefficients for obtaining u
  @unpack extrapolation_weights, extrapolation_scalars = cache.coefficients
  # Coefficients for obtaining utilde
  @unpack extrapolation_weights_2, extrapolation_scalars_2 = cache.coefficients
  # Additional constant information
  @unpack subdividing_sequence = cache.coefficients
  @unpack stage_number = cache

  # Create auxiliary variables
  u_temp1, u_temp2 = copy(uprev), copy(uprev) # Auxiliary variables for computing the internal discretisations
  u, utilde = copy(uprev), copy(uprev) # Storage for the latest approximation and its internal counterpart
  tol = integrator.opts.internalnorm(integrator.opts.reltol, t) # Used by the convergence monitor
  T = fill(zero(uprev), integrator.alg.n_max + 1) # Storage for the internal discretisations obtained by the explicit midpoint rule
  fill!(cache.Q, zero(eltype(cache.Q)))

  # Start computation
  if integrator.opts.adaptive
    # Set up the order window
    win_min = max(integrator.alg.n_min, n_curr - 1)
    win_max = min(integrator.alg.n_max, n_curr + 1)

    # Set up the current extrapolation order
    cache.n_old = n_curr # Save the suggested order for step_*_controller!
    n_curr = win_min # Start with smallest order in the order window
  end

  # Compute the internal discretisations
  for i in 0:n_curr
    j_int = 4 * subdividing_sequence[i+1]
    dt_int = dt / j_int # Stepsize of the ith internal discretisation
    W = calc_W(integrator, cache, dt_int, repeat_step)
    u_temp2 = uprev
    u_temp1 = u_temp2 + _reshape(W\-_vec(dt_int*integrator.fsalfirst), axes(uprev)) # Euler starting step
    for j in 2:j_int
      T[i+1] = 2*u_temp1 - u_temp2 + 2 * _reshape(W\-_vec(dt_int*f(u_temp1, p, t + (j-1) * dt_int) - (u_temp1 - u_temp2)),axes(uprev))
      u_temp2 = u_temp1
      u_temp1 = T[i+1]
    end
  end


  if integrator.opts.adaptive
    # Compute all information relating to an extrapolation order ≦ win_min
    for i = integrator.alg.n_min:n_curr
      u = eltype(uprev).(extrapolation_scalars[i+1]) * sum( broadcast(*, T[1:(i+1)], eltype(uprev).(extrapolation_weights[1:(i+1), (i+1)])) ) # Approximation of extrapolation order i
      utilde = eltype(uprev).(extrapolation_scalars_2[i]) * sum( broadcast(*, T[2:(i+1)], eltype(uprev).(extrapolation_weights_2[1:i, i])) ) # and its internal counterpart
      res = calculate_residuals(u, utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(res, t)
      cache.n_curr = i # Update chache's n_curr for stepsize_controller_internal!
      stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
    end

    # Check if an approximation of some order in the order window can be accepted
    while n_curr <= win_max
      if integrator.EEst <= 1.0
        # Accept current approximation u of order n_curr
        break
      elseif integrator.EEst <= tol^(stage_number[n_curr - integrator.alg.n_min + 1] / stage_number[win_max - integrator.alg.n_min + 1] - 1)
        # Reject current approximation order but pass convergence monitor
        # Compute approximation of order (n_curr + 1)
        n_curr = n_curr + 1
        cache.n_curr = n_curr

        # Update T
        j_int = 4 * subdividing_sequence[n_curr + 1]
        dt_int = dt / j_int # Stepsize of the new internal discretisation
        u_temp2 = uprev
        u_temp1 = u_temp2 + dt_int * integrator.fsalfirst # Euler starting step
        for j in 2:j_int
          T[n_curr+1] = u_temp2 + 2 * dt_int * f(u_temp1, p, t + (j-1) * dt_int)
          u_temp2 = u_temp1
          u_temp1 = T[n_curr+1]
        end

        # Update u, integrator.EEst and cache.Q
        u = eltype(uprev).(extrapolation_scalars[n_curr+1]) * sum( broadcast(*, T[1:(n_curr+1)], eltype(uprev).(extrapolation_weights[1:(n_curr+1), (n_curr+1)])) ) # Approximation of extrapolation order n_curr
        utilde = eltype(uprev).(extrapolation_scalars_2[n_curr]) * sum( broadcast(*, T[2:(n_curr+1)], eltype(uprev).(extrapolation_weights_2[1:n_curr, n_curr])) ) # and its internal counterpart
        res = calculate_residuals(u, utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
        integrator.EEst = integrator.opts.internalnorm(res, t)
        stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
      else
          # Reject the current approximation and not pass convergence monitor
          break
      end
    end
  else
    u = eltype(uprev).(extrapolation_scalars[n_curr+1]) * sum( broadcast(*, T[1:(n_curr+1)], eltype(uprev).(extrapolation_weights[1:(n_curr+1), (n_curr+1)])) ) # Approximation of extrapolation order n_curr
  end

  # Save the latest approximation and update FSAL
  integrator.u = u
  integrator.fsallast = f(u, p, t + dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function initialize!(integrator,cache::ExtrapolationMidpointHairerWannerCache)
  # cf. initialize! of MidpointCache
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 2
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
end

function perform_step!(integrator, cache::ExtrapolationMidpointHairerWannerCache, repeat_step = false)
  # Unpack all information needed
  @unpack t, uprev, dt, f, p = integrator
  @unpack n_curr, u_temp1, u_temp2, utilde, res, T, fsalfirst,k  = cache
  @unpack u_temp3, u_temp4, k_tmps = cache
  # Coefficients for obtaining u
  @unpack extrapolation_weights, extrapolation_scalars = cache.coefficients
  # Coefficients for obtaining utilde
  @unpack extrapolation_weights_2, extrapolation_scalars_2 = cache.coefficients
  # Additional constant information
  @unpack subdividing_sequence = cache.coefficients

  fill!(cache.Q, zero(eltype(cache.Q)))

  if integrator.opts.adaptive
    # Set up the order window
    # integrator.alg.n_min + 1 ≦ n_curr ≦ integrator.alg.n_max - 1 is enforced by step_*_controller!
    if !(integrator.alg.n_min + 1 <= n_curr <= integrator.alg.n_max-1)
       error("Something went wrong while setting up the order window: $n_curr ∉ [$(integrator.alg.n_min+1),$(integrator.alg.n_max-1)].
       Please report this error  ")
    end
    win_min =  n_curr - 1
    win_max =  n_curr + 1

    # Set up the current extrapolation order
    cache.n_old = n_curr # Save the suggested order for step_*_controller!
    n_curr = win_min # Start with smallest order in the order window
  end

  #Compute the internal discretisations
  if !integrator.alg.threading
    for i in 0:n_curr
      j_int = 4 * subdividing_sequence[i+1]
      dt_int = dt / j_int # Stepsize of the ith internal discretisation
      @.. u_temp2 = uprev
      @.. u_temp1 = u_temp2 + dt_int * fsalfirst # Euler starting step
      for j in 2:j_int
        f(k, cache.u_temp1, p, t + (j-1) * dt_int)
        @.. T[i+1] = u_temp2 + 2 * dt_int * k # Explicit Midpoint rule
        @.. u_temp2 = u_temp1
        @.. u_temp1 = T[i+1]
      end
    end
  else
    if integrator.alg.sequence == :romberg
      # Compute solution by using maximum two threads for romberg sequence
      # One thread will fill T matrix till second last element and another thread will
      # fill last element of T matrix.
      # Romberg sequence --> 1, 2, 4, 8, ..., 2^(i)
      # 1 + 2 + 4 + ... + 2^(i-1) = 2^(i) - 1
      let n_curr=n_curr,subdividing_sequence=subdividing_sequence,uprev=uprev,dt=dt,u_temp3=u_temp3,
          u_temp4=u_temp4,k_tmps=k_tmps,p=p,t=t,T=T
        Threads.@threads for i = 1 : 2
          startIndex = (i == 1) ? 0 : n_curr
          endIndex = (i == 1) ? n_curr - 1 : n_curr

          for index in startIndex:endIndex
            j_int_temp = 4 * subdividing_sequence[index+1]
            dt_int_temp = dt / j_int_temp # Stepsize of the ith internal discretisation
            @.. u_temp4[Threads.threadid()] = uprev
            @.. u_temp3[Threads.threadid()] = u_temp4[Threads.threadid()] + dt_int_temp * fsalfirst # Euler starting step
            for j in 2:j_int_temp
              f(k_tmps[Threads.threadid()], cache.u_temp3[Threads.threadid()], p, t + (j-1) * dt_int_temp)
              @.. T[index+1] = u_temp4[Threads.threadid()] + 2 * dt_int_temp * k_tmps[Threads.threadid()] # Explicit Midpoint rule
              @.. u_temp4[Threads.threadid()] = u_temp3[Threads.threadid()]
              @.. u_temp3[Threads.threadid()] = T[index+1]
            end
          end
        end
      end
    else
      let n_curr=n_curr,subdividing_sequence=subdividing_sequence,uprev=uprev,dt=dt,u_temp3=u_temp3,
          u_temp4=u_temp4,k_tmps=k_tmps,p=p,t=t,T=T
        Threads.@threads for i in 0:(n_curr ÷ 2)
          indices = (i, n_curr - i)
          for index in indices
            j_int_temp = 4 * subdividing_sequence[index+1]
            dt_int_temp = dt / j_int_temp # Stepsize of the ith internal discretisation
            @.. u_temp4[Threads.threadid()] = uprev
            @.. u_temp3[Threads.threadid()] = u_temp4[Threads.threadid()] + dt_int_temp * fsalfirst # Euler starting step
            for j in 2:j_int_temp
              f(k_tmps[Threads.threadid()], cache.u_temp3[Threads.threadid()], p, t + (j-1) * dt_int_temp)
              @.. T[index+1] = u_temp4[Threads.threadid()] + 2 * dt_int_temp * k_tmps[Threads.threadid()] # Explicit Midpoint rule
              @.. u_temp4[Threads.threadid()] = u_temp3[Threads.threadid()]
              @.. u_temp3[Threads.threadid()] = T[index+1]
            end
          end
        end
      end
    end
  end

  if integrator.opts.adaptive
    # Compute all information relating to an extrapolation order ≦ win_min
    for i = win_min - 1 : win_min

      #integrator.u .= extrapolation_scalars[i+1] * sum( broadcast(*, cache.T[1:(i+1)], extrapolation_weights[1:(i+1), (i+1)]) ) # Approximation of extrapolation order i
      #cache.utilde .= extrapolation_scalars_2[i] * sum( broadcast(*, cache.T[2:(i+1)], extrapolation_weights_2[1:i, i]) ) # and its internal counterpart

      u_temp1 .= false
      u_temp2 .= false
      for j in 1:(i+1)
        @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (i+1)]
      end
      for j in 2:i+1
        @.. u_temp2 += cache.T[j] * extrapolation_weights_2[j-1, i]
      end
      @.. integrator.u = extrapolation_scalars[i+1] * u_temp1
      @.. cache.utilde  = extrapolation_scalars_2[i] * u_temp2

      calculate_residuals!(cache.res, integrator.u, cache.utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(cache.res, t)
      cache.n_curr = i # Update chache's n_curr for stepsize_controller_internal!
      stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
    end

    # Check if an approximation of some order in the order window can be accepted
    # Make sure a stepsize scaling factor of order (integrator.alg.n_min + 1) is provided for the step_*_controller!
    while n_curr <= win_max
      if integrator.EEst <= 1.0
        # Accept current approximation u of order n_curr
        break
    elseif (n_curr < integrator.alg.n_min + 1) || integrator.EEst <= typeof(integrator.EEst)(prod(subdividing_sequence[n_curr+2:win_max+1] .// subdividing_sequence[1]^2))
        # Reject current approximation order but pass convergence monitor
        # Compute approximation of order (n_curr + 1)
        n_curr = n_curr + 1
        cache.n_curr = n_curr

        # Update cache.T
        j_int = 4 * subdividing_sequence[n_curr + 1]
        dt_int = dt / j_int # Stepsize of the new internal discretisation
        @.. u_temp2 = uprev
        @.. u_temp1 = u_temp2 + dt_int * fsalfirst # Euler starting step
        for j in 2:j_int
          f(k, cache.u_temp1, p, t + (j-1) * dt_int)
          @.. T[n_curr+1] = u_temp2 + 2 * dt_int * k
          @.. u_temp2 = u_temp1
          @.. u_temp1 = T[n_curr+1]
        end

        # Update u, integrator.EEst and cache.Q
        #integrator.u .= extrapolation_scalars[n_curr+1] * sum( broadcast(*, cache.T[1:(n_curr+1)], extrapolation_weights[1:(n_curr+1), (n_curr+1)]) ) # Approximation of extrapolation order n_curr
        #cache.utilde .= extrapolation_scalars_2[n_curr] * sum( broadcast(*, cache.T[2:(n_curr+1)], extrapolation_weights_2[1:n_curr, n_curr]) ) # and its internal counterpart

        u_temp1 .= false
        u_temp2 .= false
        for j in 1:n_curr+1
          @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (n_curr+1)]
        end
        for j in 2:n_curr+1
          @.. u_temp2 += cache.T[j] * extrapolation_weights_2[j-1, n_curr]
        end
        @.. integrator.u = extrapolation_scalars[n_curr+1] * u_temp1
        @.. cache.utilde  = extrapolation_scalars_2[n_curr]* u_temp2

        calculate_residuals!(cache.res, integrator.u, cache.utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
        integrator.EEst = integrator.opts.internalnorm(cache.res, t)
        stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
      else
          # Reject the current approximation and not pass convergence monitor
          break
      end
    end
  else

    #integrator.u .= extrapolation_scalars[n_curr+1] * sum( broadcast(*, cache.T[1:(n_curr+1)], extrapolation_weights[1:(n_curr+1), (n_curr+1)]) ) # Approximation of extrapolation order n_curr
    u_temp1 .= false
    for j in 1:n_curr+1
      @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (n_curr+1)]
    end
    @.. integrator.u = extrapolation_scalars[n_curr+1] * u_temp1

  end

  f(cache.k, integrator.u, p, t+dt) # Update FSAL
end

function initialize!(integrator,cache::ExtrapolationMidpointHairerWannerConstantCache)
  # cf. initialize! of MidpointConstantCache
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator, cache::ExtrapolationMidpointHairerWannerConstantCache, repeat_step = false)
  # Unpack all information needed
  @unpack t, uprev, dt, f, p = integrator
  @unpack n_curr = cache
  # Coefficients for obtaining u
  @unpack extrapolation_weights, extrapolation_scalars = cache.coefficients
  # Coefficients for obtaining utilde
  @unpack extrapolation_weights_2, extrapolation_scalars_2 = cache.coefficients
  # Additional constant information
  @unpack subdividing_sequence = cache.coefficients

  # Create auxiliary variables
  u_temp1, u_temp2 = copy(uprev), copy(uprev) # Auxiliary variables for computing the internal discretisations
  u, utilde = copy(uprev), copy(uprev) # Storage for the latest approximation and its internal counterpart
  T = fill(zero(uprev), integrator.alg.n_max + 1) # Storage for the internal discretisations obtained by the explicit midpoint rule
  fill!(cache.Q, zero(eltype(cache.Q)))

  if integrator.opts.adaptive
    # Set up the order window
    # integrator.alg.n_min + 1 ≦ n_curr ≦ integrator.alg.n_max - 1 is enforced by step_*_controller!
    if !(integrator.alg.n_min + 1 <= n_curr <= integrator.alg.n_max-1)
       error("Something went wrong while setting up the order window: $n_curr ∉ [$(integrator.alg.n_min+1),$(integrator.alg.n_max-1)].
       Please report this error  ")
    end
    win_min =  n_curr - 1
    win_max =  n_curr + 1

    # Set up the current extrapolation order
    cache.n_old = n_curr # Save the suggested order for step_*_controller!
    n_curr = win_min # Start with smallest order in the order window
  end

  #Compute the internal discretisations
  if !integrator.alg.threading
    for i in 0:n_curr
     j_int = 4 * subdividing_sequence[i+1]
     dt_int = dt / j_int # Stepsize of the ith internal discretisation
     u_temp2 = uprev
     u_temp1 = u_temp2 + dt_int * integrator.fsalfirst # Euler starting step
     for j in 2:j_int
       T[i+1] = u_temp2 + 2 * dt_int * f(u_temp1, p, t + (j-1) * dt_int) # Explicit Midpoint rule
       u_temp2 = u_temp1
       u_temp1 = T[i+1]
     end
    end
  else
    if integrator.alg.sequence == :romberg
      # Compute solution by using maximum two threads for romberg sequence
      # One thread will fill T matrix till second last element and another thread will
      # fill last element of T matrix.
      # Romberg sequence --> 1, 2, 4, 8, ..., 2^(i)
      # 1 + 2 + 4 + ... + 2^(i-1) = 2^(i) - 1
      let n_curr=n_curr, subdividing_sequence=subdividing_sequence, dt=dt, uprev=uprev,
          integrator=integrator, T=T, p=p, t=t
        Threads.@threads for i = 1 : 2
          startIndex = (i == 1) ? 0 : n_curr
          endIndex = (i == 1) ? n_curr - 1 : n_curr
          for index in startIndex:endIndex
            j_int_temp = 4 * subdividing_sequence[index+1]
            dt_int_temp = dt / j_int_temp # Stepsize of the ith internal discretisation
            u_temp4 = uprev
            u_temp3 = u_temp4 + dt_int_temp * integrator.fsalfirst # Euler starting step
            for j in 2:j_int_temp
              T[index+1] = u_temp4 + 2 * dt_int_temp * f(u_temp3, p, t + (j - 1) * dt_int_temp) # Explicit Midpoint rule
              u_temp4 = u_temp3
              u_temp3 = T[index+1]
            end
          end
        end
      end
    else
      let n_curr=n_curr, subdividing_sequence=subdividing_sequence, dt=dt, uprev=uprev,
          integrator=integrator, T=T, p=p, t=t
        Threads.@threads for i in 0:(n_curr ÷ 2)
          indices = (i, n_curr - i)
          for index in indices
            j_int_temp = 4 * subdividing_sequence[index+1]
            dt_int_temp = dt / j_int_temp # Stepsize of the ith internal discretisation
            u_temp4 = uprev
            u_temp3 = u_temp4 + dt_int_temp * integrator.fsalfirst # Euler starting step
            for j in 2:j_int_temp
              T[index+1] = u_temp4 + 2 * dt_int_temp * f(u_temp3, p, t + (j - 1) * dt_int_temp) # Explicit Midpoint rule
              u_temp4 = u_temp3
              u_temp3 = T[index+1]
            end
          end
        end
      end
    end
  end
  if integrator.opts.adaptive
    # Compute all information relating to an extrapolation order ≦ win_min
    for i = win_min - 1 : win_min
      u = eltype(uprev).(extrapolation_scalars[i+1]) * sum( broadcast(*, T[1:(i+1)], eltype(uprev).(extrapolation_weights[1:(i+1), (i+1)])) ) # Approximation of extrapolation order i
      utilde = eltype(uprev).(extrapolation_scalars_2[i]) * sum( broadcast(*, T[2:(i+1)], eltype(uprev).(extrapolation_weights_2[1:i, i])) ) # and its internal counterpart
      res = calculate_residuals(u, utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(res, t)
      cache.n_curr = i # Update chache's n_curr for stepsize_controller_internal!
      stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
    end

    # Check if an approximation of some order in the order window can be accepted
    # Make sure a stepsize scaling factor of order (integrator.alg.n_min + 1) is provided for the step_*_controller!
    while n_curr <= win_max
      if integrator.EEst <= 1.0
        # Accept current approximation u of order n_curr
        break
      elseif (n_curr < integrator.alg.n_min + 1) || integrator.EEst <= typeof(integrator.EEst)(prod(subdividing_sequence[n_curr+2:win_max+1] .// subdividing_sequence[1]^2))
        # Reject current approximation order but pass convergence monitor
        # Always compute approximation of order (n_curr + 1)
        n_curr = n_curr + 1
        cache.n_curr = n_curr

        # Update T
        j_int = 4 * subdividing_sequence[n_curr + 1]
        dt_int = dt / j_int # Stepsize of the new internal discretisation
        u_temp2 = uprev
        u_temp1 = u_temp2 + dt_int * integrator.fsalfirst # Euler starting step
        for j in 2:j_int
          T[n_curr+1] = u_temp2 + 2 * dt_int * f(u_temp1, p, t + (j - 1) * dt_int)
          u_temp2 = u_temp1
          u_temp1 = T[n_curr+1]
        end

        # Update u, integrator.EEst and cache.Q
        u = eltype(uprev).(extrapolation_scalars[n_curr+1]) * sum( broadcast(*, T[1:(n_curr+1)], eltype(uprev).(extrapolation_weights[1:(n_curr+1), (n_curr+1)])) ) # Approximation of extrapolation order n_curr
        utilde = eltype(uprev).(extrapolation_scalars_2[n_curr]) * sum( broadcast(*, T[2:(n_curr+1)], eltype(uprev).(extrapolation_weights_2[1:n_curr, n_curr])) ) # and its internal counterpart
        res = calculate_residuals(u, utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
        integrator.EEst = integrator.opts.internalnorm(res, t)
        stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
      else
          # Reject the current approximation and not pass convergence monitor
          break
      end
    end
  else
    u = eltype(uprev).(extrapolation_scalars[n_curr+1]) * sum( broadcast(*, T[1:(n_curr+1)], eltype(uprev).(extrapolation_weights[1:(n_curr+1), (n_curr+1)])) ) # Approximation of extrapolation order n_curr
  end

  # Save the latest approximation and update FSAL
  integrator.u = u
  integrator.fsallast = f(u, p, t + dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function initialize!(integrator,cache::ImplicitHairerWannerExtrapolationConstantCache)
  # cf. initialize! of MidpointConstantCache
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator, cache::ImplicitHairerWannerExtrapolationConstantCache, repeat_step = false)
  # Unpack all information needed
  @unpack t, uprev, dt, f, p = integrator
  @unpack n_curr = cache
  # Coefficients for obtaining u
  @unpack extrapolation_weights, extrapolation_scalars = cache.coefficients
  # Coefficients for obtaining utilde
  @unpack extrapolation_weights_2, extrapolation_scalars_2 = cache.coefficients
  # Additional constant information
  @unpack subdividing_sequence = cache.coefficients

  # Create auxiliary variables
  u_temp1, u_temp2 = copy(uprev), copy(uprev) # Auxiliary variables for computing the internal discretisations
  u, utilde = copy(uprev), copy(uprev) # Storage for the latest approximation and its internal counterpart
  T = fill(zero(uprev), integrator.alg.n_max + 1) # Storage for the internal discretisations obtained by the explicit midpoint rule
  fill!(cache.Q, zero(eltype(cache.Q)))

  if integrator.opts.adaptive
    # Set up the order window
    # integrator.alg.n_min + 1 ≦ n_curr ≦ integrator.alg.n_max - 1 is enforced by step_*_controller!
    if !(integrator.alg.n_min + 1 <= n_curr <= integrator.alg.n_max-1)
       error("Something went wrong while setting up the order window: $n_curr ∉ [$(integrator.alg.n_min+1),$(integrator.alg.n_max-1)].
       Please report this error  ")
    end
    win_min =  n_curr - 1
    win_max =  n_curr + 1

    # Set up the current extrapolation order
    cache.n_old = n_curr # Save the suggested order for step_*_controller!
    n_curr = win_min # Start with smallest order in the order window
  end

  #Compute the internal discretisations
  for i in 0:n_curr
    j_int = 4 * subdividing_sequence[i+1]
    dt_int = dt / j_int # Stepsize of the ith internal discretisation
    W = calc_W(integrator, cache, dt_int, repeat_step)
    u_temp2 = uprev
    u_temp1 = u_temp2 + _reshape(W\-_vec(dt_int*integrator.fsalfirst), axes(uprev)) # Euler starting step
    for j in 2:j_int
      T[i+1] = 2*u_temp1 - u_temp2 + 2*_reshape(W\-_vec(dt_int * f(u_temp1, p, t + (j-1) * dt_int) - (u_temp1 - u_temp2)),axes(uprev))
      u_temp2 = u_temp1
      u_temp1 = T[i+1]
    end
  end

  if integrator.opts.adaptive
    # Compute all information relating to an extrapolation order ≦ win_min
    for i = win_min - 1 : win_min
      u = eltype(uprev).(extrapolation_scalars[i+1]) * sum( broadcast(*, T[1:(i+1)], eltype(uprev).(extrapolation_weights[1:(i+1), (i+1)])) ) # Approximation of extrapolation order i
      utilde = eltype(uprev).(extrapolation_scalars_2[i]) * sum( broadcast(*, T[2:(i+1)], eltype(uprev).(extrapolation_weights_2[1:i, i])) ) # and its internal counterpart
      res = calculate_residuals(u, utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(res, t)
      cache.n_curr = i # Update chache's n_curr for stepsize_controller_internal!
      stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
    end

    # Check if an approximation of some order in the order window can be accepted
    # Make sure a stepsize scaling factor of order (integrator.alg.n_min + 1) is provided for the step_*_controller!
    while n_curr <= win_max
      if integrator.EEst <= 1.0
        # Accept current approximation u of order n_curr
        break
      elseif (n_curr < integrator.alg.n_min + 1) || integrator.EEst <= typeof(integrator.EEst)(prod(subdividing_sequence[n_curr+2:win_max+1] .// subdividing_sequence[1]^2))
        # Reject current approximation order but pass convergence monitor
        # Always compute approximation of order (n_curr + 1)
        n_curr = n_curr + 1
        cache.n_curr = n_curr

        # Update T
        j_int = 4 * subdividing_sequence[n_curr + 1]
        dt_int = dt / j_int # Stepsize of the new internal discretisation
        u_temp2 = uprev
        u_temp1 = u_temp2 + dt_int * integrator.fsalfirst # Euler starting step
        for j in 2:j_int
          T[n_curr+1] = u_temp2 + 2 * dt_int * f(u_temp1, p, t + (j-1) * dt_int)
          u_temp2 = u_temp1
          u_temp1 = T[n_curr+1]
        end

        # Update u, integrator.EEst and cache.Q
        u = eltype(uprev).(extrapolation_scalars[n_curr+1]) * sum( broadcast(*, T[1:(n_curr+1)], eltype(uprev).(extrapolation_weights[1:(n_curr+1), (n_curr+1)])) ) # Approximation of extrapolation order n_curr
        utilde = eltype(uprev).(extrapolation_scalars_2[n_curr]) * sum( broadcast(*, T[2:(n_curr+1)], eltype(uprev).(extrapolation_weights_2[1:n_curr, n_curr])) ) # and its internal counterpart
        res = calculate_residuals(u, utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
        integrator.EEst = integrator.opts.internalnorm(res, t)
        stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
      else
          # Reject the current approximation and not pass convergence monitor
          break
      end
    end
  else
    u = eltype(uprev).(extrapolation_scalars[n_curr+1]) * sum( broadcast(*, T[1:(n_curr+1)], eltype(uprev).(extrapolation_weights[1:(n_curr+1), (n_curr+1)])) ) # Approximation of extrapolation order n_curr
  end

  # Save the latest approximation and update FSAL
  integrator.u = u
  integrator.fsallast = f(u, p, t + dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function initialize!(integrator,cache::ImplicitHairerWannerExtrapolationCache)
  # cf. initialize! of MidpointCache
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 2
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
end

function perform_step!(integrator, cache::ImplicitHairerWannerExtrapolationCache, repeat_step = false)
  # Unpack all information needed
  @unpack t, uprev, dt, f, p = integrator
  @unpack n_curr, u_temp1, u_temp2, utilde, res, T, fsalfirst,k  = cache
  @unpack u_temp3, u_temp4, k_tmps = cache
  # Coefficients for obtaining u
  @unpack extrapolation_weights, extrapolation_scalars = cache.coefficients
  # Coefficients for obtaining utilde
  @unpack extrapolation_weights_2, extrapolation_scalars_2 = cache.coefficients
  # Additional constant information
  @unpack subdividing_sequence = cache.coefficients

  @unpack J,W,uf,tf,linsolve_tmp,jac_config = cache

  fill!(cache.Q, zero(eltype(cache.Q)))

  if integrator.opts.adaptive
    # Set up the order window
    # integrator.alg.n_min + 1 ≦ n_curr ≦ integrator.alg.n_max - 1 is enforced by step_*_controller!
    if !(integrator.alg.n_min + 1 <= n_curr <= integrator.alg.n_max-1)
       error("Something went wrong while setting up the order window: $n_curr ∉ [$(integrator.alg.n_min+1),$(integrator.alg.n_max-1)].
       Please report this error  ")
    end
    win_min =  n_curr - 1
    win_max =  n_curr + 1

    # Set up the current extrapolation order
    cache.n_old = n_curr # Save the suggested order for step_*_controller!
    n_curr = win_min # Start with smallest order in the order window
  end

  #Compute the internal discretisations
  for i in 0:n_curr
    j_int = 4 * subdividing_sequence[i+1]
    dt_int = dt / j_int # Stepsize of the ith internal discretisation
    calc_W!(W, integrator, nothing, cache, dt_int, repeat_step)
    @.. u_temp2 = uprev
    @.. linsolve_tmp = dt_int * fsalfirst
    cache.linsolve(vec(k), W, vec(linsolve_tmp), !repeat_step)
    @.. k = -k
    @.. u_temp1 = u_temp2 + k # Euler starting step
    for j in 2:j_int
      f(k, cache.u_temp1, p, t + (j - 1) * dt_int)
      @.. linsolve_tmp = dt_int*k - (u_temp1 - u_temp2)
      cache.linsolve(vec(k), W, vec(linsolve_tmp), !repeat_step)
      @.. k = -k
      @.. T[i+1] = 2*u_temp1 - u_temp2 + 2*k # Explicit Midpoint rule
      @.. u_temp2 = u_temp1
      @.. u_temp1 = T[i+1]
    end
  end

  if integrator.opts.adaptive
    # Compute all information relating to an extrapolation order ≦ win_min
    for i = win_min - 1 : win_min

      #integrator.u .= extrapolation_scalars[i+1] * sum( broadcast(*, cache.T[1:(i+1)], extrapolation_weights[1:(i+1), (i+1)]) ) # Approximation of extrapolation order i
      #cache.utilde .= extrapolation_scalars_2[i] * sum( broadcast(*, cache.T[2:(i+1)], extrapolation_weights_2[1:i, i]) ) # and its internal counterpart

      u_temp1 .= false
      u_temp2 .= false
      for j in 1:(i+1)
        @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (i+1)]
      end
      for j in 2:i+1
        @.. u_temp2 += cache.T[j] * extrapolation_weights_2[j-1, i]
      end
      @.. integrator.u = extrapolation_scalars[i+1] * u_temp1
      @.. cache.utilde  = extrapolation_scalars_2[i] * u_temp2

      calculate_residuals!(cache.res, integrator.u, cache.utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
      integrator.EEst = integrator.opts.internalnorm(cache.res, t)
      cache.n_curr = i # Update chache's n_curr for stepsize_controller_internal!
      stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
    end

    # Check if an approximation of some order in the order window can be accepted
    # Make sure a stepsize scaling factor of order (integrator.alg.n_min + 1) is provided for the step_*_controller!
    while n_curr <= win_max
      if integrator.EEst <= 1.0
        # Accept current approximation u of order n_curr
        break
    elseif (n_curr < integrator.alg.n_min + 1) || integrator.EEst <= typeof(integrator.EEst)(prod(subdividing_sequence[n_curr+2:win_max+1] .// subdividing_sequence[1]^2))
        # Reject current approximation order but pass convergence monitor
        # Compute approximation of order (n_curr + 1)
        n_curr = n_curr + 1
        cache.n_curr = n_curr

        # Update cache.T
        j_int = 4 * subdividing_sequence[n_curr + 1]
        dt_int = dt / j_int # Stepsize of the new internal discretisation
        @.. u_temp2 = uprev
        @.. u_temp1 = u_temp2 + dt_int * fsalfirst # Euler starting step
        for j in 2:j_int
          f(k, cache.u_temp1, p, t + (j-1) * dt_int)
          @.. T[n_curr+1] = u_temp2 + 2 * dt_int * k
          @.. u_temp2 = u_temp1
          @.. u_temp1 = T[n_curr+1]
        end

        # Update u, integrator.EEst and cache.Q
        #integrator.u .= extrapolation_scalars[n_curr+1] * sum( broadcast(*, cache.T[1:(n_curr+1)], extrapolation_weights[1:(n_curr+1), (n_curr+1)]) ) # Approximation of extrapolation order n_curr
        #cache.utilde .= extrapolation_scalars_2[n_curr] * sum( broadcast(*, cache.T[2:(n_curr+1)], extrapolation_weights_2[1:n_curr, n_curr]) ) # and its internal counterpart

        u_temp1 .= false
        u_temp2 .= false
        for j in 1:n_curr+1
          @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (n_curr+1)]
        end
        for j in 2:n_curr+1
          @.. u_temp2 += cache.T[j] * extrapolation_weights_2[j-1, n_curr]
        end
        @.. integrator.u = extrapolation_scalars[n_curr+1] * u_temp1
        @.. cache.utilde  = extrapolation_scalars_2[n_curr]* u_temp2

        calculate_residuals!(cache.res, integrator.u, cache.utilde, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm, t)
        integrator.EEst = integrator.opts.internalnorm(cache.res, t)
        stepsize_controller_internal!(integrator, integrator.alg) # Update cache.Q
      else
          # Reject the current approximation and not pass convergence monitor
          break
      end
    end
  else

    #integrator.u .= extrapolation_scalars[n_curr+1] * sum( broadcast(*, cache.T[1:(n_curr+1)], extrapolation_weights[1:(n_curr+1), (n_curr+1)]) ) # Approximation of extrapolation order n_curr
    u_temp1 .= false
    for j in 1:n_curr+1
      @.. u_temp1 += cache.T[j] * extrapolation_weights[j, (n_curr+1)]
    end
    @.. integrator.u = extrapolation_scalars[n_curr+1] * u_temp1

  end

  f(cache.k, integrator.u, p, t+dt) # Update FSAL
end
