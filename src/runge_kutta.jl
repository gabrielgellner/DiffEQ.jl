# Explicit Runge-Kutta solvers
##############################
# (Hairer & Wanner 1992 p.134, p.165-169)
# Dormand-Prince https://en.wikipedia.org/wiki/Dormand%E2%80%93Prince_method
type RKTableau{T <: Real}
    nstages::Int
    a::Matrix{T}
    b::Matrix{T}
    c::Vector{T}
end

function Base.convert{Tnew <: AbstractFloat}(::Type{Tnew}, rktab::RKTableau)
    RKTableau(rktab.nstages, convert(Matrix{Tnew}, rktab.a), convert(Matrix{Tnew}, rktab.b), convert(Vector{Tnew}, rktab.c))
end

# Store as Rational so that I can then convert to the needed AbstractFloat types
#TODO: currently not implemented only use Float64
const tab_dopri54_base = RKTableau{Rational}(
    7, # nstages
    #7x7 matrix (a matrix)
    [0 0 0 0 0 0 0;
     1//5 0 0 0 0 0 0;
     3//40 9//40 0 0 0 0 0;
     44/45 -56//15 32//9 0 0 0 0;
     19372//6561 -25360/2187 64448//6561 -212//729 0 0 0;
     9017//3168 -355//33 46732//5247 49//176 -5103//18656 0 0;
     35//384 0 500//1113 125/192 -2187//6784 11/84 0],
    #2x7 matrix (b matrix)
    [35//384 0 500//1113 125//192 -2187//6784 11//84 0;
     5179//57600 0 7571//16695 393//640 -92097//339200 187//2100 1//40],
    #length 7 vector (c vector)
    [0, 1//5, 3//10, 4//5, 8//9, 1, 1]
)
const tab_dopri54 = convert(Float64, tab_dopri54_base)

##############################
# Adaptive Runge-Kutta methods
##############################
aode(sys::Dopri54, tspan, options::RKOptions) = rksolver_array(sys, tspan, options, tab_dopri54)
aode(sys::Dopri54, tspan;
     reltol = 1.0e-5,
     abstol = 1.0e-8,
     maxstep = 0.1*abs(tspan[end] - tspan[1]),
     minstep = abs(tspan[end] - tspan[1])/1e18,
     initstep = 0.0
     ) = rksolver_array(sys, tspan, RKOptions(reltol, abstol, maxstep, minstep, initstep), tab_dopri54)

dode(sys::Dopri54, tspan, options::RKOptions) = rksolver_dense(sys, tspan, options, tab_dopri54)
dode(sys::Dopri54, tspan;
     reltol = 1.0e-5,
     abstol = 1.0e-8,
     maxstep = 0.1*abs(tspan[end] - tspan[1]),
     minstep = abs(tspan[end] - tspan[1])/1e18,
     initstep = 0.0
     ) = rksolver_dense(sys, tspan, RKOptions(reltol, abstol, maxstep, minstep, initstep), tab_dopri54)

function rksolver_array(sys::RungeKuttaSystem, tspan::AbstractVector{Float64}, options::RKOptions, rktab::RKTableau)
    ## Initialization
    sys.work.tstart = tspan[1]
    sys.work.tend = tspan[end]

    # initialize work arrays
    sys.work.yinit = copy(sys.y0)

    # output ys
    nsteps_fixed = length(tspan)
    ##Note: it is more column major to think of an array of points joined along
    ## columns. When returned it must be transposed.
    ys = Array{Float64}(sys.work.ydim, nsteps_fixed) #TODO allow for any AbstractFloat
    ys[:, 1] = copy(sys.y0)

    # Time
    hinit!(sys, options) # initialize sys.work using an euler step
    if options.initstep != 0
        sys.work.dt = sign(options.initstep) == sys.work.tdir ? options.initstep : error("initstep has wrong sign.")
    end

    ## Integration loop
    dts, errs, steps = rk_stepper!(sys, tspan, ys, [], options, rktab, rk_array_output!)

    ##TODO: clean up the returing of stats so that rk_stepper acutally uses a stats type.
    return RKODESolution(tspan, ys', ODESolutionStatistics(-1, steps[1], steps[2]))
end

function rksolver_dense(sys::RungeKuttaSystem, tspan::AbstractVector{Float64}, options::RKOptions, rktab::RKTableau)
    ## Initialization
    if length(tspan) > 2
        error("Dense output requires tspan to be two points (tstart, tend).")
    end
    sys.work.tstart = tspan[1]
    sys.work.tend = tspan[end]
    tout = [copy(sys.work.tstart)]

    # initialize work arrays
    sys.work.yinit = copy(sys.y0)

    # ys is an array of arrays so that it can grow as needed, this will be
    # converted to an array (table: nsteps x ydim array) at output
    ys = Array{Float64, 1}[copy(sys.y0)]
    fs = Any[] # this is an array of (ydim x 7)-arrays

    # Time
    hinit!(sys, options) # initialize sys.work with euler step
    if options.initstep != 0
        sys.work.dt = sign(options.initstep) == sys.work.tdir ? options.initstep : error("initstep has wrong sign.")
    end

    # Integrate
    ##TODO: work on this argument list!
    dts, errs = rk_stepper!(sys, tout, ys, fs, options, rktab, rk_dense_output!)

    ##TODO: think about how to deal with solver statistics for this kind of type
    # Output solution
    return DenseODESolution(tout, hcat(ys...), fs)
end

##TODO: the naming conventions in this function are totally different then in the rest of the code: ie h instead of dt
## y instead of f etc
# estimator for initial step based on book
# "Solving Ordinary Differential Equations I" by Hairer et al., p.169
function hinit!(sys::AbstractODESystem, options::RKOptions)
    # Returns first step, direction of integration and F evaluated at t0
    sys.work.tdir = sign(sys.work.tend - sys.work.tstart)
    sys.work.tdir == 0 && error("Zero time span")

    # we use the norm(a, Inf) instead of complex uses of sums and sqrt(x^2)
    # transforms to simulate the same thing like in the fotran code
    tau = max(options.reltol*norm(sys.work.yinit, Inf), options.abstol)
    d0 = norm(sys.work.yinit, Inf)/tau
    f0 = sys.func(sys.work.tstart, sys.work.yinit)
    d1 = norm(f0, Inf)/tau
    #the fortran code uses 1e-10 for both but since we are using norms instead
    # of taking sqrt(x^2) this is equivalent
    if d0 < 1e-5 || d1 < 1e-5
        h0 = 1e-6
    else
        h0 = 0.01*(d0/d1)
    end

    # perform Euler step
    x1 = sys.work.yinit + sys.work.tdir*h0*f0
    f1 = sys.func(sys.work.tstart + sys.work.tdir*h0, x1)

    # estimate second derivative
    d2 = norm(f1 - f0, Inf)/(tau*h0)
    if max(d1, d2) <= 1e-15
        h1 = max(1e-6, 1e-3*h0)
    else
        # fortran code uses (0.01/max(d1, d2))^(1/order)
        # which is the same ... but is one better numerically?
        pow = -(2.0 + log10(max(d1, d2)))/sys.work.order
        h1 = 10.0^pow
    end
    # set the first stage
    sys.work.ks[:, 1] = f0

    # update the work array with the final values
    sys.work.dt = sys.work.tdir*min(100*h0, h1, sys.work.tdir*(sys.work.tend - sys.work.tstart))
end

function rk_stepper!(sys::RungeKuttaSystem, tout, ys, fs, options::RKOptions, rktab::RKTableau, output_func!::Function)
    # Diagnostics
    ##TODO: generalize to any AbstractFloat
    dts = Float64[]
    errs = Float64[]
    steps = [0, 0]  # [accepted, rejected]

    ## Integration loop
    sys.work.laststep = abs(sys.work.tstart + sys.work.dt - sys.work.tend) <= eps(sys.work.tend) ? true : false
    sys.work.out_i = 2 # the index into tout and ys
    while true
        # do one step (assumes ks[:, 1] == f0)
        rk_embedded_step!(sys, rktab)
        # Check error and find a new step size:
        err, newdt = stepsize_hw92!(sys, options)

        if err <= 1.0 # accept step
            ## diagnostics
            steps[1] += 1
            push!(dts, sys.work.dt)
            push!(errs, err)

            ##TODO:
            ## Stiffness Detection

            ## Output:
            # setup interpolating coefficients
            setup_hermite!(sys)
            # output/save step
            output_func!(sys, ys, fs, tout)

            ## Prepare for next iteration
            # we are only using methods with the FSAL (first same as last) property
            sys.work.ks[:, 1] = sys.work.ks[:, 7] # load ks[:, 1] == f0 for next step

            # Break (end integration loop) if this was the last step:
            islaststep(sys) && break

            # Swap bindings of y and ytrial, avoids one copy
            sys.work.yinit, sys.work.ytrial = sys.work.ytrial, sys.work.yinit

            # Update t to the time at the end of current step:
            sys.work.tstart += sys.work.dt
            sys.work.dt = newdt

            # Hit end point exactly if next step within 1% of end:
            if sys.work.tdir*(sys.work.tstart + sys.work.dt*1.01) >= sys.work.tdir*sys.work.tend
                sys.work.dt = sys.work.tend - sys.work.tstart
                sys.work.laststep = true # next step is the last, if it succeeds
            end
        elseif abs(newdt) < options.minstep  # minimum step size reached, break
            ##TODO; make this a real error: not clear that giving back partial
            ## broken information is a good procedure
            println("Warning: dt < minstep.  Stopping.")
            break
        else # step failed: redo step with smaller dt
            sys.work.laststep = false
            steps[2] += 1 # increment nfailed steps
            sys.work.dt = newdt
        end
    end
    return dts, errs, steps
end

##TODO: I have broken the tdir variable, so I need to add checks for
## integrating in reverse
function rk_array_output!(sys, ys, fs, tout)
    ## interpolate onto requested times in (t, t + dt)
    # we need out_i - 1 < nout so that we don't have infinite loop at laststep
    nout = size(ys, 2)
    while sys.work.out_i - 1 < nout && (tout[sys.work.out_i] < sys.work.tstart + sys.work.dt || islaststep(sys))
        hermite_shampine_interp!(view(ys, :, sys.work.out_i), tout[sys.work.out_i], sys.work.tstart, sys.work.dt, view(sys.work.ycont, :, :))
        sys.work.out_i += 1
    end

    return nothing
end

function rk_dense_output!(sys, ys, fs, tout)
    push!(ys, deepcopy(sys.work.ytrial))
    push!(tout, sys.work.tstart + sys.work.dt)
    # Also save the hermite coefficients
    push!(fs, deepcopy(sys.work.ycont))

    return nothing
end

#TOD0: arguably rktab should be part of sys?
function rk_embedded_step!(sys, rktab::RKTableau)
    # Does one embedded R-K step updating ytrial, yerr and ks.
    #
    # Assumes that work.ks[1, :] is already calculated!
    #
    # Modifies work.ytrial, work.yerr, work.ks, and work.ytmp
    ##NOTE: currently hard coded to be Float64, fix
    fill!(sys.work.ytrial, 0.0)
    fill!(sys.work.yerr, 0.0)
    for d = 1:sys.work.ydim
        sys.work.ytrial[d] += rktab.b[1, 1]*sys.work.ks[d, 1]
        sys.work.yerr[d] += rktab.b[2 ,1]*sys.work.ks[d, 1]
    end
    for s = 2:rktab.nstages
        calc_next_k!(sys, s, rktab)
        for d = 1:sys.work.ydim
            ##TODO: this might be a source of a slowdown, as it is better to access
            ## rktab.b by the rows not across the columns. See about changing this.
            sys.work.ytrial[d] += rktab.b[1, s]*sys.work.ks[d, s]
            sys.work.yerr[d] += rktab.b[2, s]*sys.work.ks[d, s]
        end
    end
    for d = 1:sys.work.ydim
        # here we set yerr to the difference between the higher order method `ytrial`
        # and the lower order embeded method (which has been put in `yerr` in the previous
        # steps, but gets overwritten with the difference here) and the stepsize.
        sys.work.yerr[d] = sys.work.dt*(sys.work.ytrial[d] - sys.work.yerr[d])
        sys.work.ytrial[d] = sys.work.yinit[d] + sys.work.dt*sys.work.ytrial[d]
    end

    return nothing
end

function stepsize_hw92!(sys, options)
    # Estimates the error and a new step size following Hairer &
    # Wanner 1992, p167 (with some modifications)
    #
    # Returns the error, newdt
    #
    # TODO:
    # - allow component-wise reltol and abstol?
    #NOTE: fac is the stepsize scaling safety fac(tor), it is used so that the steps do
    # not grow or shrink to much
    ##TODO: fortran code has EXPO1 = 1/8, SAFE = 0.9, FAC1 = 0.2, FAC2 = 10,
    ## FACC1 = 1/FAC1, FACC2 = 1/FAC2
    ## and FAC1 <= HNEW/H <= FAC2
    ## which means:
    ## facmax = FACC1 = 1/FAC1 = 1/0.2 = 5.0
    ## facmin = FACC2 = 1/FAC1 = 1/10 = 0.1 (whereas we have 1/0.8 = 1.25)

    ##TODO: this is a very complicated way to calculate 0.8 ;) These are all the possible
    # safety factors listed in Hairer and Wanner, but the Dopri5.f codes just uses the 0.9
    # Just leave this as a comment for now, maybe in future versions it
    # would be worth having this as a selectable option? Scipy makes this an option, and it
    # looks like it is an option in the orignal fortran as well the IWORK[1] setting
    #fac = [0.8, 0.9, 0.25^(1/sys.work.order), 0.38^(1/sys.work.order)][1]
    # it wold seem that larger values run the risk of less accurate answers for less cpu
    # time. The 0.8 default is a conservative measure that goes for accuracy over speed.
    fac = 0.25^(1/5) # ~ 0.7578
    facmax = 5.0 # maximal step size increase. 1.5 - 5
    facmin = 0.1 #1.0/facmax  # maximal step size decrease. ?

    # The error used for step size selection in Hairer and Wanner uses the following
    # "norm"
    # err = \sqrt{\frac{1}{n}\sum_{i=1}^{n}(\frac{y_{1i} - \yhat{y_{1i}}}{sc_i}^2)}
    # with sc_i = atol_i + \max(\abs(y_{0i}), \abs(y_{1i}))*rtol_i
    # which in terms of norms can be seen as
    # err = norm((y1[i] - yhat1[i])/sci)/sqrt(n) for i in 1:n
    # and I think yerr is equal to y1[i] - yhat1[i] that is it is the difference between
    # the lower and higher order method prediction

    # in-place calculate yerr./tol
    for d = 1:sys.work.ydim
        ##TODO: this is not a "usually NaN" as: isoutofdomain(x) = isnan(x) maybe this was a place holder?
        # if outside of domain (usually NaN) then make step size smaller by maximum
        if isoutofdomain(sys.work.ytrial[d]) # this code is not in fortran version, though it might be suggested in the book. Check
            #NOTE 10.0 is the returned err > 1.0 therefore it is a failed step.
            # Returning dt*facmin gives the smallest step decrease possible
            return 10.0, sys.work.dt*facmin
        end
        # rescale yerr by abstol + reltol*max(abs(y0), abs(y1)) which is called
        sys.work.yerr[d] = sys.work.yerr[d]/(options.abstol + max(norm(sys.work.yinit[d]), norm(sys.work.ytrial[d]))*options.reltol) # Eq 4.10
    end
    ##TODO: the error formula Eq. 4.11 in the book has an extra scaling of
    ## 1/sqrt(ydim)
    err = norm(sys.work.yerr) #/sqrt(sys.work.ydim) # Eq. 4.11
    ##TODO: fortran code has:
    # FAC = ERR^EXP01 = ERR^(1/8)
    # FAC = max(FACC2, min(FACC1, FAC/SAFE))
    # HNEW = H/FAC
    # The book has:
    # h_new = h*min(facmax, max(facmin, fac*(1/err)^(1/(q + 1))))
    # so ODE.jl is changing this so that instead of using h*facmax it uses maxstep for the maximum stepsize
    newdt = sys.work.tdir*sys.work.dt*min(facmax, max(facmin, fac*(1/err)^(1/sys.work.order))) # Eq 4.13
    return err, sys.work.tdir*newdt
end

function calc_next_k!(sys, s::Integer, rktab::RKTableau)
    # Calculates the next ks and puts it into ks[s, :]
    # - ks and ytmp are modified inside this function.
    sys.work.ytmp[:] = sys.work.yinit #TODO: does this line copy?
    for ss = 1:(s - 1), d = 1:sys.work.ydim
        sys.work.ytmp[d] += sys.work.dt*sys.work.ks[d, ss]*rktab.a[s, ss]
    end
    sys.work.ks[:, s] = sys.func(sys.work.tstart + rktab.c[s]*sys.work.dt, sys.work.ytmp)

    return nothing
end
