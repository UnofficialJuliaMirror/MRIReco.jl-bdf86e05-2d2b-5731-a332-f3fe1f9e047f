export saveasIBIFile, trajectory, sequence, rawdata, acquisitionData,
       loadIBIFile, loadParams, saveParams

using HDF5

export MRIFileIBI

# Only hold the handle to the file an load/save all data on demand.
struct MRIFileIBI <: MRIFile
  filename::String
end

### reading ###

function trajectory(f::MRIFileIBI)
  fid = h5open(f.filename, "r")
  tr = fid["sequence/trajectory"]

  params = Dict{Symbol, Any}()
  for field = names(tr)
    params[Symbol(field)] = read(tr[field])
  end

  close(fid)
  return trajectory(params[:name], params[:numProfiles], params[:numSamplingPerProfile]; params...)
end

function sequence(f::MRIFileIBI)
  fid = h5open(f.filename, "r")

  # general sequence inforamation
  seq = fid["sequence"]
  seqParams = Dict{Symbol, Any}()
  for field = names(seq)
    field == "trajectory" && continue
    seqParams[Symbol(field)] = read(seq[field])
  end

  # information on trajectories used
  tr = fid["sequence/trajectory"]
  trParams = Dict{Symbol, Any}()
  for field = names(tr)
    trParams[Symbol(field)] = read(tr[field])
  end
  close(fid)

  return sequence(seqParams[:name], trParams[:name], trParams[:numProfiles], trParams[:numSamplingPerProfile]; seqParams..., trParams...)
end

function rawdata(f::MRIFileIBI)
  data = h5read(f.filename, "/rawdata")
  # workaround for hdf5 not supporting complex
  return reshape(reinterpret(Complex{eltype(data)}, vec(data)), (size(data)[2:end]...,) )
end

function acquisitionData(f::MRIFileIBI)
  return AcquisitionData(sequence(f),
                        rawdata(f),
                        h5read(f.filename, "sequence/numEchoes"),
                        h5read(f.filename, "numCoils"),
                        h5read(f.filename, "numSlices"),
                        h5read(f.filename, "samplePointer"),
                        h5read(f.filename, "samplingIdx"))
end

### writing ###

function saveasIBIFile(filename::AbstractString, rawdata::Array{Complex{T}}, tr::AbstractTrajectory) where T<:Real


  h5open(filename, "w") do file

    # Trajectory Information
    write(file, "sequence/trajectory/name", string(tr))
    write(file, "sequence/trajectory/numProfiles", tr.numProfiles)
    write(file, "sequence/trajectory/numSamplingPerProfile", tr.numSamplingPerProfile)
    write(file, "sequence/trajectory/TE", tr.TE)
    write(file, "sequence/trajectory/AQ", tr.AQ)

    rawdata_real = reshape(reinterpret(T, vec(rawdata)), (2,size(rawdata)...))
    write(file, "/rawdata", rawdata_real)

  end
end

function saveasIBIFile(filename::AbstractString, aqData::AcquisitionData)

  h5open(filename, "w") do file

    # Sequence Information
    write(file, "sequence/name", string(aqData.seq))
    write(file, "sequence/trajectory/name", string(trajectory(aqData.seq)))
    tr = trajectory(aqData.seq)
    for field in fieldnames(tr)
      a = getfield(tr,field)
      write( file, "sequence/trajectory/"*string(field), a )
    end

    write(file, "sequence/numEchoes", numEchoes(aqData.seq))
    write(file, "sequence/flipAngles", flipAngles(aqData.seq))

    # number of Coils, and sampled points and number of slices
    write(file, "numCoils", aqData.numCoils)
    write(file, "samplingIdx", aqData.idx)
    write(file, "numSlices", aqData.numSlices)

    # pointer to the data corresponding to a given echo, coil and slice
    write(file, "samplePointer", aqData.samplePointer)

    # kspace data
    rawdata_real = reshape(reinterpret(Float64, vec(aqData.kdata)), (2,size(aqData.kdata)...))
    write(file, "/rawdata", rawdata_real)

  end
end

function convertIBIFile(fileIn::AbstractString, fileOut::AbstractString)
  f = MRIFileIBI(fileIn)
  kdata = rawdata(f)
  seq = sequence(f)
  numEchoes = h5read(f.filename, "sequence/numEchoes")
  numCoils = h5read(f.filename, "numCoils")
  numSlices = h5read(f.filename, "numSlices")
  samplingIdx = h5read(f.filename, "samplingIdx")
  numSamplesPerShot = length(kdata)/(numEchoes*numCoils*numSlices)
  samplePointer = collect(1:numSamplesPerShot:length(kdata)-numSamplesPerShot+1)

  aqData = AcquisitionData(seq, vec(kdata), numEchoes, numCoils, numSlices
                          , samplePointer, samplingIdx)

  saveasIBIFile(fileOut, aqData)

  return aqData
end

function loadIBIFile(filename::AbstractString)
  acq = acquisitionData(MRIFileIBI(filename))
  return acq
end

# The follwing are helper functions that allow to store an entire Dict
# in an HDF5 file and load it.

export loadParams, saveParams

function saveParams(filename::AbstractString, path, params::Dict)
  h5open(filename, "w") do file
    saveParams(file, path, params)
  end
end

function saveParams(file, path, params::Dict)
  for (key,value) in params
    ppath = joinpath(path,string(key))
    if typeof(value) <: Bool
      write(file, ppath, UInt8(value))
      dset = file[ppath]
      attrs(dset)["isbool"] = "true"
    elseif typeof(value) <: Range
      write(file, ppath, [first(value),step(value),last(value)])
      dset = file[ppath]
      attrs(dset)["isrange"] = "true"
    elseif value == nothing
      write(file, ppath, "")
      dset = file[ppath]
      attrs(dset)["isnothing"] = "true"
    elseif typeof(value) <: Array{Any}
      write(file, ppath, [v for v in value])
    elseif typeof(value) <: Tuple
      write(file, ppath, [v for v in value])
      dset = file[ppath]
      attrs(dset)["istuple"] = "true"
    elseif typeof(value) <: AbstractLinearOperator
      continue
    else
      write(file, ppath, value)
    end
  end
end

function loadParams(filename::AbstractString, path)
  params = h5open(filename, "r") do file
   loadParams(file, path)
 end
  return params
end

function loadParams(file, path)
  params = Dict{Symbol,Any}()

  g = file[path]
  for obj in g
    key = last(splitdir(HDF5.name(obj)))
    data = read(obj)
    attr = attrs(obj)
    if exists(attr, "isbool")
      params[Symbol(key)] = Bool(data)
    elseif exists(attr, "isrange")
      if data[2] == 1
        params[Symbol(key)] = data[1]:data[3]
      else
        params[Symbol(key)] = data[1]:data[2]:data[3]
      end
    elseif exists(attr, "isnothing")
       params[Symbol(key)] = nothing
    elseif exists(attr, "istuple")
      params[Symbol(key)] = Tuple(data)
    else
      params[Symbol(key)] = data
    end
  end

  return params
end