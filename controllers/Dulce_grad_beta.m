
function [Rbetarecord,Lbetarecord,Rmeanbeta,Lmeanbeta,Rstdbeta,Lstdbeta] = Dulce_grad_beta(velL,velR,FzThreshold)
%This function takes two vectors of speeds (one for each treadmill belt)
%and succesively updates the belt speed upon ipsilateral Toe-Off
%The function only updates the belts alternatively, i.e., a single belt
%speed cannot be updated twice without the other being updated
%The first value for velL and velR is the initial desired speed, and new
%speeds will be sent for the following N-1 steps, where N is the length of
%velL
% global listbox%the text inside the log list on the GUI
global PAUSE %pause button value
global STOP
STOP = false;
global Rbetarecord
global Lbetarecord
global LTOp
global LHSp
global RTOp
global RHSp
Rbetarecord = zeros(10000,1);%pre-allocate size for speed
Lbetarecord = zeros(10000,1);
LTOp = 0;
LHSp = 0;
RTOp = 0;
RHSp = 0;

ghandle = guidata(AdaptationGUI);%get handle to the GUI so displayed data can be updated

%Intiate timing
baseTime=clock;
curTime=baseTime;
lastCommandTime=baseTime;

%Default threshold
if nargin<3
    FzThreshold=30; %Newtons (30 is minimum for noise not to be an issue)
elseif FzThreshold<30
    warning = ['Warning: Fz threshold too low to be robust to noise, using 30N instead'];
    %     disp(warning);
%     listbox{end+1} = warning;
%     set(ghandle.listbox1,'String',listbox);
end

%Check that velL and velR are of equal length
N=length(velL);
if length(velL)~=length(velR)
    warning = ['Velocity vectors of different length'];
    %     disp(warning);
%     listbox{end+1} = warning;
%     set(ghandle.listbox1,'String',listbox);
    return
end

%Initialize nexus & treadmill comm
try
[MyClient] = openNexusIface();
t = openTreadmillComm();
catch ME
    log=['Error ocurred when opening communications with Nexus & Treadmill'];
%     listbox{end+1}=log;
    disp(log);
end

% try %So that if something fails, communications are closed properly
[FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);

% listbox{end+1} = ['Nexus and Bertec Interfaces initialized: ' num2str(clock)];
% set(ghandle.listbox1,'String',listbox);

%Initiate variables
new_stanceL=false;
new_stanceR=false;
phase=0; %0= Double Support, 1 = single L support, 2= single R support
LstepCount=0;
RstepCount=0;
RTOTime(N)=TimeStamp;
LTOTime(N)=TimeStamp;
RHSTime(N)=TimeStamp;
LHSTime(N)=TimeStamp;
commSendTime=zeros(2*N-1,6);
commSendFrame=zeros(2*N-1,1);
stepFlag=0;

[cur_speedR,cur_speedL,cur_incl] = getCurrentData(t); %Read treadmill speed, most importantly we want the current incline value
%Send first speed command
[payload] = getPayload(velR(1),velL(1),1000,1000,cur_incl);
sendTreadmillPacket(payload,t);
commSendTime(1,:)=clock;
% log1 = ['Packet sent, Lspeed = ' num2str(velL(LstepCount+1)) ', Rspeed = ' num2str(velR(RstepCount+1))];
% disp(log1);
% listbox{end+1} = log1;
% set(ghandle.listbox1,'String',listbox);

%Old Code...
%Initiate GUI with stop button
%MessageBox = msgbox( ['Stop Treadmill Loop ']);

%% Main loop
%while ishandle( MessageBox )
while ~STOP %only runs if stop button is not pressed
    while PAUSE %only runs if pause button is pressed
        pause(.1);
%         log=['Paused at ' num2str(clock)];
%         disp(log)
%         listbox{end+1}=log;
        %bring treadmill to a stop and keep it there!...
        [payload] = getPayload(0,0,500,500,cur_incl);
        sendTreadmillPacket(payload,t);
    end
    %newSpeed
    drawnow;
    lastFrameTime=curTime;
    curTime=clock;
    elapsedFrameTime=etime(curTime,lastFrameTime);
    old_stanceL=new_stanceL;
    old_stanceR=new_stanceR;
    
    %Read frame, update necessary structures
    [FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);
    %Assuming there is only 1 subject, and that I care about a marker called MarkerA (e.g. Subject=Wand)
    Fz_R = MyClient.GetDeviceOutputValue( 'Right Treadmill', 'Fz' );
    Fz_L = MyClient.GetDeviceOutputValue( 'Left Treadmill', 'Fz' );
    
    %get marker data for the ankles and GT to be used in the state machine
    %to calculate gamma stuff...
    SubjectName = MyClient.GetSubjectName(1).SubjectName;
    LANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LANK' );
    RANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RANK' );
    LHIP = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LHIP' );
    RHIP = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RHIP' );
    LANK = LANK.Translation;
    RANK = RANK.Translation;
    LHIP = LHIP.Translation;
    RHIP = RHIP.Translation;
    LANK = LANK(2);
    RANK = RANK(2);
    LHIP = LHIP(2);
    RHIP = RHIP(2);
    
    %read from treadmill
    [RBS,LBS,theta] = getCurrentData(t);
    
    set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
    set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));
    
    new_stanceL=Fz_L.Value<-FzThreshold; %20N Threshold
    new_stanceR=Fz_R.Value<-FzThreshold;
    
    LHS=new_stanceL && ~old_stanceL;
    RHS=new_stanceR && ~old_stanceR;
    LTO=~new_stanceL && old_stanceL;
    RTO=~new_stanceR && old_stanceR;
    
    %Maquina de estados: 0 = initial, 1 = single L, 2= single R, 3 = DS from
    %single L, 4= DS from single R
    switch phase
        case 0 %DS, only initial phase
            if RTO
                phase=1; %Go to single L
                RstepCount=RstepCount+1;
%                 RTOTime(RstepCount) = TimeStamp;
                stepFlag=1; %R step
                RTOp= RHIP-RANK;
            elseif LTO %Go to single R
                phase=2;
                LstepCount=LstepCount+1;
%                 LTOTime(LstepCount) = TimeStamp;
                stepFlag=2; %L step
                LTOp = LHIP-LANK;
            end
        case 1 %single L
            if RHS
                phase=3;
                set(ghandle.Right_step_textbox,'String',num2str(LstepCount));
                %plot cursor
                plot(ghandle.profileaxes,RstepCount,velR(RstepCount+1)/1000,'o','MarkerFaceColor',[1 0.6 0.78],'MarkerEdgeColor','r');
                set(ghandle.Right_step_textbox,'String',num2str(RstepCount));
                drawnow;
%                 disp('RHS position');
                RHSp = RHIP-RANK
                %now calculate gamma
                Rbetarecord(RstepCount+1) = (-RTOp)/RHSp;
            end
        case 2 %single R
            if LHS
                phase=4;
                set(ghandle.Left_step_textbox,'String',num2str(LstepCount));
                %plot cursor
                plot(ghandle.profileaxes,LstepCount,velL(LstepCount+1)/1000,'o','MarkerFaceColor',[0.68 .92 1],'MarkerEdgeColor','b');
                set(ghandle.Left_step_textbox,'String',num2str(LstepCount));
                drawnow;
%                 disp('LHS position');
                LHSp= LHIP-LANK;
                Lbetarecord(LstepCount+1) = (-LTOp)/LHSp;
            end
        case 3 %DS, coming from single L
            if LTO
                phase = 2; %To single R
                LstepCount=LstepCount+1;
                stepFlag=2; %Left step
                LTOp = LHIP-LANK;
            end
        case 4 %DS, coming from single R
            if RTO
                phase =1; %To single L
                RstepCount=RstepCount+1;
                stepFlag=1; %R step
                RTOp = RHIP-RANK;
            end
    end
    
    
    %Every now & then, send an action
    auxTime=clock;
    elapsedCommTime=etime(auxTime,lastCommandTime);
    if (elapsedCommTime>0.2)&&(LstepCount<N)&&(RstepCount<N)&&(stepFlag>0) %Orders are at least 200ms apart, only sent if a new step was detected, and max steps has not been exceeded.
        [payload] = getPayload(velR(RstepCount+1),velL(LstepCount+1),1000,1000,cur_incl);
        sendTreadmillPacket(payload,t);
        lastCommandTime=clock;
        commSendTime(LstepCount+RstepCount+1,:)=clock;
        commSendFrame(LstepCount+RstepCount+1)=FrameNo;
        stepFlag=0;
%         disp(['Packet sent, Lspeed = ' num2str(velL(LstepCount+1)) ', Rspeed = ' num2str(velR(RstepCount+1))])
    end
    
    if (LstepCount>=N) || (RstepCount>=N)
        log = ['Reached the end of programmed speed profile, no further commands will be sent ' num2str(clock)];
        break; %While loop
    end
end %While, when STOP button is pressed
if STOP
    log=['Stop button pressed, stopping... ' num2str(clock)];
%     listbox{end+1}=log;
    disp(log);
else
end
% catch ME
%     log=['Error ocurred during the control loop'];%End try
% %     listbox{end+1}=log;
%     disp(log);
% end
%% Closing routine
%End communications

%see if the treadmill is supposed to stop at the end of the profile
if get(ghandle.StoptreadmillEND_checkbox,'Value')==1 && STOP ~=1
    set(ghandle.Status_textbox,'String','Stopping...');
    set(ghandle.Status_textbox,'BackgroundColor','red');
    pause(1)%provide a little time to collect the last steps and so forth
    smoothStop(t);
else
end

%see if the treadmill should be stopped when the STOP button is pressed
if get(ghandle.StoptreadmillSTOP_checkbox,'Value')==1 && STOP == 1
    
%     set(ghandle.Status_textbox,'String','Stopped');
%     set(ghandle.Status_textbox,'BackgroundColor','red');
    smoothStop(t);

else
end



try
    closeNexusIface(MyClient);
    closeTreadmillComm(t);
catch ME
    log=['Error ocurred when closing communications with Nexus & Treadmill (maybe they were not open?) ' num2str(clock)];
%     listbox{end+1}=log;
    disp(log);
end

%Finally, prepare the data to be returned
Rbetarecord(Rbetarecord == 0) = [];
Lbetarecord(Lbetarecord == 0) = [];
Rmeanbeta = median(Rbetarecord);
Lmeanbeta = median(Lbetarecord);
Rstdbeta = std(Rbetarecord);
Lstdbeta = std(Lbetarecord);





%}