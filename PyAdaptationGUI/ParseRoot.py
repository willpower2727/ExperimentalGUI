import struct

def ParseRoot(root):#the purpose of this function is to make sure that marker data is used correctly since they can arrive in different order, depending on the order the models are listed in Nexus

		tempdat = root.split(',')
##		print tempdat
		del tempdat[-1]#the last element is an empty string ""
		data = {}#create dictionary
                try:
                    data["FN"] = int(tempdat[0])#frame number
                    data["Rz"] = float(tempdat[4])#right forceplate Z component
                    data["Lz"] = float(tempdat[2])#left forceplate Z comp.
                    data["DeviceCount"] = float(tempdat[5])# #of devices besides forceplates
                    for x in range(6,6+2*int(data["DeviceCount"])-1,2):  #assumes one value per device for now...
                            temp = tempdat[x]
                            data[temp] = [tempdat[x+1]]
                    for z in range(6+2*int(data["DeviceCount"]),len(tempdat),4):
                            temp = tempdat[z]
            #		print temp
                            data[temp] = [tempdat[z+1],tempdat[z+2],tempdat[z+3]]
        
                except:
                    print('Warning!!!TCP out of synch, data incorrectly parsed.')
		    data["FN"] = 0
		    data["Rz"] = 0
		    data["Lz"] = 0
		    data["DeviceCount"] = 0
		    for x in range(6,6+2*int(data["DeviceCount"])-1,2):
                            temp = tempdat[x]
                            data[temp] = [tempdat[x+1]]
                            #place marker data into dictionary
                    for z in range(6+2*int(data["DeviceCount"]),len(tempdat),4):
                            temp = tempdat[z]
                            data[temp] = [tempdat[z+1],tempdat[z+2],tempdat[z+3]]
  
	#	print data
		return data
