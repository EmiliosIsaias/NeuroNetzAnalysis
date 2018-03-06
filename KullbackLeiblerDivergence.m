function kbd = KullbackLeiblerDivergence(P1,P2)
% KULLBACKLEIBLERDIVERGENCE returns the similarity measure between two
% probability distributions
if abs(sum(P1) - 1.0) > 1e-3
    P1 = P1/sum(P1);
end
if length(P1) == length(P2)
    N = length(P1);
    if abs(sum(P2) - 1) > 1e-3
        P2 = P2/sum(P2);
    end
else
    kbd = NaN;
    fprintf([],'! he distributions have different resolutions (different length)!\n')
    return;
end
kbd = dot(P1,log2(P1 ./ P2))/log2(N);
end