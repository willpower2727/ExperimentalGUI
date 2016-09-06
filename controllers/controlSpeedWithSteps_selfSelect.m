
function [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, commSendFrame] = controlSpeedWithSteps_selfSelect(velL,velR,FzThreshold,profilename,mode,signList,paramComputeFunc,paramCalibFunc)
%This function takes two vectors of speeds (one for each treadmill belt)
%and succesively updates the belt speed upon ipsilateral Toe-Off
%The function only updates the belts alternatively, i.e., a single belt
%speed cannot be updated twice without the other being updated
%The first value for velL and velR is the initial desired speed, and new
%speeds will be sent for the following N-1 steps, where N is the length of
%velL

%close all
global feedbackFlag
if feedbackFlag==1  %&& size(get(0,'MonitorPositions'),1)>1
    ff=figure('Units','Normalized','Position',[1 0 1 1]);
    pp=gca;
    axis([0 length(velL)  0 2]);
    ccc1=animatedline('Parent',pp,'Marker','o','LineStyle','none','MarkerFaceColor',[0 0 1],'MarkerEdgeColor','none');
    ccc2=animatedline('Parent',pp,'Marker','o','LineStyle','none','MarkerFaceColor',[1 0 0],'MarkerEdgeColor','none');

end



paramLHS=0;
paramRHS=0;
lastParamLHS=0;
lastParamRHS=0;
lastRstepCount=0;
lastLstepCount=0;
LANK=zeros(1,6);
RANK=zeros(1,6);
RHIP=zeros(1,6);
LHIP=zeros(1,6);
LANKvar=1e5*ones(6);
RANKvar=1e5*ones(6);
RHIPvar=1e5*ones(6);
LHIPvar=1e5*ones(6);
lastLANK=nan(1,6);
lastRANK=nan(1,6);
lastRHIP=nan(1,6);
lastLHIP=nan(1,6);
toneplayed=false;

if nargin<7 || isempty(paramComputeFunc)
   paramComputeFunc=@(w,x,y,z) (-w(2) + .5*(y(2)+z(2)))/1000; %Default
end
[d,~,~]=fileparts(which(mfilename));
if nargin<8 || isempty(paramCalibFunc)
   load([d '\..\calibrations\lastCalibration.mat']) 
else
    save([d '\..\calibrations\lastCalibration.mat'],'paramCalibFunc','paramComputeFunc')
end




if nargin<5 || isempty(mode)
    error('Need to specify control mode')
end
if nargin<6
    %disp('no sign list')
    signList=[];
end
signCounter=1;

global PAUSE%pause button value
global STOP
global memory
global enableMemory
global firstPress
STOP = false;
fo=4000;
signS=0; %Initialize
endTone=3*sin(2*pi*[1:2048]*fo*.025/4096);  %.5 sec tone at 100Hz, even with noise cancelling this is heard
tone=sin(2*pi*[1:2048]*1.25*fo/4096); %.5 sec tone at 5kHz, even with noise cancelling this is heard

ghandle = guidata(AdaptationGUI);%get handle to the GUI so displayed data can be updated

%Initialize some graphical objects:
ppp1=animatedline('Parent',ghandle.profileaxes,'LineStyle','none','Marker','o','MarkerFaceColor',[0.68 .92 1],'MarkerEdgeColor','none');
ppp2=animatedline('Parent',ghandle.profileaxes,'LineStyle','none','Marker','o','MarkerFaceColor',[1 .6 .78],'MarkerEdgeColor','none');
ppp3=animatedline('Parent',ghandle.profileaxes,'LineStyle','none','Marker','.','Color',[0 0 1]);
ppp4=animatedline('Parent',ghandle.profileaxes,'LineStyle','none','Marker','.','Color',[1 0 0]);
ppv1=animatedline('Parent',ghandle.profileaxes,'LineStyle','none','Marker','.','Color',[0 .5 1]);
ppv2=animatedline('Parent',ghandle.profileaxes,'LineStyle','none','Marker','.','Color',[1 .5 0]);

yl=get(ghandle.profileaxes,'YLim');
%Add text with signlist:
%tt=text(1,yl(2)-.05*diff(yl),['Sign List for null trials= ' num2str(signList)],'Parent',ghandle.profileaxes);
%Add patches to show self-controlled strides:
aux1=diff(isnan(velL));
iL=find(aux1==1);
iL2=find(aux1==-1);
counter=1;
for i=1:length(iL)
    pp=patch([iL(i) iL2(i) iL2(i) iL(i)],[yl(1) yl(1) yl(2) yl(2)],[0 .3 .6],'FaceAlpha',.2,'EdgeColor','none');
    uistack(pp,'bottom')
    if (velL(iL(i))-velR(iL(i)))==0
        try
            auxT=signList(counter);
        catch
            if mode==0
            warning('Provided sign list seems to be shorter than # of null trials, adding default sign.')
            end
            signList(counter)=1;
            auxT=signList(counter);
        end
        counter=counter+1;
    else
        auxT=sign(velR(iL(i))-velL(iL(i)));
    end
    text(iL(i),yl(1)+.05*diff(yl),[num2str(auxT)],'Color',[0 0 1])
end
aux1=diff(isnan(velR));
iL=find(aux1==1);
iL2=find(aux1==-1);
counter=1;
for i=1:length(iL)
    pp=patch([iL(i) iL2(i) iL2(i) iL(i)],[yl(1) yl(1) yl(2) yl(2)],[.6 .3 0],'FaceAlpha',.2,'EdgeColor','none');
    uistack(pp,'bottom')
    if (velL(iL(i))-velR(iL(i)))==0
        try
        auxT=-signList(counter);
        catch
            if mode==0
            warning('Provided sign list seems to be shorter than # of null trials, adding default sign.')
            end
            signList(counter)=1;
            auxT=-signList(counter);
        end
        counter=counter+1;
    else
        auxT=sign(velL(iL(i))-velR(iL(i)));
    end
    text(iL(i),yl(1)+.1*diff(yl),[num2str(auxT)],'Color',[1 0 0])
end

%initialize a data structure that saves information about the trial
datlog = struct();
datlog.buildtime = now;%timestamp
temp = datestr(datlog.buildtime,30); %Using ISO 8601 for date/time string format
a = regexp(temp,'-');
temp(a) = '_';
b = regexp(temp,':');
temp(b) = '_';
c = regexp(temp,' ');
temp(c) = '_';
[d,~,~]=fileparts(which(mfilename));
[~,n,~]=fileparts(profilename);
savename = [[d '\..\datlogs\'] temp '_' n];
set(ghandle.sessionnametxt,'String',[temp '_' n]);
datlog.session_name = savename;
datlog.errormsgs = {};
datlog.messages = {};
datlog.framenumbers.header = {'frame #','U Time','Relative Time'};
datlog.framenumbers.data = zeros(300*length(velR)+7200,2);
datlog.stepdata.header = {'Step#','U Time','frame #','Relative Time'};
datlog.stepdata.RHSdata = zeros(length(velR)+50,3);%empty cell theoretically big enough to house all the steps taken
datlog.stepdata.RTOdata = zeros(length(velR)+50,3);
datlog.stepdata.LHSdata = zeros(length(velL)+50,3);
datlog.stepdata.LTOdata = zeros(length(velL)+50,3);
datlog.stepdata.paramLHS = zeros(length(velR)+50,1);
datlog.stepdata.paramRHS = zeros(length(velL)+50,1);
datlog.audioCues.start = nan(length(velL)+50,1);
datlog.audioCues.stop = nan(length(velL)+50,1);
histL=nan(1,50);
histR=nan(1,50);
histCount=1;
filtLHS=0;
filtRHS=0;
datlog.inclineang = [];
datlog.speedprofile.velL = velL;
datlog.speedprofile.velR = velR;
datlog.speedprofile.signListForNullTrials = signList;
datlog.TreadmillCommands.header = {'RBS','LBS','angle','U Time','Relative Time'};
datlog.TreadmillCommands.read = nan(300*length(velR)+7200,4);
datlog.TreadmillCommands.sent = nan(300*length(velR)+7200,4);%nan(length(velR)+50,4);
datlog.Markers.header = {'x','y','z'};
datlog.Markers.LHIP = nan(300*length(velR)+7200,3);
datlog.Markers.RHIP = nan(300*length(velR)+7200,3);
datlog.Markers.LANK = nan(300*length(velR)+7200,3);
datlog.Markers.RANK = nan(300*length(velR)+7200,3);
datlog.Markers.LHIPfilt = nan(300*length(velR)+7200,6);
datlog.Markers.RHIPfilt = nan(300*length(velR)+7200,6);
datlog.Markers.LANKfilt = nan(300*length(velR)+7200,6);
datlog.Markers.RANKfilt = nan(300*length(velR)+7200,6);
datlog.Markers.LHIPvar = nan(300*length(velR)+7200,36);
datlog.Markers.RHIPvar = nan(300*length(velR)+7200,36);
datlog.Markers.LANKvar = nan(300*length(velR)+7200,36);
datlog.Markers.RANKvar = nan(300*length(velR)+7200,36);
datlog.stepdata.paramComputeFunc=func2str(paramComputeFunc);
if mode==4
    datlog.stepdata.paramCalibFunc=func2str(paramCalibFunc);
end

%do initial save
try
    save(savename,'datlog');
catch ME
    disp(ME);
end
%Default threshold
if nargin<3
    FzThreshold=40; %Newtons (40 is minimum for noise not to be an issue)
elseif FzThreshold<40
%     warning = ['Warning: Fz threshold too low to be robust to noise, using 30N instead'];
    datlog.messages{end+1} = 'Warning: Fz threshold too low to be robust to noise, using 40N instead';
    disp('Warning: Fz threshold too low to be robust to noise, using 40N instead');
    FzThreshold=40;
end


%Check that velL and velR are of equal length
N=length(velL)+1;
if length(velL)~=length(velR)
    disp('WARNING, velocity vectors of different length!');
    datlog.messages{end+1} = 'Velocity vectors of different length selected';
end
%Adding a fake step at the end to avoid out-of-bounds indexing, but those
%speeds should never get used in reality:
velL(end+1)=0;
velR(end+1)=0;

%Initialize nexus & treadmill communications
try
% [MyClient] = openNexusIface();
    Client.LoadViconDataStreamSDK();
    MyClient = Client();
    Hostname = 'localhost:801';
    out = MyClient.Connect(Hostname);
    out = MyClient.EnableMarkerData();
    out = MyClient.EnableDeviceData();
    %MyClient.SetStreamMode(StreamMode.ServerPush);
    MyClient.SetStreamMode(StreamMode.ClientPullPreFetch);
        mn={'LHIP','RHIP','LANK','RANK'};
    altMn={'LGT','RGT','LANK','RANK'};
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

[~,~,cur_incl] = readTreadmillPacket(t); %Read treadmill incline angle
lastRead=now;
datlog.inclineang = cur_incl;

%Send first speed command & store
acc=3000;
[payload] = getPayload(velR(1),velL(1),acc,acc,cur_incl);
memoryR=velR(1);
memoryL=velL(1);
sendTreadmillPacket(payload,t);
lastSent=now;
datlog.TreadmillCommands.firstSent = [velR(RstepCount),velL(LstepCount),acc,acc,cur_incl,lastSent];%record the command
commSendTime(1,:)=clock;
datlog.TreadmillCommands.sent(1,:) = [velR(RstepCount),velL(LstepCount),cur_incl,now];%record the command   
datlog.messages{end+1} = ['First speed command sent' num2str(now)];
datlog.messages{end+1} = ['Lspeed = ' num2str(velL(LstepCount)) ', Rspeed = ' num2str(velR(RstepCount))];

%% Main loop

old_velR = libpointer('doublePtr',velR(1));
old_velL = libpointer('doublePtr',velL(1));
frameind = libpointer('doublePtr',1);
framenum = libpointer('doublePtr',0);

%Get first frame
MyClient.GetFrame();
framenum.Value = MyClient.GetFrameNumber().FrameNumber;
datlog.framenumbers.data(frameind.Value,:) = [framenum.Value now];

while ~STOP %only runs if stop button is not pressed
    pause(.001) %This ms pause is required to allow Matlab to process callbacks from the GUI. 
    %It actually takes ~2ms, as Matlab seems to be incapable of pausing for less than that (overhead of the pause() function, I presume)
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
    %drawnow;
%     lastFrameTime=curTime;
%     curTime=clock;
%     elapsedFrameTime=etime(curTime,lastFrameTime);
    old_stanceL=new_stanceL;
    old_stanceR=new_stanceR;
    
    
    
    %Read frame, update necessary structures4
    MyClient.GetFrame();
    framenum.Value = MyClient.GetFrameNumber().FrameNumber;
    if framenum.Value~= datlog.framenumbers.data(frameind.Value,1) %Frame num value changed, reading data
        frameind.Value = frameind.Value+1; %Frame counter
        datlog.framenumbers.data(frameind.Value,:) = [framenum.Value now];
    
    %Read treadmill, if enough time has elapsed since last read
    aux=(datevec(now)-datevec(lastRead));
    if aux(6)>.1 || any(aux(1:5)>0)  %Only read if enough time has elapsed
        [RBS, LBS,read_theta] = readTreadmillPacket(t);%also read what the treadmill is doing
        lastRead=now;
        datlog.TreadmillCommands.read(frameind.Value,:) = [RBS,LBS,read_theta,lastRead];%record the read
        set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));
        set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
    end
    
    %Read markers:
    sn=MyClient.GetSubjectName(1).SubjectName;
    for l=1:4
        md=MyClient.GetMarkerGlobalTranslation(sn,mn{l});
        if md.Result.Value==2 %%Success getting marker
            aux=double(md.Translation);
        else
            md=MyClient.GetMarkerGlobalTranslation(sn,altMn{l});
            if md.Result.Value==2
                aux=double(md.Translation);
            else
                aux=[nan nan nan]';
            end
            if all(aux==0) %Nexus returns 'Success' values even when marker is missing, and assigns it to origin!
                %warning(['Nexus is returning origin for marker position of ' mn{l}]) %This shouldn't happen
                aux=[nan nan nan]';
            end
        end
        %aux
        %Here we should implement some Kalman-like filter:
        %eval(['v' mn(l) '=.8*v' mn(l) '+ (aux-' mn(l) ');']);
        eval(['lastEstimate=' mn{l} ''';']); %Saving previous estimate
        eval(['last' mn{l} '=lastEstimate'';']); %Saving previous estimate as row vec
        eval(['lastEstimateCovar=' mn{l} 'var;']); %Saving previous estimate's variance
        eval(['datlog.Markers.' mn{l} '(frameind.Value,:) = aux;']);%record the current read
        
        elapsedFramesSinceLastRead=framenum.Value-datlog.framenumbers.data(frameind.Value-1,1);
        %What follows assumes a 100Hz sampling rate
        n=elapsedFramesSinceLastRead;
        if n<0
            error('inconsistent frame numbering')
        end
        
        %Construct relevant matrices:
        switch mn{l}(2:4) %Different parameters for different
            case 'HIP'
                qxy=2*n;
                qz=n;
                tauZ=15;
                tauXY=20;
                zLim=100;
                zLim=1e6;
            case 'ANK'
                qxy=10*n; %I think this should be much less, like 5*n
                qz=10*n;
                tauZ=15;
                tauXY=20;
                zLim=1e6;
            otherwise
                
        end
        r=30; %std of measurement. It is actually close to 3mm
        tt=exp(-1/tauXY);
        Axy=[1+tt -tt; 2-tt tt-1];
        tt=exp(-1/tauZ);
        Az=[1+tt -tt; 2-tt tt-1];
        A=zeros(6,6);
        for c=1:3
            if c<3
                A([c,c+3],[c,c+3])=Axy;
            else
                A([c,c+3],[c,c+3])=Az;
            end
        end
        A=A^n;
        %Q=diag(max([qxy qxy qz qxy qxy qz],.5*[lastEstimate(1:3)-lastEstimate(4:6); lastEstimate(1:3)-lastEstimate(4:6)]'.^2));
        Q=diag([qxy qxy qz qxy qxy qz]);
        C=[eye(3) zeros(3)];
        R=r^2*eye(3);
        
        %Predict:
        newPrediction= A*lastEstimate;
        newPredictionCovar = A*lastEstimateCovar*A' + Q;
        
        %I will put some bounds on the prediction covariance in z-axis
        if newPredictionCovar(3,3)>zLim && frameind.Value>100 %Burn in period
            newPredictionCovar(3,6)= zLim*newPredictionCovar(3,6)/newPredictionCovar(3,3);
            newPredictionCovar(6,3)= zLim*newPredictionCovar(6,3)/newPredictionCovar(3,3);
           newPredictionCovar(3,3)= zLim;
        end
        
        %MAP estimation of mislabeling: 
        err=(aux-C*newPrediction);
        D=C*newPredictionCovar*C'+R;
        R1=eye(3)*1e6; %95% of samples should lie in a sphere of radius ~1m
        if trace(R1) > .5*trace(D) %If the estimation uncertainty is a sphere at least 40% smaller than R1
            l1= exp(-.5*err.*diag(R1).^(-1).*err)./sqrt(diag(R1));%Likelihood of observation assuming mislabeling
        else %Case that the estimation variance grew too much, have no option but to reset the filter
            l1=0; 
            newPredictionCovar=eye(6)*1e6; %For numerical stability, fixing the covariance matrix
        end
        if aux(3)>0
            l2= exp(-.5*err.*diag(D).^(-1).*err)./sqrt(diag(D));%Likelihood of observation assuming good label
        else
            l2=0; %Rejecting all samples that are in z<0, as that is impossible
        end
        p=.1; %Prior for mislabeling
        pm= p*l1./(p*l1+(1-p)*l2); %Posterior for mislabeling
        if any(pm>.5) %Mislabeling detected
            aux=nan(3,1);
        elseif any(l1>l2) %MLE returns mislabeling, proceeding with caution
            R=.5*R1;
        end
        
        %Do update:
        if ~any(isnan(aux)) %Good data (not mislabeled)
            K=newPredictionCovar*C'*pinv(C*newPredictionCovar*C'+R);
            newEstimate=newPrediction+K*(err);
            newEstimateCovar=(eye(6) - K*C)*newPredictionCovar;
        else %Bad data, proceeding with estimation only
            %warning('No update this time')
            newEstimate=newPrediction;
            newEstimateCovar=newPredictionCovar;
        end
        
        %Save results for this frame
        %if all(lastEstimate(4:6)==0)
        %    newEstimate(4:6)=newEstimate(1:3);
        %end
        eval([mn{l} '=newEstimate'';']); %Saving as row vector
        eval([mn{l} 'var=newEstimateCovar;']);
        eval(['datlog.Markers.' mn{l} 'filt(frameind.Value,:) = newEstimate;']);%record the current estim
        eval(['datlog.Markers.' mn{l} 'var(frameind.Value,:) = newEstimateCovar(:);']);%record the current var
    end
    
    
    %Read forces
    Fz_R = MyClient.GetDeviceOutputValue( 'Right Treadmill', 'Fz' );
    Fz_L = MyClient.GetDeviceOutputValue( 'Left Treadmill', 'Fz' );
    if (Fz_R.Result.Value ~= 2) || (Fz_L.Result.Value ~= 2) %failed to find the devices, try the alternate name convention
        %Fz_L.Result
        Fz_R = MyClient.GetDeviceOutputValue( 'Right', 'Fz' );
        Fz_L = MyClient.GetDeviceOutputValue( 'Left', 'Fz' );
        if (Fz_R.Result.Value ~= 2) || (Fz_L.Result.Value ~= 2)
            %Fz_L.Result
            %Fz_R.Result.Value
            %Fz_L.Result.Value
            STOP = 1;  %stop, the GUI can't find the forceplate values
            disp('ERROR! Adaptation GUI unable to read forceplate data, check device names and function');
            datlog.errormsgs{end+1} = 'Adaptation GUI unable to read forceplate data, check device names and function';
        end
    end
    new_stanceL=Fz_L.Value<-FzThreshold; %20N Threshold
    new_stanceR=Fz_R.Value<-FzThreshold;
    end
    

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
                
                %NO LONGER ALLOWING SINGLE L AS START PHASE, FOR UNIFORMITY
                %ACROSS SUBJECTS. THIS MEANS WE MAY MISS THE VERY FIRST
                %STEP IN GUI COUNTING, WHICH MAY OR MAY NOT BE DESIRABLE:
            %elseif LTO %Go to single R
            %    phase=2;
            %    LstepCount=LstepCount+1;
%                 LTOTime(LstepCount) = TimeStamp;
            %    LTOTime(LstepCount) = now;
            %    datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1,now,framenum.Value];
            %    set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount)/1000));
            end
        case 1 %single L
            if RHS
                phase=3;
                datlog.stepdata.RHSdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
%                 RHSTime(RstepCount) = TimeStamp;
                RHSTime(RstepCount) = now;
                set(ghandle.Right_step_textbox,'String',num2str(LstepCount-1));
                
                %Compute a relevant param:
                lastParamRHS=paramRHS;
                paramRHS=paramComputeFunc(RANK,LANK,RHIP,LHIP);
                %paramRHS=paramComputeFunc(lastRANK,lastLANK,lastRHIP,lastLHIP);
                datlog.stepdata.paramRHS(RstepCount-1)=paramRHS;
                
                %plot cursor
                 addpoints(ppp4,RstepCount-1,paramRHS);
                 addpoints(ppv2,RstepCount-1,lastR/1000)%paramCalibFunc(paramRHS)/1000)
                if ~isnan(velR(RstepCount))
                    yR=velR(RstepCount)/1000;
                else
                    yR=sentR/1000;
                end
                addpoints(ppp2,RstepCount-1,yR)
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
                
                %Compute a relevant param:
                lastParamLHS=paramLHS;
                paramLHS=paramComputeFunc(LANK,RANK,LHIP,RHIP);
                %paramLHS=paramComputeFunc(lastLANK,lastRANK,lastLHIP,lastRHIP);
                datlog.stepdata.paramLHS(LstepCount-1)=paramLHS;
                
                %plot cursor
                %ppp=plot(ghandle.profileaxes,LstepCount-1,paramLHS/1000,'.','Color',[0.68 .92 1]);
                addpoints(ppp3,LstepCount-1,paramLHS)
                addpoints(ppv1,LstepCount-1,lastL/1000)%paramCalibFunc(paramLHS)/1000)
                if ~isnan(velL(LstepCount))
                    yL=velL(LstepCount)/1000;
                else
                    yL=sentL/1000;
                end
                addpoints(ppp1,LstepCount-1,yL)
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
                if LstepCount>=N-3
                   set(ghandle.profileaxes,'Color',[1,.8,.7]); 
                end
            end
        case 4 %DS, coming from single R
            if RTO
                phase =1; %To single L
                RstepCount=RstepCount+1;
%                 RTOTime(RstepCount) = TimeStamp;
                RTOTime(RstepCount) = now;
                datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
                set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount)/1000));
                if RstepCount>=N-3
                   set(ghandle.profileaxes,'Color',[1,.8,.7]);
                end
                    
            end
    end
    %ll=findobj(ghandle.profileaxes,'Type','Line');
    if exist('ff','var') && isvalid(ff) && (RHS || LHS) %If the figure was closed, this is ignored
        try
        if RHS
            addpoints(ccc2,RstepCount-1,yR)
        end
        if LHS
            addpoints(ccc1,LstepCount-1,yL)
        end
        drawnow
        catch
            %nop
        end
    end
    %Set next speed command to be sent, as either from memory or scheduled
    smoothReturn=true;
    
    if ~isnan(velR(RstepCount)) && ~isnan(velL(LstepCount)) %Not in self-controlled mode, yet.
        sentR=velR(RstepCount);
        sentL=velL(LstepCount);
        lastL=sentL;
        lastR=sentR;
        memory=0;
        
        %Re-setting self-control sign, if necessary
        if (RstepCount>1 && isnan(velR(RstepCount-1))) || (LstepCount>1 && isnan(velL(LstepCount-1)))
            signS=0; %Re-setting sign
        end
    else %At least one of the belts is in self-controlled mode
        
        %If entering self-control mode on this step:
        if (RstepCount<N-1 && ~isnan(velR(RstepCount-1))) && (LstepCount<N-1 && ~isnan(velL(LstepCount-1))) 
            %Next STRIDE will be self-controlled for AT LEAST one of the belts
            if mode==0 && signS==0 %Determine the sign of keypresses if it hasn't been determined yet
                firstPress=true; %Set to ignore first keypress, it is unset automatically after first keypress by AdaptationGUI.m
                signS=sign(velR(RstepCount-1)-velL(LstepCount-1));
                if signS==0 %Null perturbation case
                    if ~isempty(signList)
                        signS=signList(signCounter);
                        signCounter=signCounter+1;
                    else
                        signS=1;
                    end
                end
                %signS
            end
            if mode~=2
                enableMemory=true;
            end
            if ~toneplayed
                datlog.audioCues.start(RstepCount)=now;
                sound(tone,4096) 
                toneplayed=true;
                endTonePlayed=false;
            end
        end

        
        %Do the control:
        switch mode
            case 0
                auxR=lastR+signS*imag(memory); %Unsigned mode
                auxL=lastL-signS*imag(memory);
            case 1
                auxR=lastR+real(memory); %Signed mode
                auxL=lastL-real(memory);
            case 2
                auxR=lastR; %Fixed mode
                auxL=lastL;
            case 3 %Signed mode with superposed mean speed changes
                auxR=lastR+real(memory)+imag(memory); %Signed mode
                auxL=lastL-real(memory)+imag(memory);
            case 4 %Closed-loop mode
                if RstepCount>lastRstepCount || LstepCount>lastLstepCount %Only updating once per step
                    
                    midSpeed=.5*(lastR+lastL); %Mid speed of belts is fixed
                    lastDiff=.5*(lastL-lastR); %Last belt speed difference sent
                    
                    if paramLHS>0 && paramRHS>0 && paramRHS<350 && paramLHS<350 % make sure the data is not caused by mislabeling or something
                        %Add to history: (in an efficient way)
                        histL(histCount)=paramLHS;
                        histR(histCount)=paramRHS;
                        histCount=histCount+1;
                        if histCount>length(histL)
                            histCount=1;
                        end
                        
                        %Do some median filtering
                        %(should I?)
                        
                        %Do some LPF:
                        b=.1; %Per step, on a per-stride basis the equivalent value of 'b' is 2*b - b^2
                        a=1-b; %This means it takes ~1/b strides to reach 63% of steady-state value, when null initial condition
                        MM=round(1/b);
                        if RstepCount>MM && LstepCount>MM
                            filtRHS=a*filtRHS+b*paramRHS;
                            filtLHS=a*filtLHS+b*paramLHS;
                        else %For the burn-in period
                           filtRHS=nanmedian(histR);
                           filtLHS=nanmedian(histL);
                        end
                    end
                    newDiff=.5*paramCalibFunc(filtLHS,filtRHS);
                    
                    if ~isnan(newDiff) %Only doing the update if we have a numerical value
                        th=1;%Clipping changes to be limited to 1mm/s per step on EACH belt
                        if abs(newDiff-lastDiff)>th
                            newDiff=lastDiff+th*sign(newDiff-lastDiff);
                        end
                    end
                    %Generating new speeds to be sent:
                    auxR=round(midSpeed-newDiff); 
                    auxL=round(midSpeed+newDiff);

                    %Logging values & updating step count:
                    lastR=auxR;
                    lastL=auxL;
                    lastRstepCount=RstepCount;
                    lastLstepCount=LstepCount;
                    
                else
                    %Speeds to be sent are the same as before
                    auxR=lastR;
                    auxL=lastL;
                end
                
            otherwise
                error('Invalid mode')
        end
        if isnan(velR(RstepCount)) %Only updating belts under self-control
            sentR=auxR;
        end
        if isnan(velL(LstepCount))
            sentL=auxL;
        end
        if (RstepCount<N-1 && ~isnan(velR(RstepCount+1))) && (LstepCount<N-1 && ~isnan(velL(LstepCount+1))) %Next step won't be self-controlled for EITHER belt. 
            if ~endTonePlayed 
                datlog.audioCues.stop(RstepCount)=now;
                sound(endTone,4096)
                endTonePlayed=true;
                toneplayed=false; %flag to check that tone is not played twice for a single selection interval
            end
            enableMemory=false;
            M=5; %Take M strides to actually go to the desired target speed, to avoid sharp transitions 
            if smoothReturn && RstepCount<(N-M) && LstepCount<(N-M) %Smooth transition to computer control
                 velR(RstepCount+[1:M-1])=sentR+(velR(RstepCount+M)-sentR)*[1:M-1]/M;
                velL(LstepCount+[1:M-1])=sentL+(velL(LstepCount+M)-sentL)*[1:M-1]/M;
            end
        end
    end

    aux=(now-lastSent)*86400; %Time elapsed in secs
    if LstepCount >= N && RstepCount >= N%if taken enough steps, stop
        break
    %only send a command if it is different from the previous one. Don't
    %overload the treadmill controller with commands (only one command
    %every 100ms)
    elseif ((sentR ~= old_velR.Value) || (sentL ~= old_velL.Value)) && LstepCount<N && RstepCount<N && aux>.15
        payload = getPayload(sentR,sentL,acc,acc,cur_incl);
        sendTreadmillPacket(payload,t);
        lastSent=now;
        datlog.TreadmillCommands.sent(frameind.Value,:) = [sentR,sentL,cur_incl,lastSent];%record the command
        disp(['Packet sent, Lspeed = ' num2str(sentL) ', Rspeed = ' num2str(sentR)])
        old_velR.Value = sentR;
        old_velL.Value = sentL;
    end
    
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
    disp(ME)
    %disp(ME.stack)
    ME.getReport
%     log=['Error ocurred during the control loop'];%End try
%     listbox{end+1}=log;
    disp('Error ocurred during the control loop, see datlog for details...');
end
%% Closing routine
%End communications
global addLog
try
    aux = cellfun(@(x) (x-datlog.framenumbers.data(1,2))*86400,addLog.keypress(:,2),'UniformOutput',false);
    addLog.keypress(:,2)=aux;
    addLog.keypress=addLog.keypress(cellfun(@(x) ~isempty(x),addLog.keypress(:,1)),:); %Eliminating empty entries
    datlog.addLog=addLog;
catch ME
    ME
end
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

%convert frame times & markers
temp = find(datlog.framenumbers.data(:,1)==0,1,'first');
datlog.framenumbers.data(temp:end,:) = [];
for z = 1:temp-1
    datlog.framenumbers.data(z,3) = etime(datevec(datlog.framenumbers.data(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
 %save marker positions for the SAME frames
 for l=1:length(mn)
     eval(['aux=datlog.Markers.' mn{l} ';']);
     aux(temp:end,:)=[];
     eval(['datlog.Markers.' mn{l} '=aux;']);
     eval(['aux=datlog.Markers.' mn{l} 'filt;']);
     aux(temp:end,:)=[];
     eval(['datlog.Markers.' mn{l} 'filt=aux;']);
     eval(['aux=datlog.Markers.' mn{l} 'var;']);
     aux(temp:end,:)=[];
     eval(['datlog.Markers.' mn{l} 'var=aux;']);
 end

%convert RHS times
temp = find(datlog.stepdata.RHSdata(:,1) == 0,1,'first');
datlog.stepdata.RHSdata(temp:end,:) = [];
datlog.stepdata.paramRHS(temp:end,:) = [];
for z = 1:temp-1
   datlog.stepdata.RHSdata(z,4) = etime(datevec(datlog.stepdata.RHSdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
%convert LHS times
temp = find(datlog.stepdata.LHSdata(:,1) == 0,1,'first');
datlog.stepdata.LHSdata(temp:end,:) = [];
datlog.stepdata.paramLHS(temp:end,:) = [];
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
temp = all(isnan(datlog.TreadmillCommands.read(:,4)),2);
datlog.TreadmillCommands.read=datlog.TreadmillCommands.read(~temp,:);
for z = 1:size(datlog.TreadmillCommands.read,1)
    datlog.TreadmillCommands.read(z,4) = etime(datevec(datlog.TreadmillCommands.read(z,4)),datevec(datlog.framenumbers.data(1,2))); %This fails when no frames were received
end

temp = all(isnan(datlog.TreadmillCommands.sent(:,4)),2);
datlog.TreadmillCommands.sent=datlog.TreadmillCommands.sent(~temp,:);
 for z = 1:size(datlog.TreadmillCommands.sent,1)
     datlog.TreadmillCommands.sent(z,4) = etime(datevec(datlog.TreadmillCommands.sent(z,4)),datevec(datlog.framenumbers.data(1,2)));
 end
 
%convert audio times
temp = isnan(datlog.audioCues.start);
datlog.audioCues.start=datlog.audioCues.start(~temp);
datlog.audioCues.start = ((datlog.audioCues.start)-(datlog.framenumbers.data(1,2)))*86400;

temp = isnan(datlog.audioCues.stop);
datlog.audioCues.stop=datlog.audioCues.stop(~temp);
datlog.audioCues.stop = ((datlog.audioCues.stop) - (datlog.framenumbers.data(1,2)))*86400;

 
 %Get rid of graphical objects we no longer need:
 if exist('ff','var') && isvalid(ff)
    close(ff)
 end
 set(ghandle.profileaxes,'Color',[1,1,1]) 
 delete(findobj(ghandle.profileaxes,'Type','Text'))
 delete(findobj(ghandle.profileaxes,'Type','Patch'))
 
 %Print some info:
 NR=length(datlog.stepdata.paramRHS);
 NL=length(datlog.stepdata.paramLHS);
 for M=[20,50]
     i1=max([1 NR-M]);
     i2=max([1 NL-M]);
    disp(['Average params for last ' num2str(M) ' strides: '])
    disp(['R=' num2str(nanmean(datlog.stepdata.paramRHS(i1:end))) ', L=' num2str(nanmean(datlog.stepdata.paramLHS(i2:end)))])
 end
 
 disp('saving datlog...');
try
    save(savename,'datlog');
    [d,~,~]=fileparts(which(mfilename));
    save([d '\..\datlogs\lastDatlog.mat'],'datlog');
catch ME
    disp(ME);
end

