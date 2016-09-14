def ControlLoop(CARGS):

    keyp = CARGS["keypressed"]
    prevvelR = CARGS["prevvelR"]
    prevvelL = CARGS["prevvelL"]
    #determine if speeds need to be sent
    if (CARGS["lstrides"] >= CARGS["maxstridecount"]) | (CARGS["rstrides"] >= CARGS["maxstridecount"]):
        CARGS["stopevent"].set()
    elif CARGS["pauseevent"].is_set(): #check to see if pause button is pressed
        if (prevvelR != 0) & (prevvelL != 0):
            speedlist = [0,0,1000,1000,CARGS["inclineang"]]
            CARGS["q3"].put(speedlist)
        prevvelR = 0
        prevvelL = 0
    elif (CARGS["isnan"](CARGS["velR"][CARGS["rstrides"]])) or (CARGS["isnan"](CARGS["velL"][CARGS["lstrides"]])): #alter speeds based on key press, note this is regardless of which leg has nan in profile
        if (keyp == 9999): #Next button 
            speedlist = [int(1000*(prevvelR+CARGS["sign"](1-prevvelR)*0.1)),int(1000*(prevvelL+CARGS["sign"](1-prevvelL)*0.1)),1000,1000,CARGS["inclineang"]]
            CARGS["q3"].put(speedlist)
            prevvelR = prevvelR+CARGS["sign"](1-prevvelR)*0.1
            prevvelL = prevvelL+CARGS["sign"](1-prevvelL)*0.1
        elif (keyp == 7777): #Prior button
            speedlist = [int(1000*(prevvelR-CARGS["sign"](1-prevvelR)*0.1)),int(1000*(prevvelL-CARGS["sign"](1-prevvelL)*0.1)),1000,1000,CARGS["inclineang"]]
            CARGS["q3"].put(speedlist)
            prevvelR = prevvelR-CARGS["sign"](1-prevvelR)*0.1
            prevvelL = prevvelL-CARGS["sign"](1-prevvelL)*0.1
    elif (prevvelR != CARGS["velR"][CARGS["rstrides"]]) or (prevvelL != CARGS["velL"][CARGS["lstrides"]]):#only send a new command if it is different from the old one or a key was pressed
            speedlist = [int(1000*CARGS["velR"][CARGS["rstrides"]]),int(1000*CARGS["velL"][CARGS["lstrides"]]),1000,1000,CARGS["inclineang"]]
            CARGS["q3"].put(speedlist)
            prevvelR = CARGS["velR"][CARGS["rstrides"]]
            prevvelL = CARGS["velL"][CARGS["lstrides"]]

    return [prevvelL,prevvelR]

    

    



