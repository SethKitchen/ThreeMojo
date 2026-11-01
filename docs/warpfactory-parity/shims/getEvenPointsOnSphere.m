function [Vector] = getEvenPointsOnSphere(R,numberOfPoints,useGPU)
% SHIM COPY of WarpFactory Analyzer/utils/getEvenPointsOnSphere.m (commit 03b10cb).
% Octave zeros() rejects the 'gpuArray' class name: zeros(3,n,'gpuArray') -> gpuArray(zeros(3,n)),
% where gpuArray is the identity shim. Note that generateUniformField always calls this with useGPU=1. Math unchanged.
%GETEVENPOINTSONSPHERE Summary of this function goes here
%   Detailed explanation goes here

if useGPU
    goldenRatio = gpuArray((1+5^0.5)/2);
    numberOfPoints = gpuArray(numberOfPoints);
    R = gpuArray(R);
    Vector = gpuArray(zeros(3,numberOfPoints));
else
    goldenRatio = (1+5^0.5)/2;
    Vector = zeros(3,numberOfPoints);
end

for i = 0:numberOfPoints-1
    theta = 2*pi*i/goldenRatio;
    phi = acos(1-2*(i+0.5)/numberOfPoints);

    Vector(1,i+1) = R*cos(theta)*sin(phi);
    Vector(2,i+1) = R*sin(theta)*sin(phi);
    Vector(3,i+1) = R*cos(phi);
end

Vector = real(Vector);
end

