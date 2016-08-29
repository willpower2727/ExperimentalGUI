function [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, commSendFrame, Lswing,Rswing,Lstance,Rstance,whiletime,Lstept,Rstept,Lstancet,Rstancet,Lstepp,Rstepp,Lstancep,Rstancep] = SelfSelectedSpeed_swing(velL,velR,FzThreshold)
%This function allows matlab to control the treadmill speed based on
%subject's swing speed, in an attempt to measure the presence of a natural
%tendancy to return to a normal symetric gait after being adapted to split
%belt condition
%WDA 6/27/2014

global listbox%the text inside the log list on the GUI
global PAUSE%pause button value
global STOP
global manspeed
global SSrecord
global RTOt%time at TO
global LTOt
global RHSt%time at HS
global LHSt
global Rstept%swing time from TO to HS
global Lstept
global LANK%ankle position
global RANK
global RHSp%ankle position at HS
global LHSp
global RTOp%ankle position at TO
global LTOp
global Rstepp%swing distance from TO to HS
global Lstepp
global Rswing
global Lswing
global Lstancet
global Lstancep
global Rstancet
global Rstancep
global LTOE
global RTOE
global whiletime


% recflag = 0;
SSrecord = 0;
% SSrecstd = 0;
RTOt = clock;
LTOt = clock;
RHSt = clock;
LHSt = clock;
Rstept = 0;
Lstept = 0;
LANK = nan;
RANK = nan;
RHSp = 0;
LHSp = 0;
RTOp = 0;
LTOp = 0;
Rstepp = 0;
Lstepp = 0;
% Rvelupdate = [500 500 500 500 500];
% Lvelupdate = [1000 1000 1000 1000 1000];
Rswing = velL(1);
Lswing = velR(1);

Lstancet = 0;
Rstancet = 0;
Lstancep = 0;
Rstancep = 0;

Lstance = 0;
Rstance = 0;


STOP = 0;
% tempstep = 0;

manspeed = 0;

ghandle = guidata(AdaptationGUI);%get handle to the GUI so displayed data can be updated

%Intiate timing
baseTime=clock;
curTime=baseTime;
lastCommandTime=baseTime;

listbox = {'Function "SelfSelectedSpeed" called at: ' num2str(baseTime)};
drawnow;

%Default threshold
if nargin<3
    FzThreshold=30; %Newtons (30 is minimum for noise not to be an issue)
elseif FzThreshold<30
    warning = ['Warning: Fz threshold too low to be robust to noise, using 30N instead'];
    %     disp(warning);
    listbox{end+1} = warning;
    set(ghandle.listbox1,'String',listbox);
end

%Check that velL and velR are of equal length
N=length(velL);
if length(velL)~=length(velR)
    warning = ['Velocity vectors of different length'];
    %     disp(warning);
    listbox{end+1} = warning;
    set(ghandle.listbox1,'String',listbox);
    return
end

%Initialize nexus & treadmill comm
try
[MyClient] = openNexusIface();
t = openTreadmillComm();
catch ME
    log=['Error ocurred when opening communications with Nexus & Treadmill'];
    listbox{end+1}=log;
    disp(log);
end

%  try%So that if something fails, communications are closed properly
[FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);

listbox{end+1} = ['Nexus and Bertec Interfaces initialized: ' num2str(clock)];
set(ghandle.listbox1,'String',listbox);

%Initiate variables
new_stanceL=false;
new_stanceR=false;
phase=0; %0= Double Support, 1 = single L support, 2= single R support
LstepCount=1;
RstepCount=1;
RTOTime(N)=TimeStamp;
LTOTime(N)=TimeStamp;
RHSTime(N)=TimeStamp;
LHSTime(N)=TimeStamp;
commSendTime=zeros(2*N-1,6);
commSendFrame=zeros(2*N-1,1);
stepFlag=0;
% keyboard
%initialize speed for controller
velupdate = velL(1);

%Send first speed command
[payload] = getPayload(velR(1),velL(1),1000,1000,0);%speed up a little slower 
sendTreadmillPacket(payload,t);
commSendTime(1,:)=clock;
set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(1)/1000));
set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(1)/1000));
log1 = ['Packet sent, Lspeed = ' num2str(velL(LstepCount+1)) ', Rspeed = ' num2str(velR(RstepCount+1))];
disp(log1);
listbox{end+1} = log1;
set(ghandle.listbox1,'String',listbox);

%get reference from nexus
[FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);

z=1;
%% Main loop
while STOP == 0 %only runs if stop button is not pressed
    while PAUSE %only runs if pause button is pressed
        pause(.1);
        log=['Paused at ' num2str(clock)];
        disp(log)
        listbox{end+1}=log;
        
        %bring treadmill to a stop and keep it there!...
        [payload] = getPayload(0,0,500,500,0);
        sendTreadmillPacket(payload,t);
        
    end
    %newSpeed
    drawnow;
    lastFrameTime=curTime;
    curTime=clock;
    elapsedFrameTime=etime(curTime,lastFrameTime);
    whiletime(z) = elapsedFrameTime;
    old_stanceL=new_stanceL;
    old_stanceR=new_stanceR;
    
    %Read frame, update necessary structures
    [FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);
    
    %get data from Nexus
    Fz_R = MyClient.GetDeviceOutputValue( 'Right Treadmill', 'Fz' );
    Fz_L = MyClient.GetDeviceOutputValue( 'Left Treadmill', 'Fz' );
    
    SubjectName = MyClient.GetSubjectName(1).SubjectName;
    
    LANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LANK' );
    RANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RANK' );
    LTOE = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LTOE' );
    RTOE = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RTOE' );
    
    LANK = LANK.Translation;
    RANK = RANK.Translation;
    LTOE = LTOE.Translation;
    RTOE = RTOE.Translation;
    
    if LANK(2) == 0
        LANK(2) = nan;
    end
    if RANK(2) == 0
        RANK(2) = nan;
    end
    if LTOE(2) == 0
        LTOE(2) = nan;
    end
    if RTOE(2) == 0
        RTOE(2) = nan;
    end
    
    %read from treadmill
    [RBS,LBS,~] = getCurrentData(t);
    
    set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
    set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));
    
    new_stanceL=Fz_L.Value<-FzThreshold; %20N Threshold
    new_stanceR=Fz_R.Value<-FzThreshold;
    
    LHS=new_stanceL && ~old_stanceL;
    RHS=new_stanceR && ~old_stanceR;
    LTO=~new_stanceL && old_stanceL;
    RTO=~new_stanceR && old_stanceR;
    
    %State Machine: 0 = initial, 1 = single L, 2= single R, 3 = DS from
    %single L, 4= DS from single R
    switch phase
        case 0 %DS, only initial phase
            if RTO
                phase=1; %Go to single L
                RstepCount=RstepCount+1;
                RTOTime(RstepCount) = TimeStamp;
                stepFlag=1; %R step
                
%                 RTOtime = FrameNo;
                
            elseif LTO %Go to single R
                phase=2;
                LstepCount=LstepCount+1;
                LTOTime(LstepCount) = TimeStamp;
                stepFlag=2; %L step
                
%                 LTOtime = FrameNo;

            end
        case 1 %single L
            if RHS
                RHSt = clock;%immediatly get time when HS becomes detectable by this function (actual time of HS may vary)
                RHSp = RANK(2);%get position of ankle at HS
                phase=3;
                log = ['Right step #' num2str(LstepCount) ' ' num2str(clock)]
                RHSTime(RstepCount) = TimeStamp;
                set(ghandle.Right_step_textbox,'String',num2str(LstepCount));
                listbox{end+1} = log;
                set(ghandle.listbox1,'String',listbox);
                
                %plot cursor
                plot(ghandle.profileaxes,RstepCount,RBS/1000,'o','MarkerFaceColor',[1 0.6 0.78]);

                Rstept(RstepCount+1) = etime(RTOt,RHSt);%calculate time between HS and previous TOFF
                Rstepp(RstepCount+1) = diff([RHSp RTOp]);

                %disp(RBS);
                %disp(LBS);
                if RstepCount > 10
                Rswing = abs(Rstepp(RstepCount+1)/Rstept(RstepCount+1));%-0.03*RBS;%right swing velocity, assuming the right belt is the fast one, add %4.23 to the belt speed to match realistic swing speed
                
                else
                    
                end
%                 whos
                
            end
        case 2 %single R
            if LHS
                LHSt = clock;
                LHSp = LANK(2);
                phase=4;
                log = ['Left step #' num2str(LstepCount) ' ' num2str(clock)]
                LHSTime(LstepCount) = TimeStamp;
                set(ghandle.Left_step_textbox,'String',num2str(LstepCount));
                listbox{end+1} = log;
                set(ghandle.listbox1,'String',listbox);
                plot(ghandle.profileaxes,LstepCount,LBS/1000,'o','MarkerFaceColor',[0.68 .92 1]);            
                Lstept(LstepCount+1) = etime(LTOt,LHSt);
                Lstepp(LstepCount+1) = diff([LHSp LTOp]);

%                 Lvelupdate = [Lvelupdate(2:end) (abs(Lstepp/Lstept))];
                if LstepCount > 10
%                 Lswing(LstepCount) = abs(Lstepp(LstepCount+1)/Lstept(LstepCount+1));%left swing velocity
                Lswing = abs(Lstepp(LstepCount+1)/Lstept(LstepCount+1));%-0.03*LBS;%left swing velocity, assuming the slow leg
                
                else
                end
            end
        case 3 %DS, coming from single L
            if LTO
                phase = 2; %To single R
                LstepCount=LstepCount+1;
                LTOTime(LstepCount) = TimeStamp;
                stepFlag=2; %Left step
                LTOt = clock;
                LTOp = LANK(2);
                
                %calculate the stance time, to compare and determine gain
                %needed to get this right.
                Lstancet(LstepCount+1) = etime(LTOt,LHSt);
                Lstancep(LstepCount+1) = diff([LHSp LTOp]);
                Lstance(LstepCount+1) = abs(Lstancep(LstepCount+1)/Lstancet(LstepCount+1));%left stance vel

            end
        case 4 %DS, coming from single R
            if RTO
                phase =1; %To single L
                RstepCount=RstepCount+1;
                RTOTime(RstepCount) = TimeStamp;
                stepFlag=1; %R step
                RTOt = clock;
                RTOp = RANK(2);
                
                %calculate the stance time, to compare and determine gain
                %needed to get this right.
                Rstancet(RstepCount+1) = etime(RTOt,RHSt);
                Rstancep(RstepCount+1) = diff([RHSp RTOp]);
                Rstance(RstepCount+1) = abs(Rstancep(RstepCount+1)/Rstancet(RstepCount+1));%right stance vel
                
            end
    end
    
    
    %Every now & then, send an action
    auxTime=clock;
    elapsedCommTime=etime(auxTime,lastCommandTime);
    if (elapsedCommTime>0.2)&&(LstepCount<N)&&(RstepCount<N)&&(stepFlag>0) %Orders are at least 200ms apart, only sent if a new step was detected, and max steps has not been exceeded.
        [payload] = getPayload(Lswing,Rswing,1000,1000,0);%sends new speeds based on feedback from contralateral swing speeds
%         [payload] = getPayload(velR(RstepCount+1),velL(LstepCount+1),1000,1000,0);%sends speed of selected profile, so as to debug timing of contralateral steps
        sendTreadmillPacket(payload,t);
        lastCommandTime=clock;
        commSendTime(LstepCount+RstepCount+1,:)=clock;
        commSendFrame(LstepCount+RstepCount+1)=FrameNo;
        stepFlag=0;
%         disp(['Packet sent, Lspeed = ' num2str(velL(LstepCount+1)) ', Rspeed = ' num2str(velR(RstepCount+1))])
    end
    
    if (LstepCount>=N) || (RstepCount>=N)
        log = ['Reached the end of programmed speed profile, no further commands will be sent ' num2str(clock)];
        disp(log);
        listbox{end+1} = log;
        set(ghandle.listbox1,'String',listbox);

        break; %While loop
    end
    z=z+1;
end %While, when STOP button is pressed
if STOP
    log=['Stop button pressed, stopping... ' num2str(clock)];
    listbox{end+1}=log;
%     disp(log);
else
end
% catch ME
%     log=['Error ocurred during the control loop'];%End try
%     listbox{end+1}=log;
%     disp(log);
% % keyboard
% end
%% Closing routine
%End communications

%see if the treadmill should be stopped when the STOP button is pressed
if get(ghandle.StoptreadmillSTOP_checkbox,'Value')==1 && STOP == 1
    
%     set(ghandle.Status_textbox,'String','Stopped');
%     set(ghandle.Status_textbox,'BackgroundColor','red');

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
% keyboard
try
    closeNexusIface(MyClient);
    closeTreadmillComm(t);
catch ME
    log=['Error ocurred when closing communications with Nexus & Treadmill (maybe they were not open?) ' num2str(clock)];
    listbox{end+1}=log;
    disp(log);
end
%}


end

