
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
        disp('walking towards door');
    else
        disp('walking towards windows');
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

datlog.cadence.R = cadenceR;
datlog.cadence.L = cadenceL;

disp(['Mean R Cadence: ' num2str(nanmean(datlog.cadence.R))]);
disp(['Mean L Cadence: ' num2str(nanmean(datlog.cadence.L))]);




% datlog.targets.Rdata(1,8) = 0;
% datlog.targets.Rdata = [datlog.targets.Rdata(:,8);retime];

%{
hip(hip<2000)=nan;%remove turnarounds
hip(hip>7000)=nan;
hipd = diff(hip)./0.008333333;%velocity
out = nanmean(hipd(hipd>0));
back = nanmean(abs(hipd(hipd<0)));
datlog.OGspeed = nanmean([out,back]);

er = rank-lank;
er2 = lank-rank;

[~,ploc] = findpeaks(er,'MinPeakHeight',490,'MinPeakDistance',3);%find peaks of ank-ank


if temp(1) > 20
    ploc(1)=[];
end


figure(1)
plot(er);
hold on
plot(ploc,er(ploc),'green')

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
%}