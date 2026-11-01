import json, struct, numpy as np
g=json.load(open('scene.gltf')); buf=open('scene.bin','rb').read()
CT={5126:('f',4),5123:('H',2),5125:('I',4),5121:('B',1)}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}
def acc(i):
    a=g['accessors'][i]; bv=g['bufferViews'][a['bufferView']]
    fmt,sz=CT[a['componentType']]; n=NC[a['type']]
    off=bv.get('byteOffset',0)+a.get('byteOffset',0)
    stride=bv.get('byteStride',sz*n)
    out=np.zeros((a['count'],n))
    for k in range(a['count']):
        out[k]=struct.unpack_from('<'+fmt*n,buf,off+k*stride)
    return out
def local(n):
    if 'matrix' in n: return np.array(n['matrix']).reshape(4,4).T
    M=np.eye(4)
    t=n.get('translation',[0,0,0]); r=n.get('rotation',[0,0,0,1]); s=n.get('scale',[1,1,1])
    x,y,z,w=r
    R=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
    M[:3,:3]=R*np.array(s); M[:3,3]=t; return M
world={}
def walk(i,P):
    W=P@local(g['nodes'][i]); world[i]=W
    for c in g['nodes'][i].get('children',[]): walk(c,W)
walk(g['scenes'][0]['nodes'][0],np.eye(4))
meshes={}
for i,n in enumerate(g['nodes']):
    if 'mesh' in n:
        m=g['meshes'][n['mesh']]; p=m['primitives'][0]
        pos=acc(p['attributes']['POSITION']); nor=acc(p['attributes']['NORMAL']); idx=acc(p['indices'])[:,0].astype(int)
        W=world[i]; pw=(W[:3,:3]@pos.T).T+W[:3,3]
        nw=(np.linalg.inv(W[:3,:3]).T@nor.T).T; nw/=np.linalg.norm(nw,axis=1,keepdims=True)+1e-9
        mat=g['materials'][p['material']]
        meshes[n['name']]=dict(pos=pw.tolist(),nor=nw.tolist(),idx=idx.tolist(),color=mat['pbrMetallicRoughness']['baseColorFactor'][:3],mat=mat['name'],bmin=pw.min(0).tolist(),bmax=pw.max(0).tolist())
for k,v in meshes.items(): print(k,v['mat'],[round(x,2) for x in v['bmin']],[round(x,2) for x in v['bmax']])
json.dump(meshes,open('meshes.json','w'))
