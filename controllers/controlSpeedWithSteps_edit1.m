
function [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, commSendFrame] = controlSpeedWithSteps_edit1(velL,velR,FzThreshold,profilename)
%This function takes two vectors of speeds (one for each treadmill belt)
%and succesively updates the belt speed upon ipsilateral Toe-Off
%The function only updates the belts alternatively, i.e., a single belt
%speed cannot be updated twice without the other being updated
%The first value for velL and velR is the initial desired speed, and new
%speeds will be sent for the following N-1 steps, where N is the length of
%velL

global PAUSE%pause button value
global STOP
STOP = false;

ghandle = guidata(AdaptationGUI);%get handle to the GUI so displayed data can be updated

%initialize a data structure that saves information about the trial
datlog = struct();
datlog.buildtime = now;%timestamp
temp = datestr(datlog.buildtime);
a = regexp(temp,'-');
temp(a) = '_';
b = regexp(temp,':');
temp(b) = '_';
c = regexp(temp,' ');
temp(c) = '_';
[d,n,e]=fileparts(which(mfilename));
savename = [[d '\..\datlogs\'] temp '_' profilename];
set(ghandle.sessionnametxt,'String',savename);
datlog.session_name = savename;
datlog.errormsgs = {};
datlog.messages = {};
datlog.framenumbers.header = {'frame #','U Time','Relative Time'};
datlog.framenumbers.data = zeros(300*length(velR)+7200,2);
datlog.forces.header = {'frame #','U time','Rfz','Lfz','Relative Time'};
datlog.forces.data = zeros(300*length(velR)+7200,4);
datlog.stepdata.header = {'Step#','U Time','frame #','Relative Time'};
datlog.stepdata.RHSdata = zeros(length(velR)+50,3);%empty cell theoretically big enough to house all the steps taken
datlog.stepdata.RTOdata = zeros(length(velR)+50,3);
datlog.stepdata.LHSdata = zeros(length(velL)+50,3);
datlog.stepdata.LTOdata = zeros(length(velL)+50,3);
datlog.inclineang = [];
datlog.speedprofile.velL = velL;
datlog.speedprofile.velR = velR;
datlog.TreadmillCommands.header = {'RBS','LBS','angle','U Time','Relative Time'};
datlog.TreadmillCommands.read = nan(300*length(velR)+7200,4);
datlog.TreadmillCommands.sent = nan(300*length(velR)+7200,4);%nan(length(velR)+50,4);

%do initial save
try
    save(savename,'datlog');
catch ME
    disp(ME);
end
%Default threshold
if nargin<3
    FzThreshold=30; %Newtons (30 is minimum for noise not to be an issue)
elseif FzThreshold<30
%     warning = ['Warning: Fz threshold too low to be robust to noise, using 30N instead'];
    datlog.messages{end+1} = 'Warning: Fz threshold too low to be robust to noise, using 30N instead';
    disp('Warning: Fz threshold too low to be robust to noise, using 30N instead');
end

%Check that velL and velR are of equal length
N=length(velL)+1;
if length(velL)~=length(velR)
    disp('WARNING, velocity vectors of different length!');
    datlog.messages{end+1} = 'Velocity vectors of different length selected';
end

%Initialize nexus & treadmill communications
try
% [MyClient] = openNexusIface();
    Client.LoadViconDataStreamSDK();
    MyClient = Client();
    Hostname = 'localhost:801';
    out = MyClient.Connect(Hostname);
    out = MyClient.EnableMarkerData();
    out = MyClient.EnableDeviceData();
    MyClient.SetStreamMode(StreamMode.ServerPush);
    %MyClient.SetStreamMode(StreamMode.ClientPull);
catch ME
    disp('Error in creating Nexus Client Object/communications see datlog for details');
    datlog.errormsgs{end+1} = 'Error in creating Nexus Client Object/communications';
    datlog.errormsgs{end+1} = ME;%store specific error
    disp(ME);
end
try
t = openTreadmillComm();
catch ME
    disp('Error in creating TCP connection to Treadmill, see datlog for details...');
    datlog.errormsgs{end+1} = 'Error in creating TCP connection to Treadmill';
    datlog.errormsgs{end+1} = ME;
    disp(ME);
%     log=['Error ocurred when opening communications with Nexus & Treadmill'];
%     listbox{end+1}=log;
%     disp(log);
end

try %So that if something fails, communications are closed properly
% [FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);
MyClient.GetFrame();
% listbox{end+1} = ['Nexus and Bertec Interfaces initialized: ' num2str(clock)];
datlog.messages{end+1} = ['Nexus and Bertec Interfaces initialized: ' num2str(now)];
% set(ghandle.listbox1,'String',listbox);

%Initiate variables
new_stanceL=false;
new_stanceR=false;
phase=0; %0= Double Support, 1 = single L support, 2= single R support
LstepCount=1;
RstepCount=1;
% RTOTime(N)=TimeStamp;
% LTOTime(N)=TimeStamp;
% RHSTime(N)=TimeStamp;
% LHSTime(N)=TimeStamp;
RTOTime(N) = now;
LTOTime(N) = now;
RHSTime(N) = now;
LHSTime(N) = now;
commSendTime=zeros(2*N-1,6);
commSendFrame=zeros(2*N-1,1);
% stepFlag=0;

[RBS,LBS,cur_incl] = readTreadmillPacket(t); %Read treadmill incline angle
lastRead=now;
datlog.inclineang = cur_incl;
read_theta = cur_incl;

%Added 5/10/2016 for Nimbus start sync, create file on hard drive, then
%delete later after the task is done.
time1 = now;
syncname = fullfile(tempdir,'SYNCH.dat');
[f,~]=fopen(syncname,'wb');
fclose(f);
time2 = now;
disp(etime(datevec(time2),datevec(time1)));

disp('File creation time');


%Send first speed command & store
acc=3500;
[payload] = getPayload(velR(1),velL(1),acc,acc,cur_incl);
sendTreadmillPacket(payload,t);
datlog.TreadmillCommands.firstSent = [velR(RstepCount),velL(LstepCount),acc,acc,cur_incl,now];%record the command
commSendTime(1,:)=clock;
datlog.TreadmillCommands.sent(1,:) = [velR(RstepCount),velL(LstepCount),cur_incl,now];%record the command   
datlog.messages{end+1} = ['First speed command sent' num2str(now)];
datlog.messages{end+1} = ['Lspeed = ' num2str(velL(LstepCount)) ', Rspeed = ' num2str(velR(RstepCount))];

%% Main loop

old_velR = libpointer('doublePtr',velR(1));
old_velL = libpointer('doublePtr',velL(1));
frameind = libpointer('doublePtr',1);
framenum = libpointer('doublePtr',0);
while ~STOP %only runs if stop button is not pressed
    while PAUSE %only runs if pause button is pressed
        pause(.2);
        datlog.messages{end+1} = ['Loop paused at ' num2str(now)];
        disp(['Paused at ' num2str(clock)]);
        %bring treadmill to a stop and keep it there!...
        [payload] = getPayload(0,0,500,500,cur_incl);
        %cur_incl
        sendTreadmillPacket(payload,t);
        %do a quick save
        try
            save(savename,'datlog');
        catch ME
            disp(ME);
        end
        old_velR.Value = 1;%change the old values so that the treadmill knows to resume when the pause button is resumed
        old_velL.Value = 1;
    end
    %newSpeed
    drawnow;
%     lastFrameTime=curTime;
%     curTime=clock;
%     elapsedFrameTime=etime(curTime,lastFrameTime);
    old_stanceL=new_stanceL;
    old_stanceR=new_stanceR;
    
    %Read frame, update necessary structures

    MyClient.GetFrame();
    framenum.Value = MyClient.GetFrameNumber().FrameNumber;
    datlog.framenumbers.data(frameind.Value,:) = [framenum.Value now];
    
    %Read treadmill, if enough time has elapsed since last read
    aux=(datevec(now)-datevec(lastRead));
    if aux(6)>.1 || any(aux(1:5)>0)  %Only read if enough time has elapsed
        [RBS, LBS,read_theta] = readTreadmillPacket(t);%also read what the treadmill is doing
        lastRead=now;
    end
    
    datlog.TreadmillCommands.read(frameind.Value,:) = [RBS,LBS,read_theta,now];%record the read
    set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));
    set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
    
    frameind.Value = frameind.Value+1;
    
    %Assuming there is only 1 subject, and that I care about a marker called MarkerA (e.g. Subject=Wand)
    Fz_R = MyClient.GetDeviceOutputValue( 'Right Treadmill', 'Fz' );
    Fz_L = MyClient.GetDeviceOutputValue( 'Left Treadmill', 'Fz' );
    datlog.forces.data(frameind.Value,:) = [framenum.Value now Fz_R.Value Fz_L.Value];
    Hx = MyClient.GetDeviceOutputValue( 'Handrail', 'Fx' );
    Hy = MyClient.GetDeviceOutputValue( 'Handrail', 'Fy' );
    Hz = MyClient.GetDeviceOutputValue( 'Handrail', 'Fz' );
    Hm = sqrt(Hx.Value^2+Hy.Value^2+Hz.Value^2);
%     keyboard
    %if handrail force is too high, notify the experimentor
    if (Hm > 25)
        set(ghandle.figure1,'Color',[238/255,5/255,5/255]);
    else
        set(ghandle.figure1,'Color',[1,1,1]);
    end
    
    if (Fz_R.Result.Value ~= 2) || (Fz_L.Result.Value ~= 2) %failed to find the devices, try the alternate name convention
        Fz_R = MyClient.GetDeviceOutputValue( 'Right', 'Fz' );
        Fz_L = MyClient.GetDeviceOutputValue( 'Left', 'Fz' );
        if (Fz_R.Result.Value ~= 2) || (Fz_L.Result.Value ~= 2)
            STOP = 1;  %stop, the GUI can't find the forceplate values
            disp('ERROR! Adaptation GUI unable to read forceplate data, check device names and function');
            datlog.errormsgs{end+1} = 'Adaptation GUI unable to read forceplate data, check device names and function';
        end
    end

    %read from treadmill
%     [RBS,LBS,theta] = getCurrentData(t);
%     set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
%     set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));
    
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
                RTOTime(RstepCount) = now;
                datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
                set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount)/1000));
            elseif LTO %Go to single R
                phase=2;
                LstepCount=LstepCount+1;
%                 LTOTime(LstepCount) = TimeStamp;
                LTOTime(LstepCount) = now;
                datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1,now,framenum.Value];
                set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount)/1000));
            end
        case 1 %single L
            if RHS
                phase=3;
                datlog.stepdata.RHSdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
%                 RHSTime(RstepCount) = TimeStamp;
                RHSTime(RstepCount) = now;
                set(ghandle.Right_step_textbox,'String',num2str(LstepCount-1));
                %plot cursor
                plot(ghandle.profileaxes,RstepCount-1,velR(RstepCount)/1000,'o','MarkerFaceColor',[1 0.6 0.78],'MarkerEdgeColor','r');
                drawnow;
                if LTO %In case DS is too short and a full cycle misses the phase switch
                    phase=2;
                    LstepCount=LstepCount+1;
%                   LTOTime(LstepCount) = TimeStamp;
                    LTOTime(LstepCount) = now;
                    datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1,now,framenum.Value];
                    set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount)/1000));
                end
            end
        case 2 %single R
            if LHS
                phase=4;
                datlog.stepdata.LHSdata(LstepCount-1,:) = [LstepCount-1,now,framenum.Value];
%                 LHSTime(LstepCount) = TimeStamp;
                LHSTime(LstepCount) = now;
                set(ghandle.Left_step_textbox,'String',num2str(LstepCount-1));
                %plot cursor
                plot(ghandle.profileaxes,LstepCount-1,velL(LstepCount)/1000,'o','MarkerFaceColor',[0.68 .92 1],'MarkerEdgeColor','b');
                drawnow;
                if RTO %In case DS is too short and a full cycle misses the phase switch
                    phase=1;
                    RstepCount=RstepCount+1;
%                 RTOTime(RstepCount) = TimeStamp;
                    RTOTime(RstepCount) = now;
                    datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
                    set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount)/1000));
                end
            end
        case 3 %DS, coming from single L
            if LTO
                phase = 2; %To single R
                LstepCount=LstepCount+1;
%                 LTOTime(LstepCount) = TimeStamp;
                LTOTime(LstepCount) = now;
                datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1,now,framenum.Value];
                set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount)/1000));
            end
        case 4 %DS, coming from single R
            if RTO
                phase =1; %To single L
                RstepCount=RstepCount+1;
%                 RTOTime(RstepCount) = TimeStamp;
                RTOTime(RstepCount) = now;
                datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
                set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount)/1000));
            end
    end
    
    if LstepCount >= N || RstepCount >= N%if taken enough steps, stop
        break
    %only send a command if it is different from the previous one. Don't
    %overload the treadmill controller with commands
    elseif (velR(RstepCount) ~= old_velR.Value) || (velL(LstepCount) ~= old_velL.Value) && LstepCount<N && RstepCount<N
        payload = getPayload(velR(RstepCount),velL(LstepCount),acc,acc,cur_incl);
        sendTreadmillPacket(payload,t);
        datlog.TreadmillCommands.sent(frameind.Value,:) = [velR(RstepCount),velL(LstepCount),cur_incl,now];%record the command
        disp(['Packet sent, Lspeed = ' num2str(velL(LstepCount)) ', Rspeed = ' num2str(velR(RstepCount))])
%         set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount)/1000));
%         set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount)/1000));
    else
        %simply record what the treadmill should be doing
        datlog.TreadmillCommands.sent(frameind.Value,:) = [velR(RstepCount),velL(LstepCount),cur_incl,now];%record the command
    end
    
    old_velR.Value = velR(RstepCount);
    old_velL.Value = velL(LstepCount);
    
    %{
    %Every now & then, send an action
%     auxTime=clock;
%     elapsedCommTime=etime(auxTime,lastCommandTime);
%     if (elapsedCommTime>0.2)&&(LstepCount<N)&&(RstepCount<N)&&(stepFlag>0) %Orders are at least 200ms apart, only sent if a new step was detected, and max steps has not been exceeded.
%         [payload] = getPayload(velR(RstepCount+1),velL(LstepCount+1),1000,1000,cur_incl);
% %         ['length of payload is: ' num2str(length(payload))];
%         sendTreadmillPacket(payload,t);
%         lastCommandTime=clock;
%         commSendTime(LstepCount+RstepCount+1,:)=clock;
%         commSendFrame(LstepCount+RstepCount+1)=FrameNo;
%         stepFlag=0;
%         disp(['Packet sent, Lspeed = ' num2str(velL(LstepCount+1)) ', Rspeed = ' num2str(velR(RstepCount+1))])
%     end
    
%     if (LstepCount>=N) || (RstepCount>=N)
%         datlog.messages{end+1} = ['Reached the end of programmed speed profile, no further commands will be sent ' num2str(now)];
% %         log = ['Reached the end of programmed speed profile, no further commands will be sent ' num2str(clock)];
%         disp(['Reached the end of programmed speed profile, no further commands will be sent ' num2str(clock)]);
% %         listbox{end+1} = log;
% %         set(ghandle.listbox1,'String',listbox);
% %        if exist('MessageBox','var')
% %            delete(MessageBox)
% %             close(MessageBox);
% %            clear MessageBox
% %        end
%         break; %While loop
%     end
    %}
end %While, when STOP button is pressed
if STOP
    datlog.messages{end+1} = ['Stop button pressed at: ' num2str(now) ' ,stopping... '];
%     log=['Stop button pressed, stopping... ' num2str(clock)];
%     listbox{end+1}=log;
    disp(['Stop button pressed, stopping... ' num2str(clock)]);
    set(ghandle.Status_textbox,'String','Stopping...');
    set(ghandle.Status_textbox,'BackgroundColor','red');
else
end
catch ME
    datlog.errormsgs{end+1} = 'Error ocurred during the control loop';
    datlog.errormsgs{end+1} = ME;
%     log=['Error ocurred during the control loop'];%End try
%     listbox{end+1}=log;
    disp('Error ocurred during the control loop, see datlog for details...');
end
%% Closing routine
%End communications
try
    save(savename,'datlog');
catch ME
    disp(ME);
end

delete(syncname);%added 5/10/2016 delete sync file in prep for next trial

try %stopping the treadmill
%see if the treadmill is supposed to stop at the end of the profile
    if get(ghandle.StoptreadmillEND_checkbox,'Value')==1 && STOP ~=1
        set(ghandle.Status_textbox,'String','Stopping...');
        set(ghandle.Status_textbox,'BackgroundColor','red');
        set(ghandle.figure1,'Color',[1,1,1]);
        pause(1)%provide a little time to collect the last steps and so forth
        smoothStop(t);
    %see if the treadmill should be stopped when the STOP button is pressed
    elseif get(ghandle.StoptreadmillSTOP_checkbox,'Value')==1 && STOP == 1

        set(ghandle.Status_textbox,'String','Stopping');
        set(ghandle.Status_textbox,'BackgroundColor','red');
        pause(1)
        smoothStop(t);
    end
    
catch ME
    datlog.errormsgs{end+1} = 'Error stopping the treadmill';
    datlog.errormsgs{end+1} = ME;
end
    
% pause(1)
disp('closing comms');
try
    closeNexusIface(MyClient);
    closeTreadmillComm(t);
%     keyboard
catch ME
    datlog.errormsgs{end+1} = ['Error ocurred when closing communications with Nexus & Treadmill at ' num2str(clock)];
    datlog.errormsgs{end+1} = ME;
%     log=['Error ocurred when closing communications with Nexus & Treadmill (maybe they were not open?) ' num2str(clock)];
%     listbox{end+1}=log;
    disp(['Error ocurred when closing communications with Nexus & Treadmill, see datlog for details ' num2str(clock)]);
    disp(ME);
end

disp('converting time in datlog...');
%convert time data into clock format then re-save
datlog.buildtime = datestr(datlog.buildtime);

%convert frame times
temp = find(datlog.framenumbers.data(:,1)==0,1,'first');
datlog.framenumbers.data(temp:end,:) = [];
for z = 1:temp-1
    datlog.framenumbers.data(z,3) = etime(datevec(datlog.framenumbers.data(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
%convert force times
datlog.forces.data(1,:) = [];
temp = find(datlog.forces.data(:,1)==0,1,'first');
% keyboard
datlog.forces.data(temp:end,:) = [];
for z = 1:temp-1
    datlog.forces.data(z,5) = etime(datevec(datlog.forces.data(z,2)),datevec(datlog.forces.data(1,2)));
end
%convert RHS times
temp = find(datlog.stepdata.RHSdata(:,1) == 0,1,'first');
datlog.stepdata.RHSdata(temp:end,:) = [];
for z = 1:temp-1
   datlog.stepdata.RHSdata(z,4) = etime(datevec(datlog.stepdata.RHSdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
%convert LHS times
temp = find(datlog.stepdata.LHSdata(:,1) == 0,1,'first');
datlog.stepdata.LHSdata(temp:end,:) = [];
for z = 1:temp-1
   datlog.stepdata.LHSdata(z,4) = etime(datevec(datlog.stepdata.LHSdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
%convert RTO times
temp = find(datlog.stepdata.RTOdata(:,1) == 0,1,'first');
datlog.stepdata.RTOdata(temp:end,:) = [];
for z = 1:temp-1
   datlog.stepdata.RTOdata(z,4) = etime(datevec(datlog.stepdata.RTOdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
%convert LTO times
temp = find(datlog.stepdata.LTOdata(:,1) == 0,1,'first');
datlog.stepdata.LTOdata(temp:end,:) = [];
for z = 1:temp-1
   datlog.stepdata.LTOdata(z,4) = etime(datevec(datlog.stepdata.LTOdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end

%convert command times
temp = find(isnan(datlog.TreadmillCommands.read(:,4)),1,'first');
datlog.TreadmillCommands.read(temp:end,:) = [];
for z = 1:temp-1
    datlog.TreadmillCommands.read(z,4) = etime(datevec(datlog.TreadmillCommands.read(z,4)),datevec(datlog.framenumbers.data(1,2))); %This fails when no frames were received
end

%temp = find(isnan(datlog.TreadmillCommands.sent(:,4)),1,'first');
% datlog.TreadmillCommands.sent(temp:end,:) = [];
 for z = 1:temp-1
     datlog.TreadmillCommands.sent(z,4) = etime(datevec(datlog.TreadmillCommands.sent(z,4)),datevec(datlog.framenumbers.data(1,2)));
 end


disp('saving datlog...');
try
    save(savename,'datlog');
catch ME
    disp(ME);
end

