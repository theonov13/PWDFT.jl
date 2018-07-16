function KS_solve_TRDCM!( Ham::Hamiltonian;
                          NiterMax = 100, startingwfc=nothing,
                          savewfc=false, ETOT_CONV_THR=1e-6 )


	pw = Ham.pw
    Ngw = pw.gvecw.Ngw
    Ns = pw.Ns
    Npoints = prod(Ns)
    ΔV = pw.Ω/Npoints
    Focc = Ham.electrons.Focc
    Nstates = Ham.electrons.Nstates
    Nocc = Ham.electrons.Nstates_occ
    Nkpt = Ham.pw.gvecw.kpoints.Nkpt
    Nspin = Ham.electrons.Nspin

    Nkspin = Nkpt*Nspin

    psiks = Array{Array{ComplexF64,2},1}(undef,Nkspin)

    #
    # Initial wave function
    #
    if startingwfc == nothing
        srand(1234)
        for ispin = 1:Nspin
        for ik = 1:Nkpt
            ikspin = ik + (ispin - 1)*Nkpt
            psiks[ikspin] = ortho_gram_schmidt( rand(ComplexF64,Ngw[ik],Nstates) )
        end
        end
    else
        psiks = startingwfc
    end

    #
    # Calculated electron density from this wave function and update Hamiltonian
    #
    Rhoe = zeros(Float64,Npoints,Nspin)
    for ispin = 1:Nspin
        idxset = (Nkpt*(ispin-1)+1):(Nkpt*ispin)
        Rhoe[:,ispin] = calc_rhoe( pw, Focc[:,idxset], psiks[idxset] )
    end
    update!(Ham, Rhoe)

    evals = zeros(Float64,Nstates,Nkspin)
    
    # Starting eigenvalues and psi
    for ispin = 1:Nspin
    for ik = 1:Nkpt
        Ham.ik = ik
        Ham.ispin = ispin
        ikspin = ik + (ispin - 1)*Nkpt
        evals[:,ikspin], psiks[ikspin] =
        diag_lobpcg( Ham, psiks[ikspin], verbose_last=false, NiterMax=10 )
    end
    end

    Ham.energies = calc_energies( Ham, psiks )
    
    Etot = Ham.energies.Total
    Etot_old = Etot

    # subspace
    Y = Array{Array{ComplexF64,2},1}(undef,Nkspin)
    R = Array{Array{ComplexF64,2},1}(undef,Nkspin)
    P = Array{Array{ComplexF64,2},1}(undef,Nkspin)
    G = Array{Array{ComplexF64,2},1}(undef,Nkspin)
    T = Array{Array{Float64,2},1}(undef,Nkspin)
    B = Array{Array{Float64,2},1}(undef,Nkspin)
    A = Array{Array{Float64,2},1}(undef,Nkspin)
    C = Array{Array{Float64,2},1}(undef,Nkspin)
    for ispin = 1:Nspin
    for ik = 1:Nkpt
        ikspin = ik + (ispin - 1)*Nkpt
        Y[ikspin] = zeros( ComplexF64, Ngw[ik], 3*Nstates )
        R[ikspin] = zeros( ComplexF64, Ngw[ik], Nstates )
        P[ikspin] = zeros( ComplexF64, Ngw[ik], Nstates )
        G[ikspin] = zeros( ComplexF64, 3*Nstates, 3*Nstates )
        T[ikspin] = zeros( Float64, 3*Nstates, 3*Nstates )
        B[ikspin] = zeros( Float64, 3*Nstates, 3*Nstates )
        A[ikspin] = zeros( Float64, 3*Nstates, 3*Nstates )
        C[ikspin] = zeros( Float64, 3*Nstates, 3*Nstates )
    end
    end

    D = zeros(Float64,3*Nstates,Nkspin)  # array for saving eigenvalues of subspace problem

    #XXX use plain 3d-array for G, T, and B ?

    set1 = 1:Nstates
    set2 = Nstates+1:2*Nstates
    set3 = 2*Nstates+1:3*Nstates
    set4 = Nstates+1:3*Nstates
    set5 = 1:2*Nstates

    MaxInnerSCF = 3
    MAXTRY = 10
    FUDGE = 1e-12
    SMALL = 1e-12

    sigma = zeros(Float64,Nkspin)
    gapmax = zeros(Float64,Nkspin)

    for iter = 1:NiterMax
        
        for ispin = 1:Nspin
        for ik = 1:Nkpt
            Ham.ik = ik
            Ham.ispin = ispin
            ikspin = ik + (ispin - 1)*Nkpt
            #
            Hpsi = op_H( Ham, psiks[ikspin] )
            #
            psiHpsi = psiks[ikspin]' * Hpsi
            psiHpsi = 0.5*( psiHpsi + psiHpsi' )
            # Calculate residual
            R[ikspin] = Hpsi - psiks[ikspin]*psiHpsi
            R[ikspin] = Kprec( ik, pw, R[ikspin] )
            # Construct subspace
            Y[ikspin][:,set1] = psiks[ikspin]
            Y[ikspin][:,set2] = R[ikspin]
            #
            if iter > 1
                Y[ikspin][:,set3] = P[ikspin]
            end
            
            #
            # Project kinetic and ionic potential
            #
            if iter > 1
                KY = op_K( Ham, Y[ikspin] ) + op_V_Ps_loc( Ham, Y[ikspin] )
                T[ikspin] = real(Y[ikspin]'*KY)
                B[ikspin] = real(Y[ikspin]'*Y[ikspin])
                B[ikspin] = 0.5*( B[ikspin] + B[ikspin]' )
            else
                # only set5=1:2*Nstates is active for iter=1
                KY = op_K( Ham, Y[ikspin][:,set5] ) + op_V_Ps_loc( Ham, Y[ikspin][:,set5] )
                T[ikspin][set5,set5] = real(Y[ikspin][:,set5]'*KY)
                bb = real(Y[ikspin][set5,set5]'*Y[ikspin][set5,set5])
                B[ikspin][set5,set5] = 0.5*( bb + bb' )
            end

            if iter > 1
                G[ikspin] = Matrix(1.0I, 3*Nstates, 3*Nstates) #eye(3*Nstates)
            else
                G[ikspin][set5,set5] = Matrix(1.0I, 2*Nstates, 2*Nstates)
            end
        end
        end
        
        @printf("DCM iter: %3d\n", iter)

        sigma[:] .= 0.0  # reset sigma to zero at the beginning of inner SCF iteration
        numtry = 0
        Etot0 = Ham.energies.Total

        println("Etot0 = ", Etot0)

        for iterscf = 1:MaxInnerSCF
            
            for ispin = 1:Nspin
            for ik = 1:Nkpt
                #
                Ham.ik = ik
                Ham.ispin = ispin
                ikspin = ik + (ispin - 1)*Nkpt
                #
                # Project Hartree, XC potential, and nonlocal pspot if any
                #
                V_loc = Ham.potentials.Hartree + Ham.potentials.XC[:,ispin]
                #
                if iter > 1
                    yy = Y[ikspin]
                else
                    yy = Y[ikspin][:,set5]
                end
                # 
                if Ham.pspotNL.NbetaNL > 0
                    VY = op_V_Ps_nloc( Ham, yy ) + op_V_loc( ik, pw, V_loc, yy )
                else
                    VY = op_V_loc( ik, pw, V_loc, yy )
                end
                #
                if iter > 1
                    A[ikspin] = real( T[ikspin] + yy'*VY )
                    A[ikspin] = 0.5*( A[ikspin] + A[ikspin]' )
                else
                    aa = real( T[ikspin][set5,set5] + yy'*VY )
                    A[ikspin] = 0.5*( aa + aa' )
                end
                #
                if iter > 1
                    BG = B[ikspin]*G[ikspin][:,1:Nocc]
                    C[ikspin] = real( BG*BG' )
                    C[ikspin] = 0.5*( C[ikspin] + C[ikspin]' )
                else
                    BG = B[ikspin][set5,set5]*G[ikspin][set5,1:Nocc]
                    cc = real( BG*BG' )
                    C[ikspin][set5,set5] = 0.5*( cc + cc' )
                end
                #
                # apply trust region if necessary
                if abs(sigma[ikspin]) > SMALL # sigma is not zero
                    println("Trust region is imposed")
                    if iter > 1
                        D[:,ikspin], G[ikspin] = eigen( A[ikspin] - sigma[ikspin]*C[ikspin], B[ikspin] )
                    else
                        D[set5,ikspin], G[ikspin][set5,set5] =
                        eigen( A[ikspin][set5,set5] - sigma[ikspin]*C[ikspin][set5,set5], B[ikspin][set5,set5] )
                    end
                else
                    if iter > 1
                        D[:,ikspin], G[ikspin] = eigen( A[ikspin], B[ikspin] )
                    else
                        D[set5,ikspin], G[ikspin][set5,set5] = eigen( A[ikspin][set5,set5], B[ikspin][set5,set5] )
                    end
                end
                #
                evals[:,ikspin] = D[1:Nstates,ikspin]  # XXX Not needed ?
                #
                # update wavefunction
                if iter > 1
                    psiks[ikspin] = Y[ikspin]*G[ikspin][:,set1]
                    ortho_gram_schmidt!(psiks[ikspin])  # is this necessary ?
                else
                    psiks[ikspin] = Y[ikspin][:,set5]*G[ikspin][set5,set1]
                    ortho_gram_schmidt!(psiks[ikspin])
                end
            end
            end

            for ispin = 1:Nspin
                idxset = (Nkpt*(ispin-1)+1):(Nkpt*ispin)
                Rhoe[:,ispin] = calc_rhoe( pw, Focc[:,idxset], psiks[idxset] )
            end
            update!( Ham, Rhoe )

            # Calculate energies once again
            Ham.energies = calc_energies( Ham, psiks )
            Etot = Ham.energies.Total

            println("Etot = ", Etot)

            if Etot > Etot0

                # Total energy is increased, impose trust region
                # Do this for all kspin

                for ikspin = 1:Nkspin

                    if iter == 1
                        gaps = D[2:2*Nstates,ikspin] - D[1:2*Nstates-1,ikspin]
                        gapmax[ikspin] = maximum(gaps)
                    else
                        gaps = D[2:3*Nstates] - D[1:3*Nstates-1]
                        gapmax[ikspin] = maximum(gaps)
                    end
                    gap0 = D[Nocc+1,ikspin] - D[Nocc,ikspin]

                    @printf("ikspin = %d, gapmax = %f\n", ikspin, gapmax[ikspin])
                    @printf("ikspin = %d, gap0 = %f\n", ikspin, gap0)

                    while (gap0 < 0.9*gapmax[ikspin]) & (numtry < MAXTRY)
                        println("Increase sigma to fix gap0")
                        if abs(sigma[ikspin]) < SMALL # approx for sigma == 0.0
                            # initial value for sigma
                            sigma[ikspin] = 2*gapmax[ikspin]
                        else
                            sigma[ikspin] = 2*sigma[ikspin]
                        end
                        @printf("ikspin = %d, sigma = %f\n", ikspin, sigma[ikspin])
                        #
                        if iter > 1
                            D[:,ikspin], G[ikspin] = eigen( A[ikspin] - sigma[ikspin]*C[ikspin], B[ikspin] )
                            gaps = D[2:2*Nstates,ikspin] - D[1:2*Nstates-1,ikspin]      
                        else
                            D[set5,ikspin], G[ikspin][set5,set5] =
                            eigen( A[ikspin][set5,set5] - sigma[ikspin]*C[ikspin][set5,set5], B[ikspin][set5,set5] )
                            gaps = D[2:3*Nstates] - D[1:3*Nstates-1]
                        end
                        gapmax[ikspin] = maximum(gaps)
                        gap0 = D[Nocc+1,ikspin] - D[Nocc,ikspin]
                    end
                    numtry = numtry + 1
                end # Nkspin

            end # if Etot > Etot0

            println("sigma = ", sigma)

            while (Etot > Etot0) &
                  (abs(Etot-Etot0) > FUDGE*abs(Etot0)) &
                  (numtry < MAXTRY)
                #
                # update wavefunction
                for ikspin = 1:Nkspin
                    if iter > 1
                        psiks[ikspin] = Y[ikspin]*G[ikspin][:,set1]
                        ortho_gram_schmidt!(psiks[ikspin])
                    else
                        psiks[ikspin] = Y[ikspin][:,set5]*G[ikspin][set5,set1]
                        ortho_gram_schmidt!(psiks[ikspin])
                    end
                end
                #
                update!( Ham, Rhoe )    
                # Calculate energies once again
                Ham.energies = calc_energies( Ham, psiks )
                Etot = Ham.energies.Total
                #
                if Etot > Etot0
                    println("Increase sigma part 2")
                    for ikspin = 1:Nkspin
                        if abs(sigma[ikspin]) < SMALL
                            sigma[ikspin] = 2*sigma[ikspin]
                        else
                            sigma[ikspin] = 1.2*gapmax[ikspin]
                        end
                        @printf("ikspin = %d sigma = %f\n", ikspin, sigma[ikspin])
                        if iter > 1
                            D[:,ikspin], G[ikspin] = eigen( A[ikspin] - sigma[ikspin]*C[ikspin], B[ikspin] )
                        else
                            D[set5,ikspin], G[ikspin][set5,set5] = eigen( A[ikspin][set5,set5] - sigma[ikspin]*C[ikspin][set5,set5], B[ikspin][set5,set5] )
                        end
                    end
                end
                numtry = numtry + 1  # outside ikspin loop
            end # while

            Etot0 = Etot
            
        end # end of inner SCF iteration

        # Calculate energies once again
        Ham.energies = calc_energies( Ham, psiks )
        Etot = Ham.energies.Total
        diffE = abs( Etot - Etot_old )
        @printf("DCM: %5d %18.10f %18.10e\n", iter, Etot, diffE)

        if abs(diffE) < ETOT_CONV_THR
            @printf("DCM is converged: iter: %d , diffE = %10.7e\n", iter, diffE)
            break
        end

        Etot_old = Etot

        # No need to update potential, it is already updated in inner SCF loop
        for ispin = 1:Nspin
        for ik = 1:Nkpt
            ikspin = ik + (ispin - 1)*Nkpt
            if iter > 1
                P[ikspin] = Y[ikspin][:,set4]*G[ikspin][set4,set1]
            else
                P[ikspin] = Y[ikspin][:,set2]*G[ikspin][set2,set1]
            end
        end
        end
    end  # end of DCM iteration
    
    Ham.electrons.ebands = evals[:,:]

    if savewfc
        for ikspin = 1:Nkpt*Nspin
            wfc_file = open("WFC_ikspin_"*string(ikspin)*".data","w")
            write( wfc_file, psiks[ikspin] )
            close( wfc_file )
        end
    end

    return
end

