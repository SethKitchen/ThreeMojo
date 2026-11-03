function tf = isgpuarray(x)
% SHIM (Octave has no Parallel Computing Toolbox): no value is ever a gpuArray.
tf = false;
end
