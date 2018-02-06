function [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, commSendFrame, SSrecord] = SelfSelectedSpeed(velL,velR,FzThreshold)
%This function allows matlab to control the treadmill speed based on
%subject's position on the treadmill in an attempt to allow them to choose
%their self selected pace

global listbox%the text inside the log list on the GUI
global PAUSE%pause button value
global STOP
global manspeed
global SSspeed
global tempstep %for making sure the 40 step buffer is overwritten before recording self select speed again
% global SSrecord
global SSrecstd
global recflag
recflag = 0;
SSrecord = 0;
SSrecstd = 0;
STOP = 0;
tempstep = 0;

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

% try%So that if something fails, communications are closed properly
[FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);

listbox{end+1} = ['Nexus and Bertec Interfaces initialized: ' num2str(clock)];
set(ghandle.listbox1,'String',listbox);

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

pause(1)%wait while the treadmill speeds up and subject finds their "happy place" to walk, then get reference position and begin the controller


%get reference from nexus
[FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);

SubjectName = MyClient.GetSubjectName(1).SubjectName;
LPSIS = MyClient.GetMarkerGlobalTranslation( SubjectName, 'PC1' );
RPSIS = MyClient.GetMarkerGlobalTranslation( SubjectName, 'PC2' );
LASIS = MyClient.GetMarkerGlobalTranslation( SubjectName, 'PC3' );
RASIS = MyClient.GetMarkerGlobalTranslation( SubjectName, 'PC4' );

LPSISref=LPSIS.Translation;%reference positions to use, comes in as a 3x1 double vector
RPSISref=RPSIS.Translation;
LASISref=LASIS.Translation;
RASISref=RASIS.Translation;

REF = mean([LPSISref(2) RPSISref(2) LASISref(2) RASISref(2)]);%this is the reference Y position!!
YOLD = REF;
disp('entered main loop')
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
    old_stanceL=new_stanceL;
    old_stanceR=new_stanceR;
    
    %Read frame, update necessary structures
    [FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);
    
    %get data from Nexus
    Fz_R = MyClient.GetDeviceOutputValue( 'Right Treadmill', 'Fz' );
    Fz_L = MyClient.GetDeviceOutputValue( 'Left Treadmill', 'Fz' );
    if (Fz_R.Result.Value ~= 2) || (Fz_L.Result.Value ~= 2) %failed to find the devices, try the alternate name convention
        Fz_R = MyClient.GetDeviceOutputValue( 'Right', 'Fz' );
        Fz_L = MyClient.GetDeviceOutputValue( 'Left', 'Fz' );
        if (Fz_R.Result.Value ~= 2) || (Fz_L.Result.Value ~= 2)
            STOP = 1;  %stop, the GUI can't find the right forceplate values
            disp('ERROR! Adaptation GUI unable to read forceplate data, check device names and function');
%             datlog.errormsgs{end+1} = 'Adaptation GUI unable to read forceplate data, check device names and function';
        end
    end
%     HANDRAIL_X = MyClient.GetDeviceOutputValue( 'Handrail', 'Fx');
%     HANDRAIL_Y = MyClient.GetDeviceOutputValue( 'Handrail', 'Fy');
%     HANDRAIL_Z = MyClient.GetDeviceOutputValue( 'Handrail', 'Fz');
    
    SubjectName = MyClient.GetSubjectName(1).SubjectName;
    LPSIS = MyClient.GetMarkerGlobalTranslation( SubjectName, 'PC1' );
    RPSIS = MyClient.GetMarkerGlobalTranslation( SubjectName, 'PC2' );
    LASIS = MyClient.GetMarkerGlobalTranslation( SubjectName, 'PC3' );
    RASIS = MyClient.GetMarkerGlobalTranslation( SubjectName, 'PC4' );
    
    LPSISref=LPSIS.Translation;%reference positions to use, comes in as a 3x1 double vector
    RPSISref=RPSIS.Translation;
    LASISref=LASIS.Translation;
    RASISref=RASIS.Translation;
    
    if LPSISref(2) == 0
        LPSISref(2) = nan;
    else
    end
    if RPSISref(2) == 0
        RPSISref(2) = nan;
    else
    end
    if LASISref(2) == 0
        LASISref(2) = nan;
    else
    end
    if RASISref(2) == 0
        RASISref(2) = nan;
    else
    end
%     [LPSISref(2) RPSISref(2) LASISref(2) RASISref(2)]
   
    YPOS = nanmean([LPSISref(2) RPSISref(2) LASISref(2) RASISref(2)]);%the current Y po

%     [REF-YPOS]
    %read from treadmill
    [RBS,LBS,~] = getCurrentData(t);
    
    set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
    set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));
    
%     %determine the new speed!!
%     if abs(HANDRAIL_X.Value) >= 5 || abs(HANDRAIL_Y.Value) >= 5 || abs(HANDRAIL_Z.Value) >=5
%         velupdate = RBS-125;%slow down the belts if someone grabs onto the handrail and keep them slowing down until it stops
%     else
if manspeed == 0 && ~isnan(YPOS)
        if YPOS >= (REF+50) || YPOS <= (REF-50)
            velupdate = RBS+0.2*(REF-YPOS)%-.015*(YPOS-YOLD)/.01
%             [manspeed]
        else %no change
        end
elseif manspeed ~= 0  %change the belt speed regardless of what may be happening
    velupdate = manspeed;
%     ['manspeed set to' num2str(manspeed)]
else
    velupdate = RBS;%use current speed if we don't care what manspeed is and if YPOS is a Nan, all 4 markers are occluded
end
%     end

    %keep track of self selected speed and stdev
%     SSspeed = [SSspeed(2:end) velupdate];%shift values and keep 40 sample moving average
%     set(ghandle.text18,'String',num2str(mean(SSspeed)));
%     set(ghandle.stdevn,'String',num2str(std(SSspeed)));
%     %if the standard deviation is low enough, indicate to operator
%     if std(SSspeed) <= 0.5
%         set(ghandle.stdevn,'BackgroundColor','green');
%     else
%         set(ghandle.stdevn,'BackgroundColor','white');
%     end
    
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
                SSspeed = round([SSspeed(2:end) velupdate]);%shift values and keep 40 sample moving average
                set(ghandle.text18,'String',num2str(round(mean(SSspeed))));
                set(ghandle.stdevn,'String',num2str(round(std(SSspeed))));
                %if the standard deviation is low enough, indicate to operator
                if std(SSspeed) <= 40 && RstepCount-tempstep >= 40  %make sure buffer has been over written before reporting another 
                    set(ghandle.stdevn,'BackgroundColor','green');
                    set(ghandle.text18,'BackgroundColor','green');
                    tempstep = RstepCount;
                    SSrecord(end+1) = round(mean(SSspeed));
                    SSrecstd(end+1) = round(std(SSspeed));
                    recflag = 1;
                    index = length(SSrecord)%this will be used to track further points beyond the 40 steps of steady state
                else
                    set(ghandle.stdevn,'BackgroundColor','white');
                    set(ghandle.text18,'BackgroundColor','white');
                end
                
                if recflag == 1 && velupdate >= SSrecord(index)-SSrecstd(end) && velupdate <= SSrecord(index)+SSrecstd(end)
                    SSrecord(end+1) = velupdate
                else
                    recflag = 0;
                end
                
                
            elseif LTO %Go to single R
                phase=2;
                LstepCount=LstepCount+1;
                LTOTime(LstepCount) = TimeStamp;
                stepFlag=2; %L step
                SSspeed = round([SSspeed(2:end) velupdate]);%shift values and keep 40 sample moving average
                set(ghandle.text18,'String',num2str(round(mean(SSspeed))));
                set(ghandle.stdevn,'String',num2str(round(std(SSspeed))));
                %if the standard deviation is low enough, indicate to operator
                if std(SSspeed) <= 40 && RstepCount-tempstep >= 40  %make sure buffer has been over written before reporting another 
                    set(ghandle.stdevn,'BackgroundColor','green');
                    set(ghandle.text18,'BackgroundColor','green');
                    tempstep = RstepCount;
                    SSrecord(end+1) = round(mean(SSspeed));
                    SSrecstd(end+1) = round(std(SSspeed));
                    recflag = 1;
                    index = length(SSrecord)%this will be used to track further points beyond the 40 steps of steady state
                else
                    set(ghandle.stdevn,'BackgroundColor','white');
                    set(ghandle.text18,'BackgroundColor','white');
                end
                
                if recflag == 1 && velupdate >= SSrecord(index)-SSrecstd(end) && velupdate <= SSrecord(index)+SSrecstd(end)
                    SSrecord(end+1) = velupdate
                else
                    recflag = 0;
                end
            end
        case 1 %single L
            if RHS
                phase=3;
                log = ['Right step #' num2str(LstepCount) ' ' num2str(clock)];
%                 disp(log)
                RHSTime(RstepCount) = TimeStamp;
                set(ghandle.Right_step_textbox,'String',num2str(LstepCount));
                listbox{end+1} = log;
                set(ghandle.listbox1,'String',listbox);
                
                %plot cursor
%                 plot(ghandle.profileaxes,RstepCount,velR(uint8(RstepCount+1))/1000,'o','MarkerFaceColor',[1 0.6 0.78]);
                plot(ghandle.profileaxes,RstepCount,RBS/1000,'o','MarkerFaceColor',[1 0.6 0.78]);

                %                 drawnow;
            end
        case 2 %single R
            if LHS
                phase=4;
                log = ['Left step #' num2str(LstepCount) ' ' num2str(clock)];
%                 disp(log)
                LHSTime(LstepCount) = TimeStamp;
                set(ghandle.Left_step_textbox,'String',num2str(LstepCount));
                listbox{end+1} = log;
                set(ghandle.listbox1,'String',listbox);
                
                %plot cursor
%                 plot(ghandle.profileaxes,LstepCount,velL(uint8(LstepCount+1))/1000,'o','MarkerFaceColor',[0.68 .92 1]);
                plot(ghandle.profileaxes,LstepCount,LBS/1000,'o','MarkerFaceColor',[0.68 .92 1]);

                %                 drawnow;
            end
        case 3 %DS, coming from single L
            if LTO
                phase = 2; %To single R
                LstepCount=LstepCount+1;
                LTOTime(LstepCount) = TimeStamp;
                stepFlag=2; %Left step
                SSspeed = round([SSspeed(2:end) velupdate]);%shift values and keep 40 sample moving average
                set(ghandle.text18,'String',num2str(round(mean(SSspeed))));
                set(ghandle.stdevn,'String',num2str(round(std(SSspeed))));
                %if the standard deviation is low enough, indicate to operator
                if std(SSspeed) <= 40 && RstepCount-tempstep >= 40  %make sure buffer has been over written before reporting another 
                    set(ghandle.stdevn,'BackgroundColor','green');
                    set(ghandle.text18,'BackgroundColor','green');
                    tempstep = RstepCount;
                    SSrecord(end+1) = round(mean(SSspeed));
                    SSrecstd(end+1) = round(std(SSspeed));
                    recflag = 1;
                    index = length(SSrecord)%this will be used to track further points beyond the 40 steps of steady state
                else
                    set(ghandle.stdevn,'BackgroundColor','white');
                    set(ghandle.text18,'BackgroundColor','white');
                end
                
                if recflag == 1 && velupdate >= SSrecord(index)-SSrecstd(end) && velupdate <= SSrecord(index)+SSrecstd(end)
                    SSrecord(end+1) = velupdate
                else
                    recflag = 0;
                end
            end
        case 4 %DS, coming from single R
            if RTO
                phase =1; %To single L
                RstepCount=RstepCount+1;
                RTOTime(RstepCount) = TimeStamp;
                stepFlag=1; %R step
                SSspeed = round([SSspeed(2:end) velupdate]);%shift values and keep 40 sample moving average
                set(ghandle.text18,'String',num2str(round(mean(SSspeed))));
                set(ghandle.stdevn,'String',num2str(round(std(SSspeed))));
                %if the standard deviation is low enough, indicate to operator
                if std(SSspeed) <= 40 && RstepCount-tempstep >= 40  %make sure buffer has been over written before reporting another 
                    set(ghandle.stdevn,'BackgroundColor','green');
                    set(ghandle.text18,'BackgroundColor','green');
                    tempstep = RstepCount;
                    SSrecord(end+1) = round(mean(SSspeed));
                    SSrecstd(end+1) = round(std(SSspeed));
                    recflag = 1;
                    index = length(SSrecord)%this will be used to track further points beyond the 40 steps of steady state
                else
                    set(ghandle.stdevn,'BackgroundColor','white');
                    set(ghandle.text18,'BackgroundColor','white');
                end
                
                if recflag == 1 && velupdate >= SSrecord(index)-SSrecstd(end) && velupdate <= SSrecord(index)+SSrecstd(end)
                    SSrecord(end+1) = velupdate
                else
                    recflag = 0;
                end
            end
    end
    
    
    %Every now & then, send an action
    auxTime=clock;
    elapsedCommTime=etime(auxTime,lastCommandTime);
    if (elapsedCommTime>0.2)&&(LstepCount<N)&&(RstepCount<N)&&(stepFlag>0) %Orders are at least 200ms apart, only sent if a new step was detected, and max steps has not been exceeded.
        [payload] = getPayload(velupdate,velupdate,750,750,0);
        sendTreadmillPacket(payload,t);
        lastCommandTime=clock;
        commSendTime(LstepCount+RstepCount+1,:)=clock;
        commSendFrame(LstepCount+RstepCount+1)=FrameNo;
        stepFlag=0;
%         YOLD = YPOS;%update derivative calculation
%         disp(['Packet sent, Lspeed = ' num2str(velL(LstepCount+1)) ', Rspeed = ' num2str(velR(RstepCount+1))])
    end
    
    if (LstepCount>=N) || (RstepCount>=N)
        log = ['Reached the end of programmed speed profile, no further commands will be sent ' num2str(clock)];
        disp(log);
        listbox{end+1} = log;
        set(ghandle.listbox1,'String',listbox);

        break; %While loop
    end
    YOLD = YPOS;%update derivative calculation
end %While, when STOP button is pressed

% save('SelfSelectedSpeedsRecord','SSrecord');
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

try
    closeNexusIface(MyClient);
    closeTreadmillComm(t);
catch ME
    log=['Error ocurred when closing communications with Nexus & Treadmill (maybe they were not open?) ' num2str(clock)];
    listbox{end+1}=log;
    disp(log);
end
%}

save('SelfSelectedSpeedsRecord','SSrecord');
end

