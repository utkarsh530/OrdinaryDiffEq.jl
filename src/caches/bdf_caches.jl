@cache mutable struct ABDF2ConstantCache{N,dtType,rate_prototype} <: OrdinaryDiffEqConstantCache
  nlsolver::N
  eulercache::ImplicitEulerConstantCache
  dtₙ₋₁::dtType
  fsalfirstprev::rate_prototype
end

function alg_cache(alg::ABDF2,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,
                   uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false})
  γ, c = 2//3, 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(false))
  eulercache = ImplicitEulerConstantCache(nlsolver)

  dtₙ₋₁ = one(dt)
  fsalfirstprev = rate_prototype

  ABDF2ConstantCache(nlsolver, eulercache, dtₙ₋₁, fsalfirstprev)
end

@cache mutable struct ABDF2Cache{uType,rateType,uNoUnitsType,N,dtType} <: OrdinaryDiffEqMutableCache
  uₙ::uType
  uₙ₋₁::uType
  uₙ₋₂::uType
  fsalfirst::rateType
  fsalfirstprev::rateType
  zₙ₋₁::uType
  atmp::uNoUnitsType
  nlsolver::N
  eulercache::ImplicitEulerCache
  dtₙ₋₁::dtType
end

function alg_cache(alg::ABDF2,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,
                   tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  γ, c = 2//3, 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(true))
  fsalfirst = zero(rate_prototype)

  fsalfirstprev = zero(rate_prototype)
  atmp = similar(u,uEltypeNoUnits)

  eulercache = ImplicitEulerCache(u,uprev,uprev2,fsalfirst,atmp,nlsolver)

  dtₙ₋₁ = one(dt)
  zₙ₋₁ = zero(u)

  ABDF2Cache(u,uprev,uprev2,fsalfirst,fsalfirstprev,zₙ₋₁,atmp,
              nlsolver,eulercache,dtₙ₋₁)
end

# SBDF

@cache mutable struct SBDFConstantCache{rateType,N,uType} <: OrdinaryDiffEqConstantCache
  cnt::Int
  k2::rateType
  nlsolver::N
  uprev2::uType
  uprev4::uType
  uprev3::uType
  k₁::rateType
  k₂::rateType
  k₃::rateType
  du₁::rateType
  du₂::rateType
end

@cache mutable struct SBDFCache{uType,rateType,N} <: OrdinaryDiffEqMutableCache
  cnt::Int
  u::uType
  uprev::uType
  fsalfirst::rateType
  nlsolver::N
  uprev2::uType
  uprev3::uType
  uprev4::uType
  k₁::rateType
  k₂::rateType
  k₃::rateType
  du₁::rateType
  du₂::rateType
end

function alg_cache(alg::SBDF,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false})
  γ, c = 1//1, 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(false))

  k2 = rate_prototype
  k₁ = rate_prototype; k₂ = rate_prototype; k₃ = rate_prototype
  du₁ = rate_prototype; du₂ = rate_prototype

  uprev2 = u; uprev3 = u; uprev4 = u

  SBDFConstantCache(1,k2,nlsolver,uprev2,uprev3,uprev4,k₁,k₂,k₃,du₁,du₂)
end

function alg_cache(alg::SBDF,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  γ, c = 1//1, 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(true))
  fsalfirst = zero(rate_prototype)

  order = alg.order

  k₁ = zero(rate_prototype)
  k₂ = order >= 3 ? zero(rate_prototype) : k₁
  k₃ = order == 4 ? zero(rate_prototype) : k₁
  du₁ = zero(rate_prototype)
  du₂ = zero(rate_prototype)

  uprev2 = zero(u)
  uprev3 = order >= 3 ? zero(u) : uprev2
  uprev4 = order == 4 ? zero(u) : uprev2

  SBDFCache(1,u,uprev,fsalfirst,nlsolver,uprev2,uprev3,uprev4,k₁,k₂,k₃,du₁,du₂)
end

# QNDF1

@cache mutable struct QNDF1ConstantCache{N,coefType,coefType1,dtType,uType} <: OrdinaryDiffEqConstantCache
  nlsolver::N
  D::coefType
  D2::coefType1
  R::coefType
  U::coefType
  uprev2::uType
  dtₙ₋₁::dtType
end

@cache mutable struct QNDF1Cache{uType,rateType,coefType,coefType1,coefType2,uNoUnitsType,N,dtType} <: OrdinaryDiffEqMutableCache
  uprev2::uType
  fsalfirst::rateType
  D::coefType1
  D2::coefType2
  R::coefType
  U::coefType
  atmp::uNoUnitsType
  utilde::uType
  nlsolver::N
  dtₙ₋₁::dtType
end

function alg_cache(alg::QNDF1,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false})
  γ, c = zero(inv((1-alg.kappa))), 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(false))

  uprev2 = u
  dtₙ₋₁ = t

  D = fill(zero(u), 1, 1)
  D2 = fill(zero(u), 1, 2)
  R = fill(zero(t), 1, 1)
  U = fill(zero(t), 1, 1)

  U!(1,U)

  QNDF1ConstantCache(nlsolver,D,D2,R,U,uprev2,dtₙ₋₁)
end

function alg_cache(alg::QNDF1,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  γ, c = zero(inv((1-alg.kappa))), 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(true))
  fsalfirst = zero(rate_prototype)

  D = Array{typeof(u)}(undef, 1, 1)
  D2 = Array{typeof(u)}(undef, 1, 2)
  R = fill(zero(t), 1, 1)
  U = fill(zero(t), 1, 1)

  D[1] = similar(u)
  D2[1] = similar(u); D2[2] = similar(u)

  U!(1,U)

  atmp = similar(u,uEltypeNoUnits)
  utilde = similar(u)
  uprev2 = zero(u)
  dtₙ₋₁ = one(dt)

  QNDF1Cache(uprev2,fsalfirst,D,D2,R,U,atmp,utilde,nlsolver,dtₙ₋₁)
end

# QNDF2

@cache mutable struct QNDF2ConstantCache{N,coefType,coefType1,uType,dtType} <: OrdinaryDiffEqConstantCache
  nlsolver::N
  D::coefType
  D2::coefType
  R::coefType1
  U::coefType1
  uprev2::uType
  uprev3::uType
  dtₙ₋₁::dtType
  dtₙ₋₂::dtType
end

@cache mutable struct QNDF2Cache{uType,rateType,coefType,coefType1,coefType2,uNoUnitsType,N,dtType} <: OrdinaryDiffEqMutableCache
  uprev2::uType
  uprev3::uType
  fsalfirst::rateType
  D::coefType1
  D2::coefType2
  R::coefType
  U::coefType
  atmp::uNoUnitsType
  utilde::uType
  nlsolver::N
  dtₙ₋₁::dtType
  dtₙ₋₂::dtType
end

function alg_cache(alg::QNDF2,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false})
  γ, c = zero(inv((1-alg.kappa))), 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(false))

  uprev2 = u
  uprev3 = u
  dtₙ₋₁ = zero(t)
  dtₙ₋₂ = zero(t)

  D = fill(zero(u), 1, 2)
  D2 = fill(zero(u), 1, 3)
  R = fill(zero(t), 2, 2)
  U = fill(zero(t), 2, 2)

  U!(2,U)

  QNDF2ConstantCache(nlsolver,D,D2,R,U,uprev2,uprev3,dtₙ₋₁,dtₙ₋₂)
end

function alg_cache(alg::QNDF2,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  γ, c = zero(inv((1-alg.kappa))), 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(true))
  fsalfirst = zero(rate_prototype)

  D = Array{typeof(u)}(undef, 1, 2)
  D2 = Array{typeof(u)}(undef, 1, 3)
  R = fill(zero(t), 2, 2)
  U = fill(zero(t), 2, 2)

  D[1] = similar(u); D[2] = similar(u)
  D2[1] = similar(u);  D2[2] = similar(u); D2[3] = similar(u)

  U!(2,U)

  atmp = similar(u,uEltypeNoUnits)
  utilde = similar(u)
  uprev2 = zero(u)
  uprev3 = zero(u)
  dtₙ₋₁ = zero(dt)
  dtₙ₋₂ = zero(dt)

  QNDF2Cache(uprev2,uprev3,fsalfirst,D,D2,R,U,atmp,utilde,nlsolver,dtₙ₋₁,dtₙ₋₂)
end

@cache mutable struct QNDFConstantCache{N,coefType1,coefType2,coefType3,uType,dtType,dtsType} <: OrdinaryDiffEqConstantCache
  nlsolver::N
  D::coefType3
  D2::coefType2
  R::coefType1
  U::coefType1
  order::Int
  max_order::Int
  udiff::uType
  dts::dtsType
  h::dtType
  c::Int
end

@cache mutable struct QNDFCache{uType,rateType,coefType1,coefType,coefType2,coefType3,dtType,dtsType,uNoUnitsType,N} <: OrdinaryDiffEqMutableCache
  fsalfirst::rateType
  D::coefType3
  D2::coefType2
  R::coefType1
  U::coefType1
  order::Int
  max_order::Int
  udiff::coefType
  dts::dtsType
  atmp::uNoUnitsType
  utilde::uType
  nlsolver::N
  h::dtType
  c::Int
end

function alg_cache(alg::QNDF,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false})
  γ, c = one(eltype(alg.kappa)), 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(false))

  udiff = fill(zero(u), 1, 6)
  dts = fill(zero(dt), 1, 6)
  h = zero(dt)

  D = fill(zero(u), 1, 5)
  D2 = fill(zero(u), 6, 6)
  R = fill(zero(t), 5, 5)
  U = fill(zero(t), 5, 5)

  max_order = 5

  QNDFConstantCache(nlsolver,D,D2,R,U,1,max_order,udiff,dts,h,0)
end

function alg_cache(alg::QNDF,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  γ, c = one(eltype(alg.kappa)), 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(true))
  fsalfirst = zero(rate_prototype)

  udiff = Array{typeof(u)}(undef, 1, 6)
  dts = fill(zero(dt), 1, 6)
  h = zero(dt)

  D = Array{typeof(u)}(undef, 1, 5)
  D2 = Array{typeof(u)}(undef, 6, 6)
  R = fill(zero(t), 5, 5)
  U = fill(zero(t), 5, 5)

  for i = 1:5
    D[i] = zero(u)
    udiff[i] = zero(u)
  end
  udiff[6] = zero(u)

  for i = 1:6, j = 1:6
      D2[i,j] = zero(u)
  end

  max_order = 5
  atmp = similar(u,uEltypeNoUnits)
  utilde = nlsolver.tmp

  QNDFCache(fsalfirst,D,D2,R,U,1,max_order,udiff,dts,atmp,utilde,nlsolver,h,0)
end


@cache mutable struct MEBDF2Cache{uType,rateType,uNoUnitsType,N} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  uprev2::uType
  fsalfirst::rateType
  z₁::uType
  z₂::uType
  tmp2::uType
  atmp::uNoUnitsType
  nlsolver::N
end

function alg_cache(alg::MEBDF2,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,
                   tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  γ, c = 1, 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(true))
  fsalfirst = zero(rate_prototype)

  z₁ = zero(u); z₂ = zero(u); z₃ = zero(u); tmp2 = zero(u)
  atmp = similar(u,uEltypeNoUnits)

  MEBDF2Cache(u,uprev,uprev2,fsalfirst,z₁,z₂,tmp2,atmp,nlsolver)
end

mutable struct MEBDF2ConstantCache{N} <: OrdinaryDiffEqConstantCache
  nlsolver::N
end

function alg_cache(alg::MEBDF2,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,
                   tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false})
  γ, c = 1, 1
  nlsolver = build_nlsolver(alg,u,uprev,p,t,dt,f,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,γ,c,Val(false))
  MEBDF2ConstantCache(nlsolver)
end
