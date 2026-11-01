import json, sys, numpy as np, base64, io
from PIL import Image
src=sys.argv[1]
g=json.load(open(src+'/scene.gltf')); buf=open(src+'/scene.bin','rb').read()
CT={5126:np.float32,5123:np.uint16,5125:np.uint32,5121:np.uint8}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}
def acc(i):
    a=g['accessors'][i]; bv=g['bufferViews'][a['bufferView']]
    dt=np.dtype(CT[a['componentType']]); n=NC[a['type']]
    off=bv.get('byteOffset',0)+a.get('byteOffset',0); stride=bv.get('byteStride',dt.itemsize*n)
    if stride==dt.itemsize*n:
        return np.frombuffer(buf,dt,a['count']*n,off).reshape(a['count'],n)
    raw=np.frombuffer(buf,np.uint8)
    return np.stack([np.frombuffer(buf,dt,n,off+k*stride) for k in range(a['count'])])
def local(n):
    if 'matrix' in n: return np.array(n['matrix']).reshape(4,4).T
    return np.eye(4)
world={}
def walk(i,P):
    W=P@local(g['nodes'][i]); world[i]=W
    for c in g['nodes'][i].get('children',[]): walk(c,W)
walk(g['scenes'][0]['nodes'][0],np.eye(4))
out=[]
for i,n in enumerate(g['nodes']):
    if 'mesh' not in n: continue
    p=g['meshes'][n['mesh']]['primitives'][0]
    pos=acc(p['attributes']['POSITION']).astype(float); uv=acc(p['attributes']['TEXCOORD_0']).astype(float); idx=acc(p['indices'])[:,0].astype(int)
    W=world[i]; pw=(W[:3,:3]@pos.T).T+W[:3,3]
    mat=g['materials'][p['material']]
    tex=mat['emissiveTexture']['index']
    out.append(dict(name=n['name'],mat=mat['name'],tex=tex,alpha=mat.get('alphaMode','OPAQUE'),a=mat['pbrMetallicRoughness']['baseColorFactor'][3],
        atex=mat['pbrMetallicRoughness'].get('baseColorTexture',{}).get('index'),
        pos=pw.round(4).flatten().tolist(),uv=uv.round(5).flatten().tolist(),idx=idx.tolist(),bmin=pw.min(0).tolist(),bmax=pw.max(0).tolist()))
    print(n['name'],mat['name'],mat.get('alphaMode'),len(pos),len(idx),np.round(pw.min(0),1),np.round(pw.max(0),1))
json.dump(out,open('parts.json','w'))
