import pythoncom
import pyHook
import time

def Hook(q5,stopevent):
    hm = pyHook.HookManager()
    hm.KeyDown = hm.OnKeyboardEvent #sloppy method, maybe in future can find a cleaner way to implement this
    hm.HookKeyboard()
    while (not stopevent.is_set()):
        pythoncom.PumpWaitingMessages()
        if (len(hm.keypressed)>0):#
            if (hm.keypressed == 'Next'):
                q5.put(9999)
            elif(hm.keypressed == 'Prior'):
                q5.put(7777)
            elif(len(hm.keypressed)>1):
                q5.put(666)#some other weird button was pressed like Space and can't be converted to ascii code from a string
            else:
                q5.put(ord(hm.keypressed))#pass along the ascii code for the key pressed
        hm.keypressed = ''
##        time.sleep(0.1)#only scan every 100 ms
    hm.UnhookKeyboard()
    print "Keyboard unhooked..."


