import Base: println
function println( energies::Energies; use_smearing=false )

    @printf("Kinetic    energy: %18.10f\n", energies.Kinetic )
    @printf("Ps_loc     energy: %18.10f\n", energies.Ps_loc )
    @printf("Ps_nloc    energy: %18.10f\n", energies.Ps_nloc )
    @printf("Hartree    energy: %18.10f\n", energies.Hartree )
    @printf("XC         energy: %18.10f\n", energies.XC )
    @printf("PspCore    energy: %18.10f\n", energies.PspCore )

    if ( abs(energies.mTS) > eps() ) || use_smearing
        @printf("-TS              : %18.10f\n", energies.mTS)
    end

    @printf("-------------------------------------\n")
    
    E_elec = energies.Kinetic + energies.Ps_loc + energies.Ps_nloc +
             energies.Hartree + energies.XC + energies.PspCore + energies.mTS
    
    @printf("Electronic energy: %18.10f\n", E_elec)
    @printf("NN         energy: %18.10f\n", energies.NN )
    @printf("-------------------------------------\n")
    
    E_total = E_elec + energies.NN
    
    if use_smearing
        @printf("Total free energy: %18.10f\n", E_total)
        @printf("\n")
        @printf("Total energy (extrapolated to T=0): %18.10f\n", E_total - 0.5*energies.mTS)
    else
        @printf("Total      energy: %18.10f\n", E_total )
    end
end