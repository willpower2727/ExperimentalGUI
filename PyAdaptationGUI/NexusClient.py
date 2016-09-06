import subprocess
import time
import socket
import sys

def NexusClient(root,q1,stopevent):

		cpps = subprocess.Popen('"C:/Users/Public/Documents/V2PMainPC/Release/PyAdaptVicon2Python.exe"',shell=False)
		time.sleep(3)#wait for server to initialize

		HOST = 'localhost'#IP address of CPP server
		PORT = 50008
		s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		print 'Socket created'
		print 'Socket now connecting'
		s.connect((HOST,PORT))
		s.send('1')#send initial request for data
		while (not stopevent.is_set()):
			data = s.recv(50)#receive the initial message
			data3 = data[:3]#get first 3 letters
##			print('data3: ',data3)
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
				print("WARNING! TCP out of synch this frame...")
##				break
			if not data: break
			s.send('b')
		s.close()
		print('Nexus communications terminated.')
		cpps.kill()
		print('CPP server killed')
