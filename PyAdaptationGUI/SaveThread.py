import csv
import time
import numpy
import ntpath

def save(savestring,q2,treadsave,q4,velL,velR,profilename,stopevent,inclineang):

		mst = time.time()
		mst2 = int(round(mst))

		mststring = str(mst2)+'_'+ntpath.basename(profilename)[:-4]+'_PyGUI.txt'
		print("Data File created named: ")
		print(mststring)
		path = "C:\Users\BioE\Documents\MATLAB\ExperimentalGUI\PyAdaptationGUI\DataFiles\\"
##		print(path+mststring)
		filename = path+mststring
		fileout = open(filename,'w+')
		csvw = csv.writer(fileout)
		velLw = [item for sublist in velL for item in sublist]#convert shallow list to list for writing
		velRw = [item for sublist in velR for item in sublist]
		csvw.writerow(['Left Belt Velocity Profile:'])
		csvw.writerow(velLw)
		csvw.writerow(['Right Belt Velocity Profile:'])
		csvw.writerow(velRw)
		csvw.writerow(['Incline Angle'])
		csvw.writerow([inclineang])
		csvw.writerow(['FrameNumber','Rfz','Lfz','RHS','LHS','RTO','LTO','Pause','RBSsent','LBSsent','RBSread','LBSread','incang_read'])#write the header
		fileout.close()
		
		fileout = open(filename,'a')
		csvw = csv.writer(fileout)
		while (not stopevent.is_set()):
                    nex = q2.get()
		    try:
			    tread2 = q4.get(False)
		    except:
			    tread2 = ['nan','nan','nan','nan','nan']
		    savestr = nex+tread2
		    csvw.writerow(savestr)
		fileout.close() 
		print('Saving complete.')
