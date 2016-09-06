import pythoncom
import pyHook
##import sys

global latestkey #how to tell what the latest key press was
latestkey = ''

def OnKeyboardEvent(event):
    global latestkey
##    print 'MessageName:',event.MessageName
##    if (not stopevent.is_set()):
##    print 'Key:',event.Key
##    print 'Ascii:',chr(event.Ascii)
    latestkey = event.Key
    print 'KeyHook says:', latestkey

def starthook(q5,stopevent):
    global latestkey
    hm = pyHook.HookManager()
    hm.KeyDown = OnKeyboardEvent
    hm.HookKeyboard()
    while (not stopevent.is_set()):
        if (len(latestkey)>0):
            q5.put(latestkey)
            latestkey = ''
        pythoncom.PumpWaitingMessages()
    hm.UnhookKeyboard()
    print "Keyboard unhooked..."


