import math
import sys

def render_path_ascii(path_str):
    tokens = path_str.split()
    pts = []
    curr = (0,0)
    for i in range(len(tokens)):
        if tokens[i] == 'M':
            curr = (float(tokens[i+1]), float(tokens[i+2].replace(',','')))
            pts.append(curr)
        elif tokens[i] == 'C':
            # just sample a few points along the bezier
            p1 = curr
            p2 = (float(tokens[i+1]), float(tokens[i+2].replace(',','')))
            p3 = (float(tokens[i+3]), float(tokens[i+4].replace(',','')))
            p4 = (float(tokens[i+5]), float(tokens[i+6].replace(',','')))
            
            for t_step in range(1, 6):
                t = t_step / 5.0
                x = (1-t)**3 * p1[0] + 3*(1-t)**2 * t * p2[0] + 3*(1-t) * t**2 * p3[0] + t**3 * p4[0]
                y = (1-t)**3 * p1[1] + 3*(1-t)**2 * t * p2[1] + 3*(1-t) * t**2 * p3[1] + t**3 * p4[1]
                pts.append((x,y))
            curr = p4
        elif tokens[i] == 'L':
            curr = (float(tokens[i+1]), float(tokens[i+2].replace(',','')))
            pts.append(curr)
            
    grid = [[' ' for _ in range(80)] for _ in range(50)]
    for p in pts:
        x = int(p[0] * 0.8)
        y = int(p[1] * 0.5)
        if 0 <= x < 80 and 0 <= y < 50:
            grid[y][x] = '#'
            
    print('\n'.join(''.join(row) for row in grid))

path1 = "M 45 5 C 48 3 52 3 55 5 C 57 8 57 14 55 17 C 54 20 53 21 53 22 C 58 22 62 23 66 25 C 70 28 75 35 78 45 C 80 55 80 62 80 62 C 77 64 75 62 74 60 C 73 55 71 45 68 40 C 66 45 66 50 66 55 C 66 65 66 75 65 90 C 64 96 59 96 58 90 C 57 80 55 70 53 60 C 51 55 49 55 47 60 C 45 70 43 80 42 90 C 41 96 36 96 35 90 C 34 75 34 65 34 55 C 34 50 34 45 32 40 C 29 45 27 55 26 60 C 25 62 23 64 20 62 C 20 62 20 55 22 45 C 25 35 30 28 34 25 C 38 23 42 22 47 22 C 47 21 46 20 45 17 C 43 14 43 8 45 5 Z"
print("THUMBS UP:")
render_path_ascii(path1)

path2 = "M 45 5 C 48 3 52 3 55 5 C 57 8 57 14 55 17 C 54 20 53 21 53 22 C 58 22 62 23 66 25 C 70 28 75 35 78 45 C 80 50 80 55 78 58 C 75 60 73 55 71 52 C 69 48 68 45 66 42 C 66 48 66 55 66 65 C 66 75 66 85 66 95 L 34 95 C 34 85 34 75 34 65 C 34 55 35 50 35 45 C 30 55 25 65 18 75 C 15 80 5 80 5 75 C 8 65 15 50 25 35 C 28 30 31 27 34 25 C 38 23 42 22 47 22 C 47 21 46 20 45 17 C 43 14 43 8 45 5 Z"
print("\nSELFIE:")
render_path_ascii(path2)
