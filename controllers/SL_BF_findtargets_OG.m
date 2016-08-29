
function [] = SL_BF_findtargets_OG(velL,velR,FzThreshold,profilename)
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
savename = [temp '_SL_BF_FT_OG_' profilename];
set(ghandle.sessionnametxt,'String',savename);
datlog.session_name = savename;
datlog.errormsgs = {};
datlog.messages = {};
datlog.framenumbers.header = {'frame #','U Time','Relative Time'};
datlog.framenumbers.data = zeros(300*length(velR)+7200,2);
% datlog.stepdata.header = {'Step#','U Time','frame #','Relative Time'};
% datlog.stepdata.RHSdata = zeros(length(velR)+50,3);%empty cell theoretically big enough to house all the steps taken
% datlog.stepdata.RTOdata = zeros(length(velR)+50,3);
% datlog.stepdata.LHSdata = zeros(length(velL)+50,3);
% datlog.stepdata.LTOdata = zeros(length(velL)+50,3);
datlog.inclineang = [];
datlog.speedprofile.velL = 'OG';
datlog.speedprofile.velR = 'OG';
datlog.targets.header = {'ANKx','ANKy','ANKz','HIPx','HIPy','HIPz','time'};
datlog.targets.Rdata = zeros(300*length(velR)+7200,7);
datlog.targets.Ldata = zeros(300*length(velR)+7200,7);
% datlog.TreadmillCommands.header = {'RBS','LBS','angle','U Time','Relative Time'};
% datlog.TreadmillCommands.read = zeros(300*length(velR)+7200,4);
% datlog.TreadmillCommands.sent = zeros(length(velR)+50,4);

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
% try
% t = openTreadmillComm();
% catch ME
%     disp('Error in creating TCP connection to Treadmill, see datlog for details...');
%     datlog.errormsgs{end+1} = 'Error in creating TCP connection to Treadmill';
%     datlog.errormsgs{end+1} = ME;
%     disp(ME);
% %     log=['Error ocurred when opening communications with Nexus & Treadmill'];
% %     listbox{end+1}=log;
% %     disp(log);
% end

try %So that if something fails, communications are closed properly
% [FrameNo,TimeStamp,SubjectCount,LabeledMarkerCount,UnlabeledMarkerCount,DeviceCount,DeviceOutputCount] = NexusGetFrame(MyClient);
MyClient.GetFrame();
% listbox{end+1} = ['Nexus and Bertec Interfaces initialized: ' num2str(clock)];
datlog.messages{end+1} = ['Nexus Interface initialized: ' num2str(now)];
% set(ghandle.listbox1,'String',listbox);

%Initiate variables
rtemp = zeros(20000,3);%for storing heel down data, search for min
ltemp = zeros(20000,3);
rstep = 1;
lstep = 1;
rz = 1;
lz = 1;
rphase = 0;
lphase = 0;
%% Main loop
frameind = libpointer('doublePtr',1);
framenum = libpointer('doublePtr',0);
while ~STOP %only runs if stop button is not pressed
    while PAUSE %only runs if pause button is pressed
        pause(.2);
        datlog.messages{end+1} = ['Loop paused at ' num2str(now)];
        disp(['Paused at ' num2str(clock)]);
        try
            save(savename,'datlog');
        catch ME
            disp(ME);
        end
    end
    drawnow;
    
    %Read frame, update necessary structures

    MyClient.GetFrame();
    framenum.Value = MyClient.GetFrameNumber().FrameNumber;
    datlog.framenumbers.data(frameind.Value,:) = [framenum.Value now];
    frameind.Value = frameind.Value+1;
    
    SubjectCount = MyClient.GetSubjectCount();%see how many subjects are loaded
    if SubjectCount.SubjectCount > 2
        disp('ERROR: more than 2 subject models are active, please review code to handle this situation');
        datlog.errormsgs{end+1} = 'ERROR: more than 2 subject models are active, please review code to handle this situation';
        STOP = 1;
    end
    SubjectName = MyClient.GetSubjectName(1).SubjectName;
    if strcmp(SubjectName,'DK2')
        SubjectName = MyClient.GetSubjectName(2).SubjectName;%look for the other subject
    else
        LANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LANK');
        RANK = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RANK');
        LHIP = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LHIP');
        RHIP = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RHIP');
        
        %check to make sure we have the right name for hip markers
        if (RHIP.Result.Value ~=2) || (LHIP.Result.Value ~= 2)
            LHIP = MyClient.GetMarkerGlobalTranslation( SubjectName, 'LGT');
            RHIP = MyClient.GetMarkerGlobalTranslation( SubjectName, 'RGT');
            if (RHIP.Result.Value ~=2) || (LHIP.Result.Value ~= 2)%check once more
                disp('ERROR: Hip makers not identified, please review')
                datlog.errormsgs{end+1} = 'ERROR: Hip makers not identified, please review';
                datlog.errormsgs{end+1} = LHIP;%save the result strucure which contains a flag indicating the reason of failure
                datlog.errormsgs{end+1} = RHIP;
                STOP = 1;%stop the collection, no point in collecting data without hip markers
            end
        end
    end
    
    LANK = LANK.Translation;
    RANK = RANK.Translation;
    LHIP = LHIP.Translation;
    RHIP = RHIP.Translation;
%     LANKY = LANK(2);
%     RANKY = RANK(2);
    datlog.targets.Rdata(frameind.Value,:) = [RANK(1) RANK(2) RANK(3) RHIP(1) RHIP(2) RHIP(3) now];
    datlog.targets.Ldata(frameind.Value,:) = [LANK(1) LANK(2) LANK(3) LHIP(1) LHIP(2) LHIP(3) now];
    %{
%     LANKZ = LANK(3);
%     RANKZ = RANK(3);
%     LTOEY = LTOE(2);
%     RTOEY = RTOE(2);
    
    %check for right leg down
%     if rphase ==0
%         if RANKY < 6500 && RANKY > 1450 %subject is in walking lane at speed
%             if RANKZ < 130
%                 rphase = 1;
%             end
%         end
%     elseif rphase == 1
%         if RANKZ < 130
%             rtemp(rz,:) = [RANKY RANKZ RTOEY];
%             rz = rz+1;
%         else
%             rz = 1;
%             rphase = 2;
%         end
%     elseif rphase == 2
%         t1 = rtemp(:,1);
%         t2 = rtemp(:,2);
%         t3 = rtemp(:,3);
%         t1(t1==0)=[];
%         t2(t2==0)=[];
%         t3(t3==0)=[];
%         [~,loc] = min(t2);
%         if ~isempty(t1)
%             datlog.targets.Rdata(rstep,:) = [t1(loc) t3(loc)];
%         end
%         rtemp = zeros(2000,3);%reset the temp matrix
%         rphase = 0;
%         rstep = rstep+1;
%         clear t1 t2 t3 loc;
%     end
%     
%     
%     
%     %check for left leg down
%     if lphase ==0
%         if LANKY < 6500 && LANKY > 1450 %subject is in walking lane at speed
%             if LANKZ < 130
%                 lphase = 1;
%             end
%         end
%     elseif lphase == 1
%         if LANKZ < 130
%             ltemp(lz,:) = [LANKY LANKZ LTOEY];
%             lz = lz+1;
%         else
%             lz = 1;
%             lphase = 2;
%         end
%     elseif lphase == 2
%         t3 = ltemp(:,1);
%         t4 = ltemp(:,2);
%         t5 = ltemp(:,3);
%         t3(t3==0)=[];
%         t4(t4==0)=[];
%         t5(t5==0)=[];
%         [~,loc1] = min(t4);
%         if ~isempty(t3)
%             datlog.targets.Ldata(lstep,:) = [t3(loc1) t5(loc1)];
%         end
%         ltemp = zeros(2000,3);%reset the temp matrix
%         lphase = 0;
%         lstep = lstep+1;
%         clear t3 t4 t5 loc1;
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

try %stopping the treadmill
%see if the treadmill is supposed to stop at the end of the profile
    if get(ghandle.StoptreadmillEND_checkbox,'Value')==1 && STOP ~=1
        set(ghandle.Status_textbox,'String','Stopping...');
        set(ghandle.Status_textbox,'BackgroundColor','red');
%         pause(1)%provide a little time to collect the last steps and so forth
%         smoothStop(t);
    %see if the treadmill should be stopped when the STOP button is pressed
    elseif get(ghandle.StoptreadmillSTOP_checkbox,'Value')==1 && STOP == 1

    %     set(ghandle.Status_textbox,'String','Stopped');
    %     set(ghandle.Status_textbox,'BackgroundColor','red');
%         smoothStop(t);
    end
    
catch ME
    datlog.errormsgs{end+1} = 'Error stopping the treadmill';
    datlog.errormsgs{end+1} = ME;
end
    
    
disp('closing comms');
try
    closeNexusIface(MyClient);
%     closeTreadmillComm(t);
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


%finalize the values of targets and prepare the mean values
%scan for direction of walking

%very important, remove zeros in padding
temp = datlog.targets.Rdata;
temp2 = datlog.targets.Ldata;

[zlocs] = find(temp(:,1),1,'last');
[zlocs2] = find(temp2(:,1),1,'last');

datlog.targets.Rdata(zlocs:end,:)=[];
datlog.targets.Ldata(zlocs2:end,:)=[];

ranky = datlog.targets.Rdata(:,2);
rhipy = datlog.targets.Rdata(:,5);
lanky = datlog.targets.Ldata(:,2);
lhipy = datlog.targets.Ldata(:,5);

rankz = datlog.targets.Rdata(:,3);%missing data in current collection
rhipz = datlog.targets.Rdata(:,6);
lankz = datlog.targets.Ldata(:,3);
lhipz = datlog.targets.Ldata(:,6);

rdata = calcangle([ranky rankz],[rhipy rhipz],[rhipy+100 rhipz])-90;
ldata = calcangle([lanky lankz],[lhipy lhipz],[lhipy+100 lhipz])-90;

pad = 25;

%from labtools, getEventsFromAngles
hip = (rhipy+lhipy)./2;
hipvel = diff(hip);
hipvel(abs(hipvel)>50) = 0;
%Use hip velocity to determine when subject is walking
midHipVel = nanmedian(abs(hipvel));
% midHipVel = 7;
walking = abs(hipvel)>0.5*midHipVel;
% keyboard
% Eliminate walking or turn around phases shorter than 0.25 seconds
[walking] = deleteShortPhases(walking,100,0.25);

% split walking into individual bouts
walkingSamples = find(walking);

if ~isempty(walkingSamples)
    StartStop = [walkingSamples(1) walkingSamples(diff(walkingSamples)~=1)'...
        walkingSamples(find(diff(walkingSamples)~=1)+1)' walkingSamples(end)];
    StartStop = sort(StartStop);
else
    warning('Subject was not walking during one of the overground trials');
    return
end

RightTO = [];
RightHS = [];
LeftHS = [];
LeftTO = [];

for i = 1:2:(length(StartStop))
    
    %find HS/TO for right leg
    %Finds local minimums and maximums.
    start = StartStop(i);
    stop = StartStop(i+1);
    median(hipvel(start:stop))
    
    if median(hipvel(start:stop))>=0 % in our lab, walking towards door
        % Reverse angles for walking towards lab door (this is to make angle
        % maximums HS and minimums TO, as they are when on treadmill)
        rdata(start:stop) = -1*rdata(start:stop);
        ldata(start:stop) = -1*ldata(start:stop);
%         disp('walking towards door');
    else
%         disp('walking towards windows');
    end
    
    startHS = start;
    startTO  = start;
    
    %Find all maximum (HS)
    while (startHS<stop)
        RHS = FindKinHS(startHS,stop,rdata,pad);
        RightHS = [RightHS RHS];
        startHS = RHS+1;
    end
    
    %Find all minimum (TO)
    while (startTO<stop)
        RTO = FindKinTO(startTO,stop,rdata,pad);
        RightTO = [RightTO RTO];
        startTO = RTO+1;
    end
    
    RightTO(RightTO == start | RightTO == stop) = [];
    RightHS(RightHS == start | RightHS == stop) = [];
    
    %% find HS/TO for left leg
    startHS = start;
    startTO  = start;
    
    %find all maximum (HS)
    while (startHS<stop)
        LHS = FindKinHS(startHS,stop,ldata,pad);
        LeftHS = [LeftHS LHS];
        startHS = LHS+pad;
    end
    
    %find all minimum (TO)
    while (startTO<stop)
        LTO = FindKinTO(startTO,stop,ldata,pad);
        LeftTO = [LeftTO LTO];
        startTO = LTO+pad;
    end
    
    LeftTO(LeftTO == start | LeftTO == stop)=[];
    LeftHS(LeftHS == start | LeftHS == stop)=[];
end

% Remove any events due to marker dropouts
RightTO(rdata(RightTO)==0)=[];
RightHS(rdata(RightHS)==0)=[];
LeftTO(rdata(LeftTO)==0)=[];
LeftHS(rdata(LeftHS)==0)=[];

% Remove any events that don't make sense
RightTO(rdata(RightTO)>5 | abs(rdata(RightTO))>40)=[];
RightHS(rdata(RightHS)<10 | abs(rdata(RightHS))>40)=[];
LeftTO(ldata(LeftTO)>5 | abs(ldata(LeftTO))>40)=[];
LeftHS(ldata(LeftHS)<10 | abs(ldata(LeftHS))>40)=[];

LHSevent(LeftHS)=true;
RTOevent(RightTO)=true;
RHSevent(RightHS)=true;
LTOevent(LeftTO)=true;


% figure(1)
% % subplot(2,1,1)
% plot(1:length(rdata),rdata,1:length(ldata),ldata);
% hold on
% plot(RightHS,rdata(RightHS),'green');
% plot(LeftHS,ldata(LeftHS),'red');

% temper = ranky-lanky;
% temper2 = lanky-ranky;

% figure(2)
% plot(temper,'black');
% hold on
% plot(RightHS,temper(RightHS));
% subplot(2,1,2)
% plot(ldata)
% hold on
% plot(LeftHS,ldata(LeftHS),'green');

Ralphas = ranky-lanky;
Lalphas = lanky-ranky;

Rtargets = Ralphas(RightHS);
Rtargets(Rtargets<0)=[];

Ltargets = Lalphas(LeftHS);
Ltargets(Ltargets<0)=[];

datlog.targets.Rtargets = Rtargets;
datlog.targets.Ltargets = Ltargets;

datlog.targets.Xr = nanmean(Rtargets);
datlog.targets.Xl = nanmean(Ltargets);

hipv = hip;
hipv(hipv<2000)=nan;%remove turnarounds
hipv(hipv>7000)=nan;
hipd = diff(hipv)./0.01;%velocity
out = nanmean(hipd(hipd>0));
back = nanmean(abs(hipd(hipd<0)));
datlog.OGspeed = nanmean([out,back]);

disp(['Mean OG speed: ' num2str(datlog.OGspeed)]);
disp(['Mean Xr: ' num2str(datlog.targets.Xr)]);
disp(['Mean Xl: ' num2str(datlog.targets.Xl)]);

%calculate cadence
for z=3:length(datlog.targets.Rdata)
    retime(z) = etime(datevec(datlog.targets.Rdata(z,7)),datevec(datlog.targets.Rdata(2,7)));
end
retime = retime';
cadenceR = 60./diff(retime(RightHS));
cadenceR(abs(cadenceR)<25)=[];

for z=3:length(datlog.targets.Ldata)
    letime(z) = etime(datevec(datlog.targets.Ldata(z,7)),datevec(datlog.targets.Ldata(2,7)));
end
letime = letime';
cadenceL = 60./diff(retime(LeftHS));
cadenceL(abs(cadenceL)<25)=[];

cadenceR(cadenceR<30)=[]; %remove noise
cadenceR(cadenceR>80)=[];
cadenceL(cadenceL<30)=[]; %remove noise
cadenceL(cadenceL>80)=[];

datlog.cadence.R = cadenceR;
datlog.cadence.L = cadenceL;

figure(70)
subplot(2,1,1)
plot(cadenceR);
title('Right cadence')
xlabel('strides')
ylabel('cadence (stride/min)');
subplot(2,1,2)
plot(cadenceL);
title('Left cadence')
xlabel('strides')
ylabel('cadence (stride/min)');

disp(['Mean R Cadence: ' num2str(nanmean(datlog.cadence.R))]);
disp(['Mean L Cadence: ' num2str(nanmean(datlog.cadence.L))]);


disp('saving datlog...');
try
    save(savename,'datlog');
catch ME
    disp(ME);
end

