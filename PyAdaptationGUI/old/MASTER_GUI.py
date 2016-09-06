#MASTER GUI can do what the MATLAB GUI does only better and for running biofeedback routines.
#
#Advantages:    - multithtreading ensures no loss of data from Nexus
#               - lower computational load on the PC
#               
# WDA 11/30/2015

import sys
import matplotlib
matplotlib.use('TkAgg')
#import matplotlib.pyplot as PLT
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2TkAgg
import scipy.io
import tkFileDialog
import numpy
import Tkinter
import time
import socket
import io
import re
import threading
import Queue
import csv
import itertools
import struct
import array
import math
import os.path
import subprocess
import matplotlib.animation as animation
from matplotlib import style
import serial

	
rot = Tkinter.Tk()
rot.wm_title("MASTER GUI")
rot.geometry('{}x{}'.format(700,500))

global stopvar #how to signal stops
stopvar = 0

#start setting up the axes
global f #figure variable
f = Figure(figsize=(5,4),dpi=100)
global axe #plot
axe = f.add_subplot(111)
global canvas
canvas = FigureCanvasTkAgg(f, master=rot)

global nexusvar#variable flag that indicates whether or not to start Nexus on startup
nexusvar = Tkinter.IntVar()

global sport
sport = serial.Serial()
sport.port = "COM1"


#initialize profiles
global velL #belt speed profiles
global velR
velL = 0
velR = 0

def startup(): #what to do when the gui is created
	global f
	global axe
	axe.plot(0,0)
	axe.set_title('Velocity Profile')
	
##	canvas = FigureCanvasTkAgg(f, master=rot)
	canvas.show()
	canvas.get_tk_widget().place(x=0,y=50,width=500,height=400)

def ClosebyX(): #what to do when closing the gui
##	print('Window closed')
	rot.quit()
	rot.destroy()
	sys.exit

def Execute():  #what to do when execute is pressed
	global stopvar
	stopvar = 0

	StatusText.configure(state='normal')
	StatusText.configure(background='#FFB400')
	StatusText.delete(1.0,Tkinter.END)
	StatusText.insert(Tkinter.END,'Busy')
	StatusText.configure(state='disabled')#don't let anyone type in this

	StartNexus.configure(state='disabled')#don't allow anyone to change whether or not Nexus trials toggle capture

	print('defaultcontrolwithstrides executed at: ',time.time())
	
	def controlLoop(root,q1,speedlist,q3,savestring,q2):
		global stopvar
		global velL
		global velR
		global histzL
		global histzR
		global rstrides
		global lstrides
		global maxstridecount
		global axe
		global canvas
		global nexusvar
		global sport
		histzL=0
		histzR=0
		rstrides = 0
		lstrides = 0

##		global cpps
		#start cpp server
		cpps = subprocess.Popen('"C:/Users/Public/Documents/Release/Vicon2Python_DK2_rev1.exe"',shell=False)
#		cpps = subprocess.Popen('"C:/Users/Gelsey Torres-Oviedo/Desktop/Vicon2Python_DK2_rev1.LNK"',shell=True)
		time.sleep(3)#wait for server to initialize
#		rot.lift()#bring gui to the front
		
		if isinstance(velL,( int, long )):#check to make sure user loaded a profile
			print('No speed profile has been loaded.')
			stopvar = 1
		else:
			#send the first speed command...
			speedlist = [int(1000*velR[0]),int(1000*velL[0]),1000,1000,0]
			q3.put(speedlist)
			print('first speed command sent')
			
		maxstridecount = len(velL)
##		print(maxstridecount)

		#before starting check to see if we need to start Nexus
		if nexusvar.get()==1:
			sport.open()
##			time.sleep(0.1)
			sport.close()
		
		while (stopvar !=1):
			root = q1.get()
			data = ParseRoot(root)
			
			Rz = float(data["Rz"])
			Lz = float(data["Lz"])
			
			if (Rz<-30) & (histzR>-30): #RHS
##				print('rhs')
				Rspdind.configure(state='normal')
				Rspdind.delete(1.0,Tkinter.END)
				Rspdind.insert(Tkinter.END,str(rstrides))
				Rspdind.configure(state='disabled')#don't let anyone type in this
				axe.plot(rstrides,velR[rstrides],'r',marker='o',fillstyle='full')
				canvas.draw()

			elif (Rz>-30) & (histzR<-30): #RTO
				rstrides +=1
##				print('rto',rstrides)
				if (rstrides<maxstridecount):
					speedlist = [int(1000*velR[rstrides]),int(1000*velL[lstrides]),1000,1000,0]
					q3.put(speedlist)
##					print('speed command requested R')
##					print('q3 size: ',q3.qsize())
				else:
					stopvar = 1
					continue
				
			if (Lz<-30) & (histzL>-30): #LHS
##				print('lhs')
				Lspdind.configure(state='normal')
				Lspdind.delete(1.0,Tkinter.END)
				Lspdind.insert(Tkinter.END,str(lstrides))
				Lspdind.configure(state='disabled')#don't let anyone type in this
				axe.plot(lstrides,velL[lstrides],'b',marker='o',fillstyle='full')
				canvas.draw()
			elif (Lz>-30) & (histzL<-30): #LTO
				lstrides +=1
##				print('lto',lstrides)
				if (lstrides<maxstridecount):
					speedlist = [int(1000*velR[rstrides]),int(1000*velL[lstrides]),1000,1000,0]
					q3.put(speedlist)
##					print('speed command requested L')
				else:
					stopvar = 1
					continue
			savestring = [data["FN"],Rz,Lz]
			q2.put(savestring)
			
			histzL = Lz
			histzR = Rz
		speedlist = [int(0),int(0),1000,1000,0]
		q3.put(speedlist)
##		t1.join()
		
		if nexusvar.get()==1:#stop data collection in nexus
			sport.open()
##			time.sleep(0.1)
			sport.close()
			
		cpps.kill()
		print('CPP server killed')
##		stopvar = 0#reset for the next execute
		StatusText.configure(state='normal')
		StatusText.delete(1.0,Tkinter.END)
		StatusText.insert(Tkinter.END,'Ready')
		StatusText.configure(background='#00D400')
		StatusText.configure(state='disabled')#don't let anyone type in this
		StartNexus.configure(state='normal')
		
			
	def NexusClient(root,q1):
		global stopvar

		HOST = 'localhost'#IP address of CPP server
		PORT = 50008
		s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		print 'Socket created'
		print 'Socket now connecting'
		s.connect((HOST,PORT))
		s.send('1')#send initial request for data
		while (stopvar != 1):
			data = s.recv(50)#receive the initial message
			data3 = data[:3]#get first 3 letters
			if (data3 == "New"):
				nextsizestring = data[3:]#get the integer after "New"
				nextsizestring2 = nextsizestring.rstrip('\0')#format
				nextsize = int(nextsizestring2,10)#cast as type int
	#			print("Next Packet is size: ")
	#			print(nextsize)
				s.send('b')#tell cpp server we are ready for the packet
				databuf = ''#initialize a buffer
				while (sys.getsizeof(databuf) < nextsize):
					data = s.recv(nextsize)#data buffer as a python string
					databuf = databuf + data#collect data into buffer until size is matched
				root = databuf
##				print('root: ',root)

				q1.put(root)#place the etree into the threading queue
			elif (data3 != "New"):
				print("WARNING! TCP SYNCH HAS FAILED")
				break
			if not data: break
			s.send('b')
		s.close()
		print('Nexus communications terminated.')
		
	def save(savestring,q2,treadsave,q4):
		global stopvar

		mst = time.time()
		mst2 = int(round(mst))

		mststring = str(mst2)+'PyGUI_OpenLoopController.txt'
		print("Data File created named: ")
		print(mststring)
		fileout = open(mststring,'w+')
		csvw = csv.writer(fileout)
		csvw.writerow(['FrameNumber','Rfz','Lfz','Rbeltspeed','Lbeltspeed'])#write the header
		fileout.close()

		
		fileout = open(mststring,'a')#open for append
		csvw = csv.writer(fileout)
		while (stopvar != 1):
			nex = q2.get()
			try:
				tread = q4.get(False)
				tread2 = [tread[1],tread[2]]
##				print('tread saved')
			except:
				tread2 = ['nan','nan']
			savestr = nex+tread2
			csvw.writerow(savestr)
		fileout.close() 
		print('Saving complete.')

		

	def ParseRoot(root):#the purpose of this function is to make sure that marker data is used correctly since they can arrive in different order, depending on the order the models are listed in Nexus
		tempdat = root.split(',')
	#	print tempdat
		del tempdat[-1]#the last element is a empty string ""
		data = {}#create dictionary
		
		data["FN"] = int(tempdat[0])#frame number
		data["Rz"] = float(tempdat[4])#right forceplate Z component
		data["Lz"] = float(tempdat[2])#left forceplate Z comp.
		data["DeviceCount"] = float(tempdat[5])# #of devices besides forceplates
		for x in range(6,6+2*int(data["DeviceCount"])-1,2):  #assumes one value per device for now...
			temp = tempdat[x]
			data[temp] = [tempdat[x+1]]
	#		print temp
		
		#place marker data into dictionary
		for z in range(6+2*int(data["DeviceCount"]),len(tempdat),4):
			temp = tempdat[z]
	#		print temp
			data[temp] = [tempdat[z+1],tempdat[z+2],tempdat[z+3]]
			
	#	print data
		return data

	def sendtreadmillcommand(speedlist,q3,treadsave,q4):
		global stopvar
##		HOST2 = 'BIOE-PC'
		HOST2 = 'localhost'
		PORT2 = 4000
		s2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		print 'Treadmill Socket created\n'
		print 'Treadmill Socket now connecting\n'
		s2.connect((HOST2,PORT2))
		print 'Treadmill comms linked\n'
		
		def serializepacket(speedR,speedL,accR,accL,theta):
			fmtpack = struct.Struct('>B 18h 27B')#should be 64 bits in length to work properly
			outpack = fmtpack.pack(0,speedR,speedL,0,0,accR,accL,0,0,theta,~speedR,~speedL,~0,~0,~accR,~accL,~0,~0,~theta,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
			return(outpack)

		def parsepacket(inpack):
##			print('outpack lengthL ',len(outpack))
			fmtin = struct.Struct('>B 5h 21B')
			treadsave = fmtin.unpack(inpack)
##			print(treadsave)
			q4.put(treadsave)#send it off to be saved
			
		old0 = -1
		old1 = -1
##		print('stopvar',stopvar)
		while (stopvar != 1):
##			print('stopvar',stopvar)

##			print(q3.empty())
			if (q3.empty()==False):
				speedlist = q3.get()#do not wait for something to be added to the queue
##				print('speed command detected\n')
##				print(speedlist)

				out = serializepacket(speedlist[0],speedlist[1],speedlist[2],speedlist[3],speedlist[4])
				s2.send(out)
				old0 = speedlist[0]
				old1 = speedlist[1]

				inpack = ''#initialize a buffer
				temp = s2.recv(1)#start to clear the buffer
				s2.setblocking(False)
				while (len(temp)>0):
##					print('clearing the buffer')
					try:
						s2.recv(1)
					except:
##						print('buffer cleared')
						break
				s2.setblocking(True)
				inpack = s2.recv(32)#read from the treadmill
				parsepacket(inpack)
			else:
				inpack = ''#initialize a buffer
				temp = s2.recv(1)#start to clear the buffer
				s2.setblocking(False)
				while (len(temp)>0):
##					print('clearing the buffer')
					try:
						s2.recv(1)
					except:
##						print('buffer cleared')
						break
				s2.setblocking(True)
				inpack = s2.recv(32)#read from the treadmill
				parsepacket(inpack)
				

		#at the end make sure the treadmill is stopped
		out = serializepacket(0,0,500,500,0) 
#		print('out',out)
		s2.send(out)
		print('stop command sent')
		s2.close()
##		t3.join()
		print('Treadmill communications terminated.')


	root = ''#empty string
	savestring = ''
	speedlist = array.array('i')
	treadsave = array.array('i')
	q1 = Queue.Queue()#initialize the queue
	q2 = Queue.Queue()#another queue for save strings
	q3 = Queue.Queue()#for the treadmill commands
	q4 = Queue.Queue()#for saving treadmill comms

	t1 = threading.Thread(target=NexusClient,args=(root,q1))
	t2 = threading.Thread(target=controlLoop,args=(root,q1,speedlist,q3,savestring,q2))
	t3 = threading.Thread(target=save,args=(savestring,q2,treadsave,q4))
	t4 = threading.Thread(target=sendtreadmillcommand,args=(speedlist,q3,treadsave,q4))
		
		
	t1.daemon = True
	t2.daemon = True
	t3.daemon = True
	t4.daemon = False
	#start the threads
	t1.start()
	t2.start()
	t3.start()
	t4.start()

def plot():
	global f
	global axe

	StatusText.configure(state='normal')
	StatusText.configure(background='#FFB400')
	StatusText.delete(1.0,Tkinter.END)
	StatusText.insert(Tkinter.END,'Plotting')
	StatusText.configure(state='disabled')#don't let anyone type in this

##	global canvas
##	axe.clear()
	filename = tkFileDialog.askopenfilename()
#	print(filename)
	mat = scipy.io.loadmat(filename)#loads a dictionary
##	print(type(mat))
	
	global velL #make these available to the rest of the GUI
	global velR
	velL = mat["velL"]#look for the profiles in the loaded dictionary
	velR = mat["velR"]
	print(velL)
	size = velR.shape
	if (size[1] > size[0]):#detect if row or column vector
		velR = velR.T
		velL = velL.T
		size = velR.shape
	t = numpy.arange(0,size[0],1)
	axe.plot(t,velR,color="red")
	axe.plot(t,velL,color="blue")
	axe.set_title('Velocity Profile')
	axe.set_xlabel('stride')
	axe.set_ylabel('Velocity (m/s)')
	axe.set_ylim((0,numpy.max([velR,velL])+0.2))

##	canvas = FigureCanvasTkAgg(f, master=rot)
	canvas.draw()
	canvas.get_tk_widget().place(x=0,y=50,width=500,height=400)
	
	startbut.configure(state='normal')
	
	StatusText.configure(state='normal')
	StatusText.delete(1.0,Tkinter.END)
	StatusText.insert(Tkinter.END,'Ready')
	StatusText.configure(background='#00D400')
	StatusText.configure(state='disabled')#don't let anyone type in this

	stopbut.configure(state='normal')

def stop():
	global stopvar
	stopvar = 1
#	print('control loop stopped at: ',time.time())

#########################################################################################################################################################################################################
#Make buttons and text displays
fakebut = Tkinter.Button(rot,command=startup())#fake button that is not visible or placed, but runs the startup script

Title = Tkinter.Text(rot,background="#C8C8C8",font=("Helvetica",30))
Title.insert(Tkinter.END,'PyAdaptation GUI')
Title.place(x=0,y=0,width=450,height=45)

startbut = Tkinter.Button(rot,text='EXECUTE',command = Execute,bg='#FF4600')
startbut.place(x=0,y=475,width=50,height=25)
startbut.configure(state='disabled');

exitbut = Tkinter.Button(rot,text='EXIT',command = ClosebyX,bg='red')
exitbut.place(x=650,y=475,width=50,height=25)

stopbut = Tkinter.Button(rot,text='STOP',command = stop,bg='red')
stopbut.place(x=75,y=475,width=50,height=25)
stopbut.configure(state='disabled')

plotbutton = Tkinter.Button(rot,text='PLOT',command = plot,bg='yellow')
plotbutton.place(x=150,y=475,width=50,height=25)

Rspdlabel = Tkinter.Text(rot,background='#C8C8C8')
Rspdlabel.place(x=590,y=65,width=70,height=25)
Rspdlabel.insert(Tkinter.END,'Right')
Rspdlabel.configure(state='disabled')
Lspdlabel = Tkinter.Text(rot,background='#C8C8C8')
Lspdlabel.place(x=510,y=65,width=70,height=25)
Lspdlabel.insert(Tkinter.END,'Left')
Lspdlabel.configure(state='disabled')

Rspdind = Tkinter.Text(rot,background='#FF3C3C',font=("Helvetica",20))
Rspdind.place(x=590,y=100,width=70,height=35)
Rspdind.insert(Tkinter.END,'000')
Rspdind.configure(state='disabled')#don't let anyone type in this

Lspdind = Tkinter.Text(rot,background='#3CFF3C',font=("Helvetica",20))
Lspdind.place(x=510,y=100,width=70,height=35)
Lspdind.insert(Tkinter.END,'000')
Lspdind.configure(state='disabled')

StatusText = Tkinter.Text(rot,background='#6E67FF',font=("Helvetica",25))
StatusText.place(x=510,y=150,width=220,height=40)
StatusText.insert(Tkinter.END,'Idle')
StatusText.configure(state='disabled')

StartNexus = Tkinter.Checkbutton(rot,text="Start Nexus",anchor=Tkinter.W,background="#C8C8C8",variable=nexusvar)
StartNexus.place(x=510,y=200,width=220,height=35)
StartNexus.select()#default make this option selected

StopatEnd = Tkinter.Checkbutton(rot,text="Stop Treadmill @ END",anchor=Tkinter.W,background="#C8C8C8")
StopatEnd.place(x=510,y=240,width=220,height=35)
StopatEnd.select()

StoponStop = Tkinter.Checkbutton(rot,text="Stop Treadmill on STOP",anchor=Tkinter.W,background="#C8C8C8")
StoponStop.place(x=510,y=280,width=220,height=35)
StoponStop.select()

#drop down menu for different control function
global funlist
funlist = Tkinter.StringVar(rot)
funlist.set("defaultcontrolwithstrides")

drplabel = Tkinter.Text(rot,background='#C8C8C8')
drplabel.place(x=225,y=455,width=150,height=20)
drplabel.insert(Tkinter.END,'Control Function')
drplabel.configure(state='disabled')
dropdown = Tkinter.OptionMenu(rot,funlist,"defaultcontrolwithstrides")
dropdown.place(x=225,y=475,width=160,height=25)


rot.protocol('WM_DELETE_WINDOW', ClosebyX)
rot.mainloop()
