"""Author and bake Primate Rush's three-quarter-view pixel characters.

Run: python tools/art/monkeys.py
Heads and torsos are species-specific pixel grids. Poses place those drawings
on a small integer rig; limbs have clustered light/shadow and outlined digits.
No random pixels, antialiasing, image generation, or external source artwork.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageChops
import json
import math

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "monkeys"
REVIEW = ROOT / "output" / "art-direction" / "monkeys"
SIZE = 64
SPECIES = ("macaque", "gorilla", "gibbon", "orangutan", "capuchin")

# . transparent; o ink; q deepest fur; d fur shade; f fur; h fur light;
# H fur glint; s skin shade; m skin; L skin light; e eye white; p pupil;
# n nose/mouth; b belly shade; B belly; C chest highlight.
HEADS = {
"macaque": [
".........ff..f..........",
"........fhhffhf.........",
"......ffhHHhhfff........",
".....fhhhhhffffff.......",
"....fhhfffmmmmffff......",
"...fhhffmLLLLLmmfff.....",
"..fffffmLLLLLLLmmff.....",
".ffmmffmLLmmmLLLmmf.....",
"fhLmmffmLeepmLeepmfmm...",
"fLmsmffmLeppmLeppmfsmf..",
"fmssmffmLeppmLeppmfsmf..",
".fmmdffmLmmmLLmmmLmmf...",
"..fffdfmLLLLLLLmmmLmf...",
"...fddfmLLLmmnnmmLmf...",
"...fddfmLLLmmnnmmLmf...",
"....fdfmmLLLmmmmLLmf....",
"....fdfmmLnnmmmmnmmf....",
".....fdmmLLnnnnnmmf.....",
"......fdmmLLLLmmmsf.....",
".......fdmmmmmsssf......",
"........fddffffdf.......",
".........fddfff.........",
],
"gorilla": [
"..........fffff.............",
"........ffhhhhfff...........",
"......ffhHHhhhhfff..........",
".....fhhhhffffffddf.........",
"....fhhhffffffffdddf........",
"...fhhffffmmmmfffdddf.......",
"..fhhfffmmLLLLLmmfdddf......",
"..fhffmLLLLLLLLLmmfddf......",
".fffffmmnnnmmmnnnmmffff.....",
"ffmmffmnnepmmnnepmmfmmff....",
"fmssffmmmeppmmeeppmmfssmf...",
"fmssffmmmppmmmeppmmmfsmmf...",
".fmdffmLLLLmmmmLLLLmmfmmf...",
"..ffdffmLLmmnnnnmmLmmff....",
"..fddffmLmmnnnnnnmmLmdf....",
"..fdddffmmmnnmmnnmmmmddf....",
"...fdddmmLLLLLLLLLmmddf.....",
"...fdddmmLLLnnnnLLmmddf.....",
"....fddmmLLnnmmnnLmmddf.....",
".....fddmmmLLLLLmmmddf......",
"......fdddmmmmmmmdddf.......",
".......fddddddddddf.........",
".........ffffffff...........",
],
"gibbon": [
"..........h............",
".........hHh...........",
"........hHhhf..........",
"......hhHHhhfff........",
".....hHHhhhhffff.......",
"....hHhmmmmmmfff.......",
"...hHhmssssssmmff......",
"..hHhmssLLLLssmmff.....",
"..hhmssLLssLLssmmf.....",
".ffhmssLeepLeepmmff....",
"fmfhmssLeppLeppmfmf....",
"fmfhmssLeppLeppmfsmf...",
".ffhmssLLmLLmLLmmff....",
"..fhmssLLLLnnLLmmf.....",
"..fhmssLLLnnnLLmmf.....",
"...fhmssLLmmmmLmmf.....",
"...fhmssLLnnnnLmmf.....",
"....fhmssLLLLLmmf......",
".....fhmmssssmmf.......",
"......fhhmmmmff........",
".......fffffff.........",
],
"orangutan": [
"..........hh..h...............",
".........hHHhhHh..............",
"........hHHHHhhff.............",
"......hhHHhhhhhffff............",
".....hHHhhhhfffffff...........",
"....hHHhhfffmmmmfffff..........",
"...hhhhffmmmLLLLmmmfff.........",
"..hhfffmmLLmmmmLLmmffff........",
".hhffssfmLeepmmLeepmfssff......",
"hhfsLLssmLeppmmLeppmssLLsff....",
"hfsLLLssmLeppmmLeppmssLLLsf....",
"hfsLLLssmLLmmLLLmmLmmssLLsf....",
"hfsLLsssmLLLmmnnmmLLmsssLsf....",
"hfsLLsssmLLmmnnnnmmLmssLLsf....",
".fsLssssmLLLmmnnmmLLmssssf.....",
".ffsssssmmLLLLLLLLLmmsssff.....",
"..ffssssmmLnnmmmmnnLmmssff.....",
"...ffsssmmLLnnnnnnLLmssff......",
"....ffssmmmLLLLLLLmmssff.......",
".....ffdddmmsssssmdddff........",
"......ffdhfffffffhddff.........",
".......fdhffhffhffddf..........",
"........fdfhfdfhddff...........",
".........ffdfdfdff.............",
],
"capuchin": [
".........ffff..........",
".......ffhhhhff........",
"......fhhHHhhfff.......",
".....fhhhffffddff......",
"....fhhffffffdddff.....",
"...ffmmmmffmmmmddff....",
"..ffmLLLLmmLLLLmddf....",
".fffmLLLLLLLLLLLmdff...",
"ffmmfmLeepmLeepLmfmmf..",
"fLmmfmLeppmLeppLmfsmf..",
"fmssfmLeppmLeppLmfsmf..",
".fmmfmLLmmLLmmLLmmff...",
"..fffmLLLLLLLmmmLmf....",
"...fmmLLLmmnnmmLLmf....",
"...fmmLLLLmmnmmLLmf....",
"....fmmLLnmmmmnLmmf....",
"....fmmLLLnnnnLLmsf....",
".....fmmLLLLLLLmsf.....",
"......fmmmLLmmssf......",
".......fmmmssssf.......",
"........fffffff........",
],
}

BODIES = {
"macaque": [
".....hhhhhff......",
"...hhHHhhhffff....",
"..hhhhhfffffddf...",
".hhfffBBBBBfdddf..",
"hhfffBCCBBBFdddf..",
"hfffBCCCCBBBFdddf.",
"hfffBCCCCBBBFdddf.",
"hfffBCCCCCBBFdddf.",
"hfffBCCCCBBBFdddf.",
"hfffBCCCBBBBFdddf.",
".hffBBBBBBBbfdddf.",
".hfffBBBBBbbfdddf.",
"..hfffBbbbbfdddf..",
"..fhfffbbbffdddf..",
"...fhffffffdddf...",
"...fffffffddddf...",
"....ffddddddff....",
],
"gorilla": [
"......hhhhhhffff.........",
"...hhhHHhhhhhhfffff......",
"..hhHHHhhhhhhhhhfffff....",
".hhHHhhhhhhhhhhhffffdf...",
"hhHhhfffCCCCCCfffddddf...",
"hHhhffCCCCCBBBBBffdddf...",
"hhhhfCCCCCCBBBBBBfddddf..",
"hhhfCCCCCCBBBBBBBfddddf..",
"hhhfCCCCCCBBBBBBBfddddf..",
"hhhfCCCCCCBBBBBBbfddddf..",
"hhhfCCCCCCBBBBBbbfddddf..",
".hhfCCCCBBBBBBbbbfddddf..",
".hhffBBBBBBBBbbbfddddf...",
"..hhffBBBBBbbbbffddddf...",
"...hhffBBBBbbbffddddf....",
"....hhffbbbbfffddddf.....",
"....fhhfffffffddddf......",
".....fffffffdddddf......",
"......fffdddddddf.......",
],
"gibbon": [
"....hHhhhhf.....",
"...hHHhhhfff....",
"..hHHhhhfffdf...",
".hHHhfBBBfddf...",
"hHHhfBCCBBfddf..",
"hHhhfCCBBBfddf..",
"hhhhfCCBBBfddf..",
".hhhfCCBBBfddf..",
".hhhfCBBBBfddf..",
"..hhfBBBBbfddf..",
"..hhfBBBbbfddf..",
"..hhffBbbffddf..",
"..fhhfffffdddf..",
"...fhfffffddf...",
"...fhffffdddf...",
"....ffdddddf....",
],
"orangutan": [
"......hhHHhhfff.......",
"....hhHHHhhhhfff......",
"...hHHHHhhhhhffff.....",
"..hHHHhhhfffffddff....",
".hHHhhhffBBBBffddff...",
"hHHhhhffBCCBBBfdddf...",
"hHhhhffBCCCBBBbfdddf..",
"hhhhffBCCCCBBBbfdddf..",
"hhfffBCCCCBBBBbfdddf..",
"hhfffBCCCBBBBBbfdddf..",
".hfffBCCBBBBBBbfdddf..",
".hfffBBBBBBBBbbfdddf..",
".hffffBBBBBBbbffdddf..",
"..hffffBbbbbbfffdddf..",
"..hhffffbbbffffddddf..",
"...hhfffffffffddddf...",
"...fhffhffffhfdddf....",
"....fdfhffhffdddf....",
".....ffdfdfdfddf.....",
],
"capuchin": [
"....CCCCCBB.....",
"...CCCCCCCBB....",
"..CCCCCBBBBBf...",
".CCCBfffBBBbdf..",
".CCBfffBCCBfddf.",
".hffffBCCCBBfdf.",
".hffffBCCCBBfdf.",
".hffffBCCBBBfdf.",
"..hfffBBBBBbfdf.",
"..hffffBBBbbfdf.",
"..hfffffbbbfddf.",
"...hfffffffddf..",
"...fffffffdddf..",
"....ffddddddf...",
],
}

PALETTES = {
#           q        d        f        h        H        s        m        L        b        B        C
"macaque":  ["38252a","604034","995e36","c48a4b","e4b76a","b17b51","e5ad70","ffe0a0","a6794b","d9ad70","f4d799"],
"gorilla":  ["171f2c","29313f","414d60","66778b","93a0ad","51596b","8e9caa","c1cbd0","354050","5c6a7d","8998a8"],
"gibbon":   ["463832","8b7456","c7ad7b","e3ce98","fff0be","352e30","675048","caa17a","9c815d","d2b686","f1dca9"],
"orangutan":["4a2629","84422d","ba622d","e3933c","f6c566","965b45","c18a60","f0bd82","864b32","b97943","dca05d"],
"capuchin": ["28252b","46342d","70503b","9c7048","c9a76b","b9a579","e5d5aa","fff1c9","a68a62","dbbf8b","fff0c0"],
}
BUILDS = {
"macaque":   dict(body_y=39, head_y=18, arm=13, radius=2, legs=8, tail=1, near=24, far=40, feet=(27,38)),
"gorilla":   dict(body_y=35, head_y=14, arm=19, radius=3, legs=8, tail=0, near=21, far=44, feet=(25,40)),
"gibbon":    dict(body_y=37, head_y=18, arm=21, radius=2, legs=10,tail=0, near=26, far=39, feet=(28,37)),
"orangutan": dict(body_y=36, head_y=14, arm=21, radius=3, legs=7, tail=0, near=23, far=43, feet=(27,39)),
"capuchin":  dict(body_y=43, head_y=24, arm=12, radius=2, legs=7, tail=2, near=26, far=39, feet=(28,37)),
}

def palette(species, skin="natural"):
    values = list(PALETTES[species])
    if skin == "rose":
        values[:5] = ["47263f","8b426d","c56b9c","e998bd","ffc8db"]
    elif skin == "moss":
        values[:5] = ["24372e","3e6443","628750","9eba65","d9dd93"]
    p = {k: tuple(bytes.fromhex(v)) + (255,) for k,v in zip("qdfhHsmLbBC",values)}
    p.update({"o":(14,19,28,255),"e":(255,247,219,255),"p":(18,18,24,255),"n":(47,30,31,255)})
    p["F"] = p["f"]
    return p

def grid(rows, colors):
    width = max(map(len, rows))
    img = Image.new("RGBA", (width, len(rows)))
    for y, row in enumerate(rows):
        for x, code in enumerate(row):
            if code != ".":
                img.putpixel((x,y), colors[code])
    return outline(img, colors["o"])

def outline(img, color):
    size=(img.width+2,img.height+2)
    edge=Image.new("L",size)
    alpha=img.getchannel("A")
    for offset in ((0,1),(2,1),(1,0),(1,2)):
        shifted=Image.new("L",size);shifted.paste(alpha,offset)
        edge=ImageChops.lighter(edge,shifted)
    expanded=Image.new("RGBA",size,color);expanded.putalpha(edge)
    expanded.alpha_composite(img,(1,1))
    return expanded

def stamp(canvas, image, at):
    canvas.alpha_composite(image, (round(at[0]),round(at[1])))

def capsule(draw, a, b, r, color):
    a,b = tuple(round(v) for v in a),tuple(round(v) for v in b)
    draw.line((a,b),fill=color,width=r*2+1)
    for x,y in (a,b):
        draw.ellipse((x-r,y-r,x+r,y+r),fill=color)

def limb(canvas, root, elbow, hand, r, p, far=False, foot=False, open_hand=False, shaggy=False):
    layer=Image.new("RGBA",(SIZE,SIZE)); d=ImageDraw.Draw(layer)
    for a,b in ((root,elbow),(elbow,hand)):
        capsule(d,a,b,r,p["d"] if far else p["f"])
        if not far:
            d.line([(round(a[0]-r+1),round(a[1])),(round(b[0]-r+1),round(b[1]))], fill=p["h"],width=max(1,r-1))
        d.line([(round(a[0]+r),round(a[1])),(round(b[0]+r),round(b[1]))],fill=p["q"] if far else p["d"],width=1)
    x,y=map(round,hand)
    hr=r+1
    if foot:
        d.ellipse((x-hr,y-1,x+hr+2,y+2),fill=p["s"])
        d.line((x-hr+1,y,x+hr+1,y),fill=p["L"] if not far else p["m"],width=1)
        for dx in (-1,1,3): d.point((x+dx,y+2),fill=p["n"])
    else:
        d.ellipse((x-hr,y-hr,x+hr,y+hr),fill=p["s"] if far else p["m"])
        d.line((x-hr+1,y-hr+1,x+1,y-hr+1),fill=p["L"] if not far else p["m"],width=1)
        for dx in (-1,1): d.point((x+dx,y+hr-1),fill=p["s"] if not far else p["n"])
        if open_hand:
            for dx,extra in ((-2,1),(0,3),(2,2)):
                d.line((x+dx,y-hr,x+dx,y-hr-extra),fill=p["m"],width=1)
    if shaggy:
        ex,ey=map(round,elbow)
        for dx,dy in ((-r,1),(-r+1,4),(r,2)):
            d.line((ex+dx,ey+dy,ex+dx-1,ey+dy+3),fill=p["d"],width=1)
    stamp(canvas,outline(layer,p["o"]),(-1,-1))

def poses():
    result={}; anims={}
    counts={"idle":4,"run":8,"jump":3,"fall":2,"land":3,"climb":6,"swing":4,"punch":5,"slap":5,"kick":5,"dash":4,"roll":8,"stun":4,"wave":4,"cheer":4}
    fps={"idle":4,"run":12,"jump":12,"fall":5,"land":12,"climb":9,"swing":6,"punch":18,"slap":18,"kick":18,"dash":12,"roll":20,"stun":8,"wave":7,"cheer":7}
    for name,count in counts.items():
        keys=[]
        for i in range(count):
            key=f"{name}_{i}"; keys.append(key)
            result[key]={"animation":name,"phase":i,"count":count}
        anims[name]={"frames":keys,"fps":fps[name],"loop":name in ("idle","run","climb","swing","fall","stun","wave","cheer")}
    result["blink"]={"animation":"blink","phase":0,"count":1}
    return result,anims

POSES, ANIMS=poses()

def pose_offsets(name,i,n,b):
    # Integer pose keys keep both shoulders and both hips visible. Perspective
    # comes from asymmetry, overlap, far-side shade and the offset chest patch.
    t=i/max(n-1,1); phase=i*math.tau/n; sine=math.sin(phase)
    a=b["arm"]
    p=dict(bob=0,lean=0,head=0,head_dx=0,near=(-3,a),far=(3,a-2),nf=(0,0),ff=(0,0),tail=sine,eyes="open",open=False)
    if name in ("idle","blink"):
        p["bob"]=1 if i in (1,2) else 0
        p["near"]=(-3,a-1+(i%2)); p["far"]=(3,a-3)
        if name=="blink":p["eyes"]="shut"
    elif name=="run":
        p.update(bob=-round(abs(sine)*2),lean=2,near=(-3+round(sine*9),a-3-round(abs(sine)*5)),far=(3-round(sine*9),a-4-round(abs(sine)*5)),nf=(round(sine*6),-round(max(0,sine)*5)),ff=(-round(sine*6),-round(max(0,-sine)*5)))
    elif name=="jump":
        p.update(bob=(-1,-3,-2)[i],lean=1,near=(-5,-25),far=(5,-23),nf=(-2,-5-i),ff=(3,-3-i),open=True)
    elif name=="fall":
        p.update(near=(-a+2,-2),far=(a-4,1),nf=(-2,-2),ff=(3,-2),open=True,bob=i)
    elif name=="land":
        p.update(bob=(3,2,0)[i],near=(-5,a-4),far=(5,a-5),nf=(-2,0),ff=(2,0))
    elif name=="climb":
        p.update(bob=-round(sine*2),near=(-2,-24+round(sine*7)),far=(4,-24-round(sine*7)),nf=(0,-3-round(max(0,sine)*5)),ff=(2,-3-round(max(0,-sine)*5)))
    elif name=="swing":
        p.update(lean=round(sine*3),near=(2,-30),far=(0,-29),nf=(round(sine*5),-4),ff=(round(sine*4)+2,-3))
    elif name in ("punch","slap"):
        reach=(0,6,16,11,0)[i]
        p.update(lean=(0,-2,3,2,0)[i],near=(reach+2,(-5,-9,-2,2,a-1)[i]),far=(4,a-5),open=name=="slap",nf=(-2,0),ff=(2,0))
    elif name=="kick":
        p.update(lean=-2,near=(-7,5),far=(7,2),nf=(0,0),ff=((0,3,13,8,0)[i],(0,-5,-10,-6,0)[i]))
    elif name=="dash":
        p.update(bob=3+i%2,lean=5,near=(-9,4+i%2),far=(-3,4),nf=(-4+i,-2),ff=(8-i,-4))
    elif name=="roll":
        # A tuck, not a rotated standing monkey: chin down onto the chest,
        # knees pulled up in front of it, both arms wrapped round the shins.
        # The ball this makes is what spins, and a ball spinning reads as a
        # roll where a spinning upright body reads as a cartwheel.
        p.update(head=9,head_dx=3,near=(8,4),far=(6,3),nf=(4,-12),ff=(5,-11),tail=None,eyes="shut")
    elif name=="stun":
        p.update(lean=(-2,2,-2,1)[i],near=(-9,2),far=(10,1),eyes="dizzy",bob=1,open=True)
    elif name=="wave":
        p.update(near=(-7+round(sine*3),-a+4),far=(3,a-3),open=True)
    elif name=="cheer":
        p.update(bob=-(i%2),near=(-7,-a+3),far=(7,-a+4),nf=(-2,-(i%2)*2),ff=(2,-(i%2)*2),open=True)
    return p

def draw_tail(canvas,b,p,colors):
    if not b["tail"] or p["tail"] is None:return
    # Two deliberately different authored silhouettes: short macaque curl;
    # high, long capuchin spiral. Sway moves the hook, not the attachment.
    shift=round(p["tail"]*2)
    points=[(27,52),(20,53),(16,50),(14,45),(14,41),(17,38),(21,39),(22,42),(20,44),(18,43)]
    if b["tail"]==2:
        points=[(28,54),(21,55),(15,53),(11,49),(10,43),(11,37),(15,34),(20,35),(22,39),(20,42),(17,42),(16,39)]
    points=[(x+(shift if j>2 else 0),y+p["bob"]) for j,(x,y) in enumerate(points)]
    d=ImageDraw.Draw(canvas)
    d.line(points,fill=colors["o"],width=5,joint="curve")
    d.line(points,fill=colors["d"],width=3,joint="curve")
    d.line([(x-1,y-1) for x,y in points],fill=colors["h"],width=1)

def wrap_tail(ball,colors):
    # Tailed monkeys hug the tail round the ball: a short arc behind the
    # back, so the silhouette stays round and the species stays readable.
    w,h=ball.size
    out=Image.new("RGBA",(w+4,h+2)); d=ImageDraw.Draw(out)
    arc=(0,1,w+2,h+1)
    d.arc(arc,start=100,end=250,fill=colors["o"],width=4)
    d.arc((1,2,w+1,h),start=104,end=246,fill=colors["d"],width=2)
    out.alpha_composite(ball,(2,1))
    return out

def head_image(species,p,colors):
    rows=[list(row) for row in HEADS[species]]
    if p["eyes"]=="shut":
        for y,row in enumerate(rows):
            for x,c in enumerate(row):
                if c in "ep":row[x]="n" if y==10 else "m"
    elif p["eyes"]=="dizzy":
        eyes=[]
        for y,row in enumerate(rows):
            for x,c in enumerate(row):
                if c=="e" and (y==0 or x>=len(rows[y-1]) or rows[y-1][x]!="e"):
                    if not eyes or x-eyes[-1][0]>2:eyes.append((x,y))
        for ex,ey in eyes:
            for dy,line in enumerate(("pmp","mpm","pmp")):
                for dx,c in enumerate(line):
                    if ey+dy<len(rows) and ex+dx<len(rows[ey+dy]):rows[ey+dy][ex+dx]=c
    return grid(["".join(r) for r in rows],colors)

def render(species,pose,skin="natural"):
    b=BUILDS[species]; colors=palette(species,skin)
    p=pose_offsets(pose["animation"],pose["phase"],pose["count"],b)
    canvas=Image.new("RGBA",(SIZE,SIZE))
    draw_tail(canvas,b,p,colors)
    by=b["body_y"]+p["bob"]; lean=p["lean"]
    body=grid(BODIES[species],colors)
    # Far arm and leg are distinct limbs behind the chest, never hidden on
    # the same centreline as the near pair (the old side-on stick rig).
    def arm(near):
        root=(b["near"]+lean if near else b["far"]+lean,by+4 if near else by+5)
        dx,dy=p["near" if near else "far"]
        hand=(root[0]+dx,root[1]+dy)
        hand=(min(56,max(6,hand[0])),min(57,max(6,hand[1])))
        elbow=((root[0]+hand[0])/2+(-2 if near else 1),(root[1]+hand[1])/2+2)
        limb(canvas,root,elbow,hand,b["radius"],colors,far=not near,open_hand=p["open"],shaggy=species=="orangutan")
    def leg(near):
        x=b["feet"][0 if near else 1]
        dx,dy=p["nf" if near else "ff"]
        root=(x,54 if species!="capuchin" else 55)
        foot=(x+dx,(58 if species in ("gorilla","orangutan") else 59)+dy)
        knee=((root[0]+foot[0])/2+(1 if near else -1),(root[1]+foot[1])/2)
        limb(canvas,root,knee,foot,2 if species not in ("gorilla","orangutan") else 3,colors,far=not near,foot=True)
    arm(False);leg(False)
    stamp(canvas,body,(32-body.width//2+lean,by))
    leg(True)
    head=head_image(species,p,colors)
    stamp(canvas,head,(33-head.width//2+lean+p["head_dx"],b["head_y"]+p["bob"]+p["head"]))
    arm(True)
    if pose["animation"]=="roll":
        # Bake the spin onto the pixel canvas, rather than rotate the runtime
        # sprite through fractional screen pixels during the double jump.
        # The ball is centred low in the cell, where the body was, so the
        # roll does not jump upward on the first frame.
        ball=canvas.crop(canvas.getbbox())
        if tail_ball:=b["tail"]:
            ball=wrap_tail(ball,colors)
        compact=ball.rotate(-pose["phase"]*45,resample=Image.Resampling.NEAREST,expand=True)
        canvas=Image.new("RGBA",(SIZE,SIZE))
        stamp(canvas,compact,((SIZE-compact.width)//2,SIZE-6-compact.height//2-ball.height//2))
    return canvas

def create_review(frames_by_species):
    REVIEW.mkdir(parents=True,exist_ok=True)
    # Review boards only: the shipped sheets remain transparent native pixels.
    bg=(9,21,29,255); text=(241,221,168,255); muted=(128,167,151,255)
    font=ImageFont.load_default(size=16)
    board=Image.new("RGBA",(1100,400),bg);d=ImageDraw.Draw(board)
    d.text((28,18),"PRIMATE RUSH / THREE-QUARTER CHARACTER LINEUP",fill=text,font=font)
    desc=["CHEEK TUFTS / CURLED TAIL","HEAVY BROW / BROAD CHEST","FACE RING / LONG ARMS","CHEEK PADS / SHAGGY FUR","PALE MANTLE / SPIRAL TAIL"]
    for i,sp in enumerate(SPECIES):
        x=18+i*217
        sprite=frames_by_species[sp]["idle_0"].resize((192,192),Image.Resampling.NEAREST)
        board.alpha_composite(sprite,(x+6,60))
        d.text((x+25,275),sp.upper(),fill=text,font=font)
        d.text((x+6,308),desc[i],fill=muted,font=ImageFont.load_default(size=10))
    d.text((28,365),"64 x 64 cells / 2x in game / hand-authored species anatomy / shared upper-left lighting",fill=muted,font=ImageFont.load_default(size=14))
    board.save(REVIEW/"lineup.png")
    for sp in SPECIES:
        board=Image.new("RGBA",(1100,len(ANIMS)*150+55),bg);d=ImageDraw.Draw(board)
        d.text((18,12),sp.upper()+" / ANIMATION CONTACT SHEET",fill=text,font=font)
        for row,(name,anim) in enumerate(ANIMS.items()):
            y=42+row*150
            d.text((12,y+54),name.upper(),fill=text,font=ImageFont.load_default(size=13))
            for col,key in enumerate(anim["frames"]):
                frame=frames_by_species[sp][key].resize((128,128),Image.Resampling.NEAREST)
                board.alpha_composite(frame,(78+col*127,y))
        board.save(REVIEW/f"{sp}-animations.png")
    # Animated proof of all species exercising the same motion together.
    sequence=[]
    for name in ("idle","run","jump","fall","land","climb","swing","slap","punch","kick","roll","stun","wave","cheer"):
        for repeat in range(2 if ANIMS[name]["loop"] else 1):
            for key in ANIMS[name]["frames"]:
                frame=Image.new("RGBA",(1000,260),bg);d=ImageDraw.Draw(frame)
                d.text((20,12),"PRIMATE RUSH / "+name.upper(),fill=text,font=font)
                for i,sp in enumerate(SPECIES):
                    frame.alpha_composite(frames_by_species[sp][key].resize((192,192),Image.Resampling.NEAREST),(i*200+4,38))
                    d.text((i*200+45,237),sp.upper(),fill=text,font=font)
                sequence.append(frame.convert("RGB"))
    sequence[0].save(REVIEW/"animation-preview.gif",save_all=True,append_images=sequence[1:],duration=110,loop=0,disposal=2)

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    frames_by_species={}; metadata={"cell_size":[SIZE,SIZE],"anchor":[32,64],"columns":8,"frame_names":list(POSES),"animations":ANIMS,"species":{}}
    variants=[(sp,"natural") for sp in SPECIES]+[("macaque","rose"),("macaque","moss")]
    for sp,skin in variants:
        folder=OUT/(sp if skin=="natural" else sp+"_"+skin);folder.mkdir(exist_ok=True)
        frames={key:render(sp,pose,skin) for key,pose in POSES.items()}
        if skin=="natural":frames_by_species[sp]=frames
        atlas=Image.new("RGBA",(8*SIZE,math.ceil(len(POSES)/8)*SIZE))
        for i,(key,frame) in enumerate(frames.items()):
            atlas.alpha_composite(frame,((i%8)*SIZE,(i//8)*SIZE))
            # Transparent margins prevent neighbouring cells bleeding and
            # prove no swinging hand, foot, or tail was cut by the canvas.
            box=frame.getbbox()
            assert box and box[0]>0 and box[1]>0 and box[2]<SIZE and box[3]<SIZE,(sp,key,box)
        atlas.save(folder/"atlas.png")
        for name,anim in ANIMS.items():
            strip=Image.new("RGBA",(SIZE*len(anim["frames"]),SIZE))
            for i,key in enumerate(anim["frames"]):strip.alpha_composite(frames[key],(i*SIZE,0))
            strip.save(folder/(name+".png"))
            assert len({frames[k].tobytes() for k in anim["frames"]})>1,(sp,name,"identical animation frames")
        head=head_image(sp,{"eyes":"open"},palette(sp,skin))
        portrait=Image.new("RGBA",(40,40));portrait.alpha_composite(head,((40-head.width)//2,(40-head.height)//2))
        portrait.save(folder/"portrait.png")
        top=SIZE-frames["idle_0"].getbbox()[1]
        metadata["species"][folder.name]={"base_species":sp,"skin":skin,"head_height":top,"palette":{k:list(v) for k,v in palette(sp,skin).items()}}
        print(folder.name,len(frames),"frames",top,"pixels tall")
    (OUT/"manifest.json").write_text(json.dumps(metadata,indent=2)+"\n")
    # Frame enums are generated from the same manifest, avoiding frame drift.
    lines=["class_name MonkeyFrames","extends RefCounted","","const COLUMNS: int = 8",f"const ROWS: int = {math.ceil(len(POSES)/8)}","const POSES: Dictionary = {"]
    lines += [f'\t&"{key}": {i},' for i,key in enumerate(POSES)]
    lines += ["}","const ANIMS: Dictionary = {"]
    for name,a in ANIMS.items():
        names=", ".join('&"'+k+'"' for k in a["frames"])
        lines.append(f'\t&"{name}": {{"frames": [{names}], "fps": {float(a["fps"])}, "loop": {str(a["loop"]).lower()}}},')
    lines += ["}","const HEIGHTS: Dictionary = {"]
    lines += [f'\t&"{sp}": {metadata["species"][sp]["head_height"]},' for sp in SPECIES]
    lines += ["}",""]
    (ROOT/"scripts/player/MonkeyFrames.gd").write_text("\n".join(lines))
    create_review(frames_by_species)
    print("Wrote production atlases, animation strips, manifest and review boards.")

if __name__=="__main__":main()
