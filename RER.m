function [] = RER(OGspeed)
%Generates speed profiles for time based treadmill control
%   input "OGspeed" is the subject's overground speed
%   
%   function will generate a 6 minute profile, and save

velL = 0.6666*OGspeed*ones(180,1);
x = 1:180;
y = 0.6666*OGspeed+(OGspeed-0.6666*OGspeed)/180*x;

velL = [velL;y'];
velR = velL;

velL = [velL;OGspeed*ones(180,1)];
velR = velL;

save('RER.mat','velL','velR');
end

