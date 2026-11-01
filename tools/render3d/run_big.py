import json, base64, math, sys
from playwright.sync_api import sync_playwright
meshes=json.load(open('meshes.json'))
SEL={'wB':'Bishop_0','wP':'Pawn_0','wR':'Rook_0','wQ':'Queen_0','wK':'King_0','wN':'Knight_0',
     'bB':'Bishop.002_0','bP':'Pawn.008_0','bR':'Rook.002_0','bQ':'Queen.001_0','bK':'King.001_0','bN':'Knight.002_0'}
YAW={'N':float(sys.argv[1]) if len(sys.argv)>1 else 0.0}
elev=math.radians(22)
W=H=1000
import os
os.makedirs('big',exist_ok=True)
# common scale: king height projected
kb=meshes['King_0']; kh=(kb['bmax'][1]-kb['bmin'][1])
# unit -> ndc: height 1.72*cos(elev)+depth*sin(elev) ~ want king to fill 86% of height
ndc=1.0/ (kh*math.cos(elev)+0.8*math.sin(elev)) * 1.9
with sync_playwright() as p:
    b=p.chromium.launch(args=['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'])
    pg=b.new_page(viewport={'width':520,'height':520}); pg.goto('file://'+os.path.abspath('render.html'))
    for k,name in SEL.items():
        m=dict(meshes[name]); m['color']=[min(1,c*1.7) for c in m['color']] if k[0]=='b' else [min(1,c*1.12) for c in m['color']]; mn,mx=m['bmin'],m['bmax']
        cx=(mn[0]+mx[0])/2; cz=(mn[2]+mx[2])/2
        yaw=YAW['N'] if k[1]!='N' else (math.pi/2 if len(sys.argv)<3 else float(sys.argv[2]))
        o=dict(W=W,H=H,yaw=yaw,elev=elev,cx=cx,cy=mn[1],cz=cz,sx=ndc,sy=ndc,ox=0,oy=-0.93)
        url=pg.evaluate('([a,b])=>render(a,b)',[[m],o])
        open(f'big/{k}.png','wb').write(base64.b64decode(url.split(',')[1]))
    b.close()
print('ok')
