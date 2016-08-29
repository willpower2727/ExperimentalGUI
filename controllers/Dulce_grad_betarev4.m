function [Ralpha,Lalpha,Rbeta,Lbeta,R,R2] = Dulce_grad_betarev4(velL,velR,FzThreshold)
%This function allows matlab to control the treadmill speed based on
%subject's position on the treadmill in an attempt to allow them to choose
%their self selected pace

global listbox%the text inside the log list on the GUI
global PAUSE%pause button value
global STOP
STOP = 0;
global Ralpha
global Lalpha
global Rbeta
global Lbeta
% global R
% global R2
% global Rsci
% global Lsci

Ralpha = zeros(length(velL),1);
Lalpha = zeros(length(velL),1);
Rbeta = zeros(length(velL),1);
Lbeta = zeros(length(velL),1);
R = zeros(length(velL),1);
R2 = zeros(length(velL),1);
% Rsci = zeros(length(velL),1);
% Lsci = zeros(length(velL),1);

ghandle = guidata(AdaptationGUI);%get handle to the GUI so displayed data can be updated

%Default threshold
if nargin<3
    FzThreshold=30; %Newtons (30 is minimum for noise not to be an issue)
elseif FzThreshold<30
    warning = ['Warning: Fz threshold too low to be robust to noise, using 30N instead'];
    listbox{end+1} = warning;
    set(ghandle.listbox1,'String',listbox);
end

%Check that velL and velR are of equal length
N=length(velL);
if length(velL)~=length(velR)
    warning = ['Velocity vectors of different length'];
    listbox{end+1} = warning;
    set(ghandle.listbox1,'String',listbox);
    return
end

%Initialize nexus & treadmill comm
try
[MyClient] = openNexusIface();
t = openTreadmillComm();
catch ME
    log=['Error ocurred when opening communications with Nexus & | Treadmill'];
    listbox{end+1}=log;
    disp(log);
end

% try%So that if something fails, communications are closed properly
[~,~,~,~,~,~,~] = NexusGetFrame(MyClient);

%Initiate variables
LstepCount=2;
RstepCount=2;

%Send first speed command
[payload] = getPayload(velR(1),velL(1),1000,1000,0);%start the belts moving
sendTreadmillPacket(payload,t);
set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(1)/1000));
set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(1)/1000));

Rzold = 0;
Lzold = 0;
RBS = velR(1);
LBS = velL(1);
RBSold = 0;
LBSold = 0;
pause(2)%wait while the treadmill speeds up
% keyboard
%% Main loop
while STOP == 0%only runs if stop button is not pressed
    while PAUSE %only runs if pause button is pressed
        pause(.1);
        log=['Paused at ' num2str(clock)];
%         disp(log)
        listbox{end+1}=log;
        
        %bring treadmill to a stop and keep it there!...
        [payload] = getPayload(0,0,500,500,0);
        sendTreadmillPacket(payload,t);
        
    end

    %Read frame, update necessary structures
    [~,~,~,~,~,~,~] = NexusGetFrame(MyClient);
%     disp('im runnin');
    %get data from Nexus
    Fz_R = MyClient.GetDeviceOutputValue( 'Right Treadmill', 'Fz' );
    Fz_L = MyClient.GetDeviceOutputValue( 'Left Treadmill', 'Fz' );
    
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
    
    
    %detect gait events
    if Fz_R.Value <= -30 && Rzold > -30
        %RHS
        set(ghandle.Right_step_textbox,'String',num2str(RstepCount));
        Ralpha(RstepCount) = RHIP-RANK;
        R(RstepCount) = abs(Rbeta(RstepCount-1))/Ralpha(RstepCount);
        abs(Rbeta(RstepCount-1))/Ralpha(RstepCount)
        plot(ghandle.profileaxes,RstepCount,velR(RstepCount+1)/1000,'o','MarkerFaceColor',[1 0.6 0.78],'MarkerEdgeColor','r');
        drawnow;
    elseif Fz_R.Value >=-30 && Rzold < -30
        %RTO
        Rbeta(RstepCount) = RHIP-RANK;
        RstepCount=RstepCount+1;
    end
    
    if Fz_L.Value <= -30 && Lzold > -30
        %LHS
        Lalpha(LstepCount) = LHIP-LANK;
        R2(LstepCount) = abs(Lbeta(LstepCount-1))/Lalpha(LstepCount);
        abs(Lbeta(LstepCount-1))/Lalpha(LstepCount)
        set(ghandle.Left_step_textbox,'String',num2str(LstepCount));
        plot(ghandle.profileaxes,LstepCount,velL(LstepCount+1)/1000,'o','MarkerFaceColor',[0.68 .92 1],'MarkerEdgeColor','b');
        drawnow;
    elseif Fz_L.Value >=-30 && Lzold < -30
        %LTO
        Lbeta(LstepCount) = LHIP-LANK;
        LstepCount=LstepCount+1;
    end
    
    %{
%     new_stanceL=Fz_L.Value<-FzThreshold; %20N Threshold
%     new_stanceR=Fz_R.Value<-FzThreshold;
%     
%     LHS=new_stanceL && ~old_stanceL;
%     RHS=new_stanceR && ~old_stanceR;
%     LTO=~new_stanceL && old_stanceL;
%     RTO=~new_stanceR && old_stanceR;
%     
%     %Maquina de estados: 0 = initial, 1 = single L, 2= single R, 3 = DS from
%     %single L, 4= DS from single R
%     switch phase
%         case 0 %DS, only initial phase
%             if RTO
%                 phase=1; %Go to single L
%                 RstepCount=RstepCount+1;
%                 RTOTime(RstepCount) = TimeStamp;
%                 stepFlag=1; %R step
%             elseif LTO %Go to single R
%                 phase=2;
%                 LstepCount=LstepCount+1;
%                 LTOTime(LstepCount) = TimeStamp;
%                 stepFlag=2; %L step
%             end
%         case 1 %single L
%             if RHS
%                 phase=3;
%                 log = ['Right step #' num2str(LstepCount) ' ' num2str(clock)];
% %                 disp(log)
%                 RHSTime(RstepCount) = TimeStamp;
%                 set(ghandle.Right_step_textbox,'String',num2str(LstepCount));
%                 listbox{end+1} = log;
%                 set(ghandle.listbox1,'String',listbox);
%                 %plot cursor
% %                 plot(ghandle.profileaxes,RstepCount,velR(uint8(RstepCount+1))/1000,'o','MarkerFaceColor',[1 0.6 0.78]);
%                 plot(ghandle.profileaxes,RstepCount,RBS/1000,'o','MarkerFaceColor',[1 0.6 0.78]);
% 
%                 %                 drawnow;
%             end
%         case 2 %single R
%             if LHS
%                 phase=4;
%                 log = ['Left step #' num2str(LstepCount) ' ' num2str(clock)];
% %                 disp(log)
%                 LHSTime(LstepCount) = TimeStamp;
%                 set(ghandle.Left_step_textbox,'String',num2str(LstepCount));
%                 listbox{end+1} = log;
%                 set(ghandle.listbox1,'String',listbox);
%                 %plot cursor
% %                 plot(ghandle.profileaxes,LstepCount,velL(uint8(LstepCount+1))/1000,'o','MarkerFaceColor',[0.68 .92 1]);
%                 plot(ghandle.profileaxes,LstepCount,LBS/1000,'o','MarkerFaceColor',[0.68 .92 1]);
% 
%                 %                 drawnow;
%             end
%         case 3 %DS, coming from single L
%             if LTO
%                 phase = 2; %To single R
%                 LstepCount=LstepCount+1;
%                 LTOTime(LstepCount) = TimeStamp;
%                 stepFlag=2; %Left step
%             end
%         case 4 %DS, coming from single R
%             if RTO
%                 phase =1; %To single L
%                 RstepCount=RstepCount+1;
%                 RTOTime(RstepCount) = TimeStamp;
%                 stepFlag=1; %R step
%             end
%     end
    %}
    %see if new belt speed command needs to be sent
%     keypress = getkeywait(0.05);
    

%     if strcmp(keypress,'8')%press # 8
%         %speed up
%         disp('speed up command detected');
%         RBS = RBS + 10;
%         LBS = LBS + 10;
%         keypress = 'n';%change the value or the speed will keep increasing
%         if RBS >= 1700
%             disp('max speed limit reached');
%             RBS = 1700;%cap the speed
%             LBS = 1700;
%         else
%         end
%     elseif strcmp(keypress,'2')% press # 2
%         %slow down
%         disp('slow down command detected');
%         RBS = RBS - 10;
%         LBS = LBS - 10;
%         keypress = 'n';
%         if RBS <= 0
%             disp('min speed limit reached');
%             RBS = 0;%cap the speed
%             LBS = 0;
%         else
%         end
%     elseif strcmp(keypress,'f')%perturb fast
%         disp('Fast perturb command deteced');
%         RBS = 1500;
%         LBS = 1500;
%         keypress = 'n';
%     elseif strcmp(keypress,'s')
%         disp('Slow Perturb command detected');
%         RBS = 500;
%         LBS = 500;
%         keypress = 'n';
%     elseif strcmp(keypress,'b')% press "b"
%         %experimentor reset to current profile velocity
%         disp('return to profile speed detected');
%         RBS = velR(RstepCount+1);
%         LBS = velL(LstepCount+1);
%         keypress = 'n';
%     end
    
    %update the record
%     speedrecord.Value(end+1) = RBS;
%     speedrecord.Value(1) = [];

    %see if we should notify that the current speed is a preferred speed
%     if range(speedrecord.Value) == 0 %40 strides of the same speed
%         ssactual.Value(RstepCount) = RBS;
%         set(ghandle.text18,'String',num2str(RBS/1000));
%         set(ghandle.stdevn,'String',num2str(round(std(speedrecord.Value)))/1000);
%         set(ghandle.text18,'BackgroundColor','green');
%         set(ghandle.stdevn,'BackgroundColor','green');
%     else
%         set(ghandle.text18,'String',num2str(RBS/1000));
%         set(ghandle.stdevn,'String',num2str(round(std(speedrecord.Value)))/1000);
%         set(ghandle.stdevn,'BackgroundColor','white');
%         set(ghandle.text18,'BackgroundColor','white');
%     end
    
    RBS = velR(RstepCount);
    LBS = velL(LstepCount);
    %determine if we need to send a command to the treadmill
    if RBS == RBSold && LBS == LBSold
    else% something is new and needs to be sent to treadmill
        set(ghandle.LBeltSpeed_textbox,'String',num2str(velL));
        set(ghandle.RBeltSpeed_textbox,'String',num2str(velR));
        drawnow
        payload = getPayload(velR(RstepCount),velL(LstepCount),1000,1000,0);
        sendTreadmillPacket(payload,t);
    end
    
    Rzold = Fz_R.Value;
    Lzold = Fz_L.Value;
    RBSold = velR(RstepCount);
    LBSold = velL(LstepCount);
    
    if (LstepCount>=N) || (RstepCount>=N)
        break
    end
    pause(0.001);%slow down the while loop a little so it has time to check for keys being pressed
end %While, when STOP button is pressed
% ssout = ssactual.Value;
% keyboard
% Rsci = 0.5*(1./(Ralpha+1./(1+R)*(abs(Rbeta)-R.*Ralpha)));
% Lsci = 0.5*(1./(Lalpha+1./(1+R2)*(abs(Lbeta)-R2.*Lalpha)));
Ralpha(Ralpha <= 0) = [];
Lalpha(Lalpha <= 0) = [];
Rbeta(Rbeta == 0)=[];
Lbeta(Lbeta==0)=[];
R(R==0)=[];
R2(R2==0)=[];

% Rmaxlen = min([length(Ralpha) length(Rbeta)]);
% Lmaxlen = min([length(Lalpha) length(Lbeta)]);
% 
% Ralpha(Rmaxlen+1:end) = [];
% Rbeta(Rmaxlen+1:end) = [];
% Lalpha(Lmaxlen+1:end) = [];
% Lbeta(Lmaxlen+1:end) = [];
% keyboard
% Rsci = 0.5*(1./(Ralpha+1./(1+R).*(abs(Rbeta)-R.*Ralpha)));
% Lsci = 0.5*(1./(Lalpha+1./(1+R2).*(abs(Lbeta)-R2.*Lalpha)));


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

end

