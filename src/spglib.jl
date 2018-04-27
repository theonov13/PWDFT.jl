function gen_kgrid_reduced(
           atoms::Atoms, mesh::Array{Int64,1}, is_shift::Array{Int64,1};
           time_reversal=1)
    
    num_ir, kgrid, mapping =
    spg_get_ir_reciprocal_mesh( atoms, mesh, is_shift, is_time_reversal=time_reversal )

    umap = unique(mapping)

    Nkpt = prod(mesh)

    list_ir_k = []
    for ikk = 1:num_ir
        for ik = 1:Nkpt
            if umap[ikk] == mapping[ik]
                append!( list_ir_k, [kgrid[:,ik]] )
                break
            end
        end
    end

    RecVecs = 2*pi*inv(atoms.LatVecs')

    kred = zeros(Float64,3,num_ir)
    for ik = 1:num_ir
        kred[1,ik] = list_ir_k[ik][1] / mesh[1]
        kred[2,ik] = list_ir_k[ik][2] / mesh[2]
        kred[3,ik] = list_ir_k[ik][3] / mesh[3]
    end
    kred = RecVecs*kred  # convert to cartesian
    
    # prepare for
    kcount = zeros(Int64,num_ir)
    for ik = 1:num_ir
        kcount[ik] = count( i -> ( i == umap[ik] ), mapping )
    end

    # calculate the weights
    wk = kcount[:]/sum(kcount)

    return kred, wk

end


"""
This function try to reduce number of atoms by exploting crystal symmetry.
"""
function reduce_atoms( atoms::Atoms; symprec=1e-5 )

    lattice = copy(atoms.LatVecs)'
    positions = inv(atoms.LatVecs)*copy(atoms.positions) # convert to fractional coordinates

    num_atom = Base.cconvert( Int32, atoms.Natoms )
    types = Base.cconvert(Array{Int32,1}, atoms.atm2species)

    num_primitive_atom =
    ccall( (:spg_find_primitive,SPGLIB_SO_PATH), Int32,
           ( Ptr{Float64}, Ptr{Float64}, Ptr{Int32}, Int32, Float64 ),
           lattice, positions, types, num_atom, symprec )

    # Prepare for reduced Atoms
    Natoms = Base.cconvert( Int64, num_primitive_atom )
    LatVecs = lattice'
    positions = LatVecs*positions[:,1:num_primitive_atom]
    atm2species = Base.cconvert( Array{Int64,1}, types[1:num_primitive_atom] )
    Nspecies = atoms.Nspecies
    SpeciesSymbols = atoms.SpeciesSymbols
    atsymbs = Array{String}(Natoms)
    for ia = 1:Natoms
        isp = atm2species[ia]
        atsymbs[ia] = SpeciesSymbols[isp]
    end
    Zvals = zeros(Nspecies)
    return Atoms( Natoms, Nspecies, positions, atm2species, atsymbs, SpeciesSymbols, LatVecs, Zvals )

end


function spg_find_primitive( atoms::Atoms; symprec=1e-5)

# We need to transpose lattice
# For positions we don't need to transpose it.

    lattice = copy(atoms.LatVecs)'
    positions = inv(atoms.LatVecs)*copy(atoms.positions) # convert to fractional coordinates

    num_atom = Base.cconvert( Int32, atoms.Natoms )
    types = Base.cconvert(Array{Int32,1}, atoms.atm2species)

    num_primitive_atom =
    ccall( (:spg_find_primitive,SPGLIB_SO_PATH), Int32,
           ( Ptr{Float64}, Ptr{Float64}, Ptr{Int32}, Int32, Float64 ),
           lattice, positions, types, num_atom, symprec )

    return Base.cconvert(Int64,num_primitive_atom)

end


function spg_get_ir_reciprocal_mesh(
             atoms::Atoms, mesh::Array{Int64,1}, is_shift::Array{Int64};
             is_time_reversal=1, symprec=1e-5
         )

    lattice = copy(atoms.LatVecs)'
    positions = inv(atoms.LatVecs)*copy(atoms.positions) # convert to fractional coordinates

    cmesh = Base.cconvert( Array{Cint,1}, mesh )
    cis_shift = Base.cconvert( Array{Cint,1}, is_shift )
    ctypes = Base.cconvert( Array{Cint,1}, atoms.atm2species)
    num_atom = Base.cconvert( Cint, atoms.Natoms )
    is_t_rev = Base.cconvert( Cint, is_time_reversal )
    
    # Prepare for output
    Nkpts = prod(mesh)
    kgrid = zeros(Cint,3,Nkpts)
    mapping = zeros(Cint,Nkpts)
    
    num_ir =
    ccall((:spg_get_ir_reciprocal_mesh, SPGLIB_SO_PATH), Cint,
        (Ptr{Cint}, Ptr{Cint}, Ptr{Cint}, Ptr{Cint}, Cint, Ptr{Float64}, Ptr{Float64}, 
        Ptr{Cint}, Cint, Float64),
        kgrid, mapping, cmesh, cis_shift, is_t_rev,
        lattice, positions, ctypes, num_atom, symprec)
    
    return Base.cconvert(Int64, num_ir),
           Base.cconvert(Array{Int64,2}, kgrid),
           Base.cconvert(Array{Int64,1}, mapping)

end
