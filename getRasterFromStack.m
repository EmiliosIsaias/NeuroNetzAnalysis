function [relativeSpikeTimes, tx] =...
    getRasterFromStack(...
    discreteStack,... Discrete stack containing the alignment points
    kIdx,... Boolean array indicating which trials should be ignored
    koIdx,... Boolean array indicating which events should be taken out.
    timeLapse,... 2 element array contaning the time before the trigger and the time after the trigger in seconds
    fs,... Original sampling frequency
    ERASE_kIDX... Boolean flag indicating if
    )
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here
[Ne, Nt, Na] = size(discreteStack);
% There will be for each neuron (or event) Na - !(kIdx) number of trials
relativeSpikeTimes = cell(Ne-(sum(~koIdx) + 1), Na);
iE = find(koIdx);
if isempty(iE)
    iE = 2;
else
    iE = [2, 2 + iE'];
end
% Time axis
spIdx = 1;
tx = linspace(-timeLapse(1),timeLapse(2),Nt);
for cse = iE
    % For each spike train
    for cap = Na:-1:1
        % For each alignment point
        if ~kIdx(cap)
            % If the alignment point should be ignored
            % upEdge = diff(discreteStack(cse,:,cap)) > 0;
            % if sum(upEdge) ~= 0
                % If there are events in this alignment point
                % downEdge = diff(discreteStack(cse,:,cap)) < 0;
                % isSpike = upEdge(1:end-1) - downEdge(2:end);
                % if sum(isSpike) == 0
                    % If the event contains spikes
                    spikeTimes = tx(squeeze(discreteStack(cse,:,cap)));
                    relativeSpikeTimes(spIdx,cap) = {round(fs*spikeTimes)};
                    %lvl = (cse - 2)*Na + cap;
                % end
            % end
        end
    end
    spIdx = spIdx + 1;
    
end
if exist('ERASE_kIDX','var') && ERASE_kIDX
    % If the user chose to erase the kick out alignment trials
    relativeSpikeTimes(:,cellfun(@isempty,relativeSpikeTimes(1,:))) = [];
end



