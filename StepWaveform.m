classdef StepWaveform < DiscreteWaveform
    %STEPWAVEFORM is derived from the DiscreteWaveform class and contains
    %only the extra necessary properties to produce time stamps for
    %triggering or anyother desired method.
    
    properties (SetAccess = 'private')
        Triggers
        % Reminder: Size and validator functions not supported for
        % properties defined as abstract in superclasses
    end
    
    methods
        % Constructor
        function obj = StepWaveform(data, samplingFreq, units, title)
            %STEPWAVEFORM Construct an instance of this class
            %   Detailed explanation goes here
            if nargin < 3
                units = 'on-off';
                title = 'Step Waveform';
            end
            obj@DiscreteWaveform(data,samplingFreq, units,title);
            obj.Triggers = computeTriggers(obj);
        end
        
        % Rising and falling edges
        function RaF = get.Triggers(obj)
            RaF = obj.Triggers;
        end 
        
        function subRaF = subTriggers(obj)
            try
                subRaF = [find(obj.Triggers(:,1)),find(obj.Triggers(:,2))];
            catch 
                subRaF = [];
                return
            end
            invertedFlags = diff(subRaF,1,2) < 0;
            if any(invertedFlags)
                fprintf(1,'%d Downwards pulses detected!\n',...
                    sum(invertedFlags))
                subRaF(invertedFlags,:) = flip(subRaF(invertedFlags,:),2);
            end
        end

        % Display object information
        function disp(obj)
            disp('Step waveform-------')
            if ~isempty(obj.Data)
                fprintf('Title: %s\n',obj.Title)
                fprintf('Triggers: %d\n',length(obj.Triggers))
                fprintf('Sampling Frequency: %0.3f kHz\n',obj.SamplingFreq/1e3)
            end
        end
    end
    %% Private Methods
    methods (Access = 'private')
        function RaF = computeTriggers(obj)
            % Checking the data type
            if isa(obj.Data,'double')
                % Real valued signal
                ds = diff(obj.Data);
                if sum(ds>0) ~= numel(obj.Data)-1
                    data = obj.Data - mean(obj.Data);
                    zs2 = (mean(data)/std(obj.Data))^2;
                    fprintf(1,'The square z-score of the signal is %.2f\n',zs2)
                    if zs2 < 0.9
                        rise = false(obj.NSamples,1);    % Rising edge times
                        fall = rise;                    % Falling edge times
                        % Maximum value divided by three
                        rise(2:end) = ds > max(abs(ds))/3;
                        rise = StepWaveform.cleanEdges(rise);
                        fall(1:end-1) = ds < min(ds)/3;
                        fall = StepWaveform.cleanEdges(fall);
                        if sum(rise) ~= sum(fall)
                            warning('The cardinality of the rising edges is different for the falling edges')
                            if abs(sum(rise) - sum(fall)) == 1
                                % Determining the missing edge (normally
                                % would be at the extreme cases; at the
                                % beguinning or at the end of the time
                                % series)
                                fprintf(1,'Perhaps it is a truncated pulse...\n')
                                r = find(rise);
                                f = find(fall);
                                dm = distmatrix(r,f);
                                if numel(r) < numel(f)
                                    dim = 1;
                                else
                                    dim = 2;
                                end
                                [~,Sub] = max(min(dm,[],dim));
                                if dim == 2
                                    rise(r(Sub)) = false;
                                else
                                    fall(f(Sub)) = false;
                                end
                            else
                                fprintf(1,'It might be worth improving ')
                                fprintf(1,'signal quality\n')
                            end % abs(sum(rise) - sum(fall)) == 1
                        end % sum(rise) ~= sum(fall)
                        try
                            RaF = [rise, fall];
                        catch
                            warning('Unable to correct the difference in cardinality...')
                            warning('Returning a cell array!')
                            RaF = {rise, fall};
                        end
                    else
                        fprintf(1,'The input signal seems to be only noise.\n')
                        fprintf(1,'Consider examining it closely...\n')
                        RaF = [];
                    end % if zs2 < 0.9 -- Noise-like signal?
                else
                    disp('The given data are probably the triggers already!')
                    RaF = obj.Data;
                end % sum(ds>0) ~= numel(obj.Data)-1 -- Triggers given?
                obj.Triggers = RaF;
                
            elseif isa(obj.Data,'logical')
                % Boolean step function
                aux = obj.Data(1:end-1) - obj.Data(2:end);
                %aux = diff(obj.Data);
                rise = find(aux == -1)' + 1;
                fall = find(aux == 1)';
                if (~isempty(rise) && isempty(fall)) || (numel(rise) ~= numel(fall))
                    if numel(fall) < numel(rise)
                        fall = [fall;length(obj.Data)];
                    else
                        rise = [1;rise];
                    end
                elseif sum((rise - fall) > 0)
                    if obj.Data(1)
                        rise = [1;rise];
                    end
                    if obj.Data(end)
                        fall = [fall;length(obj.Data)];
                    end
                elseif isempty(rise) && isempty(fall)
                    if sum(obj.Data)
                        % All data is a constant 1. Otherwise, the data
                        % contains no steps.
                        rise = 1;
                        fall = obj.NSamples;
                    else
                        warning('No steps found in these data!')
                        fprintf('Returning empty variables...\n')
                    end
                end
                RaF = [rise,fall];
            end % isa double/logical ?
        end
    end
    
    %% Static methods
    methods (Static, Access = 'private')
        function edgeOut = cleanEdges(edgeIn)
            doubleEdge = edgeIn(1:end-1) + edgeIn(2:end);
            repeatIdx = doubleEdge > 1;
            edgeOut = edgeIn;
            if sum(repeatIdx)
                edgeOut(repeatIdx) = false;
            end
        end
    end
    
    
end

