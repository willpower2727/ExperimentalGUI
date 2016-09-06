#test script

import matplotlib
matplotlib.use('TkAgg')
##import matplotlib.pyplot as PLT
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2TkAgg
import Tkinter
##import time

root = Tkinter.Tk()
root.wm_title("GUI")
root.geometry('{}x{}'.format(700,500))

#start setting up the axes
global f #figure variable
f = Figure(figsize=(5,4),dpi=100)
global axe #plot
axe = f.add_subplot(111)
global canvas
canvas = FigureCanvasTkAgg(f, master=root)

def ClosebyX(): #what to do when closing the gui
	root.quit()
	root.destroy()

def startup(): #what to do when the gui is created
	global f
	global axe
	axe.plot(0,0,marker='x')
##	canvas = FigureCanvasTkAgg(f, master=root)
	canvas.show()
	canvas.get_tk_widget().place(x=0,y=50,width=500,height=400)

def addplot():
    global axe
    global canvas
    axe.plot(0.01,0.01,marker='x')
    canvas.draw()
    print('plotting extra marker')

fakebut = Tkinter.Button(root,command=startup())#fake button that is not visible or placed, but runs the startup script
startbut = Tkinter.Button(root,text='EXECUTE',command = addplot,bg='#FF4600')
startbut.place(x=0,y=475,width=50,height=25)
root.protocol('WM_DELETE_WINDOW', ClosebyX)
root.mainloop()

