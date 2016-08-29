function smoothStop(t)
    %NEW SMOOTH STOP ATTEMPT: (comment to revert)
%     [cur_speedR,cur_speedL,cur_incl] = getCurrentData(t); %Read treadmill speed
    [cur_speedR,cur_speedL,cur_incl] = readTreadmillPacket(t);
    v=[cur_speedR,cur_speedL];
    [vM,iM]=max(abs(v));
    [vn,in]=min(abs(v));
    %Set decceleration rates proportional to current speed (so both belts
    %stop at the same time)
    aR=abs(cur_speedR)*700/vM;
    aL=abs(cur_speedL)*700/vM;
    %First: get the fast belt to go at the speed of the slow one:
    [payload] = getPayload(v(in),v(in),aR,aL,cur_incl);
    sendTreadmillPacket(payload,t);
    expectedStopTime=(vM-vn)/700;
    %expectedStopTime=(v(iM)-v(in))/500;
    pause(expectedStopTime+.4)
%     pause(2)
    %Then ask for a full stop:
    [payload] = getPayload(0,0,700,700,cur_incl);
    disp('created stop')
    sendTreadmillPacket(payload,t)
    disp('sent stop')
    clear aR aL

    %WHAT WE WERE DOING BEFORE: (uncomment to revert)
    %[payload] = getPayload(0,0,500,500,0);
    %sendTreadmillPacket(payload,t);
end

