# blender -b -P cut.py -- in.avi out(.mp4|dir) start_frame frame_count [stills]
# Cuts a clip out of a Godot Movie Maker AVI with Blender's sequencer and encodes H.264/AAC MP4
# (X-compatible), or with "stills" renders every 30th frame of the range as PNGs into `out`.
import bpy, sys, os

a = sys.argv[sys.argv.index("--") + 1:]
src, dst, start, count = a[0], a[1], int(a[2]), int(a[3])
stills = len(a) > 4 and a[4] == "stills"

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 60
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 100
se = scene.sequence_editor_create()
coll = se.strips if hasattr(se, "strips") else se.sequences
mv = coll.new_movie("play", src, channel=1, frame_start=1)
if not stills:
    coll.new_sound("snd", src, channel=2, frame_start=1)
scene.frame_start = start + 1
scene.frame_end = start + count

ims = scene.render.image_settings
if stills:
    ims.file_format = "PNG"
    os.makedirs(dst, exist_ok=True)
    for f in range(scene.frame_start, scene.frame_end + 1, 30):
        scene.frame_set(f)
        scene.render.filepath = os.path.join(dst, "f%05d.png" % (f - 1))
        bpy.ops.render.render(write_still=True)
    print("STILLS done")
else:
    if hasattr(ims, "media_type"):
        ims.media_type = "VIDEO"
    ims.file_format = "FFMPEG"
    ff = scene.render.ffmpeg
    ff.format = "MPEG4"
    ff.codec = "H264"
    ff.constant_rate_factor = "HIGH"
    ff.ffmpeg_preset = "GOOD"
    ff.gopsize = 30
    ff.audio_codec = "AAC"
    ff.audio_bitrate = 192
    ff.audio_channels = "STEREO"
    ff.audio_mixrate = 48000
    scene.render.filepath = dst
    bpy.ops.render.render(animation=True)
    print("MP4 done", dst, os.path.getsize(dst) if os.path.exists(dst) else "missing")
