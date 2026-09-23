"""Bake approved sprite studies into the game's existing 64px atlas contract.

This import step extracts outlined sprite islands, discards sheet backgrounds,
aligns feet and records shoulder pivots. Source artwork is never overwritten.
Run with Pillow and numpy. Outputs live separately from the older authored art.
"""
from pathlib import Path
from collections import deque
import json
import re
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'output/monkey-animation-prototype/locked-design-pack'
OUT = ROOT / 'assets/monkeys/locked'
REVIEW = ROOT / 'output/monkey-animation-prototype/integration'
SPECIES = ['macaque', 'capuchin', 'gorilla', 'orangutan', 'gibbon']
HEIGHTS = [46, 44, 50, 50, 46]
SHEETS = {
    'approved': ('approved-design.png', [0,168,325,480,634,785,940,1091,1250,1410,1536], [0,200,389,577,776,1024]),
    'move': ('locomotion.png', [0,150,275,394,508,640,765,890,1010,1140,1265,1385,1536], [0,208,389,580,777,1024]),
    'action': ('traversal-reactions.png', [0,150,285,425,565,700,830,974,1110,1270,1400,1536], [0,208,387,582,783,1024]),
    'body': ('swing-components/swing-bodies.png', [150,450,780,1120,1450], [0,211,388,579,775,1024]),
    'arm': ('swing-components/stretch-arms.png', [0,542,1013,1536], [0,207,389,581,782,1024]),
}

def components(mask):
    seen = np.zeros(mask.shape, bool)
    result = []
    h,w = mask.shape
    for y,x in zip(*np.where(mask)):
        if seen[y,x]: continue
        q = deque([(int(x),int(y))]); seen[y,x] = True; pts=[]
        while q:
            xx,yy=q.popleft(); pts.append((xx,yy))
            for nx,ny in ((xx-1,yy),(xx+1,yy),(xx,yy-1),(xx,yy+1)):
                if 0<=nx<w and 0<=ny<h and mask[ny,nx] and not seen[ny,nx]:
                    seen[ny,nx]=True; q.append((nx,ny))
        result.append(pts)
    return result

def isolate(image):
    rgb=np.asarray(image.convert('RGB')).astype(float)
    light=np.asarray(image.convert('L')).astype(float)
    blurred=np.asarray(image.convert('L').filter(ImageFilter.GaussianBlur(5))).astype(float)
    # Fit the smooth painted sheet background from its border; unlike a
    # darkness threshold this retains bright fur and dark chimp limbs alike.
    h,w=light.shape
    yy,xx=np.mgrid[-1:1:complex(h),-1:1:complex(w)]
    terms=np.stack([np.ones_like(xx),xx,yy,xx*yy,xx*xx,yy*yy],axis=-1)
    border=(abs(xx)>.94)|(abs(yy)>.94)
    fit=np.linalg.lstsq(terms[border],rgb[border],rcond=None)[0]
    estimate=terms@fit
    delta=np.sqrt(np.mean((rgb-estimate)**2,axis=2))
    edges=(delta>22)|((rgb.max(axis=2)<105)&(blurred-light>5))
    wall=Image.fromarray((edges*255).astype('uint8')).filter(ImageFilter.MaxFilter(5))
    wall=np.asarray(wall)>0
    # Fill enclosed regions. The largest outlined island is the character.
    h,w=wall.shape
    outside=np.zeros_like(wall); q=deque()
    for x in range(w):
        for y in (0,h-1):
            if not wall[y,x]: outside[y,x]=True; q.append((x,y))
    for y in range(h):
        for x in (0,w-1):
            if not wall[y,x]: outside[y,x]=True; q.append((x,y))
    while q:
        x,y=q.popleft()
        for nx,ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if 0<=nx<w and 0<=ny<h and not wall[ny,nx] and not outside[ny,nx]:
                outside[ny,nx]=True;q.append((nx,ny))
    islands=components(~outside)
    if not islands: raise ValueError('No sprite contour found')
    island=max(islands,key=len)
    alpha=np.zeros((h,w),np.uint8)
    for x,y in island: alpha[y,x]=255
    alpha=Image.fromarray(alpha).filter(ImageFilter.MinFilter(5))
    result=image.convert('RGBA');result.putalpha(alpha)
    return result.crop(result.getbbox())

def main():
    OUT.mkdir(parents=True,exist_ok=True); REVIEW.mkdir(parents=True,exist_ok=True)
    sources={k:Image.open(SRC/v[0]).convert('RGB') for k,v in SHEETS.items()}
    cache={}
    def get(key,row,col):
        token=(key,row,col)
        if token not in cache:
            _,xs,ys=SHEETS[key]
            cache[token]=isolate(sources[key].crop((xs[col],ys[row],xs[col+1],ys[row+1])))
        return cache[token].copy()
    poses=dict((name,int(idx)) for name,idx in re.findall(r'&"([a-z]+_?\d*|blink)": (\d+)',(ROOT/'scripts/player/MonkeyFrames.gd').read_text().split('const ANIMS')[0]))
    def source(pose):
        kind,_,n=pose.partition('_'); i=int(n or 0)
        if kind=='idle': return 'move',i
        if kind=='blink': return 'move',2
        if kind=='run': return 'move',8+(i//2)%4
        if kind=='jump': return 'action',[0,1,2][i]
        if kind=='fall': return 'action',2
        if kind=='land': return 'action',[3,3,0][i]
        if kind=='climb': return 'action',[4,5,6,5,4,5][i]
        if kind=='swing': return 'body',[0,1,2,3][i]
        if kind in ('punch','slap','kick'): return 'body',0
        if kind=='dash': return 'move',8+i
        if kind=='roll': return 'approved',1+(i//2)%4
        if kind=='stun': return 'action',7+i
        if kind in ('wave','cheer'): return 'move',i%4
        return 'approved',0
    review=Image.new('RGBA',(64*12,64*5),(34,58,66,255))
    details={}
    for row,species in enumerate(SPECIES):
        folder=OUT/species;folder.mkdir(exist_ok=True)
        atlas=Image.new('RGBA',(512,576));pivots={}
        for pose,index in poses.items():
            key,col=source(pose); cut=get(key,row,col)
            h=HEIGHTS[row]
            if pose.startswith('roll'): h=round(h*.76)
            if pose.startswith('land'): h=round(h*.83)
            factor=min(h/cut.height,60/cut.width)
            cut=cut.resize((max(1,round(cut.width*factor)),max(1,round(cut.height*factor))),Image.Resampling.NEAREST)
            x=(64-cut.width)//2;y=62-cut.height
            atlas.alpha_composite(cut,((index%8)*64+x,(index//8)*64+y))
            # Local art coordinates before the sprite's 2x world scale.
            shoulder=[x+round(cut.width*.29)-32,y+round(cut.height*.40)-64]
            pivots[pose]=shoulder
        atlas.save(folder/'atlas.png')
        # Full approved silhouette supplies a portrait consistent with the model.
        face=get('approved',row,0);face=face.crop((int(face.width*.24),0,face.width,int(face.height*.58)))
        face.thumbnail((36,36),Image.Resampling.NEAREST)
        portrait=Image.new('RGBA',(40,40));portrait.alpha_composite(face,((40-face.width)//2,(40-face.height)//2));portrait.save(folder/'portrait.png')
        for i in range(3):
            arm=get('arm',row,i)
            arm=arm.resize((128,max(8,round(arm.height*128/arm.width))),Image.Resampling.NEAREST)
            arm.save(folder/('arm_%s.png'%['reach','grip','release'][i]))
        details[species]={'pivots':pivots,'height':HEIGHTS[row]}
        samples=['idle_0','run_0','run_2','jump_1','roll_0','roll_2','swing_0','swing_1','punch_2','stun_1']
        for c,pose in enumerate(samples):
            at=poses[pose];review.alpha_composite(atlas.crop(((at%8)*64,(at//8)*64,(at%8+1)*64,(at//8+1)*64)),(c*64,row*64))
        for i in range(2):
            arm=Image.open(folder/('arm_%s.png'%['reach','grip'][i]));arm.thumbnail((62,62),Image.Resampling.NEAREST)
            review.alpha_composite(arm,(640+i*64,row*64+20))
    (OUT/'rig.json').write_text(json.dumps(details,indent=2))
    review.resize((1536,640),Image.Resampling.NEAREST).save(REVIEW/'import-review.png')
    print('Baked 5 locked character atlases, portraits, 15 arm textures and shoulder pivots.')

if __name__=='__main__': main()
