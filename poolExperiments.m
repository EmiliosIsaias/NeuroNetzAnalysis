clearvars
%% Experiment pooling
% Experiment folder search
experimentDir = uigetdir('Z:\Jesus\LTP_Jesus_Emilio',...
    'Select an experiment directory');
if experimentDir == 0
    return
end
% Folders existing in the selected directory
expFolders = dir(experimentDir);
expFolders(1:2) = [];
folderNames = arrayfun(@(x) x.name, expFolders, 'UniformOutput', 0);
folderFlag = arrayfun(@(x) x.isdir, expFolders);
% Selection of the considered experiments
[fSel, iOk] = listdlg('ListString', folderNames(folderFlag),...
    'InitialValue', 1:nnz(folderFlag),...
    'PromptString', 'Select the experiments to consider:',...
    'SelectionMode', 'multiple', 'ListSize', [350, (nnz(folderFlag))*16]);
if ~iOk
    fprintf(1, 'Cancelling...\n');
    return
end
folderSub = find(folderFlag);
chExp = folderSub(fSel);
Nexp = numel(chExp);
% Auxiliary variable for the phy multiple updates
phyNames = ["ch","channel";...
    "sh", "shank";...
    "fr", "firing_rate"];
% Function for performing ONLY autocorrelograms
corrWin = 0.05;

%% User controlling variables
% Time lapse, bin size, and spontaneous and response windows
promptStrings = {'Viewing window (time lapse) [s]:','Response window [s]',...
    'Bin size [s]:'};
defInputs = {'-0.1, 0.1', '0.002, 0.05', '0.001'};
answ = inputdlg(promptStrings,'Inputs', [1, 30],defInputs);
if isempty(answ)
    fprintf(1,'Cancelling...\n')
    return
else
    timeLapse = str2num(answ{1}); %#ok<*ST2NM>
    if numel(timeLapse) ~= 2
        timeLapse = str2num(inputdlg('Please provide the time window [s]:',...
            'Time window',[1, 30], '-0.1, 0.1'));
        if isnan(timeLapse) || isempty(timeLapse)
            fprintf(1,'Cancelling...')
            return
        end
    end
    responseWindow = str2num(answ{2});
    binSz = str2double(answ(3));
end
fprintf(1,'Time window: %.2f - %.2f ms\n',timeLapse(1)*1e3, timeLapse(2)*1e3)
fprintf(1,'Response window: %.2f - %.2f ms\n',responseWindow(1)*1e3, responseWindow(2)*1e3)
fprintf(1,'Bin size: %.3f ms\n', binSz*1e3)
sponAns = questdlg('Mirror the spontaneous window?','Spontaneous window',...
    'Yes','No','Yes');
spontaneousWindow = -flip(responseWindow);
if strcmpi(sponAns,'No')
    spontPrompt = "Time before the trigger in [s] (e.g. -0.8, -0.6 s)";
    sponDef = string(sprintf('%.3f, %.3f',spontaneousWindow(1),...
        spontaneousWindow(2)));
    sponStr = inputdlg(spontPrompt, 'Inputs',[1,30],sponDef);
    if ~isempty(sponStr)
        spontAux = str2num(sponStr{1});
        if length(spontAux) ~= 2 || spontAux(1) > spontAux(2) || ...
                spontAux(1) < timeLapse(1)
            fprintf(1, 'The given input was not valid.\n')
            fprintf(1, 'Keeping the mirror version!\n')
        else
            spontaneousWindow = spontAux;
        end
    end
end
fprintf(1,'Spontaneous window: %.2f to %.2f ms before the trigger\n',...
    spontaneousWindow(1)*1e3, spontaneousWindow(2)*1e3)
statFigFileNameEndings = {'.pdf','.emf'};
printOpts = {{'-dpdf','-fillpage'},'-dmeta'};

cellLogicalIndexing = @(x,idx) x(idx);

expCo = 1;
%% Experiment loop
% For all the chosen experiments, perform the statistical test and save its
% results, and extract the spike times for all clusters blending in the
% trial information for a PDF calculation
relativeSpikeTimes = cell(Nexp);
for cexp = reshape(chExp, 1, [])
    dataDir = fullfile(expFolders(cexp).folder, expFolders(cexp).name);
    foldContents = dir(dataDir); foldContents(1:2) = [];
    contNames = arrayfun(@(x) x.name, foldContents, 'UniformOutput', 0);
    [~,~,fext] = cellfun(@fileparts, contNames, 'UniformOutput', 0);
    ksPhyFlags = cell2mat(cellfun(@(x) strcmpi(x,{'.npy','.tsv','.py'}),...
        fext, 'UniformOutput', 0));
    dirNames = contNames([foldContents.isdir]);
    if ~any(ksPhyFlags(:))
        if ~isempty(dirNames)
            [subFoldSel, iOk] = listdlg(...
                'ListString', dirNames,...
                'SelectionMode', 'single',...
                'Name', 'Select the experiment folder:',...
                'CancelString', 'Skip');
            if ~iOk
                fprintf(1, 'Skipping experiment %s', expFolders(cexp).name);
                continue
            end
            dataDir = fullfile(dataDir, dirNames{subFoldSel});
        else
            fprintf(1,'This experiment hasn''t been spike-sorted!\n')
            fprintf(1,'Skipping experiment %s\n', expFolders(cexp).name)
            continue
        end
    end
    if ~loadTriggerData(dataDir)
        fprintf(1,'Skipping experiment %s\n', expFolders(cexp).name)
        continue
    end
    %{
    % Figures directory for the considered experiment
    figureDir = fullfile(dataDir,'Figures\');
    if ~mkdir(figureDir)
        fprintf(1,'There was an issue with the figure folder...\n');
        fprintf(1,'Saving the figures in the data folder!\n');
        fprintf(1,'%s\n',dataDir);
        figureDir = dataDir;
    end
    %}
    %% Constructing the helper 'global' variables
    % Number of total samples
    Ns = structfun(@numel,Triggers);
    Ns = min(Ns(Ns>1));
    % Total duration of the recording
    Nt = Ns/fs;
    autoCorr = @(x) neuroCorr(x, corrWin, 1, fs);
    % Useless clusters (labeled as noise or they have very low firing rate)
    badsIdx = cellfun(@(x) x==3,sortedData(:,3));
    bads = find(badsIdx);
    totSpkCount = cellfun(@numel,sortedData(:,2));
    clusterSpikeRate = totSpkCount/Nt;
    silentUnits = clusterSpikeRate < 0.1;
    bads = union(bads,find(silentUnits));
    goods = setdiff(1:size(sortedData,1),bads);
    badsIdx = badsIdx | silentUnits;
    if ~any(ismember(clInfo.Properties.VariableNames,'ActiveUnit'))
        try
            clInfo = addvars(clInfo,~badsIdx,'After','id',...
                'NewVariableNames','ActiveUnit');
        catch
            clInfo = addvars(clInfo,false(size(clInfo,1),1),'After','id',...
                'NewVariableNames','ActiveUnit');
            clInfo{sortedData(~badsIdx,1),'ActiveUnit'} = true;
            fprintf(1,'Not all clusters are curated!\n')
            fprintf(1,'%s\n',dataDir)
        end
        try
            writeClusterInfo(clInfo,fullfile(dataDir,'cluster_info.tsv'),true);
        catch
            fprintf(1,'Unable to write cluster info for %s\n',dataDir)
        end
    end
    gclID = sortedData(goods,1);
    % Logical spike trace for the first good cluster
    spkLog = StepWaveform.subs2idx(round(sortedData{goods(1),2}*fs),Ns);
    % Subscript column vectors for the rest good clusters
    spkSubs = cellfun(@(x) round(x.*fs),sortedData(goods(2:end),2),...
        'UniformOutput',false);
    % Number of good clusters
    Ncl = numel(goods);
    % Redefining the stimulus signals from the low amplitude to logical values
    whStim = {'piezo','whisker','mech','audio'};
    cxStim = {'laser','light'};
    lfpRec = {'lfp','s1','cortex','s1lfp'};
    trigNames = fieldnames(Triggers);
    numTrigNames = numel(trigNames);
    continuousSignals = struct2cell(Triggers);
    % User defined conditions variables if not already chosen
    if ~exist('chCond','var')
        Nt = round(sum(ceil(abs(timeLapse)*fs))+1);
        % Computing the time axis for the stack
        tx = (0:Nt - 1)/fs + timeLapse(1);
        %% Condition triggered stacks
        condNames = arrayfun(@(x) x.name,Conditions,'UniformOutput',false);
        condGuess = contains(condNames, 'whiskerall', 'IgnoreCase', true);
        % Choose the conditions to create the stack upon
        [chCond, iOk] = listdlg('ListString',condNames,'SelectionMode','single',...
            'PromptString',...
            'Choose the condition which has all whisker triggers: (one condition)',...
            'InitialValue', find(condGuess), 'ListSize', [350, numel(condNames)*16]);
        if ~iOk
            fprintf(1,'Cancelling...\n')
            return
        end
        
        % Select the onset or the offset of a trigger
        fprintf(1,'Condition ''%s''\n', Conditions(chCond).name)
        onOffStr = questdlg('Trigger on the onset or on the offset?','Onset/Offset',...
            'on','off','Cancel','on');
        if strcmpi(onOffStr,'Cancel')
            fprintf(1,'Cancelling...\n')
            return
        end
        
        %% Considered conditions selection
        % Choose the conditions to look at
        auxSubs = setdiff(1:numel(condNames), chCond);
        ccondNames = condNames(auxSubs);
        [cchCond, iOk] = listdlg('ListString',ccondNames,'SelectionMode','multiple',...
            'PromptString',...
            'Choose the condition(s) to look at (including whiskers):',...
            'ListSize', [350, numel(condNames)*16]);
        if ~iOk
            fprintf(1,'Cancelling...\n')
            return
        end
        
        % Select the onset or the offset of a trigger
        fprintf(1,'Condition(s):\n')
        fprintf('- ''%s''\n', Conditions(auxSubs(cchCond)).name)
        
        ansFilt = questdlg('Would you like to filter for significance?','Filter',...
            'Yes','No','Yes');
        filtStr = 'unfiltered';
        if strcmp(ansFilt,'Yes')
            filtStr = 'filtered';
        end
        % Subscript to indicate the conditions with all whisker stimulations,
        % whisker control, laser control, and the combination whisker and laser.
        consideredConditions = auxSubs(cchCond);
        Nccond = length(consideredConditions);
        
        % Select the onset or the offset of a trigger
        fprintf(1,'Condition(s):\n')
        fprintf('- ''%s''\n', Conditions(auxSubs(cchCond)).name)
        % Subscripts and names for the considered conditions
        consCondNames = condNames(consideredConditions);
        
        % Time windows for comparison between conditions and activity
        sponActStackIdx = tx >= spontaneousWindow(1) & tx <= spontaneousWindow(2);
        respActStackIdx = tx >= responseWindow(1) & tx <= responseWindow(2);
        % The spontaneous activity of all the clusters, which are allocated from
        % the second until one before the last row, during the defined spontaneous
        % time window, and the whisker control condition.
        
        timeFlags = [sponActStackIdx; respActStackIdx];
        % Time window
        delta_t = diff(responseWindow);
        % Spontaneous vs evoked comparison
        indCondSubs = cumsum(Nccond:-1:1);
        isWithinResponsiveWindow =...
            @(x) x > responseWindow(1) & x < responseWindow(2);
    end
    
    % Constructing the stack out of the user's choice
    % discStack - dicrete stack has a logical nature
    % cst - continuous stack has a numerical nature
    % Both of these stacks have the same number of time samples and trigger
    % points. They differ only in the number of considered events.
    [auxDStack, auxCStack] = getStacks(spkLog, Conditions(chCond).Triggers,...
        onOffStr, timeLapse, fs, fs, spkSubs, continuousSignals);
    % Number of clusters + the piezo as the first event + the laser as the last
    % event, number of time samples in between the time window, and number of
    % total triggers.
    [Ne, Nt, NTa] = size(auxDStack);
    
    % Computing which alignment points belong to which condition.
    auxDelayFlags = false(NTa,Nccond);
    counter2 = 1;
    for ccond = consideredConditions
        auxDelayFlags(:,counter2) = ismember(Conditions(chCond).Triggers(:,1),...
            Conditions(ccond).Triggers(:,1));
        counter2 = counter2 + 1;
    end
    NaNew = sum(auxDelayFlags,1);
    
    % All spikes in a cell format
    spkSubs = cat(1, {round(sortedData{goods(1),2}*fs)}, spkSubs);
    
    % Autocorrelation for all active units
    
    corrFileName = fullfile(dataDir, '*_ccorr.mat');
    corrFiles = dir(corrFileName); corrCorr =...
        arrayfun(@(x) contains(x.name, sprintf('%.2f', corrWin*1e3)),...
        corrFiles);
    if ~isempty(corrFiles) && any(corrCorr)
        load(fullfile(corrFiles(corrCorr).folder,corrFiles(corrCorr).name),...
            'corrs')
        eaCorr = cellfun(@(x) x(1,:), corrs, 'UniformOutput', 0);
    else
        eaCorr = arrayfun(autoCorr, spkSubs, 'UniformOutput', 0);
        eaCorr = cat(1, eaCorr{:});
    end
    eaCorr = cat(1, eaCorr{:});
    eaCorr = sparse(eaCorr);
%     % Computing the lag axis for the auto-correlograms
%     b = -ceil(Ncrs/2)/fs; corrTx = (1:Ncrs)'/fs + b;
    
    % Computing the firing rate during the different conditions
    NaCount = 1;
    % Experiment firing rate and ISI per considered condition
    efr = zeros(Ncl, size(consideredConditions,2), 'single');
    eisi = cellfun(@(x) diff(x), spkSubs, 'UniformOutput', 0);
    econdIsi = cell(Ncl, size(consideredConditions,2));
    for ccond = consideredConditions
        itiSub = mean(diff(Conditions(ccond).Triggers(:,1)));
        consTime = [Conditions(ccond).Triggers(1,1) - round(itiSub/2),...
            Conditions(ccond).Triggers(NaNew(NaCount),2) + round(itiSub/2)]...
            ./fs;
        [efr(:,NaCount),~, ~, econdIsi(:,NaCount)] =...
            getSpontFireFreq(spkSubs, Conditions(ccond).Triggers,...
            consTime, fs, delta_t + responseWindow(1));
        NaCount = NaCount + 1;
    end
    
    % Getting the clusters' waveforms
    sewf = getClusterWaveform(gclID, dataDir);
    sewf(:,1) = cellfun(@(x) [sprintf('%d_',cexp), x], sewf(:,1),...
        'UniformOutput', 0);
    mswf = cellfun(@(x) mean(x,2), sewf(:,2),'UniformOutput', 0);
    mswf = cat(2, mswf{:});
    cwID = sewf(:,1);
    %% Building the population stack
    % Removing not considered conditions
    if sum(NaNew) ~= NTa
        emtyRow = find(~sum(auxDelayFlags,2));
        auxDelayFlags(emtyRow,:) = [];
        auxDStack(:,:,emtyRow) = [];
        auxCStack(:,:,emtyRow) = [];
    end
    clInfo.id = cellfun(@(x) [sprintf('%d_',cexp), x], clInfo.id,...
        'UniformOutput', 0);
    clInfo.Properties.RowNames = clInfo.id;
    if cexp == chExp(1)
        % First assignment
        delayFlags = auxDelayFlags;
        discStack = auxDStack;
        cStack = auxCStack;
        clInfoTotal = clInfo;
        NaStack = NaNew;
        popClWf = mswf;
        pcwID = cwID;
        pfr = efr;
        pisi = eisi;
        paCorr = eaCorr;
        pcondIsi = econdIsi;
    else
        pfr = cat(1, pfr, efr);
        pisi = cat(1, pisi, eisi);
        paCorr = cat(1, paCorr, eaCorr);
        pcondIsi = cat(1, pcondIsi, econdIsi);
        popClWf = cat(2, popClWf, mswf);
        pcwID = cat(1, pcwID, cwID);
        % Homogenizing trial numbers
        if any(NaNew ~= NaStack)
            NaMin = min(NaStack, NaNew);
            NaMax = max(NaStack, NaNew);
            trigSubset = cell(numel(NaStack),1);
            for cc = 1:numel(NaStack)
                trigSubset{cc} = sort(randsample(NaMax(cc),NaMin(cc)));
                if NaStack(cc) == NaMin(cc)
                    tLoc = find(auxDelayFlags(:,cc));
                    tSubs = tLoc(trigSubset{cc});
                    auxDelayFlags(setdiff(tLoc,tSubs),:) = [];
                    auxDStack(:,:,setdiff(tLoc,tSubs)) = [];
                    auxCStack(:,:,setdiff(tLoc,tSubs)) = [];
                else
                    tLoc = find(delayFlags(:,cc));
                    tSubs = tLoc(trigSubset{cc});
                    delayFlags(setdiff(tLoc,tSubs),:) = [];
                    discStack(:,:,setdiff(tLoc,tSubs)) = [];
                    cStack(:,:,setdiff(tLoc,tSubs)) = [];
                    NaStack(cc) = NaNew(cc);
                end
            end
        end
        auxDStack(1,:,:) = [];
        discStack = cat(1, discStack, auxDStack);
        cStack = cat(1, cStack, auxCStack);
        %% Homogenizing the cluster information
        popVarNames = clInfoTotal.Properties.VariableNames;
        curVarNames = clInfo.Properties.VariableNames;
        Npv = numel(popVarNames); Ncv = numel(curVarNames);
        curInPopFlags = ismember(popVarNames, curVarNames);
        % Modifying the current cluster info to match the population table
        missingInCurSub = find(~curInPopFlags);
        missingNames = popVarNames(missingInCurSub);
        % Are the names which are missing a user addition or a phy update?
        for mn = missingNames
            addnv = true;
            phyFlag = contains(phyNames, mn, 'IgnoreCase', 1);
            if any(phyFlag(:)) % Is this name a phy update?
                addnv = false;
                varSub = (1:size(phyFlag,1))*any(phyFlag, 2); % Which variable
                phyVer = any(phyFlag, 1)*[-1;2];
                fprintf(1, 'Substitution of %s for %s\n',...
                    phyNames(varSub, 3-phyVer), phyNames(varSub, phyVer));
                posInCur = strcmp(curVarNames, phyNames(varSub, 3-phyVer));
                if any(posInCur)
                    clInfo.Properties.VariableNames(posInCur) =...
                        cellstr(phyNames(varSub, phyVer));
                else
                    fprintf(1, 'No substitution, rather ')
                    addnv = true;
                end
            end
            if addnv% or a user added variable
                fprintf(1, 'Adding %s to the current table\n', mn{1});
                tempTable = groupsummary(clInfoTotal, mn);
                [~, mstSub] = sortrows(tempTable, 'GroupCount', 'descend');
                fillVal = tempTable{mstSub(1),mn};
                clInfo = addvars(clInfo, repmat(fillVal, size(clInfo,1), 1),...
                    'NewVariableNames', mn);
            end
        end
        curVarNames = clInfo.Properties.VariableNames;
        [~, popInCurSubs] = ismember(popVarNames, curVarNames);
        % Modifying the population cluster info to match the current table
        missingInPopSubs = setdiff(1:Ncv, popInCurSubs);
        missingNames = curVarNames(missingInPopSubs);
        % I'm assuming that the missing variables are only user added
        % names.
        for mn = missingNames
            fprintf(1, 'Adding %s to the population table\n', mn{1});
            tempTable = groupsummary(clInfo, mn);
            [~, mstSub] = sortrows(tempTable, 'GroupCount', 'descend');
            fillVal = tempTable{mstSub(1),mn};
            clInfoTotal = addvars(clInfoTotal, repmat(fillVal, size(clInfoTotal,1),1),...
                'NewVariableNames', mn);
        end
        popVarNames = clInfoTotal.Properties.VariableNames;
        [curInPopFlags, popInCurSubs] = ismember(popVarNames, curVarNames);
        if ~all(curInPopFlags) || ~isempty(setdiff(1:Ncv, popInCurSubs))
            fprintf(1, 'Predicting an error!\n')
        end
        clInfoTotal = cat(1, clInfoTotal, clInfo);
    end
end
gclID = clInfoTotal{logical(clInfoTotal.ActiveUnit),'id'};
Ncl = numel(gclID);
Ne = size(discStack, 1);
%% Population analysis
figureDir = fullfile(experimentDir,'PopFigures\');
if ~mkdir(figureDir)
    fprintf(1,'There was an issue with the figure folder...\n');
    fprintf(1,'Saving the figures in the data folder!\n');
    fprintf(1,'%s\n',dataDir);
    figureDir = dataDir;
end
[~,expName] = fileparts(experimentDir);
dataDir = experimentDir;
% Statistical tests
[Results, Counts] = statTests(discStack, delayFlags, timeFlags);

% Plotting statistical tests
[figs, Results] = scatterSignificance(Results, Counts,...
    consCondNames, delta_t, gclID);
arrayfun(@configureFigureToPDF, figs);
% Firing rate for all clusters, for all trials
% meanfr = cellfun(@(x) mean(x,2)/delta_t,Counts,'UniformOutput',false);
stFigBasename = fullfile(figureDir,[expName,' ',sprintf('%d ',chExp)]);
stFigSubfix = sprintf(' Stat RW%.1f-%.1fms SW%.1f-%.1fms',...
    responseWindow(1)*1e3, responseWindow(2)*1e3, spontaneousWindow(1)*1e3,...
    spontaneousWindow(2)*1e3);
ccn = 1;
%for cc = indCondSubs
for cc = 1:numel(figs)
    if ~ismember(cc, indCondSubs)
        altCondNames = strsplit(figs(cc).Children(2).Title.String,': ');
        altCondNames = altCondNames{2};
    else
        altCondNames = consCondNames{ccn};
        ccn = ccn + 1;
    end
    stFigName = [stFigBasename, altCondNames, stFigSubfix];
    if ~exist([stFigName,'.pdf'],'file') ||...
            ~exist([stFigName,'.emf'],'file')
        print(figs(cc),[stFigName,'.pdf'],printOpts{1}{:})
        print(figs(cc),[stFigName,'.emf'],printOpts{2})
    end
end

% Filtering for the whisker responding clusters
H = cell2mat(cellfun(@(x) x.Pvalues,...
    arrayfun(@(x) x.Activity, Results(indCondSubs), 'UniformOutput', 0),...
    'UniformOutput', 0)) < 0.05;
Htc = sum(H,2);
% Those clusters responding more than 80% of all whisker stimulating
% conditions
CtrlCond = contains(consCondNames,'control','IgnoreCase',true);
wruIdx = any(H(:,CtrlCond),2);
Nwru = nnz(wruIdx);

fprintf('%d whisker responding clusters:\n', Nwru);
fprintf('- %s\n',gclID{wruIdx})
%% Filter responsive?
filterIdx = true(Ne,1);
if strcmpi(filtStr, 'filtered') && nnz(wruIdx)
    filterIdx = [true; wruIdx];
end
%% Add the response to the table
try
    clInfoTotal = addvars(clInfoTotal, false(size(clInfoTotal,1),1), 'NewVariableNames', 'Control');
    clInfoTotal{logical(clInfoTotal.ActiveUnit), 'Control'} = wruIdx;
catch
    fprintf('Reran, perhaps?\n')
end
%% Temporal dynamics
trigTms = cell2mat(arrayfun(@(x) x.Triggers(:,1), Conditions(chCond),...
    'UniformOutput', 0)')/fs;
timesum = @(x) squeeze(sum(x,2));
clsum = @(x) squeeze(sum(x,1));
matsum = @(x) timesum(clsum(x));
stackTx = (0:Nt-1)/fs + timeLapse(1) + 2.5e-3;

[~,cnd] = find(delayFlags);
[~, tmOrdSubs] = sort(trigTms, 'ascend');
cnd = cnd(tmOrdSubs); trialAx = minutes(seconds(trigTms(tmOrdSubs)));
% Modulation: distance from the y=x line.
try
    modFlags = sign(clInfoTotal{clInfoTotal.ActiveUnit &...
        clInfoTotal.Control, 'Modulation'});
catch
    clInfoTotal = addvars(clInfoTotal, zeros(size(clInfoTotal,1),1),...
        'NewVariableNames', 'Modulation');
    clInfoTotal{logical(clInfoTotal.ActiveUnit),'Modulation'} =...
        Results(1).Activity(2).Direction;
    modFlags = sign(clInfoTotal{clInfoTotal.ActiveUnit &...
        clInfoTotal.Control, 'Modulation'});
end
% Group indeces
modVal = clInfoTotal{clInfoTotal.ActiveUnit == 1, 'Modulation'};
pruIdx = wruIdx & modVal > 0; % Potentiated responding
druIdx = wruIdx & modVal <= 0; % Depressed responding
nruIdx = ~any(H,2); % Non-responding what-so-ever
nmuIdx = false(size(nruIdx)); % Non-responding nor modulating
nmuIdx(nruIdx) = abs(zscore(modVal(nruIdx))) < 0.33; % With this criteria
aruIdx = and(xor(H(:,1),H(:,2)),H(:,2)); % Response only A.-I.
sruIdx = and(xor(H(:,1),H(:,2)),H(:,1)); % Stopped responding after A.-I.

modFlags = modFlags > 0;
modFlags(:,2) = ~modFlags;
cmap = lines(Nccond);
cmap(CtrlCond,:) = ones(1,3)*1/3; cmap(:,:,2) = ones(Nccond,3)*0.7;

plotOpts = {'LineStyle', 'none', 'Marker', '.', 'Color', 'DisplayName'};
modLabel = {'Potentiation', 'Depression'};
clrSat = 0.5;
ax = gobjects(size(modFlags,2), 1);
condLey = {'Control','After Induction'};
respLey = {'Responsive', 'Non-responsive'};
% Time steps for the 3D PSTH in ms
focusStep = 2.5;
focusPeriods = (-3:focusStep:18)';
focusPeriods(:,2) = focusPeriods + focusStep; focusPeriods = focusPeriods * 1e-3;
Nfs = size(focusPeriods,1);
popMeanResp = zeros(Nfs, sum(NaStack), 4);
fws = 1:Nfs;
auxOr = [false, true];
trialBin = 1;
quartCuts = -log([4/3, 2, exp(1), 4]);
for pfp = fws
    tdFig = figure('Name', 'Temporal dynamics', 'Color', [1,1,1]);
    for cmod = 1:size(modFlags,2) % Up- and down-modulation
        tcount = 1;
        ax(cmod) = subplot(size(modFlags,2),1,cmod,'Parent',tdFig);
        ax(cmod).NextPlot = 'add';
        title(ax(cmod), sprintf('%s',modLabel{cmod}));
        
        for ccond = 1:Nccond % Cycling through the conditions (control and after-induction)
            trSubs = tcount:trialBin:sum(NaStack(1:ccond));
            clMod = modFlags(:,cmod);
            for cr = 1:2 % responsive and non-responsive
                respIdx = xor(H(:,cr), auxOr(cr)); % Negation of H(:,2)
                for cp = 1:Nfs % 'Micro' time windows
                    focusIdx = stackTx >= focusPeriods(cp,1) &...
                        stackTx <= focusPeriods(cp,2);
                    clCounts = timesum(...
                        discStack( [false; respIdx], focusIdx, delayFlags(:,ccond)));
                    %clMean = mean(clCounts(clMod,:),1); popMean = mean(clMean);
                    clMean = zeros(NaStack(ccond)/trialBin,1);
                    qTrial = zeros(NaStack(ccond)/trialBin,2);
                    for cb = 1:NaStack(ccond)/trialBin
                        trialSubs = [cb-1;cb]*trialBin + [1;0];
                        figure('IntegerHandle',102,'Visible','off');
                        h = histogram(clCounts(clMod,...
                            trialSubs(1):trialSubs(2)), -0.5:10.5);
                        expMdl = fit_poly(0:10, log10(h.BinCounts), 1);
                        qVals = quartCuts./expMdl(1);
                        clMean(cb) = qVals(3); qTrial(cb,:) = qVals([1,4]);
                    end
                    popMeanResp(cp, trSubs, [cr,cmod-1]*[1;2]) = clMean;
                end
                dispName = [condLey{ccond}, ' ', respLey{cr}];
                plot(ax(cmod), trialAx(trSubs),...
                    popMeanResp(pfp, trSubs, [cr,cmod-1]*[1,2]'),...
                    plotOpts{1:5}, cmap(ccond,:,cr),...
                    plotOpts{6}, dispName);
                clMod = true(sum(respIdx),1);
            end
            tcount = 1 + sum(NaStack(1:ccond));
        end
        cmap(ccond,:,1) = brighten(cmap(ccond, :, 1), clrSat);
        clrSat = -clrSat;
    end
    ylabel(ax(cmod), 'Spikes / Cluster'); xlabel(ax(cmod),...
        sprintf('(%.1f - %.1f [ms]) Trial [min]',focusPeriods(pfp,:)*1e3))
    linkaxes(ax,'xy')
    tdFigName = string(sprintf('Temporal dynamics exps %sFW%.1f-%.1f ms',...
        sprintf('%d ', chExp), focusPeriods(pfp,:)*1e3));
    tempFigName = fullfile(figureDir, tdFigName);
    figTdName = tempFigName + '.fig';
    if ~exist(figTdName, 'file')
        savefig(tdFig, figTdName);
    end
end
fprintf(1, 'Are there non-responsive, non-modulated clusters')
%% Getting the relative spike times for the whisker responsive units (wru)
% For each condition, the first spike of each wru will be used to compute
% the standard deviation of it.
configStructure = struct('Experiment', fullfile(dataDir,expName),...
    'Viewing_window_s', timeLapse, 'Response_window_s', responseWindow,...
    'BinSize_s', binSz, 'Trigger', struct('Name', condNames{chCond},...
    'Edge',onOffStr), 'ConsideredConditions',{consCondNames});
cellLogicalIndexing = @(x,idx) x(idx);
isWithinResponsiveWindow =...
    @(x) x > responseWindow(1) & x < responseWindow(2);

firstSpike = zeros(Nwru,Nccond);
M = 16;
binAx = responseWindow(1):binSz:responseWindow(2);
condHist = zeros(size(binAx,2)-1, Nccond);
firstOrdStats = zeros(2,Nccond);
condParams = zeros(M,3,Nccond);
txpdf = responseWindow(1):1/fs:responseWindow(2);
condPDF = zeros(numel(txpdf),Nccond);
csvSubfx = sprintf(' VW%.1f-%.1f ms.csv', timeLapse(1)*1e3, timeLapse(2)*1e3);
existFlag = false;
condRelativeSpkTms = cell(Nccond,1);
relativeSpkTmsStruct = struct('name',{},'SpikeTimes',{});
csvDir = fullfile(dataDir, 'SpikeTimes');
if ~exist(csvDir,'dir')
    iOk = mkdir(csvDir);
    if ~iOk
        fprintf(1, 'The ''Figure'' folder was not created!\n')
        fprintf(1, 'Please verify your writing permissions!\n')
    end
end
for ccond = 1:size(delayFlags,2)
    csvFileName = fullfile(csvDir,[expName,' ', sprintf('%d ',chExp),...
        consCondNames{ccond}, csvSubfx]);
    relativeSpikeTimes = getRasterFromStack(discStack,~delayFlags(:,ccond),...
        filterIdx(3:end), timeLapse, fs, true, false);
    relativeSpikeTimes(:,~delayFlags(:,ccond)) = [];
    relativeSpikeTimes(~filterIdx(2),:) = [];
    condRelativeSpkTms{ccond} = relativeSpikeTimes;
    %     respIdx = cellfun(isWithinResponsiveWindow, relativeSpikeTimes,...
    %         'UniformOutput',false);
    clSpkTms = cell(size(relativeSpikeTimes,1),1);
    if exist(csvFileName, 'file') && ccond == 1
        existFlag = true;
        ansOW = questdlg(['The exported .csv files exist! ',...
            'Would you like to overwrite them?'],'Overwrite?','Yes','No','No');
        if strcmp(ansOW,'Yes')
            existFlag = false;
            fprintf(1,'Overwriting... ');
        end
    end
    fID = 1;
    if ~existFlag
        fID = fopen(csvFileName,'w');
        fprintf(fID,'%s, %s\n','Cluster ID','Relative spike times [ms]');
    end
    rsclSub = find(filterIdx(2:end))-1;
    for cr = 1:size(relativeSpikeTimes, 1)
        clSpkTms(cr) = {sort(cell2mat(relativeSpikeTimes(cr,:)))};
        if fID > 2
            fprintf(fID,'%s,',gclID{rsclSub(cr)});
            fprintf(fID,'%f,',clSpkTms{cr});fprintf(fID,'\n');
        end
    end
    if fID > 2
        fclose(fID);
    end
    relativeSpkTmsStruct(ccond).name = consCondNames{ccond};
    relativeSpkTmsStruct(ccond).SpikeTimes = condRelativeSpkTms{ccond};
end
save(fullfile(csvDir,[expName,'_exportSpkTms.mat']),...
    'relativeSpkTmsStruct','configStructure')

%% ISI PDF & CDF
binFig = figure('Visible','off');
areaFig = figure('Visible','on', 'Color', [1,1,1],'Name','ISI probability');
areaAx = gobjects(2,1);
lax = log(1/fs):0.2:log(0.03);
% cmap = [0,0,102;... azul marino
%     153, 204, 255]/255; % azul cielo
cmap = lines(Nccond);
%areaOpts = {'EdgeColor', 'none', 'FaceAlpha', 0.3, 'FaceColor'};
areaOpts = {'Color','LineStyle','--','LineWidth',1.5};
ley = ["Potentiated", "Depressed"];
isiPdf = zeros(length(lax)-1,2*Nccond);
for cmod = 1:2 % Potentiated and depressed clusters
    areaAx(cmod) = subplot(1,2,cmod,'Parent',areaFig);
    Nccl = sum(modFlags(:,cmod));
    for ccond = 1:Nccond
        cnt = [cmod-1,ccond] * [2,1]';
        ISI = cellfun(@(x) diff(x(x >= -0.035 & x <= 0)), ...
            relativeSpkTmsStruct(ccond).SpikeTimes(modFlags(:,cmod),:),...
            'UniformOutput', 0);
        ISI_merge = [ISI{:}];
        lISI = log(ISI_merge);
        hisi = histogram(lISI, lax, 'Parent', binFig, 'DisplayStyle', 'stairs');
        spkPerT_C = hisi.Values./(NaStack(ccond)*Nccl);
        isiPdf(:,cnt) = spkPerT_C/sum(spkPerT_C);
        plot(areaAx(cmod), 1e3*exp(lax(1:end-1)), isiPdf(:,cnt),...
            areaOpts{1}, cmap(ccond,:), areaOpts{4:5});
        if ccond == 1
            hold(binFig.Children, 'on'); hold(areaAx(cmod), 'on');
            areaAx(cmod).XAxis.Scale = 'log';
            areaAx(cmod).XLabel.String = "ISI [ms]";
            areaAx(cmod).YLabel.String = "ISI probability";
        end
        yyaxis(areaAx(cmod) ,'right')
        
        plot(areaAx(cmod), 1e3*exp(lax(1:end-1)), cumsum(isiPdf(:,cnt)),...
            areaOpts{1}, cmap(ccond,:), areaOpts{2:3})
        ylim(areaAx(cmod), [0,1]); areaAx(cmod).YAxis(2).Color = [0,0,0];
        ylabel(areaAx(cmod), 'Cumulative probability');
        yyaxis(areaAx(cmod) ,'left'); set(areaAx(cmod),'Box','off')
    end
    title(areaAx(cmod), sprintf('ISI PDF for %s clusters',ley(cmod)));
end
legend(areaAx(cmod),consCondNames)
hisi = hisi.Parent.Children; linkaxes(areaAx,'xy')

%% Ordering PSTH
orderedStr = 'ID ordered';
dans = questdlg('Do you want to order the PSTH other than by IDs?',...
    'Order', 'Yes', 'No', 'No');
ordSubs = 1:nnz(filterIdx(2:Ncl+1));
pclID = gclID(filterIdx(2:Ncl+1));
if strcmp(dans, 'Yes')
    if ~exist('clInfoTotal','var')
        clInfoTotal = getClusterInfo(fullfile(dataDir,'cluster_info.tsv'));
    end
    % varClass = varfun(@class,clInfo,'OutputFormat','cell');
    [ordSel, iOk] = listdlg('ListString', clInfoTotal.Properties.VariableNames,...
        'SelectionMode', 'multiple');
    orderedStr = [];
    ordVar = clInfoTotal.Properties.VariableNames(ordSel);
    for cvar = 1:numel(ordVar)
        orderedStr = [orderedStr, sprintf('%s ',ordVar{cvar})]; %#ok<AGROW>
    end
    orderedStr = [orderedStr, 'ordered'];
    
    if ~strcmp(ordVar,'id')
        [~,ordSubs] = sortrows(clInfoTotal(pclID,:),ordVar);
    end
end
%% Plot PSTH
goodsIdx = logical(clInfoTotal.ActiveUnit);
csNames = fieldnames(Triggers);
Nbn = diff(timeLapse)/binSz;
if (Nbn - round(Nbn)) ~= 0
    Nbn = ceil(Nbn);
end
PSTH = zeros(nnz(filterIdx) - 1, Nbn, Nccond);
for ccond = 1:Nccond
    figFileName = sprintf('%s %s %sVW%.1f-%.1f ms B%.1f ms RW%.1f-%.1f ms SW%.1f-%.1f ms %sset %s (%s)',...
        expName, Conditions(consideredConditions(ccond)).name,...
        sprintf('%d ', chExp), timeLapse*1e3,...
        binSz*1e3, responseWindow*1e3, spontaneousWindow*1e3, onOffStr,...
        orderedStr, filtStr);
    [PSTH(:,:,ccond), trig, sweeps] = getPSTH(discStack(filterIdx,:,:),...
        timeLapse, ~delayFlags(:,ccond), binSz, fs);
    stims = mean(discStack(:,:,delayFlags(:,ccond)),3);
    stims = stims - median(stims,2);
    for cs = 1:size(stims,1)
        if abs(log10(var(stims(cs,:),[],2))) < 13
            [m,b] = lineariz(stims(cs,:),1,0);
            stims(cs,:) = m*stims(cs,:) + b;
        else
            stims(cs,:) = zeros(1,Nt);
        end
    end
    figs = plotClusterReactivity(PSTH(ordSubs,:,ccond), trig, sweeps,...
        timeLapse, binSz, [{Conditions(consideredConditions(ccond)).name};...
        pclID(ordSubs)], strrep(expName,'_','\_'));
    configureFigureToPDF(figs);
    figs.Children(end).YLabel.String = [figs.Children(end).YLabel.String,...
        sprintf('^{%s}',orderedStr)];
    if ~exist([figFileName,'.pdf'], 'file') || ~exist([figFileName,'.emf'], 'file')
        print(figs, fullfile(figureDir,[figFileName, '.pdf']),'-dpdf','-fillpage')
        print(figs, fullfile(figureDir,[figFileName, '.emf']),'-dmeta')
    end
end

%% Comparing the PSTHs for all conditions

txpsth = (0:Nbn-1)*binSz + timeLapse(1) + 2.5e-3;
focusWindow = [-5, 30]*1e-3;
focusIdx = txpsth >= focusWindow(1) & txpsth <= focusWindow(2);
txfocus = txpsth(focusIdx);
modLabels = {'potentiated', 'depressed'};
%modLabels = {'non-responding','non-modulated'};
for cmod = 1:2
    psthFig = figure('Color', [1,1,1], 'Name', 'Condition PSTH comparison',...
        'Visible', 'off');
    PSTH_raw = squeeze(sum(PSTH(modFlags(:,cmod),:,:),1));
    PSTH_trial = PSTH_raw./(NaStack.*sum(modFlags(:,cmod)));
    PSTH_prob = PSTH_raw./sum(PSTH_raw,1);
    PSTH_all = cat(3, PSTH_raw, PSTH_trial, PSTH_prob);
    axp = gobjects(3,1);
    subpltsTitles = {sprintf('PSTH per condition, %s clusters',modLabels{cmod}),...
        'Cumulative density function', 'Cumulative sum for normalized spikes'};
    yaxsLbls = {'Spikes / (Trials * Cluster)', 'Spike probability',...
        'Spike number'};
    for cax = 1:3
        axp(cax) = subplot(4, 1, cax, 'Parent', psthFig, 'NextPlot', 'add');
        for ccond = 1:Nccond
            plotOpts = {'DisplayName', consCondNames{ccond}};
            switch cax
                case 1 % Plot the trial-normalized PSTH; page #2
                    plot(axp(cax), txfocus, PSTH_all(focusIdx,ccond,2),...
                        plotOpts{:})
                case 2 % Plot the cumulative probability function; page 3
                    PSTH_aux = PSTH_all(focusIdx, ccond, 3);
                    PSTH_aux = PSTH_aux / sum(PSTH_aux);
                    plot(axp(cax), txfocus, cumsum(PSTH_aux), plotOpts{:})
                case 3 % Plot the cumulative sum for the mean spikes; page 2
                    plot(axp(cax), txfocus, ...
                        cumsum(PSTH_all(focusIdx, ccond, 2)), plotOpts{:})
            end
        end
        title(axp(cax), subpltsTitles{cax})
        ylabel(axp(cax), yaxsLbls{cax})
        if cax < 3
            xticks(axp(cax), '')
        else
            xlabel(axp(cax), sprintf('Time_{%.2f ms} [s]', binSz*1e3))
            legend(axp(cax), 'show', 'Location', 'best')
        end
    end
    axp(4) = subplot(4,1,4, 'Parent', psthFig);
    PSTH_diff = 100 * ((PSTH_prob(:,2)./PSTH_prob(:,1)) - 1);
    bar(axp(4), txfocus(PSTH_diff(focusIdx) > 0), PSTH_diff(PSTH_diff > 0 & focusIdx'),...
        'FaceColor', [51, 204, 51]/255, 'DisplayName', 'Potentiation'); hold on
    bar(axp(4), txfocus(PSTH_diff(focusIdx) <= 0), PSTH_diff(PSTH_diff <= 0 & focusIdx'),...
        'FaceColor', [204, 51, 0]/255, 'DisplayName', 'Depression');
    axp(4).Box = 'off'; ylabel(axp(4), '%'); title(axp(4), 'Percentage of change')
    xticks(axp(4),'')
    linkaxes(axp, 'x')
    legend show
    psthFig.Visible = 'on';
    psthFig = configureFigureToPDF(psthFig);
    psthFigFileName = sprintf('%s %sPSTH RW%.2f-%.2f ms FW%.2f-%.2f ms %s clusters',...
        expName, sprintf('%d ',chExp), responseWindow*1e3,...
        focusWindow*1e3, modLabels{cmod});
    psthFigFileName = fullfile(figureDir,psthFigFileName);
    if ~exist([psthFigFileName,'.pdf'], 'file')
        print(psthFig, [psthFigFileName, '.pdf'],'-dpdf','-fillpage')
    end
    if ~exist([psthFigFileName,'.emf'], 'file')
        print(psthFig, [psthFigFileName, '.emf'],'-dmeta')
    end
    if ~exist([psthFigFileName,'.fig'], 'file')
        savefig(psthFig, [psthFigFileName, '.fig'])
    end
end


%% Waveform analysis
pltDot = {'LineStyle', 'none', 'Marker', '.', 'MarkerSize', 5};
fprintf(1, 'This is the waveform analysis section\n');
mg2db = @(x) 20*log10(abs(x)); [Nws, Ncw] = size(popClWf);
Np = 2^(nextpow2(Nws)-1) - Nws/2; tx = (0:Nws-1)/fs;
pwf_m = popClWf - mean(popClWf); pwf_w = pwf_m .* chebwin(Nws, 150);
pwf_p = padarray(padarray(pwf_w, [floor(Np),0], 'pre'),...
    [ceil(Np),0], 'post'); pwf_n = pwf_p./max(abs(pwf_p));
ltx = ((0:size(pwf_p,1)-1)' - size(pwf_n,1)/2)/fs;
ft = fftshift(fft(pwf_n,[],1),1); dw = fs/size(ft,1); mg = mg2db(ft);
ph = angle(ft); wx = (0:size(ft,1)-1)'*dw - fs/2;
mg = mg(wx>=0,:); ph = ph(wx>=0,:); wx = wx(wx>=0); [~, mxWxSub] = max(mg);
wcp = getWaveformCriticalPoints(mg, size(ft,1)/fs);
pwc = cellfun(@(x) x(1), wcp(:,1)); mxW = wx(mxWxSub);

tcp = getWaveformCriticalPoints(pwf_n, fs);
featWf = getWaveformFeatures(pwf_n, fs);
params = emforgmm(log(featWf(:,1)), 3, 1e-7, 0);
logDomain = (round(min(log(featWf(:,1)))*1.05,1):0.01:...
    round(max(log(featWf(:,1)))*0.95,1))';
p_x = genP_x(params, logDomain);
probCriticPts = getWaveformCriticalPoints(p_x', 100);
probCriticPts = cellfun(@(x) x + logDomain(1), probCriticPts,...
    'UniformOutput', 0); logThresh = probCriticPts{1,1}(2);
time_wf = log(featWf(:,1)) > logThresh;

[m, b] = lineariz(pwc, 1, -1); pwc_n = pwc*m + b;
params_freq = emforgmm(pwc_n, 3, 1e-7, 0); wDomain = (-1.05:0.01:1.05)';
p_wx = genP_x(params_freq, wDomain);
probCriticPts_w = getWaveformCriticalPoints(p_wx', 100);
probCriticPts_w = cellfun(@(x) x + wDomain(1), probCriticPts_w,...
    'UniformOutput', 0); wThresh = probCriticPts_w{1,1}(2);
freq_wf = pwc_n < wThresh;
tf_groups = [...
    ~time_wf & ~freq_wf,...
    ~freq_wf & time_wf,...
    freq_wf & ~time_wf,...
    freq_wf & time_wf];
% meanWf = cellfun(@(x) mean(x,2), popClWf(:,2),'UniformOutput', 0);
% meanWf = cat(2,meanWf{:}); featWf = getWaveformFeatures(meanWf, fs);
% wFeat = whitenPoints(featWf);
%% Adaptation
dt = 1/8;
onst = (0:7)'*dt;
ofst = (0:7)'*dt + 0.05;
onrpWins = [onst+5e-3, onst+3e-2];
ofrpWins = [ofst+5e-3, ofst+3e-2];
onrpIdx = txpsth >= onrpWins(:,1) & txpsth <= onrpWins(:,2);
ofrpIdx = txpsth >= ofrpWins(:,1) & txpsth <= ofrpWins(:,2);
ptsOn = zeros(size(onrpIdx,1),size(PSTH_prob,2),2); % time, magnitude
ptsOf = ptsOn;
for ccond = 1:size(PSTH_prob,2)
    for crw = 1:size(onst,1)
        [mg, tmSub] = max(PSTH_prob(onrpIdx(crw,:),ccond));
        tmWinSub = find(onrpIdx(crw,:));
        ptsOn(crw, ccond, 1) = txpsth(tmWinSub(tmSub));
        ptsOn(crw, ccond, 2) = mg;
        [mg, tmSub] = max(PSTH_prob(ofrpIdx(crw,:),ccond));
        tmWinSub = find(ofrpIdx(crw,:));
        ptsOf(crw, ccond, 1) = txpsth(tmWinSub(tmSub));
        ptsOf(crw, ccond, 2) = mg;
    end
end
