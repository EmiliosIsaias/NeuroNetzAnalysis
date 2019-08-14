function params_new = select_imp_params(params,I,S)
[imp,dnd]=sort(params(:,1),'ascend');
i = 1;
needToClean = true;
while sum(params(:,1)) >= S && needToClean
    lowStd = log10(params(:,3)) <...
        mean(log10(params(:,3))) - [3,2,1].*std(log10(params(:,3)));
    overFit = sum(lowStd,2)>=2;
    needToClean = any(overFit);
    params(overFit,:)=[];
    [imp,dnd] = sort(params(:,1),'ascend');
end
params_new = params;
params_new(:,1) = params(:,1)/sum(params(:,1));
end

