from PIL import Image, ImageDraw, ImageFilter, ImageChops
import numpy as np, os
P='/tmp/claude-0/-home-claude/3d924760-20df-5fee-b4be-7cbfb0e0a507/scratchpad/proj/Chess_Dart/assets/images/'
def piece(n,h):
    im=Image.open(f'big/{n}.png').convert('RGBA'); im=im.crop(im.getchannel('A').getbbox())
    return im.resize((round(im.width*h/im.height),h),Image.LANCZOS)
def grad(w,h,c1,c2,angle=0.0):
    x=np.linspace(0,1,w)[None,:]; y=np.linspace(0,1,h)[:,None]
    t=np.clip(x*(1-angle)+y*angle,0,1)[...,None]
    a=np.array(c1)[None,None,:]; b=np.array(c2)[None,None,:]
    return Image.fromarray((a*(1-t)+b*t).astype('uint8'),'RGB')
def glow(img,cx,cy,r,color,alpha=0.55):
    w,h=img.size; yy,xx=np.mgrid[0:h,0:w]
    d=np.sqrt((xx-cx)**2+(yy-cy)**2)/r; m=np.clip(1-d,0,1)**2*alpha
    g=Image.new('RGB',img.size,color); mk=Image.fromarray((m*255).astype('uint8'),'L')
    return Image.composite(g,img,mk)
def put(img,p,cx,base,shadow=True):
    x=int(cx-p.width/2); y=int(base-p.height)
    if shadow:
        sh=Image.new('L',img.size,0); d=ImageDraw.Draw(sh)
        rw=p.width*0.55; d.ellipse((cx-rw,base-p.height*0.045,cx+rw,base+p.height*0.05),fill=150)
        sh=sh.filter(ImageFilter.GaussianBlur(p.height*0.03))
        img.paste(Image.new('RGB',img.size,(5,10,40)),(0,0),sh)
    img.paste(p,(x,y),p)
def floor(img,y,color=(255,255,255),alpha=22):
    ov=Image.new('RGBA',img.size,(0,0,0,0)); d=ImageDraw.Draw(ov)
    d.rectangle((0,y,img.width,img.height),fill=color+(alpha,))
    img.paste(ov,(0,0),ov)
def save(img,name): img.save(P+name,quality=88,optimize=True); print(name,os.path.getsize(P+name)//1024,'KB')

# 1 home hero
W,H=1080,460
im=grad(W,H,(10,24,78),(37,99,235),0.25); im=glow(im,820,230,460,(120,170,255),0.65)
floor(im,400)
put(im,piece('wP',150),560,412); put(im,piece('wQ',330),680,420)
put(im,piece('wK',390),835,425); put(im,piece('bN',270),975,420); put(im,piece('bP',140),1045,412)
save(im,'banner_play.jpg')
# 2 vs AI
W,H=1080,420
im=grad(W,H,(30,27,90),(99,102,241),0.2); im=glow(im,860,210,420,(165,170,255),0.6); floor(im,370)
put(im,piece('bN',340),860,380); put(im,piece('wP',150),700,372); put(im,piece('bB',230),1000,376)
save(im,'banner_ai.jpg')
# 3 online
im=grad(W,H,(7,60,90),(14,165,233),0.2); im=glow(im,830,200,400,(150,230,255),0.55); floor(im,370)
put(im,piece('wK',330),700,380); put(im,piece('bK',330),980,380)
earth=Image.open(P+'earth.png').convert('RGBA'); earth.thumbnail((250,250)); 
im.paste(earth,(715,40),earth)
save(im,'banner_online.jpg')
# 4 puzzles
im=grad(W,H,(6,78,59),(34,197,94),0.2); im=glow(im,860,200,420,(170,255,200),0.55); floor(im,370)
put(im,piece('wR',320),830,380); put(im,piece('bP',160),700,372); put(im,piece('wN',230),990,376)
save(im,'banner_puzzles.jpg')
# 5 learn
im=grad(W,H,(120,53,15),(245,158,11),0.2); im=glow(im,860,200,420,(255,225,160),0.55); floor(im,370)
put(im,piece('wB',320),840,380); put(im,piece('bB',250),1000,376); put(im,piece('wP',140),700,372)
save(im,'banner_learn.jpg')
# 6 auth header (taller)
W,H=1080,560
im=grad(W,H,(10,24,78),(37,99,235),0.55); im=glow(im,540,260,560,(130,175,255),0.6); floor(im,500)
put(im,piece('wQ',300),330,510); put(im,piece('wK',420),540,520); put(im,piece('bK',330),770,510); put(im,piece('wP',150),170,500); put(im,piece('bP',150),920,500)
save(im,'banner_auth.jpg')
