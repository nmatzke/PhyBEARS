
#######################################################
# Example inference: Imagine NZ sunk, recolonized from elsewhere
#######################################################

using Interpolations	# for Linear, Gridded, interpolate
using LinearAlgebra  	# for "I" in: Matrix{Float64}(I, 2, 2)
										 	# https://www.reddit.com/r/Julia/comments/9cfosj/identity_matrix_in_julia_v10/
using Sundials				# for CVODE_BDF
using Test						# for @test, @testset
using PhyloBits
using DataFrames
using CSV

using PhyBEARS
#using PhyBEARS.Parsers


# Change the working directory as needed
wd = "/GitHub/PhyBEARS.jl/sims/sunkNZ_v1/"
cd(wd)

# This simulation has 148 living species
trfn = "living_tree_noNodeLabels.newick"
tr = readTopology(trfn)
trdf = prt(tr);
oldest_possible_age = 125.0

lgdata_fn = "geog_living.data"
geog_df = Parsers.getranges_from_LagrangePHYLIP(lgdata_fn);
include_null_range = false
numareas = Rncol(geog_df)-1
max_range_size = numareas
n = numstates_from_numareas(numareas, max_range_size, include_null_range)

# DEC-type SSE model on Hawaiian Psychotria
# We are setting "j" to 0.0, for now -- so, no jump dispersal
bmo = construct_BioGeoBEARS_model_object();
#bmo.type[bmo.rownames .== "j"] .= "free";
bmo.est[bmo.rownames .== "birthRate"] .= ML_yule_birthRate(tr);
bmo.est[bmo.rownames .== "deathRate"] .= 0.9*ML_yule_birthRate(tr);
bmo.est[bmo.rownames .== "d"] .= 0.034;
bmo.est[bmo.rownames .== "e"] .= 0.028;
bmo.est[bmo.rownames .== "a"] .= 0.0;
bmo.est[bmo.rownames .== "j"] .= 0.1;
bmo.est[bmo.rownames .== "u"] .= -1.0;
bmo.min[bmo.rownames .== "u"] .= -2.5;
bmo.max[bmo.rownames .== "u"] .= 0.0;

bmo.type[bmo.rownames .== "j"] .= "free";
bmo.type[bmo.rownames .== "u"] .= "free";
bmo.type[bmo.rownames .== "birthRate"] .= "free";
bmo.type[bmo.rownames .== "deathRate"] .= "birthRate";



# Set up the model
inputs = PhyBEARS.ModelLikes.setup_DEC_SSE2(numareas, tr, geog_df; root_age_mult=1.5, max_range_size=NaN, include_null_range=include_null_range, bmo=bmo);
(setup, res, trdf, bmo, files, solver_options, p_Ds_v5, Es_tspan) = inputs;

bmo.est[:] = bmo_updater_v2(bmo, inputs.setup.bmo_rows);

inputs.setup.txt_states_list



#######################################################
# Read in and parse distances and area-of-areas
#######################################################
files.times_fn = "sunkNZ_times.txt"
files.distances_fn = "sunkNZ_distances.txt"
files.area_of_areas_fn = "sunkNZ_area_of_areas.txt"

# Construct interpolators, times-at-which-to-interpolate QC
p = p_Ds_v5;
interpolators = files_to_interpolators(files, setup.numareas, setup.states_list, setup.v_rows, p.p_indices.Carray_jvals, p.p_indices.Carray_kvals, trdf; oldest_possible_age=oldest_possible_age);

interpolators.area_of_areas_interpolator(0.0)
interpolators.area_of_areas_interpolator(10.0)
interpolators.area_of_areas_interpolator(20.0)
interpolators.area_of_areas_interpolator(21.0)
interpolators.area_of_areas_interpolator(22.0)
interpolators.area_of_areas_interpolator(23.0)
interpolators.area_of_areas_interpolator(24.0)
interpolators.area_of_areas_interpolator(25.0)
interpolators.area_of_areas_interpolator(26.0)



p_Es_v12 = (n=p_Ds_v5.n, params=p_Ds_v5.params, p_indices=p_Ds_v5.p_indices, p_TFs=p_Ds_v5.p_TFs, uE=p_Ds_v5.uE, terms=p_Ds_v5.terms, setup=inputs.setup, states_as_areas_lists=inputs.setup.states_list, use_distances=true, bmo=bmo, interpolators=interpolators);

# Add Q, C interpolators
p_Es_v12 = p = PhyBEARS.TimeDep.construct_QC_interpolators(p_Es_v12, p_Es_v12.interpolators.times_for_SSE_interpolators);

# Solve the Es
prob_Es_v12 = DifferentialEquations.ODEProblem(PhyBEARS.SSEs.parameterized_ClaSSE_Es_v12_simd_sums, p_Es_v12.uE, Es_tspan, p_Es_v12);
sol_Es_v12 = solve(prob_Es_v12, solver_options.solver, save_everystep=solver_options.save_everystep, abstol=solver_options.abstol, reltol=solver_options.reltol);

sol_Es_v12(0.0)
sol_Es_v12(22.0)
sol_Es_v12(23.0)
sol_Es_v12(24.0)
sol_Es_v12(25.0)
sol_Es_v12(26.0)

p = p_Ds_v12 = (n=p_Es_v12.n, params=p_Es_v12.params, p_indices=p_Es_v12.p_indices, p_TFs=p_Es_v12.p_TFs, uE=p_Es_v12.uE, terms=p_Es_v12.terms, setup=p_Es_v12.setup, states_as_areas_lists=p_Es_v12.states_as_areas_lists, use_distances=p_Es_v12.use_distances, bmo=p_Es_v12.bmo, interpolators=p_Es_v12.interpolators, sol_Es_v12=sol_Es_v12);

# Solve the Ds
(total_calctime_in_sec, iteration_number, Julia_sum_lq, rootstates_lnL, Julia_total_lnLs1, bgb_lnL) = PhyBEARS.TreePass.iterative_downpass_nonparallel_ClaSSE_v12!(res; trdf=trdf, p_Ds_v12=p_Ds_v12, solver_options=inputs.solver_options, max_iterations=10^5, return_lnLs=true)

(total_calctime_in_sec, iteration_number, Julia_sum_lq, rootstates_lnL, Julia_total_lnLs1, bgb_lnL) = PhyBEARS.TreePass.iterative_downpass_nonparallel_ClaSSE_v12!(res; trdf=trdf, p_Ds_v12=p_Ds_v12, solver_options=inputs.solver_options, max_iterations=10^5, return_lnLs=true)

# Single branch
# Solve the Ds
u0_Ds = res.likes_at_each_nodeIndex_branchTop[1]

prob_Ds_v12 = DifferentialEquations.ODEProblem(PhyBEARS.SSEs.parameterized_ClaSSE_Ds_v12_simd_sums, u0_Ds, Es_tspan, p_Ds_v12);
sol_Ds_v12 = solve(prob_Ds_v12, solver_options.solver, save_everystep=solver_options.save_everystep, abstol=solver_options.abstol, reltol=solver_options.reltol);

sol_Ds_v12(0.0)
sol_Ds_v12(1.0)
sol_Ds_v12(2.0)
sol_Ds_v12(22.0)
sol_Ds_v12(23.0)
sol_Ds_v12(24.0)
sol_Ds_v12(25.0)
sol_Ds_v12(26.0)

# Single branch in reverse
tmax = 1.0
rev_tspan = (tmax, 0.00)
#uMax_Ds = sol_Ds_v12(tmax) ./ sum(uMax_Ds)
uMax_Ds = sol_Ds_v12(tmax)


prob_Ds_v12rev = DifferentialEquations.ODEProblem(PhyBEARS.SSEs.parameterized_ClaSSE_Ds_v12_simd_sums_noNegs, uMax_Ds, rev_tspan, p_Ds_v12);

# Callback to ensure u never goes below 0.0 or above 1.0
# https://nextjournal.com/sosiris-de/ode-diffeq?change-id=CkQATVFdWBPaEkpdm6vuto
# resid (residual) instead of du
function g(resid,u,p,t)
  min.(0.0, u)
end
cb = ManifoldProjection(g)

resid = repeat([0.0], length(uMax_Ds))

t = 0.5
g(resid,uMax_Ds,p_Ds_v12,t)

cb = ManifoldProjection(g)
cb = PositiveDomain(deepcopy(uMax_Ds))

#solver_options.solver = Tsit5()
solver_options.solver
solver_options.abstol = 1e-14
solver_options.reltol = 1e-14
solver_options.save_everystep = false

solver_options.saveat = reverse(seq(minimum(rev_tspan), 1.0, 0.05))

sol_Ds_v12rev = solve(prob_Ds_v12rev, solver_options.solver, save_everystep=solver_options.save_everystep, saveat=solver_options.saveat, abstol=solver_options.abstol, reltol=solver_options.reltol)


#sol_Ds_v12rev = solve(prob_Ds_v12rev, solver_options.solver, save_everystep=solver_options.save_everystep, abstol=solver_options.abstol, reltol=solver_options.reltol, isoutofdomain=(u,p,t) -> any(x -> x < 0, u));

#sol_Ds_v12rev = solve(prob_Ds_v12rev, solver_options.solver, save_everystep=solver_options.save_everystep, abstol=solver_options.abstol, reltol=solver_options.reltol, callback=cb;


#truestart = sol_Ds_v12(0.0)
#approx_start = sol_Ds_v12rev(0.0)
sol_Ds_v12(0.0)
sol_Ds_v12rev(0.0)
sol_Ds_v12(1.0)
sol_Ds_v12rev(tmax)


prob_Ds_v12rev_noNegs = DifferentialEquations.ODEProblem(PhyBEARS.SSEs.parameterized_ClaSSE_Ds_v12_simd_sums_noNegs, uMax_Ds, rev_tspan, p_Ds_v12);
sol_Ds_v12rev_noNegs = solve(prob_Ds_v12rev_noNegs, solver_options.solver, save_everystep=solver_options.save_everystep, abstol=solver_options.abstol, reltol=solver_options.reltol);


#truestart = sol_Ds_v12(0.0)
#approx_start = sol_Ds_v12rev(0.0)
sol_Ds_v12(0.0)
sol_Ds_v12rev_noNegs(0.0)
sol_Ds_v12(1.0)
sol_Ds_v12rev_noNegs(tmax)

sol_Ds_v12rev_noNegs(tmax) .- sol_Ds_v12rev(tmax)

@benchmark sol_Ds_v12rev_noNegs = solve(prob_Ds_v12rev_noNegs, solver_options.solver, save_everystep=solver_options.save_everystep, abstol=solver_options.abstol, reltol=solver_options.reltol)

@benchmark sol_Ds_v12rev = solve(prob_Ds_v12rev, solver_options.solver, save_everystep=solver_options.save_everystep, abstol=solver_options.abstol, reltol=solver_options.reltol)

#sol_Ds_v12rev(0.0) ./ sum(sol_Ds_v12(tmax))


sol_Ds_v12rev(2.0)
sol_Ds_v12rev(22.0)
sol_Ds_v12rev(23.0)
sol_Ds_v12rev(24.0)
sol_Ds_v12rev(25.0)
sol_Ds_v12rev(26.0)




#######################################################
# Maximum likelihood inference
#######################################################
inputs.bmo.type[inputs.bmo.rownames .== "j"] .= "free"
inputs.bmo.type[inputs.bmo.rownames .== "birthRate"] .= "free"
inputs.bmo.type[inputs.bmo.rownames .== "deathRate"] .= "birthRate"

inputs.bmo.type[inputs.bmo.rownames .== "u"] .= "fixed"
inputs.bmo.est[inputs.bmo.rownames .== "u"] .= -1.0
inputs.bmo.init[inputs.bmo.rownames .== "u"] .= -1.0

pars = deepcopy(inputs.bmo.est[inputs.bmo.type .== "free"])
parnames = inputs.bmo.rownames[inputs.bmo.type .== "free"]
func = x -> func_to_optimize_v12(x, parnames, inputs, p_Ds_v12; returnval="lnL", printlevel=1)
#pars = [0.04, 0.001, 0.0001, 0.1, inputs.bmo.est[bmo.rownames .== "birthRate"][1], 0.0]



func(pars)
function func2(pars, dummy_gradient!)
	return func(pars)
end # END function func2(pars, dummy_gradient!)


using NLopt
opt = NLopt.Opt(:LN_BOBYQA, length(pars))
ndims(opt)
opt.algorithm
algorithm_name(opt::Opt)
opt.min_objective = func2;
lower = bmo.min[bmo.type .== "free"];
upper = bmo.max[bmo.type .== "free"];
opt.lower_bounds = lower::Union{AbstractVector,Real};
opt.upper_bounds = upper::Union{AbstractVector,Real};
#opt.ftol_abs = 0.0001 # tolerance on log-likelihood
#opt.ftol_rel = 0.01 # tolerance on log-likelihood
#opt.xtol_abs = 0.00001 # tolerance on parameters
#opt.xtol_rel = 0.001 # tolerance on parameters
(optf,optx,ret) = NLopt.optimize!(opt, pars)
#######################################################


# Get the inputs & res:
pars = optx;

# Give the simulation a substantial death rate
func(pars)
#pars[parnames .== "deathRate"] .= 0.5*pars[parnames .== "birthRate"]
#pars[parnames .== "u"] .= -1.0
func(pars)

inputs.bmo.est[inputs.bmo.type .== "free"] .= pars;
inputs.bmo.est[bmo.rownames .== "birthRate"] = inputs.bmo.est[bmo.rownames .== "birthRate"] / 5
inputs.bmo.est[:] = bmo_updater_v2(bmo, inputs.setup.bmo_rows)
res = inputs.res;

# Solution, under best ML parameters
p_Ds_v5_updater_v1!(p_Ds_v12, inputs);
p_Es_v12 = TimeDep.construct_QC_interpolators(p_Ds_v12, p_Ds_v12.interpolators.times_for_SSE_interpolators);

# Solve the Es
prob_Es_v12 = DifferentialEquations.ODEProblem(parameterized_ClaSSE_Es_v12_simd_sums, p_Es_v12.uE, inputs.Es_tspan, p_Es_v12)
# This solution is an interpolator
sol_Es_v12 = solve(prob_Es_v12, inputs.solver_options.solver, save_everystep=inputs.solver_options.save_everystep, abstol=inputs.solver_options.abstol, reltol=inputs.solver_options.reltol);
p_Ds_v12 = (n=p_Es_v12.n, params=p_Es_v12.params, p_indices=p_Es_v12.p_indices, p_TFs=p_Es_v12.p_TFs, uE=p_Es_v12.uE, terms=p_Es_v12.terms, setup=p_Es_v12.setup, states_as_areas_lists=p_Es_v12.states_as_areas_lists, use_distances=p_Es_v12.use_distances, bmo=p_Es_v12.bmo, interpolators=p_Es_v12.interpolators, sol_Es_v12=sol_Es_v12);

Rnames(p_Ds_v12.interpolators)

p_Ds_v12.interpolators.area_of_areas_interpolator(20.0)
p_Ds_v12.interpolators.area_of_areas_interpolator(21.0)
p_Ds_v12.interpolators.area_of_areas_interpolator(22.0)
p_Ds_v12.interpolators.area_of_areas_interpolator(23.0)
p_Ds_v12.interpolators.area_of_areas_interpolator(24.0)
p_Ds_v12.interpolators.area_of_areas_interpolator(25.0)
p_Ds_v12.interpolators.area_of_areas_interpolator(26.0)



p_Ds_v12.interpolators.mu_vals_interpolator(0.0)
p_Ds_v12.interpolators.mu_vals_interpolator(1.0)
p_Ds_v12.interpolators.mu_vals_interpolator(20.0)
p_Ds_v12.interpolators.mu_vals_interpolator(21.0)
p_Ds_v12.interpolators.mu_vals_interpolator(22.0)
p_Ds_v12.interpolators.mu_vals_interpolator(23.0)
p_Ds_v12.interpolators.mu_vals_interpolator(23.5)
p_Ds_v12.interpolators.mu_vals_interpolator(24.0)
p_Ds_v12.interpolators.mu_vals_interpolator(60.0)


# Calculate the Ds, and final log-likelihood etc.
(total_calctime_in_sec, iteration_number, Julia_sum_lq, rootstates_lnL, Julia_total_lnLs1, bgb_lnL) = iterative_downpass_nonparallel_ClaSSE_v12!(res; trdf=trdf, p_Ds_v12=p_Ds_v12, solver_options=inputs.solver_options, max_iterations=10^6, return_lnLs=true)

Rnames(res)
round.(res.normlikes_at_each_nodeIndex_branchTop[tr.root]; digits=3)

# 0.06
# 0.613
# 0.327


# ancestral_range_estimation
# This term is preferable to e.g. "ancestral area reconstruction"

Rnames(res)

rootnode = inputs.res.root_nodeIndex

lnode = trdf[rootnode,"leftNodeIndex"]
rnode = trdf[rootnode,"rightNodeIndex"]

# ACE for left descendant
nodenum = rootnode
nodelikes = res.normlikes_at_each_nodeIndex_branchTop[nodenum]



R_order =  sort(trdf, :Rnodenums).nodeIndex

uppass_edgematrix = res.uppass_edgematrix

include("/GitHub/PhyBEARS.jl/notes/nodeOp_Cmat_uppass_v12.jl")
current_nodeIndex = 6
x = nodeOp_Cmat_uppass_v12!(res, current_nodeIndex, trdf, p_Ds_v12, solver_options)

solver_options.abstol = 1.0e-9
solver_options.reltol = 1.0e-9
uppass_ancstates_v12(res, trdf, p_Ds_v12, solver_options; use_Cijk_rates_t=true)

res.uppass_probs_at_each_nodeIndex_branchBot[R_order,:]
res.anc_estimates_at_each_nodeIndex_branchBot[R_order,:]
res.uppass_probs_at_each_nodeIndex_branchTop[R_order,:]
res.anc_estimates_at_each_nodeIndex_branchTop[R_order,:]



tspan

uppass_Ds_v12 = DifferentialEquations.ODEProblem(parameterized_ClaSSE_Ds_v12_simd_sums, deepcopy(u0), tspan, p_Ds_v12)

	sol_Ds = solve(prob_Ds_v12, solver_options.solver, dense=false, save_start=false, save_end=true, save_everystep=false, abstol=solver_options.abstol, reltol=solver_options.reltol)


# Install modified "castor" package in R
# install.packages(pkgs="/GitHub/PhyBEARS.jl/simulator/castor_1.7.2.000004.tar.gz", lib="/Library/Frameworks/R.framework/Resources/library/", repos=NULL, type="source")

# Write model out to text files that can be read in to simulator
geog_interpolator_times = parse_times_fn(files.times_fn)
timepoints = sort(unique(vcat(seq(0.0, maximum(geog_interpolator_times), 1.0), geog_interpolator_times)))
# (the best way to do this is to do simulations for a fixed period of time; the number of taxa
#  will vary, but have an average)
outfns = model_to_text_v12(p_Ds_v12, timepoints; prefix="")


Rcode = """
library(cladoRcpp)
library(BioGeoBEARS)
library(ape)
library(castor)

# for: reorder_castor_sim_to_default_ape_node_order(simulation)
source("/GitHub/PhyBEARS.jl/Rsrc/castor_helpers.R")

wd = "/GitHub/PhyBEARS.jl/sims/sunkNZ_v1/"
setwd(wd)
simfns = c("setup_df.txt",
"timepoints.txt", 
"mu_vals_by_t.txt", 
"Qvals_by_t.txt",
"Crates_by_t.txt",
"Qarray.txt",
"Carray.txt",
"area_names.txt",
"states_list.R")


simulation2 = simulate_tdsse2_for_timeperiod(wd, start_state=2, max_simulation_time=100.0, min_tips=50, max_tips=500, simfns=default_simfns(), seedval=543221, max_rate=10.0, numtries=250)
get_root_age(simulation2$tree)
get_root_age(simulation2$living_tree)
"""
