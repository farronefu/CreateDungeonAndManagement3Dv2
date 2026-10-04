"""Generate stable connected plateau profiles for the shared six-face block shell.

Uses existing Pillow/numpy authoring dependencies; no game-time randomness or asset imports.
The original color atlases remain untouched. RGBA stores rock / mixed moss / green / dry heights.
"""
from pathlib import Path
import json,random
import numpy as np
from PIL import Image

GRID=6
VARIANTS=4

def connected_blob(rng,minimum=4,maximum=12):
    cells={(rng.randrange(GRID),rng.randrange(GRID))}
    for _ in range(rng.randint(minimum,maximum)*6):
        x,y=rng.choice(sorted(cells));dx,dy=rng.choice([(1,0),(-1,0),(0,1),(0,-1)])
        if 0<=x+dx<GRID and 0<=y+dy<GRID:cells.add((x+dx,y+dy))
        if len(cells)>=maximum:break
    return cells

def remove_isolated_highs(field):
    for y in range(GRID):
        for x in range(GRID):
            neighbors=[field[ny,nx] for nx,ny in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] if 0<=nx<GRID and 0<=ny<GRID]
            if field[y,x]>max(neighbors)+0.10:field[y,x]=max(neighbors)
    return field

def generate(root):
    out=root/'assets/models/blocks/block_surface_depth.png'
    moss=Image.open(root/'assets/models/blocks/Block_Nutrient_01_04_Moss_Block_mottled_BaseColor.png').convert('RGB')
    atlas=np.zeros((GRID*6,GRID*VARIANTS,4),dtype=np.uint8)
    metrics=[]
    for variant in range(VARIANTS):
        for face in range(6):
            rng=random.Random(73190+variant*991+face*137)
            rock=np.full((GRID,GRID),0.91)
            green=np.full((GRID,GRID),0.36)
            dry=np.full((GRID,GRID),0.52)
            for _ in range(3):
                for x,y in connected_blob(rng,4,rng.randint(7,13)):rock[y,x]=rng.choice([0.56,0.72,0.82]) if rng.random()<0.18 else 0.72
            for field in [green,dry]:
                for level in [0.72,0.94,0.56]:
                    for x,y in connected_blob(rng,4,rng.randint(6,12)):field[y,x]=level
                # A broad connected hollow, rather than separate one-cell pegs.
                for x,y in connected_blob(rng,3,6):field[y,x]=0.20
                remove_isolated_highs(field)
            # Original moss colors stay fixed; match the coarse relief to their coverage.
            mixed=rock.copy()
            for y in range(GRID):
                for x in range(GRID):
                    u=(x+0.5)/GRID
                    v=(y+0.5)/GRID
                    px=int(face%3*136+4+u*128);py=int(face//3*136+4+(1-v)*128)
                    rr,gg,bb=moss.getpixel((px,py))
                    if gg>rr and gg>bb:mixed[y,x]=max(green[y,x],0.90)
                    else:mixed[y,x]=min(rock[y,x],0.65)
            remove_isolated_highs(mixed)
            # Unequal bites at selected corners and edges, all within the nominal box.
            for field in [rock,mixed,green,dry]:
                corners=[(0,0),(0,GRID-1),(GRID-1,0),(GRID-1,GRID-1)]
                for x,y in rng.sample(corners,2):
                    field[y,x]=0.16
                    nx=x+(1 if x==0 else -1)
                    field[y,nx]=min(field[y,nx],0.44)
                field[rng.randrange(GRID),rng.randrange(GRID)]=1.0
                remove_isolated_highs(field)
                # A connected plateau reaches the old envelope, preserving exact bounds.
                highest=np.unravel_index(np.argmax(field),field.shape)
                hy,hx=highest;field[hy,hx]=1.0
                nx=hx+1 if hx<GRID-1 else hx-1;field[hy,nx]=1.0
            values=np.stack([rock,mixed,green,dry],axis=2)
            block=np.round(np.clip(values,0,1)*255).astype(np.uint8)
            atlas[face*GRID:(face+1)*GRID,variant*GRID:(variant+1)*GRID]=block
            metrics.append({'variant':variant,'face':face,'unique_levels':[len(np.unique(block[:,:,c])) for c in range(4)]})
    Image.fromarray(atlas,'RGBA').save(out)
    (out.with_suffix('.json')).write_text(json.dumps({'grid':GRID,'variants':VARIANTS,'depth_m':0.12,'height_channels':['rock','mixed_moss','green','dry'],'reference_sha256':'46ef6eaf8d9eeeb9712a3d0b1d7a24575ded82cd8608be76edefd35bc97c722b','profiles':metrics},indent=2))
    print('Generated',out,atlas.shape)

if __name__=='__main__':
    generate(Path(__file__).resolve().parents[2])
