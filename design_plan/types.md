# DiffEQ types Ideas

## Setting Type
I want to make an solver settings type that I can pass in instead of
keyword arguments. I will look to matlabs odeset as a model, I will also
want to use the naming conventions of `Optim.jl` for things like `abstol`
as best I can for consistency.

So Matlab has options for: (I am changing the naming to be Julian they use CamelCase)
* reltol = 1e-3,
* abstol = 1e-6 (can be scalor or vector),
* norm_control = 'on'|'off'
* maxstep = Postitive scalar {0.1*abs(t0 - tf)}
* initial_step::PositiveScalor
* jacobian, jpattern::SparseMatrix{Int}
* for BDF methods:
    * MaxOrder = {1|2|3|4|5}
    * BDF = {on|off}: chooses if to use BDF or NDF

They also have things like:

* mass, mstate_dependence, mvpattern, mass_singular, initial_slope (which is for the DAE solvers)
* and things like Events, NonNegative, OutputFcn, OutputSel
* Refine (refines grid of solutions by integer factor)
* Stats (reports diagnostics)

From the code I have from `ODE.jl` we have the kw args:
* `reltol = 1.0e-5`,
* `abstol = 1.0e-8`,
* `norm = Base.norm`,
* `minstep = abs(tspan[end] - tspan[1])/1e18`,
* `maxstep = abs(tspan[end] - tspan[1])/2.5`,
* `initstep = 0.0`,
* `points = :all`

## Output Type
For output Matlab either returns arrays (t, y) with the solutions
(optional `(t, y, te, ye, ie)` for event detections) or it gives back a `struct`
with default fields: `sol.x`, `sol.y`, `sol.solver::SolverName`.
I personally prefer the sturct solution which I will want to emulate.