import math

def generate_standing_thumbs_up():
    path = []
    # Realistic standing pose
    path.append("M 45,5")
    path.append("C 48,3 52,3 55,5")        # Top head
    path.append("C 57,8 57,14 55,17")      # Right head
    path.append("C 54,20 53,21 53,22")     # Right neck
    path.append("C 58,22 62,23 66,25")     # Right shoulder
    path.append("C 70,28 75,35 78,45")     # Right arm outer
    path.append("C 80,55 80,62 80,62")     # Right hand down
    path.append("C 77,64 75,62 74,60")     # Right hand tip
    path.append("C 73,55 71,45 68,40")     # Right arm inner
    path.append("C 66,45 66,50 66,55")     # Right torso
    path.append("C 66,65 66,75 65,90")     # Right leg outer
    path.append("C 64,96 59,96 58,90")     # Right foot
    path.append("C 57,80 55,70 53,60")     # Right leg inner
    path.append("C 51,55 49,55 47,60")     # Crotch
    path.append("C 45,70 43,80 42,90")     # Left leg inner
    path.append("C 41,96 36,96 35,90")     # Left foot
    path.append("C 34,75 34,65 34,55")     # Left leg outer
    path.append("C 34,50 34,45 32,40")     # Left torso
    path.append("C 29,45 27,55 26,60")     # Left arm inner
    path.append("C 25,62 23,64 20,62")     # Left hand tip
    path.append("C 20,62 20,55 22,45")     # Left arm outer
    path.append("C 25,35 30,28 34,25")     # Left arm outer up to shoulder
    path.append("C 38,23 42,22 47,22")     # Left shoulder
    path.append("C 47,21 46,20 45,17")     # Left neck
    path.append("C 43,14 43,8 45,5 Z")     # Left head
    return " ".join(path)

def generate_selfie_victory():
    path = []
    # Realistic selfie holding phone
    path.append("M 45,5")
    path.append("C 48,3 52,3 55,5")        # Top head
    path.append("C 57,8 57,14 55,17")      # Right head
    path.append("C 54,20 53,21 53,22")     # Right neck
    path.append("C 58,22 62,23 66,25")     # Right shoulder
    path.append("C 70,28 75,35 78,45")     # Right arm outer
    path.append("C 80,50 80,55 78,58")     # Right hand
    path.append("C 75,60 73,55 71,52")     # Right hand inner
    path.append("C 69,48 68,45 66,42")     # Right arm inner
    path.append("C 66,48 66,55 66,65")     # Right torso
    path.append("C 66,75 66,85 66,95")     # Right leg outer
    path.append("L 34,95")                 # Bottom horizontal line
    path.append("C 34,85 34,75 34,65")     # Left leg outer
    path.append("C 34,55 35,50 35,45")     # Left torso
    path.append("C 30,55 25,65 18,75")     # Left arm extending to camera
    path.append("C 15,80 5,80 5,75")       # Left hand holding phone
    path.append("C 8,65 15,50 25,35")      # Left arm outer
    path.append("C 28,30 31,27 34,25")     # Left arm back to shoulder
    path.append("C 38,23 42,22 47,22")     # Left shoulder
    path.append("C 47,21 46,20 45,17")     # Left neck
    path.append("C 43,14 43,8 45,5 Z")     # Left head
    return " ".join(path)

print("Thumbs Up:\\n" + generate_standing_thumbs_up())
print("Selfie:\\n" + generate_selfie_victory())
