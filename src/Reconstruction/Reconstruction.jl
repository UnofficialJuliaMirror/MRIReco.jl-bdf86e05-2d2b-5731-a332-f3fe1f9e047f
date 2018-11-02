export reconstruction

################################################################################
include("DirectReconstruction.jl")
include("IterativeReconstruction.jl")
include("RecoParameters.jl")


#### Factory method ###
# dispatch on the different reconstructions and generate the correct
# reconstruction
function reconstruction(aqData::AcquisitionData, recoParams::Dict)
  recoParams = merge(defaultRecoParams(), recoParams)
  if recoParams[:reco] == "direct"
    return reconstruction_direct(aqData, recoParams)
  elseif recoParams[:reco] == "standard"
    return reconstruction_simple(aqData, recoParams)
  elseif recoParams[:reco] == "multiEcho"
    return reconstruction_multiEcho(aqData, recoParams)
  elseif recoParams[:reco] == "multiCoil"
    return reconstruction_multiCoil(aqData, recoParams)
  elseif recoParams[:reco] == "multiCoilMultiEcho"
    return reconstruction_multiCoilMultiEcho(aqData, recoParams)
  else
    error("RecoModel $(recoParams[:reco]) not found.")
  end
end

# This version stores the reconstructed data into a file
function reconstruction(aqData::AcquisitionData, recoParams::Dict, filename::String;
                        force=false)
  if !force && isfile(filename)
    return recoImage( RecoFileIBI(filename) )
  else
    I = reconstruction(aqData, recoParams)
    saveasRecoFile(filename, I, recoParams)
    return I
  end
end