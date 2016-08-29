
function [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, commSendFrame] = controlSpeedWithSteps_edit2(velL,velR,FzThreshold)
%This function takes two vectors of speeds (one for each treadmill belt)
%and succesively updates the belt speed upon ipsilateral Heel Strike
%The function only updates the belts simultaneously,
%The first value for velL and velR is the initial desired speed, and new
%speeds will be sent for the following N-1 steps, where N is the length of
%velL
global listbox%the text inside the log list on the GUI
global PAUSE%pause button value
global STOP
global MyClient

STOP = 0;%make sure that these values are ready when execute is pressed
PAUSE = 0;

ghandle = guidata(AdaptationGUI);%get handle to the GUI so displayed data can be updated
set(ghandle.text6,'String','Step Count');
%Intiate timing
baseTime=clock;
curTime=baseTime;
lastCommandTime=baseTime;

listbox = {'Function "controlspeedwithsteps_edit1" called at: ' num2str(baseTime)};
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
[MyClient] = openNexusIface();
pause(1);%give some time before asking for information
[FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);
t = openTreadmillComm();
listbox{end+1} = ['Nexus and Bertec Interfaces initialized: ' num2str(clock)];
set(ghandle.listbox1,'String',listbox);

%Initiate variables
RTOTime(N)=TimeStamp;
LTOTime(N)=TimeStamp;
RHSTime(N)=TimeStamp;
LHSTime(N)=TimeStamp;
commSendTime=zeros(2*N-1,6);
commSendFrame=zeros(2*N-1,1);

FzR_old = 0;
FzL_old = 0;
set(ghandle.Status_textbox,'String','Counting Steps');
drawnow;
HS = 0;%HS = Heel Strike

while ~STOP%If stop button is pressed this loop ends
    
    [FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);
    pause(0.05);
    Fz_R = MyClient.GetDeviceOutputValue( 'Right Treadmill', 'Fz' );
    Fz_L = MyClient.GetDeviceOutputValue( 'Left Treadmill', 'Fz' );
    
    %read from treadmill
    [RBS,LBS,theta] = getCurrentData(t);
    
    set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
    set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));
    
    %detect if a Right HS has occured
    if abs(Fz_R.Value) >= FzThreshold && FzR_old == 0
        if PAUSE == 0
        HS = HS+1;
        else
        end
    else
    end
    %detect if Left HS has occured
    if abs(Fz_L.Value) >= FzThreshold && FzL_old == 0
        if PAUSE == 0
        HS = HS+1;
        else
        end
    else
    end
    
    %update GUI display of Step Count
    set(ghandle.StepCount_textbox,'String',num2str(HS));
    drawnow;
    FzR_old = Fz_R.Value;
    FzL_old = Fz_L.Value;
    
    %Now write commands to Treadmill
    if HS == length(velR) || HS == length(velL)
        STOP = 1;
    else
    [payload] = getPayload(velR(HS+1),velL(HS+1),1000,1000,0);
    sendTreadmillPacket(payload,t);
    set(ghandle.text11,'String',num2str(velL(HS+1)/1000));
    set(ghandle.text12,'String',num2str(velR(HS+1)/1000));
    end
%     pause(0.1);
end

set(ghandle.Status_textbox,'String','Finished!');
set(ghandle.Status_textbox,'BackgroundColor','green');

closeNexusIface(MyClient);
closeTreadmillComm(t);
%Old Code that Pablo wrote
%{
%Initiate GUI with stop button
MessageBox = msgbox( ['Stop Treadmill Loop ']);

%Main loop
while ishandle( MessageBox )
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
                RTOTime(RstepCount) = TimeStamp;
                stepFlag=1; %R step
            elseif LTO %Go to single R
                phase=2;
                LstepCount=LstepCount+1;
                LTOTime(LstepCount) = TimeStamp;
                stepFlag=2; %L step
            end
        case 1 %single L
            if RHS
                phase=3;
                log = ['Right step #' num2str(LstepCount) ' ' num2str(clock)];
                disp(log)
                RHSTime(RstepCount) = TimeStamp;
                set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount+1)/1000));
                set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount+1)/1000));
                set(ghandle.StepCount_textbox,'String',num2str(LstepCount));
                listbox{end+1} = log;
                set(ghandle.listbox1,'String',listbox);
                
%                 y = uint8(LstepCount);
%                 y2 = uint8(RstepCount);
                
%                 plot(ghandle.profileaxes,RstepCount,velR(uint8(RstepCount+1)),LstepCount,velL(uint8(LstepCount+1)),'o','MarkerFaceColor','red');
%                 drawnow;
            end
        case 2 %single R
            if LHS
                phase=4;
                log = ['Left step #' num2str(LstepCount) ' ' num2str(clock)];
                disp(log)
                LHSTime(LstepCount) = TimeStamp;
                set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount+1)/1000));
                set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount+1)/1000));
                set(ghandle.StepCount_textbox,'String',num2str(LstepCount));
                listbox{end+1} = log;
                set(ghandle.listbox1,'String',listbox);
                
                %plot cursor
%                 keyboard
%                 plot(ghandle.profileaxes,RstepCount,velR(uint8(RstepCount+1)),LstepCount,velL(uint8(LstepCount+1)),'o','MarkerFaceColor','red');
%                 drawnow;
            end
        case 3 %DS, coming from single L
            if LTO
                phase = 2; %To single R
                LstepCount=LstepCount+1;
                LTOTime(LstepCount) = TimeStamp;
                stepFlag=2; %Left step
            end
        case 4 %DS, coming from single R
            if RTO
                phase =1; %To single L
                RstepCount=RstepCount+1;
                RTOTime(RstepCount) = TimeStamp;
                stepFlag=1; %R step
            end
    end
    
    
    %Every now & then, send an action
    auxTime=clock;
    elapsedCommTime=etime(auxTime,lastCommandTime);
    if (elapsedCommTime>0.2)&&(LstepCount<N)&&(RstepCount<N)&&(stepFlag>0) %Orders are at least 200ms apart, only sent if a new step was detected, and max steps has not been exceeded.
        [payload] = getPayload(velR(RstepCount+1),velL(LstepCount+1),1000,1000,0);
        sendTreadmillPacket(payload,t);
        lastCommandTime=clock;
        commSendTime(LstepCount+RstepCount+1,:)=clock;
        commSendFrame(LstepCount+RstepCount+1)=FrameNo;
        stepFlag=0;
        disp(['Packet sent, Lspeed = ' num2str(velL(LstepCount+1)) ', Rspeed = ' num2str(velR(RstepCount+1))])
    end
    
    if (LstepCount>=N) || (RstepCount>=N)
        log = ['Reached the end of programmed speed profile, no further commands will be sent ' num2str(clock)];
        disp(log);
        listbox{end+1} = log;
        set(ghandle.listbox1,'String',listbox);
        if exist('MessageBox','var')
            delete(MessageBox)
%             close(MessageBox);
            clear MessageBox
        end
        break; %While loop
    end
end %While, when STOP button is pressed
%End communications
closeNexusIface(MyClient);
closeTreadmillComm(t);
%}