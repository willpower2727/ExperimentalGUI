import pythoncom
import pyHook
import time

def Hook(q5,stopevent):
##    currentkey = ''
##    lastkey = ''
    hm = pyHook.HookManager()
    hm.KeyDown = hm.OnKeyboardEvent #sloppy method, maybe in future can find a cleaner way to implement this
    hm.HookKeyboard()
    while (not stopevent.is_set()):
        pythoncom.PumpWaitingMessages()
##        currentkey = hm.keypressed
        if (len(hm.keypressed)>0):# & (currentkey != lastkey):
            print 'KeyPressed: ', hm.keypressed
            q5.put(hm.keypressed)
            print 'Keyevent placed in q5'
        hm.keypressed = ''
##        time.sleep(0.1)#only scan every 100 ms
    hm.UnhookKeyboard()
    print "Keyboard unhooked..."


