function [looptime Rstept Rstepp Lstept Lstepp] = SelfSelectedSpeed_swing_rev3(velL,velR)
%Self-selected speed based on swing velocity of contralateral legs, to be
%used for post-adaptation scenarios where we want to measure a tendancy, if
%any, to return from adaptation to normal gait. WDA 8/8/2014. 
%Rev 3 is a new animal, a simplified way of performing what the older
%functions do
%
%   velL and VelR are speed profiles to be passed in from the adaptation
%   GUI. 
%% 
%declare global variables needed
global STOP
global PAUSE

STOP = 0;
PAUSE = 0;
ghandle = guidata(AdaptationGUI);%get handle to the GUI so displayed data can be updated

%%
%Initialize communication with Nexus and Treadmill
[MyClient] = openNexusIface();
t = openTreadmillComm();

%%
%Initialize variables, pointers, and arrays
RstepCount = libpointer('doublePtr',1);%will be used for indexing, so cannot start at stride '0'
LstepCount = libpointer('doublePtr',1);
RTOt = libpointer('doublePtr',clock);%time at right toe-off
RTOp = libpointer('doublePtr',0);%position at right toe-off
LTOt = libpointer('doublePtr',clock);
LTOp = libpointer('doublePtr',0);
RHSt = libpointer('doublePtr',clock);%time at right HS
LHSt = libpointer('doublePtr',clock);%time at left HS
RHSp = libpointer('doublePtr',0);
LHSp = libpointer('doublePtr',0);
lastcommandtime = libpointer('doublePtr',clock);%the last time command was sent to the treadmill
lastFrameTime = libpointer('doublePtr',clock);%the last time we had a frame
curTime= libpointer('doublePtr',clock);%the current time
N = libpointer('int32Ptr',length(velL));%max # of steps allowed
z = libpointer('doublePtr',1);%counting variable
Lswing = libpointer('doublePtr',velR(1));%left swing speed
Rswing = libpointer('doublePtr',velL(1));%right swing speed
looptime = zeros(1000000,1);%create giant array for looptimes, pre-allocated for speed
Rstept = zeros(1000000,1);%arrays that record the calculated times and distances of swing phase
Rstepp = zeros(1000000,1);
Lstept = zeros(1000000,1);
Lstepp = zeros(1000000,1);

%send first speed command, get things going
[payload] = getPayload(velR(1),velL(1),1000,1000,0);
sendTreadmillPacket(payload,t);
set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(1)/1000));
set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(1)/1000));

[~,~,~,~,~,~,~] = NexusGetFrame(MyClient);
%initialize gait events
Fz_R_old = MyClient.GetDeviceOutputValue( 'Right Treadmill', 'Fz' );
Fz_L_old = MyClient.GetDeviceOutputValue( 'Left Treadmill', 'Fz' );
Fz_R_old = Fz_R_old.Value;
Fz_L_old = Fz_L_old.Value;

%%
%Begin loop
while STOP == 0
    %check if PAUSE is pressed
    while PAUSE %if pressed, stop treadmill
        pause(.1);
        [payload] = getPayload(0,0,500,500,0);
        sendTreadmillPacket(payload,t);
    end
    
    %calculate elapsed loop time
    lastFrameTime.Value = curTime.Value;
    curTime.Value = clock;
    looptime(z.Value) = etime(curTime.Value,lastFrameTime.Value);
    
    %read from treadmill
%     [RBS,LBS,~] = getCurrentData(t);
    %get frame of data from Nexus
%     [~,~,~,~,~,~,~] = NexusGetFrame(MyClient);%I don't care about any of the values that are normally returned by this function
    MyClient.GetFrame();%get a frame from nexus
    Fz_R = MyClient.GetDeviceOutputValue( 'Right Treadmill', 'Fz' );
    Fz_L = MyClient.GetDeviceOutputValue( 'Left Treadmill', 'Fz' );
    if (Fz_R.Result.Value ~= 2) || (Fz_L.Result.Value ~= 2) %failed to find the devices, try the alternate name convention
        Fz_R = MyClient.GetDeviceOutputValue( 'Right', 'Fz' );
        Fz_L = MyClient.GetDeviceOutputValue( 'Left', 'Fz' );
        if (Fz_R.Result.Value ~= 2) || (Fz_L.Result.Value ~= 2)
            STOP = 1;  %stop, the GUI can't find the right forceplate values
            disp('ERROR! Adaptation GUI unable to read forceplate data, check device names and function');
            datlog.errormsgs{end+1} = 'Adaptation GUI unable to read forceplate data, check device names and function';
        end
    end
    Fz_R = Fz_R.Value;
    Fz_L = Fz_L.Value;
    
    SubjectName = MyClient.GetSubjectName(1).SubjectName;
    
    LANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LANK' );
    RANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RANK' );
    LANK = LANK.Translation;
    RANK = RANK.Translation;
    
    if LANK(2) == 0%Nexus assigns "0" when it doesn't know where a marker is,it should be turned into nan, to avoid function errors
        LANK(2) = nan;
    end
    if RANK(2) == 0
        RANK(2) = nan;
    end

    %detect gait events
    if (Fz_R <= -20) && (Fz_R_old > -20) %RHS
        RHSt.Value = clock;%immediatly get time when HS becomes detectable by this function (actual time of HS may vary)
        RHSp.Value = RANK(2);%get Y position of ankle at HS
        set(ghandle.Right_step_textbox,'String',num2str(LstepCount.Value));
%         plot(ghandle.profileaxes,RstepCount.Value,velR(RstepCount.Value)/1000,'o','MarkerFaceColor','red');%this line creates too much delay...
        drawnow
        Rstept(RstepCount.Value+1) = etime(RTOt.Value,RHSt.Value);%calculate time between HS and previous TOFF
        Rstepp(RstepCount.Value+1) = diff([RHSp.Value RTOp.Value]);
        
        if RstepCount.Value > 10
            Rswing.Value = abs(Rstepp(RstepCount.Value+1)/Rstept(RstepCount.Value+1));%-0.03*RBS;%right swing velocity, assuming the right belt is the fast one, add %4.23 to the belt speed to match realistic swing speed
        else
        end
        
        RstepCount.Value = RstepCount.Value+1;%keep track of strides taken
        
    elseif Fz_L <= -20 && Fz_L_old > -20%LHS
        LHSt.Value = clock;
        LHSp.Value = LANK(2);
        set(ghandle.Left_step_textbox,'String',num2str(LstepCount.Value));
%         plot(ghandle.profileaxes,LstepCount.Value,velL(LstepCount.Value)/1000,'o','MarkerFaceColor','blue');% creates too much delay
        drawnow
        Lstept(LstepCount.Value+1) = etime(LTOt.Value,LHSt.Value);
        Lstepp(LstepCount.Value+1) = diff([LHSp.Value LTOp.Value]);
        
        if LstepCount.Value > 10
            Lswing.Value = abs(Lstepp(LstepCount.Value+1)/Lstept(LstepCount.Value+1));%-0.03*LBS;%left swing velocity, assuming the slow leg
        else
        end
        LstepCount.Value = LstepCount.Value+1;
        
    elseif Fz_R > -20 && Fz_R_old <= -20%RTO
        RTOt.Value = clock;
        RTOp.Value = RANK(2);
        %Determine whether to write a new speed
        if (etime(clock,lastcommandtime.Value)>0.2) && (LstepCount.Value<N.Value) && (RstepCount.Value<N.Value)
            [payload] = getPayload(Lswing.Value,Rswing.Value,1000,1000,0);
%             [payload] = getPayload(velR(RstepCount.Value+1),velL(LstepCount.Value),1000,1000,0);%!!!!!Note, belt speeds should only be updated after toe-off on one side at a time, so the indexing in this line is not a mistake!
            sendTreadmillPacket(payload,t);
            lastcommandtime.Value=clock;
        end
        
    elseif Fz_L > -20 && Fz_L_old <= -20%LTO
        LTOt.Value = clock;
        LTOp.Value = LANK(2);
        %Determine whether to write a new speed
        if (etime(clock,lastcommandtime.Value)>0.2) && (LstepCount.Value<N.Value) && (RstepCount.Value<N.Value)
            [payload] = getPayload(Lswing.Value,Rswing.Value,1000,1000,0);
%             [payload] = getPayload(velR(RstepCount.Value),velL(LstepCount.Value+1),1000,1000,0);%Again, the indexing here is not a mistake
            sendTreadmillPacket(payload,t);
            lastcommandtime.Value=clock;
        end
        
    end

    %check to see if it's time to stop
    if (LstepCount.Value>=N.Value) || (RstepCount.Value>=N.Value)
        break; %While loop
    end
    z.Value=z.Value+1;
    Fz_R_old = Fz_R;%before getting new data, save the old for one loop
    Fz_L_old = Fz_L;
end


%%
%close communications and return
if get(ghandle.StoptreadmillSTOP_checkbox,'Value')==1 && STOP == 1
    [payload] = getPayload(0,0,500,500,0);
    sendTreadmillPacket(payload,t);
else
end
%see if the treadmill is supposed to stop at the end of the profile
if get(ghandle.StoptreadmillEND_checkbox,'Value')==1
    [payload] = getPayload(0,0,500,500,0);
    set(ghandle.Status_textbox,'String','Stopping...');
    set(ghandle.Status_textbox,'BackgroundColor','red');
    pause(1)%provide a little time to collect the last steps and so forth
    sendTreadmillPacket(payload,t);
else
end

closeNexusIface(MyClient);
closeTreadmillComm(t);




end


















