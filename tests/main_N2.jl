using PWDFT

function test_main( ; method="SCF" )

    #
    # Atoms
    #
    atoms = init_atoms_xyz("N2.xyz")
    println(atoms)


    #
    # Initialize Hamiltonian
    #
    LatVecs = 16.0*diagm( ones(3) )
    ecutwfc_Ry = 40.0
    pspfiles = ["../pseudopotentials/pade_gth/N-q5.gth"]
    Ham = PWHamiltonian( atoms, pspfiles, ecutwfc_Ry, LatVecs )

    @printf("\nsum V Ps loc = %18.10f\n", sum(Ham.potentials.Ps_loc))

    #
    # calculate E_NN
    #
    strf = calc_strfact( atoms, Ham.pw )
    Zvals = get_Zvals( Ham.pspots )
    Ham.energies.NN = calc_E_NN( Ham.pw, strf, atoms.positions, atoms.Nspecies, atoms.atm2species, Zvals )

    if method == "SCF"
        λ, v = KS_solve_SCF!( Ham, β=0.2 )
        println("\nAfter calling KS_solve_SCF:")
    elseif method == "Emin"
        λ, v = KS_solve_Emin_PCG!( Ham )
        println("\nAfter calling KS_solve_Emin_PCG:")
    else
        println("ERROR: unknow method = ", method)
    end

    Nstates = Ham.electrons.Nstates
    println("\nEigenvalues")
    for ist = 1:Nstates
        @printf("%8d  %18.10f = %18.10f eV\n", ist, λ[ist], λ[ist]*Ry2eV*2)
    end
    println("\nTotal energy components")
    println(Ham.energies)

end

@time test_main(method="Emin")
#@time test_main(method="SCF")
