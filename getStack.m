function [expStack, LFPstack, Wstack] =...
    getStack(spT,alignP,ONOFF,timeSpan,fs,LFP,whiskerMovement,consEvents)
% GETPSTH returns a stack of spikes aligned to a certain event ''alignT''
% considering the events in the cell array ''consEvents''.

%% Computing the size of the PSTH stack
if isa(alignP,'logical')
    alWf = StepWaveform(alignP,fs,'on-off','Align triggers');
    alignP = alWf.Triggers;
end
switch ONOFF
    case 'on'
        disp('Considering onset of the triggers')
    case 'off'
        disp('Considering offset of the triggers')
    otherwise
        disp('Unrecognized trigger selection. Considering onsets')
        ONOFF = 'on';
end
[auxR,auxC] = size(alignP);
if auxR < auxC
    alignP = alignP';
end
[Na, raf] = size(alignP);
if raf > 2 || raf < 1
    fprintf(['Warning! The alignment matrix is expected to have ',...
        'either only rising or rising and falling edges time indices.\n'])
    expStack = NaN;
    return;
end

%% Considered events arrangement.
Ne = 0;
if nargin == 8
    typ = whos('consEvents');
    switch typ.class
        case 'double'
            [~, Ne] = size(consEvents);
            if mod(Ne,2)
                Ne = Ne/2;
            else
                fprintf('Omitting the events to consider.\n')
                Ne = 0;
            end
        case 'cell'
            Ne = length(consEvents);
            consEvents2 = consEvents;
            evntTrain = cellfun(@islogical,consEvents);
            % Converting the logical event trains into indices
            for ce = 1:Ne
                if evntTrain(ce)
                    stWv = StepWaveform(consEvents{ce},fs);
                    consEvents2{ce} = stWv.Triggers;
                end
            end
            consEvents = consEvents2;
        otherwise
            fprintf('The events to consider are not in recognized format.\n')
    end
end
%% Preallocation of the spike-stack:
toi = sum(timeSpan);
prevSamples = ceil(timeSpan(1) * fs);
postSamples = ceil(timeSpan(2) * fs);
fsLFP = 1e3;
fsConv = fsLFP/fs;
Nt = round(toi*fs) + 1;
expStack = false(2+Ne,Nt,Na);
prevSamplesLFP = ceil(timeSpan(1) * fsLFP);
postSamplesLFP = ceil(timeSpan(2) * fsLFP);
NtLFP = round(toi*fsLFP) + 1;
LFPstack = zeros(NtLFP,Na);
Wstack = LFPstack;
if isnumeric(spT)
    mxS = spT(end) + Nt;
    spTemp = false(1,mxS);
    spTemp(spT) = true;
    spT = spTemp;
end
%% Cutting the events into the desired segments.
for cap = 1:Na
    if strcmp(ONOFF, 'on')
        segmIdxs = [alignP(cap,1)-prevSamples,alignP(cap,1)+postSamples];
    elseif strcmp(ONOFF, 'off')
        segmIdxs = [alignP(cap,2)-prevSamples,alignP(cap,2)+postSamples];
    end
    % The segments should be in the range of the spike train.
    if segmIdxs(1) >= 1 && segmIdxs(2) <= length(spT)
        spSeg = spT(segmIdxs(1):segmIdxs(2));
        segmIdxsLFP = round([(alignP(cap,1)*fsConv)-prevSamplesLFP,...
            (alignP(cap,1)*fsConv)+postSamplesLFP]);
    else
        Na = Na - 1;
        continue;
    end
    expStack(2,:,cap) = spSeg;
    % Find 'overlapping' periods in time of interest
    alignPeriod = getEventPeriod(alignP, {alignP}, ONOFF, cap,...
        prevSamples, postSamples);
    expStack(1,:,cap) = alignPeriod;
    if Ne
        expStack(3:2+Ne,:,cap) =...
            getEventPeriod(alignP, consEvents, ONOFF, cap,...
            prevSamples, postSamples);
    end
    % Getting the LFP segments taking into account the different sampling
    % frequencies i.e. LFP-->1 kHz Spikes --> 20 kHz HARD CODE!! BEWARE!!
    if exist('LFP','var') && ~isempty(LFP)
        LFPstack(:,cap) = LFP(round((segmIdxsLFP(1):segmIdxsLFP(2))));
    end
    if exist('whiskerMovement','var') && ~isempty(whiskerMovement)
        Wstack(:,cap) = whiskerMovement(round((segmIdxsLFP(1):segmIdxsLFP(2))));
    end
end
end

% Aligning the events according to the considered time point. The inputs
% are time indices called Tdx as in Time inDeX.
function evntOn = getEventPeriod(alignTdx, evntTdx, ONOFF, cap, prev, post)
% Assuming that the considered events are always cells.
if isempty(evntTdx)
    evntOn = [];
    return;
else
    evntOn = false(numel(evntTdx),prev+post+1);
    for ce = 1:length(evntTdx)
        if strcmp(ONOFF,'on')
            relTdx = evntTdx{ce}(:,1) - alignTdx(cap,1);
        else
            relTdx = evntTdx{ce}(:,2) - alignTdx(cap,2);
        end
        inToi = find(relTdx >= -prev & relTdx < post);
        if ~isempty(inToi)
            psthIdx = evntTdx{ce}(inToi,1)-alignTdx(cap,1) + prev + 1;
            lenIdx = evntTdx{ce}(inToi,2)-evntTdx{ce}(inToi,1) + 1;
            for cep = 1:numel(psthIdx)
                idxs = psthIdx(cep):psthIdx(cep)+lenIdx(cep)-1;
                idxs = idxs(idxs <= post+prev+1);
                evntOn(ce,idxs) = true;
            end
        end
    end
end
end

