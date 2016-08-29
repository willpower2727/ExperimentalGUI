clear
clc

%symbolic first
a = sym('a');%x
b = sym('b');%y
g = sym('g');%z

Ra = [1 0 0;0 cos(a) -sin(a);0 sin(a) cos(a)];
Rb = [cos(b) 0 sin(b);0 1 0;-sin(b) 0 cos(b)];
Rg = [cos(g) -sin(g) 0;sin(g) cos(g) 0;0 0 1];

RhmdU0sym = Rg*Rb*Ra;


%numerical
aa = -8.57*pi/180;
bb = 86.417*pi/180;
gg = -11.31*pi/180;

Raa = [1 0 0;0 cos(aa) -sin(aa);0 sin(aa) cos(aa)];
Rbb = [cos(bb) 0 sin(bb);0 1 0;-sin(bb) 0 cos(bb)];
Rgg = [cos(gg) -sin(gg) 0;sin(gg) cos(gg) 0;0 0 1];

RhmdU0 = Rgg*Rbb*Raa

HhmdU0 = [RhmdU0(1,1),RhmdU0(1,2),RhmdU0(1,3) -396.44;
    RhmdU0(2,1),RhmdU0(2,2),RhmdU0(2,3),551.2;
    RhmdU0(3,1),RhmdU0(3,2),RhmdU0(3,3),584;
    0,0,0,1]

[-395.98;649.77;527.04;0]
Ph = inv(HhmdU0)*[-395.98;649.77;527.04;1]

Pu = HhmdU0*[55.6688;99;-7.73;1]

% RdU0 = [-1 0 0;0 1 0;0 0 1]
RdU0 = [1 0 0;0 1 0;0 0 1];

RUV = [-1 0 0;0 0 1;0 -1 0];

at = -177.9*pi/180;
bt = 31.2*pi/180;
gt = 90.4*pi/180;
% at = -156*pi/180;
% bt = 21.7*pi/180;
% gt = 43.4*pi/180;

Rat = [1 0 0;0 cos(at) -sin(at);0 sin(at) cos(at)];
Rbt = [cos(bt) 0 sin(bt);0 1 0;-sin(bt) 0 cos(bt)];
Rgt = [cos(gt) -sin(gt) 0;sin(gt) cos(gt) 0;0 0 1];

RhmdUt = Rat*Rbt*Rgt;

% RdVt = RUV*RhmdUt*RhmdU0'*RdU0
RdUt = RhmdUt*RhmdU0'*RdU0;%This is the one we want

beta = atan2(RdUt(1,3),sqrt(RdUt(2,3)^2+RdUt(3,3)^2));
alpha = atan2(-1*RdUt(2,3)/cos(beta),RdUt(3,3)/cos(beta));
gamma = atan2(-1*RdUt(1,2)/cos(beta),RdUt(1,1)/cos(beta));


disp(['alpha: ' num2str(alpha*180/pi) ',beta: ' num2str(beta*180/pi) ', gamma: ' num2str(gamma*180/pi)])


%vizard coordinate system is left handed Y-X-Z
Ra = [1 0 0;0 cos(a) sin(a);0 -sin(a) cos(a)];
Rb = [cos(b) 0 -sin(b);0 1 0;sin(b) 0 cos(b)];
Rg = [cos(g) sin(g) 0;-sin(g) cos(g) 0;0 0 1];

Rviz = Rb*Rg*Ra;


sqrt((cos(b)*cos(a))^2+(sin(b)*cos(a))^2)
