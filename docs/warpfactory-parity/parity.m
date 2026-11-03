% PARITY.M  Reference numbers from the original WarpFactory MATLAB toolkit
% (NerdsWithAttitudes/WarpFactory, MIT, commit 03b10cb), run in GNU Octave,
% for parity checks of a port. This script reports numbers only.
%
% Run:   WARPFACTORY=/path/to/WarpFactory octave-cli --no-gui docs/warpfactory-parity/parity.m
% Output: docs/warpfactory-parity/reference.txt (overwritten on every run)
% Override the WarpFactory location with the environment variable WARPFACTORY.
%
% Path order: addpath(genpath(warpfactory)) first, then addpath(shims), so the
% files in shims/ shadow the upstream files of the same name.
%
% ---------------------------------------------------------------------------
% FILE FORMAT of reference.txt
% ---------------------------------------------------------------------------
% One value per line, no header, no comment lines:
%     NAME i1 i2 ... iN VALUE
% All indices are 1-based (MATLAB indexing). VALUE is printed with '%.17g'
% (round-trips an IEEE double). Point indices (t x y z) index the 4-D grid
% arrays as array(t, x, y, z). Tensor components (mu nu) index
% tensor{mu, nu}, with 1 = t, 2 = x, 3 = y, 4 = z.
% The lines appear in the order of the list below.
%
% Constants: c = c() = 299792458, G = G() = 6.67430e-11 (WarpFactory Units).
%
% ---------------------------------------------------------------------------
% NAMES
% ---------------------------------------------------------------------------
% Case A: metricGet_AlcubierreComoving(gridSize=[1 9 9 9], worldCenter=(gridSize+1)/2.*gridScale,
%         v=0.5, R=2, sigma=1.5, gridScale=[1/c 1 1 1]).  P_A = (1,5,7,4), (1,6,5,5), (1,3,4,6).
%   A.g        t x y z mu nu VALUE  metric.tensor{mu,nu}, (mu,nu) in {(1,1),(1,2)}, at P_A.
%   A.E4       t x y z mu nu VALUE  getEnergyTensor(metric,0,'fourth').tensor{mu,nu}, all 16, at P_A.
%   A.E2       t x y z mu nu VALUE  getEnergyTensor(metric,0,'second').tensor{mu,nu}, all 16, at P_A.
%   A.EUL      t x y z mu nu VALUE  doFrameTransfer(metric,E4,"Eulerian",0).tensor{mu,nu}, all 16, at P_A.
%   A.NULL     t x y z VALUE        getEnergyConditions(E4,metric,"Null",10,3,0,0) map, at P_A.
%   A.WEAK     t x y z VALUE        same with "Weak".
%   A.STRONG   t x y z VALUE        same with "Strong".
%   A.DOMINANT t x y z VALUE        same with "Dominant".
%   A.NULLVEC  t x y z ii VALUE     [map,vec,field] = getEnergyConditions(E4,metric,"Null",10,3,1,0);
%                                   vec(t,x,y,z,ii) for direction ii = 1..10 at (1,5,7,4).
%                                   Upstream allocates vec as a x b x c x d x 10 x 3; the Null
%                                   branch writes vec(:,:,:,:,ii), which is vec(...,ii,1). The
%                                   slices vec(...,:,2) and vec(...,:,3) stay zero; they are not listed.
%   A.FIELD    row col VALUE        the Null vector field "field" (4 x 10), field(row,col).
%   A.WEAKVEC  t x y z ii jj VALUE  [map,vec,field] = getEnergyConditions(E4,metric,"Weak",10,3,1,0);
%                                   vec(t,x,y,z,ii,jj), direction ii = 1..10, shell jj = 1..3, at (1,5,7,4).
%   A.WEAKFIELD row col shell VALUE the Weak vector field (4 x 10 x 3), field(row,col,shell).
%   A.SCAL     t x y z k VALUE      [theta,shear,vort] = getScalars(metric) at P_A;
%                                   k = 1 expansion theta, k = 2 shear, k = 3 vorticity.
%   A.FLOW42   row col VALUE        paths = getMomentumFlowLines(E4,{4.5,5.2,5.0},1,20,1e-42);
%                                   paths{1}(row,col), col = 1 x, 2 y, 3 z (grid-index units).
%   A.FLOW41   row col VALUE        the same with scale 1e-41. Written ONLY when the 1e-42 line
%                                   leaves at once or barely moves (fewer than 3 rows, or a total
%                                   displacement below 0.5 grid cells).
%
% Case B: metricGet_Alcubierre(gridSize=[5 9 9 9], worldCenter=(gridSize+1)/2.*gridScale,
%         v=0.5, R=2, sigma=1.5, gridScale=[1/c 1 1 1]).
%   B.g        t x y z 1 2 VALUE    metric.tensor{1,2} at (3,5,7,4) and (1,5,7,4).
%   B.E4       t x y z mu nu VALUE  getEnergyTensor(metric,0,'fourth'), all 16, at (3,5,7,4) and (3,6,5,5).
%   B.EUL      t x y z mu nu VALUE  doFrameTransfer(metric,E4,"Eulerian",0), all 16, at the same points.
%
% Case C: metricGet_Schwarzschild(gridSize=[1 9 9 9], worldCenter=[1 5.3 5.2 5.1], rs=0.5,
%         gridScaling=[1 1 1 1]).
%   C.g        t x y z mu nu VALUE  all 16 at (1,7,6,5).
%   C.E4       t x y z mu nu VALUE  getEnergyTensor(metric,0,'fourth'), all 16, at (1,7,6,5) and (1,3,4,6).
%
% Case D: metricGet_LentzComoving(gridSize=[1 9 9 9], worldCenter as A, v=0.1, scale=2,
%         gridScale=[1/c 1 1 1]).
%   D.g        t x y z mu nu VALUE  tensor{1,2} and tensor{1,3} at every (1,x,y,5), x = 1..9, y = 1..9
%                                   (loop order: x outer, y inner, then {1,2} before {1,3}).
%   D.E4       t x y z mu nu VALUE  getEnergyTensor(metric,0,'fourth'), all 16, at (1,5,6,5).
%
% Case E: metricGet_VanDenBroeckComoving(gridSize=[1 9 9 9], worldCenter as A, v=0.1, R1=1,
%         sigma1=2, R2=3, sigma2=1, A=0.5, gridScale=[1/c 1 1 1]).
%   E.g        t x y z mu nu VALUE  all 16 at (1,5,5,5) and (1,6,7,4).
%   E.E4       t x y z mu nu VALUE  getEnergyTensor(metric,0,'fourth'), all 16, at (1,6,7,4).
%
% Case F: metricGet_WarpShellComoving(gridSize=[1 24 5 5], worldCenter=[0 -2 3 3], m=R2/(2*G)*c^2/3,
%         R1=10, R2=20, Rbuff=0, sigma=0, smoothFactor=1, vWarp=0.02, doWarp=1,
%         gridScaling=[1/(1000*c) 1 1 1]).
%   F.g        t x y z mu nu VALUE  all 16 at (1,13,3,3), (1,3,3,3), (1,20,4,2).
%   F.E4       t x y z mu nu VALUE  getEnergyTensor(metric,0,'fourth'), all 16, at (1,13,3,3).
%   F.EUL      t x y z mu nu VALUE  doFrameTransfer(metric,E4,"Eulerian",0), all 16, at (1,13,3,3).
%
% Case F2: as F but Rbuff=1, sigma=0.5.
%   F2.g       t x y z 1 2 VALUE    tensor{1,2} at (1,3,3,3), (1,9,3,3), (1,19,3,3).
%
% Component loops "all 16" run mu = 1..4 outer, nu = 1..4 inner; point loops are outermost.
% A case that errors is reported on stderr as "CASE <X> FAILED: <message>" and the script
% continues with the next case; its lines are then missing from reference.txt.
%
% NOTES on reading the values
% - "-0" is a genuine IEEE negative zero (from sign flips such as T^{0i} = -T_{0i} in
%   doFrameTransfer, or sign(y)*0 in the Lentz template). Compare it equal to 0.
% - Some nonzero entries are round-off of an analytic zero, at 1e-18..1e-16 of the largest
%   |component| at the same point: A.E4/A.E2/A.EUL and B.E4 {1,1} at (.,6,5,5) (on the
%   bubble axis), and F.E4/F.EUL {1,4},{4,1},{2,4},{4,2} at (1,13,3,3). Compare these with
%   an absolute tolerance scaled by the point's largest component, not a relative one.
% - Case F/F2 depend at the last-bit level on linspace(). Octave 8 builds linspace
%   symmetrically from both ends; MATLAB uses d1 + (0:n-1).*(d2-d1)./(n-1). With the
%   MATLAB formula, F.g moves by <= 6e-15 absolute and F.E4 by <= 5e-13 of the largest
%   component at (1,13,3,3); the round-off entries listed above change completely.
% ---------------------------------------------------------------------------

1;  % script file marker (the helper functions below are script-local)

function emitT(fid, name, T, pts, comps)
% Write T{mu,nu}(t,x,y,z) for each point (row of pts) and component (row of comps).
for p = 1:size(pts, 1)
    q = pts(p, :);
    for k = 1:size(comps, 1)
        mu = comps(k, 1); nu = comps(k, 2);
        v = T{mu, nu}(q(1), q(2), q(3), q(4));
        emitV(fid, name, [q, mu, nu], v);
    end
end
end

function emitS(fid, name, S, pts)
% Write the scalar field S(t,x,y,z) at each point (row of pts).
for p = 1:size(pts, 1)
    q = pts(p, :);
    emitV(fid, name, q, S(q(1), q(2), q(3), q(4)));
end
end

function emitV(fid, name, idx, v)
% Write one line: name, 1-based indices, value with %.17g.
if ~isscalar(v)
    error('emitV: %s value is not a scalar', name);
end
if ~isreal(v)
    error('emitV: %s value at [%s] is complex (%g%+gi)', name, num2str(idx), real(v), imag(v));
end
fprintf(fid, '%s', name);
fprintf(fid, ' %d', idx);
fprintf(fid, ' %.17g\n', double(v));
end

function C = all16()
[nu, mu] = meshgrid(1:4, 1:4);
C = [reshape(mu.', [], 1), reshape(nu.', [], 1)];
end

% ---------------------------------------------------------------------------
here = fileparts(mfilename('fullpath'));
if isempty(here)
    here = pwd;
end
warpfactory = getenv('WARPFACTORY');
if isempty(warpfactory)
    error('Set WARPFACTORY to a clone of WarpFactory at commit 03b10cb');
end
shims = fullfile(here, 'shims');
addpath(genpath(warpfactory));
addpath(shims);   % prepended last, so shims win

outFile = fullfile(here, 'reference.txt');
fid = fopen(outFile, 'w');
if fid < 0
    error('cannot open %s for writing', outFile);
end

cc = c();   % 299792458
GG = G();   % 6.67430e-11
C16 = all16();
failed = {};

% ---------------------------------------------------------------- Case A
try
    gridSize = [1 9 9 9];
    gridScale = [1/cc 1 1 1];
    worldCenter = (gridSize + 1) / 2 .* gridScale;
    metric = metricGet_AlcubierreComoving(gridSize, worldCenter, 0.5, 2, 1.5, gridScale);
    PA = [1 5 7 4; 1 6 5 5; 1 3 4 6];
    emitT(fid, 'A.g', metric.tensor, PA, [1 1; 1 2]);

    E4 = getEnergyTensor(metric, 0, 'fourth');
    emitT(fid, 'A.E4', E4.tensor, PA, C16);

    E2 = getEnergyTensor(metric, 0, 'second');
    emitT(fid, 'A.E2', E2.tensor, PA, C16);

    Eul = doFrameTransfer(metric, E4, "Eulerian", 0);
    emitT(fid, 'A.EUL', Eul.tensor, PA, C16);

    condNames = {'Null', 'Weak', 'Strong', 'Dominant'};
    condTags = {'A.NULL', 'A.WEAK', 'A.STRONG', 'A.DOMINANT'};
    for k = 1:4
        map = getEnergyConditions(E4, metric, condNames{k}, 10, 3, 0, 0);
        emitS(fid, condTags{k}, map, PA);
    end

    P0 = [1 5 7 4];
    [~, vec, field] = getEnergyConditions(E4, metric, "Null", 10, 3, 1, 0);
    for ii = 1:10
        emitV(fid, 'A.NULLVEC', [P0, ii], vec(P0(1), P0(2), P0(3), P0(4), ii));
    end
    for row = 1:size(field, 1)
        for col = 1:size(field, 2)
            emitV(fid, 'A.FIELD', [row, col], field(row, col));
        end
    end

    [~, vec, field] = getEnergyConditions(E4, metric, "Weak", 10, 3, 1, 0);
    for ii = 1:10
        for jj = 1:3
            emitV(fid, 'A.WEAKVEC', [P0, ii, jj], vec(P0(1), P0(2), P0(3), P0(4), ii, jj));
        end
    end
    for row = 1:size(field, 1)
        for col = 1:size(field, 2)
            for sh = 1:size(field, 3)
                emitV(fid, 'A.WEAKFIELD', [row, col, sh], field(row, col, sh));
            end
        end
    end

    [theta, shear, vort] = getScalars(metric);
    scal = {theta, shear, vort};
    for p = 1:size(PA, 1)
        q = PA(p, :);
        for k = 1:3
            emitV(fid, 'A.SCAL', [q, k], scal{k}(q(1), q(2), q(3), q(4)));
        end
    end

    paths = getMomentumFlowLines(E4, {4.5, 5.2, 5.0}, 1, 20, 1e-42);
    P = paths{1};
    for row = 1:size(P, 1)
        for col = 1:3
            emitV(fid, 'A.FLOW42', [row, col], P(row, col));
        end
    end
    if size(P, 1) < 3 || norm(P(end, :) - P(1, :)) < 0.5
        paths = getMomentumFlowLines(E4, {4.5, 5.2, 5.0}, 1, 20, 1e-41);
        P = paths{1};
        for row = 1:size(P, 1)
            for col = 1:3
                emitV(fid, 'A.FLOW41', [row, col], P(row, col));
            end
        end
    end
catch err
    failed{end+1} = 'A';
    fprintf(2, 'CASE A FAILED: %s\n', err.message);
end

% ---------------------------------------------------------------- Case B
try
    gridSize = [5 9 9 9];
    gridScale = [1/cc 1 1 1];
    worldCenter = (gridSize + 1) / 2 .* gridScale;
    metric = metricGet_Alcubierre(gridSize, worldCenter, 0.5, 2, 1.5, gridScale);
    emitT(fid, 'B.g', metric.tensor, [3 5 7 4; 1 5 7 4], [1 2]);
    PB = [3 5 7 4; 3 6 5 5];
    E4 = getEnergyTensor(metric, 0, 'fourth');
    emitT(fid, 'B.E4', E4.tensor, PB, C16);
    Eul = doFrameTransfer(metric, E4, "Eulerian", 0);
    emitT(fid, 'B.EUL', Eul.tensor, PB, C16);
catch err
    failed{end+1} = 'B';
    fprintf(2, 'CASE B FAILED: %s\n', err.message);
end

% ---------------------------------------------------------------- Case C
try
    metric = metricGet_Schwarzschild([1 9 9 9], [1 5.3 5.2 5.1], 0.5, [1 1 1 1]);
    emitT(fid, 'C.g', metric.tensor, [1 7 6 5], C16);
    E4 = getEnergyTensor(metric, 0, 'fourth');
    emitT(fid, 'C.E4', E4.tensor, [1 7 6 5; 1 3 4 6], C16);
catch err
    failed{end+1} = 'C';
    fprintf(2, 'CASE C FAILED: %s\n', err.message);
end

% ---------------------------------------------------------------- Case D
try
    gridSize = [1 9 9 9];
    gridScale = [1/cc 1 1 1];
    worldCenter = (gridSize + 1) / 2 .* gridScale;
    metric = metricGet_LentzComoving(gridSize, worldCenter, 0.1, 2, gridScale);
    for x = 1:9
        for y = 1:9
            emitT(fid, 'D.g', metric.tensor, [1 x y 5], [1 2; 1 3]);
        end
    end
    E4 = getEnergyTensor(metric, 0, 'fourth');
    emitT(fid, 'D.E4', E4.tensor, [1 5 6 5], C16);
catch err
    failed{end+1} = 'D';
    fprintf(2, 'CASE D FAILED: %s\n', err.message);
end

% ---------------------------------------------------------------- Case E
try
    gridSize = [1 9 9 9];
    gridScale = [1/cc 1 1 1];
    worldCenter = (gridSize + 1) / 2 .* gridScale;
    metric = metricGet_VanDenBroeckComoving(gridSize, worldCenter, 0.1, 1, 2, 3, 1, 0.5, gridScale);
    emitT(fid, 'E.g', metric.tensor, [1 5 5 5; 1 6 7 4], C16);
    E4 = getEnergyTensor(metric, 0, 'fourth');
    emitT(fid, 'E.E4', E4.tensor, [1 6 7 4], C16);
catch err
    failed{end+1} = 'E';
    fprintf(2, 'CASE E FAILED: %s\n', err.message);
end

% ---------------------------------------------------------------- Case F
gridSizeF = [1 24 5 5];
gridScalingF = [1/(1000*cc) 1 1 1];
worldCenterF = [0 -2 3 3];
R1 = 10; R2 = 20;
mF = R2 / (2*GG) * cc^2 / 3;
try
    metric = metricGet_WarpShellComoving(gridSizeF, worldCenterF, mF, R1, R2, 0, 0, 1, 0.02, 1, gridScalingF);
    emitT(fid, 'F.g', metric.tensor, [1 13 3 3; 1 3 3 3; 1 20 4 2], C16);
    E4 = getEnergyTensor(metric, 0, 'fourth');
    emitT(fid, 'F.E4', E4.tensor, [1 13 3 3], C16);
    Eul = doFrameTransfer(metric, E4, "Eulerian", 0);
    emitT(fid, 'F.EUL', Eul.tensor, [1 13 3 3], C16);
catch err
    failed{end+1} = 'F';
    fprintf(2, 'CASE F FAILED: %s\n', err.message);
end

% ---------------------------------------------------------------- Case F2
try
    metric = metricGet_WarpShellComoving(gridSizeF, worldCenterF, mF, R1, R2, 1, 0.5, 1, 0.02, 1, gridScalingF);
    emitT(fid, 'F2.g', metric.tensor, [1 3 3 3; 1 9 3 3; 1 19 3 3], [1 2]);
catch err
    failed{end+1} = 'F2';
    fprintf(2, 'CASE F2 FAILED: %s\n', err.message);
end

fclose(fid);
if isempty(failed)
    fprintf('parity.m: all cases ran; wrote %s\n', outFile);
else
    fprintf('parity.m: FAILED cases: %s; wrote %s\n', strjoin(failed, ' '), outFile);
end
