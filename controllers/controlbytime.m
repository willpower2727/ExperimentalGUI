
function [] = controlbytime(velL,velR,FzThreshold,profilename)
%This function takes two inputs, speed profiles for RER test, 
%and updates belt speeds based on time elapsed
%The function only updates the belts alternatively, i.e., a single belt
%speed cannot be updated twice without the other being updated
%
%speed updates are sent during swing phase bilaterally (not at the same
%time)
%
%WDA 12/4/2015

global PAUSE%pause button value
global STOP
STOP = false;

ghandle = guidata(AdaptationGUI);%get handle to the GUI so displayed data can be updated

%disable the pause button, it should not be pressed
set(ghandle.Pause_togglebutton,'Enable','off');

%do a correction on the plot
t = [0:length(velL)-1];

set(ghandle.profileaxes,'NextPlot','replace')
plot(ghandle.profileaxes,t,velL/1000,'b',t,velR/1000,'r','LineWidth',2);
if isrow(velL) && isrow(velR)
    ylim([min([velL/1000 velR/1000])-1,max([velL/1000 velR/1000])+1]);
else
    ylim([min([velL/1000;velR/1000])-1,max([velL/1000;velR/1000])+1]);
end

xlabel('Time (s)');
ylabel('Speed (m/s)');
legend('Left Foot','Right Foot');
set(ghandle.profileaxes,'NextPlot','add')



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
[~,filename,~] = fileparts(profilename);
savename = [temp '_controlbytime_' filename];
set(ghandle.sessionnametxt,'String',savename);
datlog.session_name = savename;
datlog.errormsgs = {};
datlog.messages = {};
datlog.framenumbers.header = {'frame #','U Time','Relative Time'};
datlog.framenumbers.data = zeros(120*length(velR)+240,2);
datlog.inclineang = [];
datlog.speedprofile.velL = velL;
datlog.speedprofile.velR = velR;
datlog.beltspeeds.header = {'frame#','elapsedtime','Rspeed','Lspeed','rhs','rto','lhs','lto'};
datlog.beltspeeds.data = zeros(120*length(velR),8);
datlog.speedcommands.header = {'frame#','velR','velL','incl'};
datlog.speedcommands.data = zeros(120*length(velR),4);
datlog.targets.header = {'Frame#','Step #','time','step length'};
datlog.targets.Rdata = zeros(length(velR)+20,4);
datlog.targets.Ldata = zeros(length(velL)+20,4);

%do initial save
try
    disp(['C:\Users\BioE\Documents\MATLAB\ExperimentalGUI\datlogs\',savename])
    save(['C:\Users\BioE\Documents\MATLAB\ExperimentalGUI\datlogs\',savename],'datlog');
catch ME
    disp(ME);
    disp(ME.stack);
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
%     MyClient.SetStreamMode(StreamMode.ServerPush);%fastest matlab can do
    MyClient.SetStreamMode(StreamMode.ClientPull);
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
LstepCount=0;
RstepCount=0;

[~,~,cur_incl] = readTreadmillPacket(t); %Read treadmill incline angle
datlog.inclineang = cur_incl;

if cur_incl ~= 0
    warndlg('WARNING!!! WARNING!!! Treadmill incline is detected as non zero, this function was not meant to be used for decline walking!! Please stop and consult the code before continuing.','STOP!','modal');
end

%Send first speed command
[payload] = getPayload(velR(1),velL(1),1000,1000,cur_incl);
sendTreadmillPacket(payload,t);

pause(3);

set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(1)/1000));
set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(1)/1000));

datlog.messages{end+1} = ['First speed command sent' num2str(now)];
datlog.messages{end+1} = ['Lspeed = ' num2str(velL(1)) ', Rspeed = ' num2str(velR(1))];

%% Main loop

histRz = libpointer('doublePtr',0);
histLz = libpointer('doublePtr',0);
old_velR = libpointer('doublePtr',velR(1));
old_velL = libpointer('doublePtr',velL(1));
frameind = libpointer('doublePtr',1);
framenum = libpointer('doublePtr',0);
starttime = clock;
elaptime = 0;
rflag = 0;
lflag = 0;
rhs = 0;
lhs = 0;
rto = 0;
lto = 0;
rspeed = velL(1);
lspeed = rspeed;
LstepCount=1;
RstepCount=1;

while ~STOP %only runs if stop button is not pressed
    while PAUSE %only runs if pause button is pressed
        pause(.2);
        datlog.messages{end+1} = ['Loop paused at ' num2str(now)];
        disp(['Paused at ' num2str(clock)]);
        %bring treadmill to a stop and keep it there!...
        [payload] = getPayload(0,0,500,500,cur_incl);
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

    MyClient.GetFrame();
    framenum.Value = MyClient.GetFrameNumber().FrameNumber;
    datlog.framenumbers.data(frameind.Value,:) = [framenum.Value now];
    
    frameind.Value = frameind.Value+1;

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
    
    SubjectCount = MyClient.GetSubjectCount();
    
    if SubjectCount.SubjectCount > 2
        disp('ERROR: more than 2 subject models are active, please review code to handle this situation');
        datlog.errormsgs{end+1} = 'ERROR: more than 2 subject models are active, please review code to handle this situation';
        STOP = 1;
    end
    
    SubjectName = MyClient.GetSubjectName(1).SubjectName;
    if strcmp(SubjectName,'DK2')
        SubjectName = MyClient.GetSubjectName(2).SubjectName;%look for the other subject
        LANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LANK');
        RANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RANK');
        if (LANK.Result.Value ~= 2) || (RANK.Result.Value ~= 2)
            disp(LANK.Result.Value);%display what is happening
        end
    else
        LANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LANK');
        RANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RANK');
        if (LANK.Result.Value ~= 2) || (RANK.Result.Value ~= 2)
            disp(LANK.Result.Value);%display what is happening
        end
    end
    
    LANK = LANK.Translation;
    RANK = RANK.Translation;
    LANK = LANK(2);
    RANK = RANK(2);

    if Fz_R.Value > -30 && histRz.Value <= -30 %RTO
        %time to update r belt speed
        rflag = 1;
        rto = 1;
        rhs = 0;
    elseif Fz_R.Value <=-30 && histRz.Value > -30 %RHS
        RstepCount = RstepCount+1;
        datlog.targets.Rdata(RstepCount-1,:) = [framenum.Value,RstepCount-1,etime(clock,starttime),LANK-RANK];
        set(ghandle.Right_step_textbox,'String',num2str(RstepCount));
        rflag = 0;
        rhs = 1;
        rto = 0;
    else
        rflag = 0;
    end
    
    if Fz_L.Value>-30 && histLz.Value <= -30 %LTO
        lflag = 1;
        lto = 1;
        lhs = 0;
    elseif Fz_L.Value <= -30 && histLz.Value > -30 %LHS
        LstepCount = LstepCount+1;
        datlog.targets.Ldata(LstepCount-1,:) = [framenum.Value,LstepCount-1,etime(clock,starttime),RANK-LANK];
        set(ghandle.Left_step_textbox,'String',num2str(LstepCount));
        lflag = 0;
        lhs = 1;
        lto = 0;
    else
        lflag = 0;
    end
    
    
    if etime(clock,starttime) < 180 %3 minutes of 25% of OG speed
        %do not update speeds
        elaptime = etime(clock,starttime);
        [~,~,~] = readTreadmillPacket(t);%also read what the treadmill is doing
    elseif 180 <= etime(clock,starttime) && etime(clock,starttime) < 360
        
        %ask for current state
        [rspeed, lspeed,~] = readTreadmillPacket(t);%also read what the treadmill is doing
        set(ghandle.RBeltSpeed_textbox,'String',num2str(rspeed/1000));
        set(ghandle.LBeltSpeed_textbox,'String',num2str(lspeed/1000));
        
        %ramp
        elaptime = etime(clock,starttime);
        if rflag
            rnewspeed = velR(1)+(velR(end)-velR(1))/180*(etime(clock,starttime)-180);
            datlog.speedcommands.data(frameind.Value,:) = [framenum.Value,rnewspeed,lspeed,cur_incl];
            payload = getPayload(rnewspeed,lspeed,1000,1000,cur_incl);
            sendTreadmillPacket(payload,t);
        end
        
        if lflag
            lnewspeed = velL(1)+(velL(end)-velL(1))/180*(etime(clock,starttime)-180);
            datlog.speedcommands.data(frameind.Value,:) = [framenum.Value,rspeed,lnewspeed,cur_incl];
            payload = getPayload(rspeed,lnewspeed,1000,1000,cur_incl);
            sendTreadmillPacket(payload,t);
        end
        
%     elseif etime(clock,starttime) >= 360 && etime(clock,starttime) <= 540
%         elaptime = etime(clock,starttime);
%         if lflag || rflag
%             payload = getPayload(velL(end),velL(end),1000,1000,cur_incl);
%             sendTreadmillPacket(payload,t);
%         end
       
    elseif etime(clock,starttime) > 360
        STOP = 1;
    end

    histRz.Value = Fz_R.Value;
    histLz.Value = Fz_L.Value;
    set(ghandle.text25,'String',num2str(round(etime(clock,starttime),2)));

    datlog.beltspeeds.data(frameind.Value,:) = [framenum.Value elaptime rspeed lspeed rhs rto lhs lto];
   
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

try %stopping the treadmill
%see if the treadmill is supposed to stop at the end of the profile
    if get(ghandle.StoptreadmillEND_checkbox,'Value')==1 && STOP ~=1
        set(ghandle.Status_textbox,'String','Stopping...');
        set(ghandle.Status_textbox,'BackgroundColor','red');
        pause(1)%provide a little time to collect the last steps and so forth
        smoothStop(t);
    %see if the treadmill should be stopped when the STOP button is pressed
    elseif get(ghandle.StoptreadmillSTOP_checkbox,'Value')==1 && STOP == 1

    %     set(ghandle.Status_textbox,'String','Stopped');
    %     set(ghandle.Status_textbox,'BackgroundColor','red');
        smoothStop(t);
    end
    
catch ME
    datlog.errormsgs{end+1} = 'Error stopping the treadmill';
    datlog.errormsgs{end+1} = ME;
end
    
set(ghandle.Pause_togglebutton,'Enable','on');
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

%finalize the values of targets and prepare the mean values
temp = find(datlog.targets.Rdata(:,2)<=0,1,'first');
datlog.targets.Rdata(temp:end,:) = [];
temp = find(datlog.targets.Ldata(:,2)<=0,1,'first');
datlog.targets.Ldata(temp:end,:) = [];
datlog.targets.Xr = mean(datlog.targets.Rdata(:,2));
datlog.targets.Xl = mean(datlog.targets.Ldata(:,2));
disp(['Mean Xr is: ' num2str(datlog.targets.Xr)]);
disp(['Mean Xl is: ' num2str(datlog.targets.Xl)]);

%find index of Right belt speeds
[~,~,x1] = intersect(datlog.targets.Rdata(:,1),datlog.beltspeeds.data(:,1));
[~,~,x2] = intersect(datlog.targets.Ldata(:,1),datlog.beltspeeds.data(:,1));


figure(5)
subplot(3,2,2)
plot(datlog.beltspeeds.data(x1,3),datlog.targets.Rdata(:,4))
title('Right Step Length')
xlabel('Velocity (mm/s)')
ylabel('SL')
subplot(3,2,1)
plot(datlog.targets.Rdata(:,3),datlog.targets.Rdata(:,4))
title('Right Step Length')
xlabel('Time (s)')
ylabel('SL')
subplot(3,2,4)
plot(datlog.beltspeeds.data(x2,4),datlog.targets.Ldata(:,4));
title('Left Step Length')
xlabel('Velocity (mm/s)')
ylabel('SL')
subplot(3,2,3)
plot(datlog.targets.Ldata(:,3),datlog.targets.Ldata(:,4));
title('Left Step Length')
xlabel('Time (s)')
ylabel('SL')

m = min([length(datlog.targets.Rdata),length(datlog.targets.Ldata)]);

temp = (datlog.targets.Rdata(1:m,4)-datlog.targets.Ldata(1:m,4))./(datlog.targets.Rdata(1:m,4)+datlog.targets.Ldata(1:m,4));
% temp(isnan(temp))=[];
subplot(3,2,6)
plot(datlog.beltspeeds.data(m,3),temp)
title('Step Length Asymmetry')
xlabel('Velocity (mm/s)')
ylabel('SA')
ylim([-1 1])
subplot(3,2,5)
plot(datlog.targets.Rdata(1:m,3),temp)
title('Step Length Asymmetry')
xlabel('Time (s)')
ylabel('SA')
ylim([-1 1])

disp('saving datlog...');
try
    save(savename,'datlog');
catch ME
    disp(ME);
end

