import socket
import io
import struct

def askforangle():
    ##  HOST2 = 'BIOE-PC'
    HOST2 = 'localhost'
    PORT2 = 4000
    s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    print('Treadmill Socket created')
    print('Treadmill Socket now connecting')
    s2.connect((HOST2,PORT2))
    print('Treadmill connection linked')
    inpack = ''#initialize a buffer
    temp = s2.recv(1)#start to clear the buffer
    s2.setblocking(False)
    while (len(temp)>0):
        try:
            s2.recv(1)
        except:
            break
    s2.setblocking(True)
    inpack = s2.recv(32)#read from the treadmill
    reads = parsepacket(inpack)
    s2.close()
##    print(reads)
    return reads[5]#return only the incline angle

def serializepacket(speedR,speedL,accR,accL,theta):
    fmtpack = struct.Struct('>B 18h 27B')#should be 64 bits in length to work properly
    outpack = fmtpack.pack(0,speedR,speedL,0,0,accR,accL,0,0,theta,~speedR,~speedL,~0,~0,~accR,~accL,~0,~0,~theta,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    return(outpack)

def parsepacket(inpack):
##  print('inpack lengthL ',len(inpack))
    fmtin = struct.Struct('>B 5h 21B')
##  print(fmtin)
    try:
        treadsave = fmtin.unpack(inpack)
##      print(treadsave)
##      q4.put(treadsave)#send it off to be saved
        return treadsave
    except:
        return ['nan','nan','nan','nan','nan','nan']

def sendreceive(speedlist,q3,treadsave,q4,stopevent,stopatendvar,inclineang):
##  HOST2 = 'BIOE-PC'
    HOST2 = 'localhost'
    PORT2 = 4000
    s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    print('Treadmill Socket created')
    print('Treadmill Socket now connecting')
    s2.connect((HOST2,PORT2))
    print('Treadmill comms linked')
            
    while (not stopevent.is_set()):
            
            if (q3.empty()==False):
                    speedlist = q3.get()
                    out = serializepacket(speedlist[0],speedlist[1],speedlist[2],speedlist[3],speedlist[4])
                    s2.send(out)
                    inpack = ''#initialize a buffer
                    temp = s2.recv(1)#start to clear the buffer
                    s2.setblocking(False)
                    while (len(temp)>0):
                            try:
                                s2.recv(1)
                            except:
                                break
                    s2.setblocking(True)
                    inpack = s2.recv(32)#read from the treadmill
##                    print('inpack on send lengthL ',len(inpack))
                    reads = parsepacket(inpack)
                    savepack = [speedlist[0],speedlist[1],reads[1],reads[2],reads[5]]
                    q4.put(savepack)
            else:
                    inpack = ''#initialize a buffer
                    temp = s2.recv(1)#stk
                    s2.setblocking(False)
                    while (len(temp)>0):
                            try:
                                s2.recv(1)
                            except:
                                break
                    s2.setblocking(True)
                    inpack = s2.recv(32)#read from the treadmill
##                    print('inpack on empty lengthL ',len(inpack))
                    reads = parsepacket(inpack)
                    savepack = ['nan','nan',reads[1],reads[2],reads[5]]
                    q4.put(savepack)
                    
    #at the end make sure the treadmill is stopped
    if stopatendvar.get()==1:
            out = serializepacket(0,0,500,500,inclineang) 
            s2.send(out)
    s2.close()

