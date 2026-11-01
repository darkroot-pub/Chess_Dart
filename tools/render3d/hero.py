import json, base64, math, os, sys
from playwright.sync_api import sync_playwright
meshes=json.load(open('meshes.json'))
yaw=float(sys.argv[1]); elev=math.radians(float(sys.argv[2])); out=sys.argv[3]
parts=[]
for k,m in meshes.items():
    m=dict(m); dark=('Dark' in m['mat']) or m['mat']=='Darks'
    m['color']=[min(1,c*(1.7 if dark else 1.12)) for c in m['color']]
    if m['mat']=='Lights': m['color']=[0.80,0.86,0.98]
    if m['mat']=='Darks': m['color']=[0.045,0.11,0.30]
    parts.append(m)
import numpy as np
allp=np.array([p for m in meshes.values() for p in m['pos']])
mn=allp.min(0); mx=allp.max(0); c=(mn+mx)/2
W,H=1100,760
# rotate corners to find extent
def ext(yaw,elev):
    xs=[];ys=[]
    for x in (mn[0],mx[0]):
        for y in (mn[1],mx[1]):
            for z in (mn[2],mx[2]):
                px,py,pz=x-c[0],y-c[1],z-c[2]
                rx=px*math.cos(yaw)+pz*math.sin(yaw); rz=-px*math.sin(yaw)+pz*math.cos(yaw)
                vy=py*math.cos(elev)-rz*math.sin(elev)
                xs.append(rx);ys.append(vy)
    return max(map(abs,xs)),max(map(abs,ys))
ex,ey=ext(yaw,elev)
sx=0.94/ex; sy=0.94/ey*(W/H)   # ndc per unit; y scaled for aspect
# keep uniform scale: sy = sx*(W/H)
s=min(0.94/ex,0.94/ey*(H/W))
o=dict(W=W,H=H,yaw=yaw,elev=elev,cx=float(c[0]),cy=float(c[1]),cz=float(c[2]),sx=s,sy=s*W/H,ox=0,oy=0)
with sync_playwright() as p:
    b=p.chromium.launch(args=['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'])
    pg=b.new_page(viewport={'width':1120,'height':780}); pg.goto('file://'+os.path.abspath('render.html'))
    url=pg.evaluate('([a,b])=>render(a,b)',[parts,o])
    open(out,'wb').write(base64.b64decode(url.split(',')[1])); b.close()
