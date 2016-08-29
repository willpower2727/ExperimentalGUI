function [fullPayload] = getPayload(speedR,speedL,accR,accL,incline)
%UNTITLED5 Summary of this function goes here
%   Detailed explanation goes here


%% Relevant parameters
maxAcc=3000;
maxVel=6500;
minVel=-6500;
maxInc=1500;
%% Range check:
if accR<1
    accR=1000;
end
if accL<1
    accL=1000;
end
if accR>maxAcc
    accR=maxAcc;
end
if accL>maxAcc
    accL=maxAcc;
end
if incline<0
    incline=0;
end
if incline>maxInc
    incline=maxInc;
end
if speedR<minVel
    speedR=minVel;
end
if speedR>maxVel
    speedR=maxVel;
end
if speedL<minVel
    speedL=minVel;
end
if speedL>maxVel
    speedL=maxVel;
end

%% Sending of packet
format=0;
speedRR=0;
speedLL=0;

accRR=0;
accLL=0;

aux=int16toBytes(round([speedR speedL speedRR speedLL accR accL accRR accLL incline]));
actualData=reshape(aux',size(aux,1)*2,1);
secCheck=255-actualData;
padding=zeros(1,27);

fullPayload=[format actualData' secCheck' padding];
keyboard
end

