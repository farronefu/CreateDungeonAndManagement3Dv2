# blender -b -P slim.py -- in.glb out.glb [body_tris] [chisel_tris] [tex_px]
# Decimates the Tripo breaker for the game and shrinks its textures; keeps BreakerBody and
# MetalChisel as separate nodes (the chisel slides along local Y in the GLB).
import bpy, sys, os

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
body_tris = int(argv[2]) if len(argv) > 2 else 24000
chisel_tris = int(argv[3]) if len(argv) > 3 else 1500
tex_px = int(argv[4]) if len(argv) > 4 else 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)

for o in bpy.data.objects:
    print("OBJ", o.name, o.type, "parent", o.parent.name if o.parent else None,
          "loc", tuple(round(v, 3) for v in o.location), "dims", tuple(round(v, 3) for v in o.dimensions),
          "tris", tris(o) if o.type == "MESH" else "-",
          "mats", [m.name for m in o.data.materials] if o.type == "MESH" else "-")

for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    target = chisel_tris if "Chisel" in o.name else body_tris
    t0 = tris(o)
    if t0 > target:
        bpy.context.view_layer.objects.active = o
        m = o.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = target / t0
        m.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=m.name)
    print("DECIMATED", o.name, t0, "->", tris(o))

for img in bpy.data.images:
    if img.size[0] > tex_px:
        img.scale(tex_px, tex_px)
        print("TEX", img.name, img.size[:])
    img.pack()

os.makedirs(os.path.dirname(dst), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_image_format="JPEG",
                          export_jpeg_quality=88, export_apply=True)
print("WROTE", dst, os.path.getsize(dst))
