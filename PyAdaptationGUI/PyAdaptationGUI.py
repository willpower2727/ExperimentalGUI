#PyAdaptation GUI can do what the MATLAB's Adaptation GUI does only better
#
#Advantages:    - multithtreading ensures 100% data capture in live mode
#               - uses more up-to-date SDK from Vicon
#               - lower computational load on the PC
#               
# WDA 8/11/2016

import sys
import matplotlib
matplotlib.use('TkAgg')
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2TkAgg
import scipy.io
import tkFileDialog
import numpy
import mtTkinter as Tkinter #special threadsafe version of Tkinter module, required for message windows. You can use regular Tkinter if needed but remove message window code that asks if Nexus is recording
import time
import threading
import Queue
import struct
import array
import math
import os
import ntpath
import ParseRoot
import StrideCounter
import NexusClient
import SaveThread
import BertecComm
import KeyHook

numpy.set_printoptions(threshold=numpy.inf)

#initialize some things
rot = Tkinter.Tk()
rot.wm_title("PyAdaptationGUI")
rot.geometry('{}x{}'.format(1100,700))

global stopevent #how to signal stopping from GUI
stopevent = threading.Event()

global pauseevent #used to signal a pause
pauseevent = threading.Event()

#start setting up the plotting axis
global f #figure variable
f = Figure(figsize=(7,5),dpi=100)
global axe #plot
axe = f.add_subplot(111)
global canvas
canvas = FigureCanvasTkAgg(f, master=rot)

##global nexusvar#variable flag that indicates whether or not to start Nexus on startup
nexusvar = Tkinter.IntVar(rot)

##global stopatendvar #whether or not to stop the treadmill at the end of a profile, default is yes stop
stopatendvar = Tkinter.IntVar(rot)

#initialize profiles
global velL #belt speed profiles to be loaded from a file later
global velR
velL = 0
velR = 0

def startup(): #what to do when the gui is created
	global f
	global axe
	axe.plot(0,0)
	axe.set_title('Velocity Profile')
	global profilename
	profilename = ''
	
##	canvas = FigureCanvasTkAgg(f, master=rot)
	canvas.show()
	canvas.get_tk_widget().place(x=0,y=50,width=875,height=575)

def ClosebyX(): #what to do when closing the gui
##	print('Window closed')
##	rot.destroy()
	rot.quit()
##	rot.destroy()
##	sys.exit

def Execute():  #what to do when execute is pressed
	global stopevent
	global pauseevent
##	global nexusvar
	global profilename
	stopevent.clear()#remove any prior event flags
	pauseevent.clear()

	StatusText.configure(state='normal')
	StatusText.configure(background='#FFB400')
	StatusText.delete(1.0,Tkinter.END)
	StatusText.insert(Tkinter.END,'Busy')
	StatusText.configure(state='disabled')#don't let anyone type in this

	StartNexus.configure(state='disabled')#don't allow anyone to change whether or not Nexus trials toggle capture
	startbut.configure(state='disabled')
	print('OpenLoopController executed at: ',time.time())

	root = ''#empty string for passing around Nexus data
	savestring = ''
	speedlist = array.array('i')#numpy arrays of type integer
	treadsave = array.array('i')
	q1 = Queue.Queue()#Queue for parsing nexus data
	q2 = Queue.Queue()#Queue for saving controller loop data
	q3 = Queue.Queue()#Queue for treadmill commands
	q4 = Queue.Queue()#Queue for saving treadmill commands+reads
	q5 = Queue.Queue()#queue for key logging

	#ask the treadmill for the current incline angle, this will be written on every command during the trial so as not to change it (that would be really bad if the treadmill was locked)
	inca = BertecComm.askforangle()#asks the treadmill 1 time what the current incline angle is
	inca = int(round(inca,-1))#format the read, and round it to nearest 10
	Incind.configure(state='normal')
	Incind.delete(1.0,Tkinter.END)
	Incind.insert(Tkinter.END,str(inca))
	Incind.configure(state='disabled')
##	print('Incline Angle: ',inca)

	#build standard input argument dictionary, this can/will be passed into whatever control algorithm is selected. It's up to the creator of each control algorithm to determine whether to use all the information or not
	STDARGS = {}#create the dictionary
	STDARGS["root"] = root
	STDARGS["q1"] = q1
	STDARGS["speedlist"] = speedlist
	STDARGS["q3"] = q3
	STDARGS["savestring"] = savestring
	STDARGS["q2"] = q2 
	STDARGS["q5"] = q5
	STDARGS["velL"] = velL#belt speed profiles
	STDARGS["velR"] = velR
	STDARGS["inclineang"] = inca #this will/should change in the future
	STDARGS["nexusvar"] = nexusvar.get()
	STDARGS["stopevent"] = stopevent #threading event raised on stop callback
	STDARGS["axe"] = axe #plot axis
	STDARGS["canvas"] = canvas #plot canvas
	STDARGS["stopatendvar"] = stopatendvar #flag to stop at end of max stride count 
	STDARGS["Rspdind"] = Rspdind #right stride count indicator
	STDARGS["Lspdind"] = Lspdind #left stride count
	STDARGS["Rbspdind"] = Rbspdind #right belt speed indicator
	STDARGS["Lbspdind"] = Lbspdind #left belt speed
	STDARGS["Incind"] = Incind #incline angle indicator
	STDARGS["Freqind"] = Freqind #GUI main loop sampling frequency indicator
	STDARGS["Misind"] = Misind #missing stride count indicator
	STDARGS["StatusText"] = StatusText #GUI status indicator
	STDARGS["startbut"] = startbut #Execute button
	STDARGS["pauseevent"] = pauseevent #threading event raised on pause callback
	STDARGS["controller"] = 'C:\Users\BioE\Documents\MATLAB\ExperimentalGUI\PyAdaptationGUI\Controllers\\' + funlist.get()
##	print(STDARGS["controller"])
	
	#define the threads
	t1 = threading.Thread(target=NexusClient.NexusClient,args=(root,q1,stopevent))#communicates with Nexus
	t2 = threading.Thread(target=StrideCounter.ControlLoop,args=(STDARGS,))#the brain thread, counts strides and updates belt speeds
	t3 = threading.Thread(target=SaveThread.save,args=(savestring,q2,treadsave,q4,velL,velR,profilename,stopevent,inca,funlist.get()[:-3]))#takes care of saving data to file
	t4 = threading.Thread(target=BertecComm.sendreceive,args=(speedlist,q3,treadsave,q4,stopevent,stopatendvar,inca,Rbspdind,Lbspdind))#communicates with the treadmill
	t5 = threading.Thread(target=KeyHook.Hook,args=(q5,stopevent))
		
	t1.daemon = True
	t2.daemon = True
	t3.daemon = True
	t4.daemon = False
	t5.daemon = True
	#start the threads
	t1.start()
	t2.start()
	t3.start()
	t4.start()
	t5.start()

def plot():
	global f
	global axe
	global profilename
	axe.clear()

	StatusText.configure(state='normal')
	StatusText.configure(background='#FFB400')
	StatusText.delete(1.0,Tkinter.END)
	StatusText.insert(Tkinter.END,'Plotting')
	StatusText.configure(state='disabled')#don't let anyone type in this

	profilename = tkFileDialog.askopenfilename(initialdir='C:\Users\BioE\Documents\MATLAB\ExperimentalGUI\profiles')
	mat = scipy.io.loadmat(profilename)#loads a dictionary
	
	global velL #make these available to the rest of the GUI
	global velR
	velL = mat["velL"]#look for the profiles in the loaded dictionary
	velR = mat["velR"]
##	velR = numpy.where(velR==numpy.nan,velR,numpy.nan)
##	print 'velR',type(velR[22])
	size = velR.shape
	if (size[1] > size[0]):#detect if row or column vector
		velR = velR.T
		velL = velL.T
		size = velR.shape
	t = numpy.arange(0,size[0],1)
	axe.plot(t,velR,color="red",linewidth=3)
	axe.plot(t,velL,color="blue",linewidth=3)
	axe.grid(b=True,which='major',color='k',linestyle='-')
	axe.set_title('Velocity Profile')
	axe.set_xlabel('stride')
	axe.set_ylabel('Velocity (m/s)')
	axe.set_ylim((0,numpy.nanmax([velR,velL])+0.2))

	canvas.draw()
	canvas.get_tk_widget().place(x=0,y=50,width=875,height=575)
	
	startbut.configure(state='normal')
	StatusText.configure(state='normal')
	StatusText.delete(1.0,Tkinter.END)
	StatusText.insert(Tkinter.END,'Ready')
	StatusText.configure(background='#00D400')
	StatusText.configure(state='disabled')#don't let anyone type in this

	stopbut.configure(state='normal')
	pausebut.configure(state='normal')

def stop():
        global stopevent
        stopevent.set()

def pause():
        global pauseevent

        if (pausebut.configure('text')[-1] == 'PAUSE'):
                pauseevent.set()
##                print('pause pressed: ',pauseevent.is_set())
                pausebut.configure(text='RESUME')
        else:
                pauseevent.clear()
##                print('pause but pressed: ',pauseevent.is_set())
                pausebut.configure(text='PAUSE')

#########################################################################################################################################################################################################
#Make buttons and text displays and place them
fakebut = Tkinter.Button(rot,command=startup())#fake button that is not visible or placed, but runs the startup script

Title = Tkinter.Text(rot,background="#C8C8C8",font=("Helvetica",30))
Title.insert(Tkinter.END,'PyAdaptation GUI')
Title.place(x=0,y=0,width=450,height=45)

startbut = Tkinter.Button(rot,text='EXECUTE',command = Execute,bg='#FF4600',font=("Helvetica",15))
startbut.place(x=0,y=650,width=100,height=50)
startbut.configure(state='disabled');

exitbut = Tkinter.Button(rot,text='EXIT',command = ClosebyX,bg='red',font=("Helvetica",15))
exitbut.place(x=1000,y=650,width=100,height=50)

stopbut = Tkinter.Button(rot,text='STOP',command = stop,bg='red',font=("Helvetica",15))
stopbut.place(x=125,y=650,width=100,height=50)
stopbut.configure(state='disabled')

pausebut = Tkinter.Button(rot,text='PAUSE',command = pause,bg='yellow',font=("Helvetica",15))
pausebut.place(x=250,y=650,width=100,height=50)
pausebut.configure(state='disabled')

plotbutton = Tkinter.Button(rot,text='PLOT',command = plot,bg='#A7ECE3',font=("Helvetica",15))
plotbutton.place(x=375,y=650,width=100,height=50)

SClabel = Tkinter.Text(rot,background='#C8C8C8',font=("Helvetica",12,"bold"))
SClabel.place(x=880,y=45,width=220,height=25)
SClabel.insert(Tkinter.END,'Stride Count')

BSlabel = Tkinter.Text(rot,background='#C8C8C8',font=("Helvetica",12,"bold"))
BSlabel.place(x=880,y=155,width=220,height=25)
BSlabel.insert(Tkinter.END,'Belt Speeds (m/s)')

Rspdlabel = Tkinter.Text(rot,background='#C8C8C8',font=("Helvetica",12,"bold"))
Rspdlabel.place(x=1000,y=75,width=70,height=25)
Rspdlabel.insert(Tkinter.END,'Right')
Rspdlabel.configure(state='disabled')
Lspdlabel = Tkinter.Text(rot,background='#C8C8C8',font=("Helvetica",12,"bold"))
Lspdlabel.place(x=900,y=75,width=70,height=25)
Lspdlabel.insert(Tkinter.END,'Left')
Lspdlabel.configure(state='disabled')

Rspdind = Tkinter.Text(rot,background='#FF3C3C',font=("Helvetica",20))
Rspdind.place(x=1000,y=105,width=100,height=35)
Rspdind.insert(Tkinter.END,'00000')
Rspdind.configure(state='disabled')#don't let anyone type in this

Lspdind = Tkinter.Text(rot,background='#4FBDE5',font=("Helvetica",20))
Lspdind.place(x=880,y=105,width=100,height=35)
Lspdind.insert(Tkinter.END,'00000')
Lspdind.configure(state='disabled')

Rbspdlabel = Tkinter.Text(rot,background='#C8C8C8',font=("Helvetica",12,"bold"))
Rbspdlabel.place(x=1000,y=190,width=70,height=25)
Rbspdlabel.insert(Tkinter.END,'Right')
Rbspdlabel.configure(state='disabled')
Lbspdlabel = Tkinter.Text(rot,background='#C8C8C8',font=("Helvetica",12,"bold"))
Lbspdlabel.place(x=900,y=190,width=70,height=25)
Lbspdlabel.insert(Tkinter.END,'Left')
Lbspdlabel.configure(state='disabled')

Rbspdind = Tkinter.Text(rot,background='#FF3C3C',font=("Helvetica",20))
Rbspdind.place(x=1000,y=220,width=100,height=35)
Rbspdind.insert(Tkinter.END,'000.00')
Rbspdind.configure(state='disabled')#don't let anyone type in this

Lbspdind = Tkinter.Text(rot,background='#4FBDE5',font=("Helvetica",20))
Lbspdind.place(x=880,y=220,width=100,height=35)
Lbspdind.insert(Tkinter.END,'000.00')
Lbspdind.configure(state='disabled')

Inclabel = Tkinter.Text(rot,background='#C8C8C8',font=("Helvetica",12,"bold"))
Inclabel.place(x=880,y=340,width=220,height=25)
Inclabel.insert(Tkinter.END,'Incline Angle')
Inclabel.configure(state='disabled')

Incind = Tkinter.Text(rot,background='#C8C8C8')
Incind.place(x=880,y=370,width=220,height=25)
Incind.insert(Tkinter.END,'0')
Incind.configure(state='disabled')

Freqlabel = Tkinter.Text(rot,background='#C8C8C8',font=("Helvetica",12,"bold"))
Freqlabel.place(x=880,y=410,width=220,height=25)
Freqlabel.insert(Tkinter.END,'Sampling Frequency (Hz)')
Freqlabel.configure(state='disabled')

Freqind = Tkinter.Text(rot,background='#C8C8C8')
Freqind.place(x=880,y=440,width=220,height=25)
Freqind.insert(Tkinter.END,'0')
Freqind.configure(state='disabled')

Mislabel = Tkinter.Text(rot,background='#C8C8C8',font=("Helvetica",12,"bold"))
Mislabel.place(x=880,y=470,width=220,height=25)
Mislabel.insert(Tkinter.END,'Missed Frame Count')
Mislabel.configure(state='disabled')

Misind = Tkinter.Text(rot,background='#C8C8C8')
Misind.place(x=880,y=500,width=220,height=25)
Misind.insert(Tkinter.END,'0')
Misind.configure(state='disabled')

StatusText = Tkinter.Text(rot,background='#6E67FF',font=("Helvetica",25))
StatusText.place(x=880,y=290,width=220,height=40)
StatusText.insert(Tkinter.END,'Idle')
StatusText.configure(state='disabled')

StartNexus = Tkinter.Checkbutton(rot,text="Start Nexus",anchor=Tkinter.W,background="#C8C8C8",variable=nexusvar)
StartNexus.place(x=880,y=550,width=220,height=35)
StartNexus.select()#default make this option selected

StopatEnd = Tkinter.Checkbutton(rot,text="Stop Treadmill @ END",anchor=Tkinter.W,background="#C8C8C8",variable=stopatendvar)
StopatEnd.place(x=880,y=590,width=220,height=35)
StopatEnd.select()

#drop down menu for different control function
##global funlist
funlist = Tkinter.StringVar(rot)

drplabel = Tkinter.Text(rot,background='#C8C8C8')
drplabel.place(x=500,y=650,width=150,height=20)
drplabel.insert(Tkinter.END,'Control Function')
drplabel.configure(state='disabled')

clist = list()
for file in os.listdir('C:\Users\BioE\Documents\MATLAB\ExperimentalGUI\PyAdaptationGUI\Controllers'):
        if file.endswith('.py'):
                clist.append(file)
funlist.set("OpenLoop.py")

##dropdown = Tkinter.OptionMenu(rot,funlist,"OpenLoop","TimeLoop","KeyboardLoop")
dropdown = Tkinter.OptionMenu(rot,funlist,*clist)
dropdown.place(x=500,y=675,width=160,height=25)


rot.protocol('WM_DELETE_WINDOW', ClosebyX)
rot.mainloop()#this actually starts the GUI
rot.destroy()
