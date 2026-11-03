function c = smooth(y, span)
% SHIM for MATLAB Curve Fitting Toolbox smooth(y, span), default 'moving' method.
% Only the case floor(span) <= 2 is implemented. MATLAB's moving() computes
% width = floor(span)-1+mod(floor(span),2); width == 1 returns the data unchanged.
% MATLAB's smooth always returns a COLUMN vector (it does y = y(:) first), and
% WarpFactory relies on that (it transposes the result back to a row).
% Any other case raises an error so it cannot pass silently.
if nargin ~= 2
    error('smooth shim: only smooth(y, span) is implemented');
end
if ~isscalar(span) || span < 1
    error('smooth shim: span < 1 (fraction-of-data convention) is not implemented');
end
if floor(span) > 2
    error('smooth shim: floor(span) = %d > 2 is not implemented', floor(span));
end
c = y(:);
end
