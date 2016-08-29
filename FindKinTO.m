function TO = FindKinTO(start,stop,ankdata,n)
% find mmin of limb angle trace

for i = start:stop
    if i == 1
        a = 1;
    elseif (i-n) < 1
        a = 1:i-1;
    else
        a = i-n:i-1;
    end
    if i == stop
        b = stop;
    elseif (i+n) > stop
        b = i+1:stop;
    else
        b = i+1:i+n;
    end
    if all(ankdata(i)<= ankdata(a)) && all(ankdata(i)<=ankdata(b))
        break;
    end
end
TO = i;
end

