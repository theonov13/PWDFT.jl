mutable struct ElecVars
    psiks::BlochWavefunc
    Hsub::Array{Matrix{ComplexF64},1}
    Haux_eigs::Array{Float64,2}
end

mutable struct ElecGradient
    psiks::BlochWavefunc
    Haux::Array{Matrix{ComplexF64},1}
end

function ElecGradient(Ham)
    psiks = zeros_BlochWavefunc(Ham)
    Nkspin = length(psiks)
    Nstates = Ham.electrons.Nstates
    Haux = Array{Matrix{ComplexF64},1}(undef,Nkspin)
    for i in 1:Nkspin
        Haux[i] = zeros(ComplexF64,Nstates,Nstates)
    end
    return ElecGradient(psiks, Haux)
end

function ElecVars( Ham::Hamiltonian )
    return ElecVars( Ham, rand_BlochWavefunc(Ham) )
end

function ElecVars( Ham::Hamiltonian, psiks::BlochWavefunc )
    
    Nkspin = length(psiks)
    Nstates = Ham.electrons.Nstates
    Nkpt = Ham.pw.gvecw.kpoints.Nkpt
    Nspin = Ham.electrons.Nspin

    Hsub = Array{Matrix{ComplexF64},1}(undef,Nkspin)
    Haux_eigs = zeros(Float64,Nstates,Nkspin) # the same as electrons.ebands
    
    for ispin in 1:Nspin, ik in 1:Nkpt
        i = ik + (ispin - 1)*Nkpt
        Ham.ik = ik
        Ham.ispin = ispin
        #
        Hsub[i] = zeros(ComplexF64,Nstates,Nstates)
        #
        Hsub[i][:] = psiks[i]' * op_H(Ham, psiks[i])
        #
        Haux_eigs[:,i] = eigvals(Hermitian(Hsub[i]))  # set Haux_eigs to eigenvalues of Hsub
    end

    return ElecVars(psiks, Hsub, Haux_eigs)
end

import Base: show
function show( io::IO, evars::ElecVars )
    Nkspin = length(evars.psiks)
    for i in 1:Nkspin
        println("Haux i = ", i)
        display(evars.Hsub[i]); println()
        println("Haux_eigs i = ", i)
        display( eigvals(Hermitian(evars.Hsub[i])) ); println()
    end
end
show( evars::ElecVars ) = show( stdout, evars )




