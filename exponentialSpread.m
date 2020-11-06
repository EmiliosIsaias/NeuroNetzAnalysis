function [mdls, r2, qVals, qDiff] =...
    exponentialSpread(signMat, tx, tmWin)
%EXPONENTIALSPREAD measures where 50% of the data is sitting in a
%semi-poisson distribution and the exponential decay of the 1 - cumulative
%sum of the given signals.
%   Detailed explanation goes here
Ns = size(signMat,1);
wIdx = tx >= tmWin(1) & tx <= tmWin(2);
shTx = reshape(tx(wIdx), sum(wIdx), 1);
wSum = sum(signMat(:,wIdx),2); zSum = wSum ~= 0;
if ~all(zSum)
    warning(['Some clusters have no spikes between ',num2str(tmWin(1)*1e3),...
        ' and ', num2str(tmWin(2)*1e3),' ms relative to the trigger'])
    wSum(~zSum) = 1;
end
ics = double(1 - cumsum(signMat(:,wIdx)./wSum,2));
% Quartile cuts
% quartCut = exp(-log([4/3, 2, exp(1), 4]))';
quartCut = [3;2;4*exp(-1);1]/4;
% Exponential analysis for the auto-correlograms
mdls = zeros(Ns,2); r2 = zeros(Ns,1); qVals = zeros(Ns,4);
for cis = 1:Ns
    % Exponential fit for the inverted cumsum
    [fitObj, gof] = fit(shTx, ics(cis,:)', 'exp1');
    mdls(cis,:) = coeffvalues(fitObj); r2(cis) = gof.rsquare;
    % Quartiles cut for exponential distribution (25, 50, 63.21, 75)
    quartFlags = ics(cis,:) >= quartCut;
    [qSubs, ~] = find(diff(quartFlags'));
    il = arrayfun(@(x) fit_poly(shTx(x:x+1), ics(cis,x:x+1), 1), qSubs,...
        'UniformOutput', 0);il = cat(2,il{:});
    if isempty(il)
        continue
    end
    qVals(cis,:) = (quartCut' - il(2,:))./il(1,:);
end
qDiff = diff(qVals(:,[1,4]),1,2);
end

% Quartile values extracted from Richard Arnold Johnson; Dean W. Wichern
% (2007). Applied Multivariate Statistical Analysis. Pearson Prentice Hall.
% ISBN 978-0-13-187715-3.