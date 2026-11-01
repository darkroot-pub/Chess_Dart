import json, base64, io, math, os, sys
from PIL import Image
from playwright.sync_api import sync_playwright
TEX=['material_emissive','hair.texture_emissive','body.texture_emissive','bow_texture_emissive','clothes_textures_emissive','body.texture.alpha_baseColor']
parts=[p for p in json.load(open('parts.json')) if p['name']!='Object_4']
def durl(n):
    im=Image.open(f'../kindred/textures/{n}.png').convert('RGBA').resize((2048,2048) if 'hair' not in n else (2048,2048),Image.LANCZOS)
    b=io.BytesIO(); im.save(b,'PNG'); return 'data:image/png;base64,'+base64.b64encode(b.getvalue()).decode()
mode=sys.argv[1]
mn=[min(p['bmin'][i] for p in parts) for i in range(3)]; mx=[max(p['bmax'][i] for p in parts) for i in range(3)]
print(mn,mx)
cx=0.04; cz=-0.02; cy=(mn[1]+mx[1])/2
H=mx[1]-mn[1]
elev=math.radians(float(sys.argv[3]) if len(sys.argv)>3 else 4)
SS=2
with sync_playwright() as p:
    b=p.chromium.launch(args=['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'])
    pg=b.new_page(viewport={'width':300,'height':300}); pg.goto('file://'+os.path.abspath('r.html'))
    n=pg.evaluate('([u,p])=>setup(u,p)',[[durl(t) for t in TEX],parts]); print('parts',n)
    def shot(yaw,W,Hh):
        # fit: height H*1.06 (+) into Hh
        sy=2.0/(H*1.08)  # ndc per unit for full height
        sx=sy*Hh/W
        return pg.evaluate('o=>render(o)',dict(W=W*SS,H=Hh*SS,yaw=yaw,elev=elev,cx=cx,cy=cy,cz=cz,sx=sx,sy=sy,oy=0))
    W,Hh=(560,680)
    os.makedirs('f',exist_ok=True)
    if mode=='test':
        ims=[]
        for deg in [0,90,180,270]:
            u=shot(math.radians(deg),W,Hh); im=Image.open(io.BytesIO(base64.b64decode(u.split(',')[1]))).resize((W//2,Hh//2),Image.LANCZOS); ims.append(im)
        sheet=Image.new('RGBA',(W//2*4,Hh//2),(40,50,80,255))
        for i,im in enumerate(ims): sheet.alpha_composite(im,(i*W//2,0))
        sheet.save('test.png')
    else:
        N=int(sys.argv[2])
        for i in range(N):
            u=shot(math.pi+2*math.pi*i/N,W,Hh); im=Image.open(io.BytesIO(base64.b64decode(u.split(',')[1]))).resize((W,Hh),Image.LANCZOS)
            im.save(f'f/k{i:02d}.webp','WEBP',quality=84,method=6)
    b.close()
