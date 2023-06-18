import sys
import math

def findNeighbours(D,R,grid,j):

    neighb = []

    #Get the current column and row of the node
    row = j/D
    col = j%D

    for x in range(D):
        for y in range(D):
            #Calculate euclidean distance
            dist = math.sqrt( abs((x-row)**2) + abs((y-col)**2))
            #Check if distance is within given range R 
            #If yes append the current node of the grid x y as a neighbour
            if (R >= dist) and (dist>0):
                neighb.append(grid[x][y])
    
    return neighb

def genTopologyFile(D,R):
    grid = [[x + y*D for x in range(D)] for y in range(D)]

    #Create file but truncate it anyway to prevent overwrites
    fileNo = str(D)
    print("Generated file name: topology_"+fileNo+".txt")
    file = open("topology_"+fileNo+".txt",'w')
    file.truncate()

    for j in range(D**2):
        neighbours = findNeighbours(D,R,grid,j)

        for i in range(len(neighbours)):
            file.write(str(grid[j/D][j%D]) + " " + str(neighbours[i]) + " -50.0\n")      

    file.close()


if __name__ == "__main__":
    
        print("Will create grid "+sys.argv[1]+"x"+sys.argv[1] +" with neighbourhood range " + sys.argv[2])
        D = int(sys.argv[1])
        R = float(sys.argv[2])
        genTopologyFile(D,R)