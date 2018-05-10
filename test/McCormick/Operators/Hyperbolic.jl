module Op_Hyperbolic

using Compat
using Compat.Test
using EAGO
using IntervalArithmetic
using StaticArrays

@testset "Test Sinh" begin
    # ADD nonsmooth test
    EAGO.set_diff_relax(1)
    a = seed_g(Float64,1,2)
    b = seed_g(Float64,2,2)
    xIBox = SVector{2,Interval{Float64}}([Interval(3.0,7.0);Interval(3.0,9.0)])
    mBox = mid.(xIBox)
    X = SMCg{2,Interval{Float64},Float64}(4.0,4.0,a,a,xIBox[1],false,xIBox,mBox)
    Y = SMCg{2,Interval{Float64},Float64}(7.0,7.0,b,b,xIBox[2],false,xIBox,mBox)
    Xn = SMCg{2,Interval{Float64},Float64}(-4.0,-4.0,a,a,-xIBox[1],false,xIBox,mBox)
    Xz = SMCg{2,Interval{Float64},Float64}(-2.0,-2.0,a,a,Interval(-3.0,1.0),false,xIBox,mBox)

    out10 = sinh(X)
    @test isapprox(out10.cc,144.59243701386904,atol=1E-5)
    @test isapprox(out10.cv,27.28991719712775,atol=1E-5)
    @test isapprox(out10.cc_grad[1],134.575,atol=1E-2)
    @test isapprox(out10.cc_grad[2],0.0,atol=1E-1)
    @test isapprox(out10.cv_grad[1],27.3082,atol=1E-2)
    @test isapprox(out10.cv_grad[2],0.0,atol=1E-1)
    @test isapprox(out10.Intv.lo,10.0178,atol=1E-2)
    @test isapprox(out10.Intv.hi,548.317,atol=1E-2)
    out10a = sinh(Xn)
    @test isapprox(out10a.cc,-27.28991719712775,atol=1E-5)
    @test isapprox(out10a.cv,-144.59243701386904,atol=1E-5)
    @test isapprox(out10a.cc_grad[1],27.3082,atol=1E-2)
    @test isapprox(out10a.cc_grad[2],0.0,atol=1E-1)
    @test isapprox(out10a.cv_grad[1],134.575,atol=1E-2)
    @test isapprox(out10a.cv_grad[2],0.0,atol=1E-1)
    @test isapprox(out10a.Intv.lo,-548.317,atol=1E-2)
    @test isapprox(out10a.Intv.hi,-10.0178,atol=1E-2)
    # ADD zero test, Plot
end

@testset "Cosh" begin

    EAGO.set_diff_relax(0)
    a = seed_g(Float64,1,2)
    b = seed_g(Float64,2,2)
    xIBox = SVector{2,Interval{Float64}}([Interval(3.0,7.0);Interval(3.0,9.0)])
    mBox = mid.(xIBox)
    X = SMCg{2,Interval{Float64},Float64}(4.0,4.0,a,a,xIBox[1],false,xIBox,mBox)
    Y = SMCg{2,Interval{Float64},Float64}(7.0,7.0,b,b,xIBox[2],false,xIBox,mBox)

    out8 = cosh(X)
    @test isapprox(out8.cc,144.63000528563632,atol=1E-5)
    @test isapprox(out8.cv,27.308232836016487,atol=1E-5)
    @test isapprox(out8.cc_grad[1],134.562,atol=1E-2)
    @test isapprox(out8.cc_grad[2],0.0,atol=1E-5)
    @test isapprox(out8.cv_grad[1],-27.2899,atol=1E-3)
    @test isapprox(out8.cv_grad[2],0.0,atol=1E-5)
    @test isapprox(out8.Intv.lo,10.0676,atol=1E-3)
    @test isapprox(out8.Intv.hi,548.318,atol=1E-3)

    EAGO.set_diff_relax(1)
    xIBox = SVector{2,Interval{Float64}}([Interval(3.0,7.0);Interval(3.0,9.0)])
    mBox = mid.(xIBox)
    X = SMCg{2,Interval{Float64},Float64}(4.0,4.0,a,a,xIBox[1],false,xIBox,mBox)
    Y = SMCg{2,Interval{Float64},Float64}(7.0,7.0,b,b,xIBox[2],false,xIBox,mBox)
    Xn = SMCg{2,Interval{Float64},Float64}(-4.0,-4.0,a,a,-xIBox[1],false,xIBox,mBox)
    Xz = SMCg{2,Interval{Float64},Float64}(-2.0,-2.0,a,a,Interval(-3.0,1.0),false,xIBox,mBox)

    out8 = cosh(X)
    @test isapprox(out8.cc,144.63000528563632,atol=1E-5)
    @test isapprox(out8.cv,27.308232836016487,atol=1E-5)
    @test isapprox(out8.cc_grad[1],134.562,atol=1E-2)
    @test isapprox(out8.cc_grad[2],0.0,atol=1E-5)
    @test isapprox(out8.cv_grad[1],-27.2899,atol=1E-3)
    @test isapprox(out8.cv_grad[2],0.0,atol=1E-5)
    @test isapprox(out8.Intv.lo,10.0676,atol=1E-3)
    @test isapprox(out8.Intv.hi,548.318,atol=1E-3)
end

@testset "Test Tanh" begin
end

end
