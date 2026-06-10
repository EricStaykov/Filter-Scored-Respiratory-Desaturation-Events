% Written by Eric Staykov (2026)
% This is code to filter scored respiratory and desaturation events to make scoring consistent across cohorts.  

respEventCriteria.ALL_EVENTS = 0;
respEventCriteria.AHI3PA = 1;
respEventCriteria.AHI3 = 2;
respEventCriteria.AHI4 = 3;
mySettings.respEventCriteriaSetting = respEventCriteria.AHI3PA; % SET THIS SETTING!
desatEventCriteria.ALL_DESATS = 0;
desatEventCriteria.DESATS_3P = 1;
desatEventCriteria.DESATS_4P = 2;
mySettings.desatEventCriteriaSetting = desatEventCriteria.DESATS_3P; % SET THIS SETTING!

filename = "test.mat"; % SET THIS WITH THE NAME OF YOUR FILE
convertedMat = load(filename);
convertedMat.Evts = filterRespiratoryEventsUsingCriteria(convertedMat.Evts, convertedMat.SigT, respEventCriteria, mySettings);
convertedMat.Evts = filterDesatEventsUsingCriteria(convertedMat.Evts, convertedMat.SigT, convertedMat.Info, desatEventCriteria, mySettings);

% Filter respiratory events based on selected criteria
% If AHI3PA is set, only respiratory events that begin in an epoch of sleep are included. All apneas are included and only hypopneas with ≥3% desaturation or arousal are kept (AASM recommended criteria), which is consistent with current AASM guidelines.
% Troester M, Quan SF, Berry R, Plante D, Abreu A, Alzoubaidi M, et al. The AASM Manual for the Scoring of Sleep and Associated Events: Rules, Terminology and Technical Specifications. Version 3. Darien, IL: American Academy of Sleep Medicine; 2023.
function [Evts] = filterRespiratoryEventsUsingCriteria(Evts, SigT, respEventCriteria, mySettings)
    % want to remove resp events that don't meet the criteria from BOTH Evts.RespT and Evts.Table1
    % iterate through RespT and find corressponding event in Table1
    % if doesn't meet criteria, then add to remove list
    RespT = Evts.RespT;
    Table1 = Evts.Table1;
    if isfield(Evts,  'EventCodesList')
        EventName = Evts.EventCodesList;
    else
        EventName = Evts.EventName;
    end
    toRemoveRespT = [];
    toRemoveTable1 = [];
    for i=1:size(RespT,1)
        eventInfo = RespT(i,:);
        indexTable1 = find((Table1.EventStart == eventInfo.EventStart) & (Table1.EventCodes == eventInfo.EventCodes) & (Table1.EventDuration == eventInfo.EventDuration));
        if isempty(indexTable1)
            disp("Error!");
            continue;
        end
        if (mySettings.respEventCriteriaSetting == respEventCriteria.AHI3)
            criteria = "InclAHI3";
        elseif (mySettings.respEventCriteriaSetting == respEventCriteria.AHI3PA)
            criteria = "InclAHI3a";
        elseif (mySettings.respEventCriteriaSetting == respEventCriteria.AHI4)
            criteria = "InclAHI4";
        else
            continue;
        end
        if (sum(eventInfo.Properties.VariableNames == criteria) > 0)
            eval(sprintf("keepEvent = eventInfo.%s;", criteria));
        else
            % calculate spo2 desat here and apply selected criteria
            indexes = (SigT.Time >= eventInfo.EventStart) & (SigT.Time < (eventInfo.EventStart + eventInfo.EventDuration));
            spo2Snippet = SigT.SpO2(indexes);
            [minValue, minIndex] =  min(spo2Snippet);
            spo2SnippetUpToMin = spo2Snippet(1:minIndex);
            deltaSpo2 = max(spo2SnippetUpToMin) - minValue;
            if (mySettings.respEventCriteriaSetting == respEventCriteria.AHI3) || (mySettings.respEventCriteriaSetting == respEventCriteria.AHI3PA)
                criteria = 3;
            elseif (mySettings.respEventCriteriaSetting == respEventCriteria.AHI4)
                criteria = 4;
            end
            if deltaSpo2 < criteria
                keepEvent = 0;
            else
                keepEvent = 1;
            end
        end
        if ~keepEvent
            toRemoveRespT = [ toRemoveRespT i ];
            toRemoveTable1 = [ toRemoveTable1 indexTable1 ];
        end
    end
    if ~isempty(toRemoveRespT)
        RespT(toRemoveRespT,:) = [];
    end
    if ~isempty(toRemoveTable1)
        Table1(toRemoveTable1,:) = [];
        EventName(toRemoveTable1,:) = [];
    end
    Evts.RespT = RespT;
    Evts.Table1 = Table1;
    if isfield(Evts,  'EventCodesList')
        Evts.EventCodesList = EventName;
    else
        Evts.EventName = EventName;
    end
end

% Filter scored desaturation events based on selected criteria
% If DESATS_3P is set, only desaturations ≥3% from baseline to nadir are kept.
function [Evts] = filterDesatEventsUsingCriteria(Evts, SigT, Info, desatEventCriteria, mySettings)
    indexesToRemove = [];
    pupEvents = Evts.Table1;
    pupStartTime = Info.StartTimeInfo.StartTime;
    adjustedStartTimes = pupEvents.EventStart - pupStartTime;
    eventDurations = pupEvents.EventDuration;
    if isfield(Evts,  'EventCodesList')
        eventNames = Evts.EventCodesList;
    else
        eventNames = Evts.EventName;
    end
    desaturationIndexes = find(contains(eventNames, 'SpO2 desaturation')); % the PUP code for desats is NaN which can refer to other things like 'Limb Movement (Right)'
    pupEvents.adjustedStartTimes = adjustedStartTimes;
    for i = 1:size(desaturationIndexes,1)
        desatIndex = desaturationIndexes(i);
        desatInfo = pupEvents(desatIndex, :);
        indexes = (SigT.Time >= desatInfo.EventStart) & (SigT.Time < (desatInfo.EventStart + desatInfo.EventDuration));
        spo2Snippet = SigT.SpO2(indexes);
        [minValue, minIndex] =  min(spo2Snippet);
        spo2SnippetUpToMin = spo2Snippet(1:minIndex);
        deltaSpo2 = max(spo2SnippetUpToMin) - minValue;
        if (mySettings.desatEventCriteriaSetting == desatEventCriteria.DESATS_3P)
            criteria = 3;
        elseif (mySettings.desatEventCriteriaSetting == desatEventCriteria.DESATS_4P)
            criteria = 4;
        else
            continue;
        end
        if deltaSpo2 < criteria
            indexesToRemove = [indexesToRemove desatIndex];
            if 0
                fig = figure; plot(spo2Snippet); hold on; plot(spo2SnippetUpToMin); title(sprintf("start time = %.2f, delta = %d", desatInfo.adjustedStartTimes, deltaSpo2));
                keyboard
                close(fig);
            end
        end
    end
    if ~isempty(indexesToRemove)
        Evts.Table1(indexesToRemove,:) = [];
        if isfield(Evts,  'EventCodesList')
            Evts.EventCodesList(indexesToRemove,:) = [];
        else
            Evts.EventName(indexesToRemove,:) = [];
        end
    end
end

