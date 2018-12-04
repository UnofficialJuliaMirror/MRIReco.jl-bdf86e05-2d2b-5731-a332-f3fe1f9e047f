# Basic Image(Shepp Logan Phantom) and

function test_kdata(N::Int64=32)
    @info "Testing simulating kdata with NFFT and exact evauluation"
    I = shepp_logan(N)
    tr = RadialTrajectory(N,N)
    println("Simulating kdata using NFFT")
    @time acqDataNFFT = simulation_fast(tr,I)
    @info "Simulating kdata rigorously"
    @time acqDataExplicit = simulation_explicit(tr,I)
    relError =  norm(acqDataExplicit.kdata[:]-acqDataNFFT.kdata[:]) / norm(acqDataExplicit.kdata[:])
    println("Relative error NFFT vs EXACT: ", relError)
    @test relError < 1e-2

end

function test_kdataMultipleSlices(N::Int64=32)
    @info "Testing simulating multiple 2d-slices with NFFT and exact evauluation"
    sh = ComplexF64.(shepp_logan(N))
    I = cat(sh,0.6*sh,0.3*sh,dims=3)
    tr = SimpleCartesianTrajectory(N,N)
    println("Simulating kdata using NFFT")
    @time acqDataNFFT = simulation(tr,I,opName="fast")
    @info "Simulating kdata rigorously"
    @time acqDataExplicit = simulation(tr,I,opName="explicit")
    relError =  norm(acqDataExplicit.kdata[:]-acqDataNFFT.kdata[:]) / norm(acqDataExplicit.kdata[:])
    println("Relative error NFFT vs EXACT: ", relError)
    @test relError < 1e-2

end

function test_kdata3d(N::Int64=16)
    @info "Testing simulating 3d-kdata with NFFT and exact evauluation"
    sh = ComplexF64.(shepp_logan(N))
    I = cat(sh,0.9*sh,0.8*sh,0.7*sh,0.6*sh,0.5*sh,0.4*sh,0.3*sh,dims=3)
    tr = CartesianTrajectory3D(N,N,numSlices=8)
    println("Simulating kdata using NFFT")
    @time acqDataNFFT = simulation(tr,I,opName="fast")
    @info "Simulating kdata rigorously"
    @time acqDataExplicit = simulation(tr,I,opName="explicit")
    relError =  norm(acqDataExplicit.kdata[:]-acqDataNFFT.kdata[:]) / norm(acqDataExplicit.kdata[:])
    println("Relative error NFFT vs EXACT: ", relError)
    @test relError < 1e-2

end

function test_kdataWithCorrection(N::Int64=32)
    # Testing generating kdata with fieldinhomogeneity
    I = shepp_logan(N)
    @info "Testing simulating kdata with correctionterm"
    fmap = quadraticFieldmap(N,N,125*2pi)[:,:,1]
    rmap = relaxationMap(I,5.0,50.0)
    cmap = rmap + 1im*fmap
    tr = SpiralTrajectory(N,2*N,TE=0.0,AQ=32e-3)

    println("Simulating kdata using NFFT to approx. correctionterm ...")
    @time acqDataNFFT = simulation_fast(tr,I,cmap;method="nfft")
    println("Simulating kdata using Least Squares to approx. correctionterm...")
    @time acqDataLSQR = simulation_fast(tr,I,cmap;method="leastsquare")
    println("Simulating kdata rigorously...")
    @time acqDataExplicit = simulation_explicit(tr,I,cmap)
    # Calculating and testing the relative error of kdata
    relErrorLeastSquare = norm(acqDataExplicit.kdata[:]-acqDataLSQR.kdata[:]) / norm(acqDataExplicit.kdata[:])
    println("Relative Error of leastsquare method: ", relErrorLeastSquare)
    @test relErrorLeastSquare < 1e-3

    relErrorNFFT = norm(acqDataExplicit.kdata[:] - acqDataNFFT.kdata[:]) / norm(acqDataExplicit.kdata[:])
    println("Relative Error of leastsquare method: ", relErrorNFFT)
    @test relErrorNFFT < 1e-3

end

function test_kdataMultiEcho(N=32)
    # image
    I = ComplexF64.(shepp_logan(N))
    @info "Testing simulating kdata with multiple echoes"
    rmap = 20.0*ones(N,N)

    # simulation
    params = Dict{Symbol, Any}()
    params[:simulation] = "fast"
    params[:trajName] = "Cartesian"
    params[:numProfiles] = floor(Int64, N)
    params[:numSamplingPerProfile] = N
    params[:TE] = 0.0

    acqData1 = simulation( real(I), params )
    kdata1 = acqData1.kdata

    params[:r2map] = rmap
    params[:TE] = 2.e-2
    params[:seqName] = "FSE"
    params[:numEchoes] = 2
    params[:flipAngles] = [pi,pi]

    acqData2 = simulation( real(I), params )
    kdata2 = reshape(acqData2.kdata,:,2)

    relErrorEcho1 = norm(exp(-20.0*2.e-2)*kdata1 - kdata2[:,1])/norm(exp(-20.0*2.e-2)*kdata1)
    @test relErrorEcho1 < 1e-3
    relErrorEcho2 = norm(exp(-20.0*4.e-2)*kdata1 - kdata2[:,2])/norm(exp(-20.0*4.e-2)*kdata1)
    @test relErrorEcho2 < 1e-3
end

function test_noise(N::Int64=32, snr::Float64=25.0)
    @info "Testing simulating kdata with NFFT and exact evauluation"
    I = shepp_logan(N)
    tr = RadialTrajectory(N,N)
    @time acqData = simulation_explicit(tr,I)
    acqDataNoisy = MRIReco.addNoise(acqData,snr)
    relError =  norm(acqData.kdata[:]-acqDataNoisy.kdata[:]) / norm(acqData.kdata[:])
    println("Relative error EXACT vs NOISY: ", relError)
    @test relError < 1e-1
end

function testSimulation()
  @testset "simulations" begin
    test_kdata()
    test_kdataMultipleSlices()
    test_kdata3d()
    test_kdataWithCorrection(16)
    test_kdataMultiEcho()
    test_noise()
  end
end