abstract type OrdinaryDiffEqCache <: DiffEqBase.DECache end
abstract type OrdinaryDiffEqConstantCache <: OrdinaryDiffEqCache end
abstract type OrdinaryDiffEqMutableCache <: OrdinaryDiffEqCache end
struct ODEEmptyCache <: OrdinaryDiffEqConstantCache end
struct ODEChunkCache{CS} <: OrdinaryDiffEqConstantCache end

mutable struct CompositeCache{T,F} <: OrdinaryDiffEqCache
  caches::T
  choice_function::F
  current::Int
end

function alg_cache(alg::CompositeAlgorithm,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false})
  caches = map(alg.algs) do x
    alg_cache(x,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,Val(false))
  end
  CompositeCache(caches,alg.choice_function,1)
end

function alg_cache(alg::CompositeAlgorithm,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  caches = map(alg.algs) do x
    alg_cache(x,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,Val(true))
  end
  CompositeCache(caches,alg.choice_function,1)
end

alg_cache(alg::OrdinaryDiffEqAlgorithm,prob,callback::F) where {F} = ODEEmptyCache()

@cache struct FunctionMapCache{uType,rateType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::rateType
end

function alg_cache(alg::FunctionMap,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  FunctionMapCache(u,uprev,FunctionMap_scale_by_time(alg) ? rate_prototype : similar(u))
end

struct FunctionMapConstantCache <: OrdinaryDiffEqConstantCache end

alg_cache(alg::FunctionMap,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = FunctionMapConstantCache()

@cache struct ExplicitRKCache{uType,rateType,uNoUnitsType,TabType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  utilde::rateType
  atmp::uNoUnitsType
  fsalfirst::rateType
  fsallast::rateType
  kk::Vector{rateType}
  tab::TabType
end

function alg_cache(alg::ExplicitRK,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  kk = Vector{typeof(rate_prototype)}(undef, 0)
  for i = 1:alg.tableau.stages
    push!(kk,zero(rate_prototype))
  end
  fsalfirst = kk[1]
  if isfsal(alg.tableau)
    fsallast = kk[end]
  else
    fsallast = zero(rate_prototype)
  end
  utilde = zero(rate_prototype)
  tmp = similar(u)
  atmp = similar(u,uEltypeNoUnits)
  tab = ExplicitRKConstantCache(alg.tableau,rate_prototype)
  ExplicitRKCache(u,uprev,tmp,utilde,atmp,fsalfirst,fsallast,kk,tab)
end

struct ExplicitRKConstantCache{MType,VType,KType} <: OrdinaryDiffEqConstantCache
  A::MType
  c::VType
  α::VType
  αEEst::VType
  stages::Int
  kk::KType
end

function ExplicitRKConstantCache(tableau,rate_prototype)
  @unpack A,c,α,αEEst,stages = tableau
  A = A' # Transpose A to column major looping
  kk = Array{typeof(rate_prototype)}(undef, stages) # Not ks since that's for integrator.opts.dense
  ExplicitRKConstantCache(A,c,α,αEEst,stages,kk)
end

alg_cache(alg::ExplicitRK,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = ExplicitRKConstantCache(alg.tableau,rate_prototype)

get_chunksize(cache::DiffEqBase.DECache) = error("This cache does not have a chunksize.")
get_chunksize(cache::ODEChunkCache{CS}) where {CS} = CS
