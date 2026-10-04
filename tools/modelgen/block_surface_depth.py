"""Generate restrained connected relief; color atlases and cell seeds stay unchanged.

Two broad patches replace small per-cell height changes. Candidate selection bounds
the number of internal steps, and removes isolated peaks instead of adding pegs.
Uses existing Pillow/numpy authoring dependencies, never gameplay RNG.
"""
from pathlib import Path
import json, random
import numpy as np
from PIL import Image

GRID = 6
VARIANTS = 4
DEPTH = 0.10
PREVIOUS_MEAN_STEPS = [26.625, 30.7916666667, 29.5833333333, 30.2916666667]

def neighbors(cell):
    x, y = cell
    return [(a,b) for a,b in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] if 0<=a<GRID and 0<=b<GRID]

def patch(rng, count, start=None, weights=None):
    if start is None:
        start = max(((x,y) for y in range(GRID) for x in range(GRID)),
                    key=lambda p: rng.random()+(float(weights[p[1],p[0]]) if weights is not None else 0))
    cells = {start}
    while len(cells)<count:
        frontier = sorted({n for p in cells for n in neighbors(p)}-cells)
        chosen = max(frontier, key=lambda p: sum(n in cells for n in neighbors(p))*0.7+rng.random()*0.9)
        cells.add(chosen)
    return cells

def components(field, value):
    remaining = {(x,y) for y in range(GRID) for x in range(GRID) if field[y,x]==value}
    groups = []
    while remaining:
        pending = [min(remaining)]; remaining.remove(pending[0]); group = set(pending)
        while pending:
            for n in neighbors(pending.pop()):
                if n in remaining: remaining.remove(n); pending.append(n); group.add(n)
        groups.append(group)
    return groups

def step_count(field):
    return int(np.sum(field[:,1:]!=field[:,:-1])+np.sum(field[1:]!=field[:-1]))

def profile(variant, face, channel, moss_weights):
    best = None
    target = round(PREVIOUS_MEAN_STEPS[channel]*0.5)
    for attempt in range(80):
        rng = random.Random(91030+variant*991+face*137+channel*2017+attempt*7919)
        base = 255 if channel==0 else (214 if channel==1 else 219)
        field = np.full((GRID,GRID),base,dtype=np.uint8)
        if channel!=0:
            for x,y in patch(rng,rng.randint(7,10),weights=moss_weights if channel==1 else None): field[y,x]=255
        corner = rng.choice([(0,0),(0,5),(5,0),(5,5)])
        hollow = patch(rng,rng.randint(5,7),corner)
        for x,y in hollow: field[y,x]=209 if channel==0 else 153
        if channel==0:
            x,y=corner;field[y,x]=166
            for a,b in neighbors(corner): field[b,a]=166
        # A valley may cut a raised patch; merge any resulting isolated peak.
        for group in components(field,255):
            if len(group)<3:
                for x,y in group: field[y,x]=base if channel else 209
        peaks = components(field,255)
        if not peaks or min(map(len,peaks))<3 or max(map(len,peaks))<4: continue
        groups=[g for value in np.unique(field) for g in components(field,value)]
        largest=max(map(len,groups));steps=step_count(field)
        if len(np.unique(field))<3 or largest<18: continue
        score=abs(steps-target)*10+(36-largest)*0.01
        if best is None or score<best[0]: best=(score,field.copy())
    if best is None: raise RuntimeError((variant,face,channel))
    return best[1]

def generate(root):
    out=root/'assets/models/blocks/block_surface_depth.png'
    moss=Image.open(root/'assets/models/blocks/Block_Nutrient_01_04_Moss_Block_mottled_BaseColor.png').convert('RGB')
    atlas=np.zeros((36,24,4),dtype=np.uint8);metrics=[]
    for variant in range(VARIANTS):
        for face in range(6):
            weights=np.zeros((6,6))
            for y in range(6):
                for x in range(6):
                    rr,gg,bb=moss.getpixel((int(face%3*136+4+(x+0.5)/6*128),int(face//3*136+4+(1-(y+0.5)/6)*128)))
                    weights[y,x]=0.8 if gg>rr and gg>bb else 0
            fields=[profile(variant,face,c,weights) for c in range(4)]
            atlas[face*6:(face+1)*6,variant*6:(variant+1)*6]=np.stack(fields,axis=2)
            metrics.append({'variant':variant,'face':face,'unique_levels':[len(np.unique(f)) for f in fields],
                            'internal_steps':[step_count(f) for f in fields],
                            'largest_flat_cells':[max(len(g) for v in np.unique(f) for g in components(f,v)) for f in fields],
                            'surface_height_range_m':[float((int(f.max())-int(f.min()))/255*DEPTH) for f in fields]})
    Image.fromarray(atlas,'RGBA').save(out)
    means=np.mean([m['internal_steps'] for m in metrics],axis=0).tolist()
    metadata={'grid':6,'variants':4,'depth_m':DEPTH,'style':'restrained_connected_plateaus',
              'height_channels':['rock','mixed_moss','green','dry'],
              'reference_sha256':'46ef6eaf8d9eeeb9712a3d0b1d7a24575ded82cd8608be76edefd35bc97c722b',
              'previous_mean_internal_steps':PREVIOUS_MEAN_STEPS,'mean_internal_steps':means,'profiles':metrics}
    out.with_suffix('.json').write_text(json.dumps(metadata,indent=2),encoding='utf8')
    print('Generated restrained profiles; mean internal steps:',means)

if __name__=='__main__':
    generate(Path(__file__).resolve().parents[2])
