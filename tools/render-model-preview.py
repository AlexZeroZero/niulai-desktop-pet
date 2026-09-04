import bpy
import math
import os
from mathutils import Vector

ROOT = r"D:\牛来桌面宠物"
MODEL = os.path.join(ROOT, "Meshy_AI_Golden_Mountain_Yak_0903061351_texture.glb")
OUTPUT = os.path.join(ROOT, "model-rig-preview.png")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=MODEL)
mesh = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")

# Reduce only the offline animation copy; the user's GLB remains untouched.
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
modifier = mesh.modifiers.new("Offline animation decimation", "DECIMATE")
modifier.ratio = min(1.0, 120000 / max(1, len(mesh.data.vertices)))
bpy.ops.object.modifier_apply(modifier=modifier.name)

def look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

camera_data = bpy.data.cameras.new("Camera")
camera = bpy.data.objects.new("Camera", camera_data)
bpy.context.collection.objects.link(camera)
camera.location = (0, -4.2, 0.15)
camera_data.type = "ORTHO"
camera_data.ortho_scale = 2.45
look_at(camera, (0, 0, 0.05))
bpy.context.scene.camera = camera

for name, location, energy, size in [
    ("Key", (-3, -4, 5), 1100, 4.0),
    ("Fill", (4, -2, 2), 750, 3.0),
    ("Rim", (1, 3, 4), 900, 3.0),
]:
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light = bpy.data.objects.new(name, light_data)
    bpy.context.collection.objects.link(light)
    light.location = location
    look_at(light, (0, 0, 0))

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.filepath = OUTPUT
scene.view_settings.look = "AgX - Medium High Contrast"
bpy.ops.render.render(write_still=True)
print(f"Rendered {OUTPUT}; vertices={len(mesh.data.vertices)}")
