##import sys
##import matplotlib
##matplotlib.use('TkAgg')
##from matplotlib.figure import Figure
##from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2TkAgg
##import scipy.io
##import tkFileDialog
##import numpy
import mtTkinter as Tkinter #special threadsafe version of Tkinter module, required for message windows. You can use regular Tkinter if needed but remove message window code that asks if Nexus is recording
##import time
##import threading
##import Queue
##import struct
##import array
##import math
##import os
##import ntpath
##import ParseRoot
##import StrideCounter
##import NexusClient
##import SaveThread
##import BertecComm
##import KeyHook


root = Tkinter.Tk()
root.wm_title("KillmePlz")
##root.geometry('{}x{}'.format(300,300))

##global stopevent #how to signal stopping from GUI
##stopevent = threading.Event()
####
##global pauseevent #used to signal a pause
##pauseevent = threading.Event()

#start setting up the plotting axis
##global f #figure variable
##f = Figure(figsize=(7,5),dpi=100)
##global axe #plot
##axe = f.add_subplot(111)
##global canvas
##canvas = FigureCanvasTkAgg(f, master=root)

##global nexusvar#variable flag that indicates whether or not to start Nexus on startup
nexusvar = Tkinter.IntVar(root)
##
##global stopatendvar #whether or not to stop the treadmill at the end of a profile, default is yes stop
##stopatendvar = Tkinter.IntVar()

def ClosebyX():
    root.destroy()

closebutton = Tkinter.Button(root,text='Quit',command=ClosebyX)
closebutton.pack()

##nexusvar = Tkinter.IntVar(master=closebutton)

root.protocol('WM_DELETE_WINDOW', ClosebyX)
root.mainloop()

