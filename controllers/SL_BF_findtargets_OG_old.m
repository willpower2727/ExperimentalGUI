
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
% datlog.targets.Rdata(1:3,:) = [];
% datlog.targets.Ldata(1:3,:) = [];
% temp = find(datlog.targets.Rdata(:,1)==0,1,'first');
% datlog.targets.Rdata(temp:end,:) = [];
% temp = find(datlog.targets.Ldata(:,1)==0,1,'first');
% datlog.targets.Ldata(temp:end,:) = [];

for z=2:length(datlog.targets.Rdata)
    datlog.targets.Rdata(z,4)=etime(datevec(datlog.targets.Rdata(z,3)),datevec(datlog.targets.Rdata(2,3)));
end
for z=2:length(datlog.targets.Ldata)
    datlog.targets.Ldata(z,4)=etime(datevec(datlog.targets.Ldata(z,3)),datevec(datlog.targets.Ldata(2,3)));
end

rank = datlog.targets.Rdata(:,1);
rhip = datlog.targets.Rdata(:,2);
lank = datlog.targets.Ldata(:,1);
lhip = datlog.targets.Ldata(:,2);

hip = (rhip+lhip)./2;
hip(hip<2000)=nan;%remove turnarounds
hip(hip>7000)=nan;
hipd = diff(hip)./0.008333333;%velocity
out = nanmean(hipd(hipd>0));
back = nanmean(abs(hipd(hipd<0)));
datlog.OGspeed = nanmean([out,back]);

er = rank-lank;
er2 = lank-rank;

[~,ploc] = findpeaks(er,'MinPeakHeight',490,'MinPeakDistance',3);
temp = diff(ploc);
if temp(1) > 20
    ploc(1)=[];
end
z=1;
flag = zeros(length(ploc),1);
while z < length(ploc)-1
    if ploc(z+1)-ploc(z) > 20
       flag(z) = ploc(z+1);
    end
    if flag(z) == 0
        z=z+1;
    else
        z=z+2;
    end 
end
for z=1:length(ploc)-1
   if ploc(z+1)-ploc(z) > 20
       flag(z) = ploc(z+1);
   end
end
for z=1:length(flag)-1
    if flag(z) ~= 0 && flag(z+1) ~= 0
        [cc,aa,bb]=intersect(ploc,flag(z));
        ploc(aa)=[];
    end
end

pulse = zeros(length(er),1);
pulse(ploc) = 1;

tr = ploc;

for z=1:2:length(ploc)-1
   [t1,t2] = min(er(ploc(z):ploc(z+1))); 
    Xl(z) = t1;
    mloc(z) = t2+ploc(z);
end
mloc(mloc==0) = [];
Xl(Xl==0)=[];
pulse2(mloc) = 1;

figure(4)
plot(1:length(er),er,1:length(pulse),pulse*700,1:length(pulse2),pulse2*700);%,[10000:20000]/9,rz(10000:20000));
datlog.targets.Xl = Xl;

% disp(['mean Xl = ' num2str(mean(datlog.targets.Xl))])
clear pulse pulse2 ploc mloc
[~,ploc] = findpeaks(er2,'MinPeakHeight',490,'MinPeakDistance',3);
if temp(1) > 20
    ploc(1)=[];
end
z=1;
flag = zeros(length(ploc),1);
while z < length(ploc)-1
    if ploc(z+1)-ploc(z) > 20
       flag(z) = ploc(z+1);
    end
    if flag(z) == 0
        z=z+1;
    else
        z=z+2;
    end 
end
for z=1:length(ploc)-1
   if ploc(z+1)-ploc(z) > 20
       flag(z) = ploc(z+1);
   end
end
for z=1:length(flag)-1
    if flag(z) ~= 0 && flag(z+1) ~= 0
        [cc,aa,bb]=intersect(ploc,flag(z));
        ploc(aa)=[];
    end
end

pulse = zeros(length(er2),1);
pulse(ploc) = 1;
tl = ploc;
Xr=0;
for z=1:2:length(ploc)-1
   [t1,t2] = min(er2(ploc(z):ploc(z+1))); 
    Xr(z) = t1;
    mloc(z) = t2+ploc(z);
end
mloc(mloc==0) = [];
Xr(Xr==0)=[];
pulse2(mloc) = 1;

figure(5)
plot(1:length(er2),er2,1:length(pulse),pulse*700,1:length(pulse2),pulse2*700);%,[10000:20000]/9,rz(10000:20000));

datlog.targets.Xr = Xr;

datlog.targets.Xr(abs(datlog.targets.Xr)>800)=[];
datlog.targets.Xl(abs(datlog.targets.Xl)>800)=[];
datlog.targets.Xr(abs(datlog.targets.Xr)<300)=[];
datlog.targets.Xl(abs(datlog.targets.Xl)<300)=[];
% datlog.targets.Xr(datlog.targets.Xr<0)=[];
% datlog.targets.Xl(datlog.targets.Xl<0)=[];

%calculate cadence
cadenceR = 60./diff(datlog.targets.Rdata(tr,4));
cadenceL = 60./diff(datlog.targets.Ldata(tl,4));

datlog.stepdata.Rcadence = cadenceR;
datlog.stepdata.Lcadence = cadenceL;



disp(['mean Xr = ' num2str(mean(abs(datlog.targets.Xr)))]);
disp(['mean Xl = ' num2str(mean(abs(datlog.targets.Xl)))]);

%calculate OG speed with hip markers
disp(['OG speed = ' num2str(datlog.OGspeed)]);

disp(['Mean R Cadence: ' num2str(nanmean(cadenceR))]);
disp(['Mean L Cadence: ' num2str(nanmean(cadenceL))]);

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

%{
%determine direction of walking
for z = 1:length(rank)
   if rank(z)-rtoe(z) < 0 %outbound
       datlog.targets.Rdata(z,3) = 1;
   elseif rank(z)-rtoe(z) > 0 %inbound
       datlog.targets.Rdata(z,3) = 2;
   end
end
for z = 1:length(lank)
   if lank(z)-ltoe(z) < 0 %outbound
       datlog.targets.Ldata(z,3) = 1;
   elseif lank(z)-ltoe(z) > 0 %inbound
       datlog.targets.Ldata(z,3) = 2;
   end
end

%parse outbound and inbound
delr = diff(datlog.targets.Rdata(:,3));
dell = diff(datlog.targets.Ldata(:,3));
c1 = 1;
c2 = 1;
for z=1:length(delr)
   if delr(z) == 0
       datlog.targets.Rdata(z,4) = c1;
   else
       datlog.targets.Rdata(z,4) = c1;
       c1 = c1+1;
   end 
end
for z=1:length(dell)
   if dell(z) == 0
       datlog.targets.Ldata(z,4) = c2;
   else
       datlog.targets.Ldata(z,4) = c2;
       c2 = c2+1;
   end 
end

rs = unique(datlog.targets.Rdata(:,4));
rs(rs>50)=[];
rs(rs==0)=[];
rs(end)=[];
ls = unique(datlog.targets.Ldata(:,4));
ls(ls>50)=[];
ls(ls==0)=[];
ls(end)=[];

for z=1:2:length(rs)
    ia = find(datlog.targets.Rdata(:,4)==rs(z));
    datlog.targets.Rout{z} = datlog.targets.Rdata(ia,1);
end
clear ia
for z=2:2:length(rs)
    ia = find(datlog.targets.Rdata(:,4)==rs(z));
    datlog.targets.Rin{z} = datlog.targets.Rdata(ia,1);
end
clear ia
for z=1:2:length(ls)
    ia = find(datlog.targets.Ldata(:,4)==ls(z));
    datlog.targets.Lout{z} = datlog.targets.Ldata(ia,1);
end
clear ia
for z=2:2:length(ls)
    ia = find(datlog.targets.Ldata(:,4)==ls(z));
    datlog.targets.Lin{z} = datlog.targets.Ldata(ia,1);
end
clear ia

datlog.targets.Rout(cellfun(@isempty,datlog.targets.Rout))=[];
datlog.targets.Lout(cellfun(@isempty,datlog.targets.Lout))=[];
datlog.targets.Rin(cellfun(@isempty,datlog.targets.Rin))=[];
datlog.targets.Lin(cellfun(@isempty,datlog.targets.Lin))=[];

%calculate targets finally
for z=1:length(datlog.targets.Rout)
   temp = datlog.targets.Rout{z};
   temp2 = datlog.targets.Lout{z};
   if temp(1)>temp2(1)%left foot first
       for zz=1:min([length(temp) length(temp2)])-1
           Xr(zz) = temp(zz)-temp2(zz);
           Xl(zz) = temp2(zz+1)-temp(zz);
       end
   else
       for zz=1:min([length(temp) length(temp2)])-1%right foot first
           Xl(zz) = temp2(zz)-temp(zz);
           Xr(zz) = temp(zz+1)-temp2(zz);
       end
   end
   datlog.targets.Xrout{z} = Xr;
   datlog.targets.Xlout{z} = Xl;
   clear Xr Xl
end

for z=1:length(datlog.targets.Rin)
   temp = datlog.targets.Rin{z};
   temp2 = datlog.targets.Lin{z};
   
   if abs(diff([temp(1) temp(2)]))<500
       temp(1) = [];
   end
   if temp(1)>temp2(1)%right foot first
       for zz=1:min([length(temp) length(temp2)])-1
           Xl(zz) = temp(zz)-temp2(zz);
           Xr(zz) = temp2(zz)-temp(zz+1);
       end
   else
       for zz=1:min([length(temp) length(temp2)])-1%left foot first
           Xr(zz) = temp2(zz)-temp(zz);
           Xl(zz) = temp(zz)-temp2(zz+1);
       end
   end
   datlog.targets.Xrin{z} = Xr;
   datlog.targets.Xlin{z} = Xl;
   clear Xr Xl
end

%conglomorate
datlog.targets.Xr = cat(2,datlog.targets.Xrout,datlog.targets.Xrin);
datlog.targets.Xr = abs(cell2mat(datlog.targets.Xr));
datlog.targets.Xl = cat(2,datlog.targets.Xlout,datlog.targets.Xlin);
datlog.targets.Xl = abs(cell2mat(datlog.targets.Xl));
%}
% disp(['Mean Xr is: ' num2str(mean(datlog.targets.Xr))]);
% disp(['Mean Xl is: ' num2str(mean(datlog.targets.Xl))]);


disp('saving datlog...');
try
    save(savename,'datlog');
catch ME
    disp(ME);
end

