# Robertson chemical reaction:
#
# Adapted from
# http://www.unige.ch/~hairer/testset/testset.html
# reference solution from
# http://www.dm.uniba.it/~testset/problems/rober.php
#
# See also:
# http://octave.sourceforge.net/odepkg/function/odepkg_testsuite_robertson.html
#
# Note that this runs over large tspan = [0,1e11] with the first step being < 1!
using DiffEQ
using Base.Test

##TODO: this code is crazy slow -- even seemingly for the ODE.jl original,
## likely this is a stiffness issue. I should get this test working so that
## it tests for the code bailing out.

##Code taken from ODE.jl
# rober testcase from http://www.unige.ch/~hairer/testset/testset.html
println("ROBER test case")
function f(t, y)
    ydot = similar(y)
    ydot[1] = -0.04*y[1] + 1.0e4*y[2]*y[3]
    ydot[3] = 3.0e7*y[2]*y[2]
    ydot[2] = -ydot[1] - ydot[3]
    ydot
end

tout = linspace(0.0, 1e11, 1000)
# This takes incredibly small steps so runs extremely slowly
#sol = aode(Dopri54(f, [1.0, 0.0, 0.0]), tout; abstol=1e-8, reltol=1e-8, maxstep=1e11/10, minstep=1e11/1e18)
sol = aode(Dopri54(f, [1.0, 0.0, 0.0]), tout; abstol=1e-8, reltol=1e-8)

# reference solution for the final time found
refsol = [0.2083340149701255e-07, 0.8333360770334713e-13, 0.9999999791665050]
@test norm(refsol - sol.y[end, :], Inf) < 2e-10
