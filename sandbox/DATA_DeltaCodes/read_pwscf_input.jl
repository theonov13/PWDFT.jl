# parse cif2cell generated PWSCF input file
function read_pwscf_input( filename::String )

    # Default values, some are not valid for PWSCF
    acell = -1.0

    Natoms = 0

    LatVecs = zeros(3,3)
    is_parse_cell = false
    N_parse_cell = 0

    xyz_string_frac = ""
    is_parse_xyz = false
    N_parse_xyz = 0

    is_parse_kpoints = false
    N_parse_kpoints = 0
    meshk = [0, 0, 0]

    f = open(filename, "r")
    
    while !eof(f)
        
        l = readline(f)
        
        if occursin("  A =", l)
            ll = split(l, "=")
            acell = parse(Float64,ll[end])*ANG2BOHR
        end

        if occursin("nat =", l)
            ll = split(l, "=", keepempty=false)
            Natoms = parse(Int64, ll[end])
            xyz_string_frac = xyz_string_frac*string(Natoms)*"\n\n"
        end

        if occursin("CELL_PARAMETERS", l)
            is_parse_cell = true
        end

        if is_parse_cell && N_parse_cell <= 3
            if N_parse_cell == 0
                N_parse_cell = N_parse_cell + 1
                continue
            end
            ll = split(l, " ", keepempty=false)
            LatVecs[1,N_parse_cell] = parse(Float64, ll[1])
            LatVecs[2,N_parse_cell] = parse(Float64, ll[2])
            LatVecs[3,N_parse_cell] = parse(Float64, ll[3])
            N_parse_cell = N_parse_cell + 1
        end


        if occursin("ATOMIC_POSITIONS", l)
            is_parse_xyz = true
        end

        if is_parse_xyz && N_parse_xyz <= Natoms
            if N_parse_xyz == 0
                N_parse_xyz = N_parse_xyz + 1
                continue
            end
            xyz_string_frac = xyz_string_frac*l*"\n"
            N_parse_xyz = N_parse_xyz + 1
        end

        if occursin("K_POINTS", l)
            is_parse_kpoints = true
        end

        if is_parse_kpoints && N_parse_kpoints <= 1
            if N_parse_kpoints == 0
                N_parse_kpoints = N_parse_kpoints + 1
                continue
            end
            ll = split(l, " ", keepempty=false)
            meshk[1] = parse(Int64,ll[1])
            meshk[2] = parse(Int64,ll[2])
            meshk[3] = parse(Int64,ll[3])
            N_parse_kpoints = N_parse_kpoints + 1
        end

    end
    close(f)

    LatVecs = acell*LatVecs

    atoms = init_atoms_xyz_string( xyz_string_frac, in_bohr=true )
    atoms.positions = LatVecs*atoms.positions
    atoms.LatVecs = LatVecs

    return atoms, meshk
end

