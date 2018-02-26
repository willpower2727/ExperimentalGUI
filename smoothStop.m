function smoothStop(t)
    %NEW SMOOTH STOP ATTEMPT: (comment to revert)
%     [cur_speedR,cur_speedL,cur_incl] = getCurrentData(t); %Read treadmill speed
    [cur_speedR,cur_speedL,cur_incl] = readTreadmillPacket(t);
    v=[cur_speedR,cur_speedL];
    [vM,iM]=max(abs(v));
    [vn,in]=min(abs(v));
    %Set decceleration rates proportional to current speed (so both belts
    %stop at the same time)
    %aR=abs(cur_speedR)*700/vM; %Stopping at 700 mm/s^2 for f
    %aL=abs(cur_speedL)*700/vM;
    %First: get the fast belt to go at the speed of the slow one:
    a=2*(vM-vn); %Take half a second to match the speeds
    [payload] = getPayload(v(in),v(in),a,a,cur_incl); %Set both belts equal to the slowest
    sendTreadmillPacket(payload,t);
    %expectedSlowdownTime=(vM-vn)/700; %Expected time until both belts
    %match each other, if decelerating at 700mm/s^2
    expectedSlowdownTime=.5;
    pause(expectedSlowdownTime+.2)%Wait 
    %Then ask for a full stop, in another 500ms:
    a=2*vn;
    [payload] = getPayload(0,0,a,a,cur_incl);
    disp('created stop')
    sendTreadmillPacket(payload,t)
    disp('sent stop')

    %WHAT WE WERE DOING BEFORE: (uncomment to revert)
    %[payload] = getPayload(0,0,500,500,0);
    %sendTreadmillPacket(payload,t);
end

