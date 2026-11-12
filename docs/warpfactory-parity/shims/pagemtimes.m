function Z = pagemtimes(X, varargin)
% SHIM for MATLAB pagemtimes (Octave 8.4 lacks it; it arrived in Octave 9).
% Supports the call forms used by Analyzer/doFrameTransfer.m:
%   Z = pagemtimes(X, Y)
%   Z = pagemtimes(X, transpX, Y, transpY)   transp* in {'none','transpose','ctranspose'}
% Z(:,:,k) = op(X(:,:,k)) * op(Y(:,:,k)) for every page k. Page dimensions of X and Y
% must be equal or 1 (singleton page dimensions expand, as in MATLAB).
if numel(varargin) == 1
    tX = 'none'; Y = varargin{1}; tY = 'none';
elseif numel(varargin) == 3
    tX = varargin{1}; Y = varargin{2}; tY = varargin{3};
else
    error('pagemtimes shim: unsupported call form');
end
tX = lower(char(tX)); tY = lower(char(tY));
okT = {'none', 'transpose', 'ctranspose'};
if ~any(strcmp(tX, okT)) || ~any(strcmp(tY, okT))
    error('pagemtimes shim: transpose option must be none, transpose or ctranspose');
end
sx = size(X); sy = size(Y);
nd = max([numel(sx), numel(sy), 3]);
sx(end+1:nd) = 1; sy(end+1:nd) = 1;
px = sx(3:end); py = sy(3:end);
if any(px ~= py & px ~= 1 & py ~= 1)
    error('pagemtimes shim: page dimensions are not compatible');
end
pz = max(px, py);
if strcmp(tX, 'none'), rX = sx(1); cX = sx(2); else, rX = sx(2); cX = sx(1); end
if strcmp(tY, 'none'), rY = sy(1); cY = sy(2); else, rY = sy(2); cY = sy(1); end
if cX ~= rY
    error('pagemtimes shim: inner matrix dimensions do not agree');
end
np = prod(pz);
Xr = reshape(X, sx(1), sx(2), []);
Yr = reshape(Y, sy(1), sy(2), []);
Z = zeros(rX, cY, np);
for k = 1:np
    if isequal(px, pz), kx = k; else, kx = pageIndex(k, pz, px); end
    if isequal(py, pz), ky = k; else, ky = pageIndex(k, pz, py); end
    A = Xr(:, :, kx); B = Yr(:, :, ky);
    if strcmp(tX, 'transpose'), A = A.'; elseif strcmp(tX, 'ctranspose'), A = A'; end
    if strcmp(tY, 'transpose'), B = B.'; elseif strcmp(tY, 'ctranspose'), B = B'; end
    Z(:, :, k) = A * B;
end
Z = reshape(Z, [rX, cY, pz]);
end

function kk = pageIndex(k, pz, p)
% Map linear page k of the expanded page grid pz onto the page grid p (singletons fixed at 1).
r = k - 1; kk = 1; stride = 1;
for d = 1:numel(pz)
    s = mod(r, pz(d)); r = floor(r / pz(d));
    if p(d) == 1, s = 0; end
    kk = kk + s * stride;
    stride = stride * p(d);
end
end
