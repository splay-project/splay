def getMill(str1):
    tmp = str1.split('.')
    frac = int(tmp[1])
    secToMill = int(tmp[0].split(':')[2]) * 1000000
    return round(float(secToMill + frac) / 1000.0, 1)

if __name__ == '__main__':
    leaves  = open('leaves', 'r')
    leavesT = open('leavesWithTimes', 'r')
    peerIds = []
    try:
        for line in leaves:
            iD = line.split()[0]
            peerIds.append( {iD: ''} )
        i = 0
        for line in leavesT:
            tmp = line.split()
            iD = tmp[0]
            leaveTime = tmp[1]
            peerIds[i][iD] = leaveTime
            i += 1
    finally:
        leaves.close()
        leavesT.close()
    outF = open('jitter.dat', 'w')
    allV = []
    try:
        for i in range(0, len(peerIds)):
            peer = peerIds[i]
            for key in peer:
                f = open('peerFile/' + key, 'r')
                lastTime = f.readline().split()[0]
                endTime = peer[key]
                jitter = abs(getMill(lastTime) - getMill(endTime))
                allV.append(jitter)
                outF.write(str(i + 1) + ' ' + str(jitter) + '\n')
        avg = 0.0
        for i in range(0, len(allV)): avg += allV[i]
        avg = avg / (len(allV) * 1.0)
        print 'Max: ' + str(max(allV)) + ', Min: ' + str(min(allV)) + ', Avg: ' + str(avg)
    finally:
        f.close()
        outF.close()
