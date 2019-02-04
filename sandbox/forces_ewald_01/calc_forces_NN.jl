using SpecialFunctions: erfc

function calc_forces_NN( atoms::Atoms )
    return calc_forces_NN( atoms.LatVecs, atoms, atoms.Zvals )
end

function calc_forces_NN( atoms::Atoms, Zvals::Array{Float64,1} )
    return calc_forces_NN( atoms.LatVecs, atoms, Zvals )
end

function calc_forces_NN( pw::PWGrid, atoms::Atoms, Zvals::Array{Float64,1} )
    return calc_forces_NN( pw.LatVecs, atoms, Zvals )
end

function Herfc(x)
    return -2*exp(-x^2)/sqrt(pi) - erfc(x)/x
end

function calc_forces_NN(
    LatVecs::Array{Float64,2},
    atoms::Atoms,
    Zvals::Array{Float64,1}
)

    t1 = LatVecs[:,1]
    t2 = LatVecs[:,2]
    t3 = LatVecs[:,3]
  
    Ω = abs(det(LatVecs))

    RecVecs = 2*pi*inv(LatVecs')
    g1 = RecVecs[:,1]
    g2 = RecVecs[:,2]
    g3 = RecVecs[:,3]

    t1m = sqrt(dot(t1,t1))
    t2m = sqrt(dot(t2,t2))
    t3m = sqrt(dot(t3,t3))

    g1m = sqrt(dot(g1,g1))
    g2m = sqrt(dot(g2,g2))
    g3m = sqrt(dot(g3,g3))

    Natoms = atoms.Natoms
    atm2species = atoms.atm2species

    # Atomic positions
    tau = atoms.positions

    # Parameters
    gcut = 2.0
    ebsl = 1e-8

    glast2 = gcut*gcut
    gexp = -log(ebsl)    
    η = sqrt(glast2/gexp)/2

    tmax = sqrt(0.5*gexp)/η

    mmm1 = round(Int64, tmax/t1m + 1.5)
    mmm2 = round(Int64, tmax/t2m + 1.5)
    mmm3 = round(Int64, tmax/t3m + 1.5)

    dtau = zeros(Float64,3)
    G = zeros(Float64,3)
    T = zeros(Float64,3)

    F_NN = zeros(3,Natoms)

    F_NN_R = zeros(3,Natoms)
    F_NN_G = zeros(3,Natoms)    

    D = zeros(3)

    for ia = 1:Natoms
    for ja = 1:Natoms
    if ia != ja

        dtau[1] = tau[1,ia] - tau[1,ja]
        dtau[2] = tau[2,ia] - tau[2,ja]
        dtau[3] = tau[3,ia] - tau[3,ja]
        
        isp = atm2species[ia]
        jsp = atm2species[ja]
        ZiZj = Zvals[isp]*Zvals[jsp]

        for i = -mmm1:mmm1
        for j = -mmm2:mmm2
        for k = -mmm3:mmm3
            if (abs(i) + abs(j) + abs(k)) != 0
                T[1] = i*t1[1] + j*t2[1] + k*t3[1]
                T[2] = i*t1[2] + j*t2[2] + k*t3[2]
                T[3] = i*t1[3] + j*t2[3] + k*t3[3]
                D[1] = dtau[1] - T[1]
                D[2] = dtau[2] - T[2]
                D[3] = dtau[3] - T[3]
                D2 = D[1]^2 + D[2]^2 + D[3]^2
                Dmag = sqrt(D2)
                F_NN_R[:,ia] = F_NN_R[:,ia] - η*Herfc(η*Dmag)*D[:]/D2*ZiZj
                #F_NN[:,ia] = F_NN[:,ia] + (2*η/sqrt(pi)*exp(-η^2*D2) +
                #             1/Dmag*erfc(η*Dmag))*D[:]/D2*Zvals[jsp]
            end
        end
        end
        end
    end
    end
    end

    println(F_NN_R)

    mmm1 = round(Int64, gcut/g1m + 1.5)
    mmm2 = round(Int64, gcut/g2m + 1.5)
    mmm3 = round(Int64, gcut/g3m + 1.5)

    for ia = 1:Natoms
    for ja = 1:Natoms
    if ia != ja
        
        isp = atm2species[ia]
        jsp = atm2species[ja]
        ZiZj = Zvals[isp]*Zvals[jsp]
        dtau[1] = tau[1,ia] - tau[1,ja]
        dtau[2] = tau[2,ia] - tau[2,ja]
        dtau[3] = tau[3,ia] - tau[3,ja]

        for i = -mmm1:mmm1
        for j = -mmm2:mmm2
        for k = -mmm3:mmm3
        if ( abs(i) + abs(j) + abs(k) ) != 0
            G[1] = i*g1[1] + j*g2[1] + k*g3[1]
            G[2] = i*g1[2] + j*g2[2] + k*g3[2]
            G[3] = i*g1[3] + j*g2[3] + k*g3[3]        
            G2 = G[1]^2 + G[2]^2 + G[3]^2
            x = 4*pi/Ω * exp(-0.25*G2/η^2)/G2
            #@printf("η = %f\n", η)
            Gtau = G[1]*dtau[1] + G[2]*dtau[2] + G[3]*dtau[3]
            if abs(exp(-0.25*G2/η^2)) > 1e-10
                @printf("%d %d %d\n", i, j, k)
                @printf("exp factor = %18.10f\n", exp(-0.25*G2/η^2))
                @printf("G2 = %18.10f\n", G2)
                @printf("x = %18.10f\n", x)
                @printf("Gtau, sin(Gtau) = %18.10f %18.10f\n", Gtau, sin(Gtau))
            end            
            F_NN_G[:,ia] = F_NN_G[:,ia] + x*sin(Gtau)*G[:]*ZiZj
        end
        end
        end
        end # if
    end
    end
    end

    println(F_NN_G)

    F_NN = F_NN_G + F_NN_R

    #return F_NN*0.5 # Convert to Hartree
    return F_NN    
end
