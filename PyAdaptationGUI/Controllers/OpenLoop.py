def ControlLoop(CARGS):
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
    elif (prevvelR != CARGS["velR"][CARGS["rstrides"]]) | (prevvelL != CARGS["velL"][CARGS["lstrides"]]):#only send a new command if it is different from the old one
        speedlist = [int(1000*CARGS["velR"][CARGS["rstrides"]]),int(1000*CARGS["velL"][CARGS["lstrides"]]),1000,1000,CARGS["inclineang"]]
        CARGS["q3"].put(speedlist)
        prevvelR = CARGS["velR"][CARGS["rstrides"]]
        prevvelL = CARGS["velL"][CARGS["lstrides"]]

    return [prevvelL,prevvelR,0]

    

    



