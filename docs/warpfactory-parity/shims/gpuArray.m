function y = gpuArray(x)
% SHIM (Octave has no Parallel Computing Toolbox): identity, data stays on the CPU.
y = x;
end
