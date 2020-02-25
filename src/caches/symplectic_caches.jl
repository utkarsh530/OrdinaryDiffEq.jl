@cache struct SymplecticEulerCache{uType,rateType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
end

function alg_cache(alg::SymplecticEuler,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  SymplecticEulerCache(u,uprev,similar(u),zero(rate_prototype),zero(rate_prototype))
end

struct SymplecticEulerConstantCache <: OrdinaryDiffEqConstantCache end

alg_cache(alg::SymplecticEuler,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = SymplecticEulerConstantCache()

@cache struct VelocityVerletCache{uType,rateType,uEltypeNoUnits} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  half::uEltypeNoUnits
end

struct VelocityVerletConstantCache{uEltypeNoUnits} <: OrdinaryDiffEqConstantCache
    half::uEltypeNoUnits
end

function alg_cache(alg::VelocityVerlet,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = zero(rate_prototype)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  half = uEltypeNoUnits(1//2)
  VelocityVerletCache(u,uprev,k,tmp,fsalfirst,half)
end

alg_cache(alg::VelocityVerlet,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = VelocityVerletConstantCache(uEltypeNoUnits(1//2))

@cache struct Symplectic2Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::VerletLeapfrog,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = VerletLeapfrogConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic2Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::VerletLeapfrog,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) =
      VerletLeapfrogConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

function alg_cache(alg::PseudoVerletLeapfrog,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = PseudoVerletLeapfrogConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic2Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::PseudoVerletLeapfrog,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) =
PseudoVerletLeapfrogConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

function alg_cache(alg::McAte2,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = McAte2ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic2Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::McAte2,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) =
McAte2ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

@cache struct Symplectic3Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::Ruth3,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = Ruth3ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic3Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::Ruth3,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) =
Ruth3ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

function alg_cache(alg::McAte3,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = McAte3ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic3Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::McAte3,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) =
McAte3ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

@cache struct Symplectic4Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::McAte4,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = McAte4ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic4Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::McAte4,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = McAte4ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

function alg_cache(alg::CandyRoz4,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = CandyRoz4ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic4Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::CandyRoz4,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = McAte4ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

@cache struct Symplectic45Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::CalvoSanz4,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = CalvoSanz4ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic45Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::CalvoSanz4,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = CalvoSanz4ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

function alg_cache(alg::McAte42,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = McAte42ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic45Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::McAte42,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = McAte42ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

@cache struct Symplectic5Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::McAte5,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = McAte5ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic5Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::McAte5,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = McAte5ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

@cache struct Symplectic6Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::Yoshida6,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = Yoshida6ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic6Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::Yoshida6,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = Yoshida6ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

@cache struct Symplectic62Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::KahanLi6,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = KahanLi6ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  Symplectic62Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::KahanLi6,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = KahanLi6ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

@cache struct McAte8Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::McAte8,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = McAte8ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  McAte8Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::McAte8,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = McAte8ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

@cache struct KahanLi8Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::KahanLi8,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = KahanLi8ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  KahanLi8Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::KahanLi8,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = KahanLi8ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))

@cache struct SofSpa10Cache{uType,rateType,tableauType} <: OrdinaryDiffEqMutableCache
  u::uType
  uprev::uType
  tmp::uType
  k::rateType
  fsalfirst::rateType
  tab::tableauType
end

function alg_cache(alg::SofSpa10,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true})
  tmp = similar(u)
  k = zero(rate_prototype)
  fsalfirst = zero(rate_prototype)
  tab = SofSpa10ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
  SofSpa10Cache(u,uprev,k,tmp,fsalfirst,tab)
end

alg_cache(alg::SofSpa10,u,rate_prototype,uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits,uprev,uprev2,f,t,dt,reltol,p,calck,::Val{false}) = SofSpa10ConstantCache(constvalue(uBottomEltypeNoUnits),constvalue(tTypeNoUnits))
