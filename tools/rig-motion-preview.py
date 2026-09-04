import bpy
import math
import os
from mathutils import Vector

ROOT = r"D:\牛来桌面宠物"
MODEL = os.path.join(ROOT, "Meshy_AI_Golden_Mountain_Yak_0903061351_texture.glb")
PREVIEW_MODE = os.environ.get("NIULAI_PREVIEW") == "1"
OUT_DIR = os.environ.get(
    "NIULAI_RIG_OUTPUT",
    os.path.join(ROOT, "assets", "animation-source", "rig-audit-v2" if PREVIEW_MODE else "rigged"),
)
FRAME_COUNT = int(os.environ.get("NIULAI_FRAME_COUNT", "12" if PREVIEW_MODE else "48"))
os.makedirs(OUT_DIR, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=MODEL)
mesh = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
decimate = mesh.modifiers.new("Animation proxy", "DECIMATE")
decimate.ratio = min(1.0, 100000 / max(1, len(mesh.data.vertices)))
bpy.ops.object.modifier_apply(modifier=decimate.name)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Preserve the original GLB texture. A previous orange multiply pass flattened
# the muzzle, horn and fur colour separation and made Niulai look pink/plastic.
for material in mesh.data.materials:
    if not material or not material.use_nodes:
        continue
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    base = principled.inputs.get("Base Color") if principled else None
    if base and base.is_linked:
        source = base.links[0].from_socket
        links.remove(base.links[0])
        grade = nodes.new("ShaderNodeHueSaturation")
        grade.inputs["Hue"].default_value = 0.46
        grade.inputs["Saturation"].default_value = 1.32
        grade.inputs["Value"].default_value = 0.78
        links.new(source, grade.inputs["Color"])
        links.new(grade.outputs["Color"], base)

# Build a small humanoid armature matching the neutral standing mesh.
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
rig = bpy.context.object
rig.name = "NiulaiRig"
edit = rig.data.edit_bones
edit.remove(edit[0])

def bone(name, head, tail, parent=None):
    b = edit.new(name)
    b.head, b.tail = head, tail
    if parent:
        b.parent = edit[parent]
    return b

bone("root", (0, 0, -0.50), (0, 0, -0.36))
bone("pelvis", (0, 0, -0.36), (0, 0, -0.16), "root")
bone("spine", (0, 0, -0.16), (0, 0, 0.18), "pelvis")
bone("chest", (0, 0, 0.18), (0, 0, 0.36), "spine")
bone("neck", (0, 0, 0.36), (0, 0, 0.55), "chest")
bone("head", (0, 0, 0.55), (0, 0, 0.88), "neck")
bone("upper_arm.L", (0.18, 0, 0.28), (0.30, 0, 0.03), "chest")
bone("forearm.L", (0.30, 0, 0.03), (0.34, 0, -0.25), "upper_arm.L")
bone("hand.L", (0.34, 0, -0.25), (0.34, 0, -0.36), "forearm.L")
bone("upper_arm.R", (-0.18, 0, 0.28), (-0.30, 0, 0.03), "chest")
bone("forearm.R", (-0.30, 0, 0.03), (-0.34, 0, -0.25), "upper_arm.R")
bone("hand.R", (-0.34, 0, -0.25), (-0.34, 0, -0.36), "forearm.R")
bone("thigh.L", (0.13, 0, -0.35), (0.14, 0, -0.61), "pelvis")
bone("shin.L", (0.14, 0, -0.61), (0.15, 0, -0.84), "thigh.L")
bone("foot.L", (0.15, 0, -0.84), (0.15, -0.14, -0.91), "shin.L")
bone("thigh.R", (-0.13, 0, -0.35), (-0.14, 0, -0.61), "pelvis")
bone("shin.R", (-0.14, 0, -0.61), (-0.15, 0, -0.84), "thigh.R")
bone("foot.R", (-0.15, 0, -0.84), (-0.15, -0.14, -0.91), "shin.R")
bone("tail", (0, 0.10, -0.35), (0, 0.45, -0.47), "pelvis")
bpy.ops.object.mode_set(mode="OBJECT")

# Build a watertight proxy for robust automatic weights, then let the textured
# render mesh follow it through surface deformation. This avoids stretched
# triangles on the dense, non-animation source topology.
proxy = mesh.copy()
proxy.data = mesh.data.copy()
proxy.name = "NiulaiDeformProxy"
bpy.context.collection.objects.link(proxy)
bpy.ops.object.select_all(action="DESELECT")
proxy.select_set(True)
bpy.context.view_layer.objects.active = proxy
proxy.data.remesh_voxel_size = 0.018
bpy.ops.object.voxel_remesh()

bpy.ops.object.select_all(action="DESELECT")
proxy.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

# Transfer the proxy's smooth bone weights back onto the textured render mesh.
for group in proxy.vertex_groups:
    mesh.vertex_groups.new(name=group.name)
transfer = mesh.modifiers.new("Transfer rig weights", "DATA_TRANSFER")
transfer.object = proxy
transfer.use_vert_data = True
transfer.data_types_verts = {"VGROUP_WEIGHTS"}
transfer.vert_mapping = "POLYINTERP_NEAREST"
transfer.layers_vgroup_select_src = "ALL"
transfer.layers_vgroup_select_dst = "NAME"
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.modifier_apply(modifier=transfer.name)
armature_modifier = mesh.modifiers.new("Niulai skeletal deformation", "ARMATURE")
armature_modifier.object = rig
proxy.hide_render = True

def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

camera_data = bpy.data.cameras.new("Camera")
camera = bpy.data.objects.new("Camera", camera_data)
bpy.context.collection.objects.link(camera)
camera.location = (0.75, -5.0, 0.22)
camera_data.type = "ORTHO"
camera_data.ortho_scale = 2.35
look_at(camera, (0, 0, 0.02))
bpy.context.scene.camera = camera

for name, location, energy, size in [
    ("Key", (-3, -4, 5), 650, 4.0),
    ("Fill", (4, -2, 2), 320, 3.0),
    ("Rim", (1, 3, 4), 500, 3.0),
]:
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.shape, data.size = energy, "DISK", size
    light = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(light)
    light.location = location
    look_at(light, (0, 0, 0))

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = scene.render.resolution_y = 320
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.render.image_settings.compression = 70
scene.view_settings.look = "AgX - Medium High Contrast"

def reset_pose():
    for p in rig.pose.bones:
        p.rotation_mode = "XYZ"
        p.rotation_euler = (0, 0, 0)
        p.location = (0, 0, 0)

def run_pose(phase):
    reset_pose()
    # One phase is one complete left/right walking cycle.  The root has two
    # shallow vertical pulses per cycle and never scales, so the torso cannot
    # appear to breathe, stretch or flicker between frames.
    double_support = math.cos(phase * 2)
    rig.pose.bones["root"].location.x = math.radians(0.04) * math.sin(phase)
    rig.pose.bones["root"].location.z = 0.012 - 0.012 * double_support
    rig.pose.bones["root"].rotation_euler.y = math.radians(-5.5)
    rig.pose.bones["pelvis"].rotation_euler.x = math.radians(2.0)
    rig.pose.bones["pelvis"].rotation_euler.z = math.radians(3.2) * math.sin(phase)
    rig.pose.bones["spine"].rotation_euler.x = math.radians(4.0)
    rig.pose.bones["spine"].rotation_euler.z = math.radians(-2.4) * math.sin(phase - 0.08)
    rig.pose.bones["chest"].rotation_euler.x = math.radians(2.0)
    rig.pose.bones["chest"].rotation_euler.z = math.radians(-2.0) * math.sin(phase - 0.16)
    rig.pose.bones["neck"].rotation_euler.x = math.radians(-4.0) + math.radians(0.8) * double_support
    rig.pose.bones["head"].rotation_euler.x = math.radians(-0.8) * double_support
    rig.pose.bones["head"].rotation_euler.z = math.radians(0.8) * math.sin(phase - 0.30)

    # Opposed arm swing.  There is no high-frequency wrist component: hands
    # inherit one smooth delayed arc from the forearm.
    for side, offset, sign in (("L", 0.0, 1), ("R", math.pi, -1)):
        p = phase + offset
        swing = math.cos(p)
        rig.pose.bones[f"upper_arm.{side}"].rotation_euler.x = math.radians(-16.0) * swing
        rig.pose.bones[f"upper_arm.{side}"].rotation_euler.z = sign * math.radians(4.0)
        rig.pose.bones[f"forearm.{side}"].rotation_euler.x = math.radians(-19.0) - math.radians(6.0) * math.cos(p - 0.35)
        rig.pose.bones[f"hand.{side}"].rotation_euler.x = math.radians(2.5) * math.cos(p - 0.55)

    # Physically legible four-stage gait for each side: heel contact, support,
    # toe-off and knee-led swing.  Left and right are exactly half a cycle
    # apart, which prevents both feet from advancing together.
    for side, offset, sign in (("L", 0.0, 1), ("R", math.pi, -1)):
        p = (phase + offset) % math.tau
        hip = math.radians(18.0) * math.cos(p)
        support_absorb = max(0.0, math.sin(p))
        swing_fold = max(0.0, -math.sin(p))
        knee = math.radians(7.0 + 10.0 * support_absorb + 29.0 * swing_fold)
        toe_off = max(0.0, math.sin(p - math.pi / 2))
        heel_contact = max(0.0, math.cos(p))
        ankle = math.radians(10.0 * toe_off - 8.0 * heel_contact - 5.0 * swing_fold)
        rig.pose.bones[f"thigh.{side}"].rotation_euler.x = hip
        rig.pose.bones[f"thigh.{side}"].rotation_euler.z = sign * math.radians(1.2) * math.cos(p)
        rig.pose.bones[f"shin.{side}"].rotation_euler.x = -knee
        rig.pose.bones[f"foot.{side}"].rotation_euler.x = ankle

    rig.pose.bones["tail"].rotation_euler.x = math.radians(2.0) * double_support
    rig.pose.bones["tail"].rotation_euler.z = math.radians(8.0) * math.sin(phase - 0.45)

def idle_pose(phase):
    reset_pose()
    breathe = math.sin(phase)
    shift = math.sin(phase - 0.45)
    greet = 0.5 - 0.5 * math.cos(phase)
    # Alert idle: a subtle weight change, an inquisitive look and a delayed
    # tail flick. No whole-image scale or camera movement is used.
    rig.pose.bones["root"].location.x = 0.010 * shift
    rig.pose.bones["root"].location.z = 0.006 * (1 - math.cos(phase * 2))
    rig.pose.bones["pelvis"].rotation_euler.z = math.radians(1.6) * shift
    rig.pose.bones["spine"].rotation_euler.x = math.radians(1.0) * breathe
    rig.pose.bones["spine"].rotation_euler.z = math.radians(-1.0) * shift
    rig.pose.bones["chest"].rotation_euler.x = math.radians(0.8) * breathe
    rig.pose.bones["neck"].rotation_euler.x = math.radians(-2.5) * greet
    rig.pose.bones["neck"].rotation_euler.y = math.radians(3.0) * math.sin(phase - 0.35)
    rig.pose.bones["neck"].rotation_euler.z = math.radians(3.2) * math.sin(phase - 0.55)
    rig.pose.bones["head"].rotation_euler.x = math.radians(-3.0) * greet
    rig.pose.bones["head"].rotation_euler.y = math.radians(3.5) * math.sin(phase - 0.60)
    rig.pose.bones["head"].rotation_euler.z = math.radians(4.5) * math.sin(phase - 0.80)
    # The near hand gives one relaxed greeting per loop; the wrist adds a
    # smaller secondary wave while the far arm counterbalances the torso.
    rig.pose.bones["upper_arm.L"].rotation_euler.x = math.radians(-10) * greet
    rig.pose.bones["upper_arm.L"].rotation_euler.z = math.radians(-24) * greet
    rig.pose.bones["forearm.L"].rotation_euler.x = math.radians(-20) * greet
    rig.pose.bones["forearm.L"].rotation_euler.z = math.radians(-30) * greet
    rig.pose.bones["hand.L"].rotation_euler.z = math.radians(10) * math.sin(phase * 3) * greet
    rig.pose.bones["upper_arm.R"].rotation_euler.x = -math.radians(3.0) * math.sin(phase - 0.25)
    rig.pose.bones["forearm.R"].rotation_euler.x = -math.radians(1.0) * breathe
    rig.pose.bones["tail"].rotation_euler.x = math.radians(2.5) * math.sin(phase - 0.70)
    rig.pose.bones["tail"].rotation_euler.z = math.radians(10) * math.sin(phase - 1.05)

def cry_pose(phase):
    reset_pose()
    pulse = (math.sin(phase) + 1) * 0.5
    sob = math.sin(phase * 2)
    rig.pose.bones["root"].location.z = -0.13 - 0.012 * pulse
    rig.pose.bones["pelvis"].rotation_euler.x = math.radians(7)
    rig.pose.bones["pelvis"].rotation_euler.z = math.radians(1.5) * math.sin(phase)
    rig.pose.bones["spine"].rotation_euler.x = math.radians(11 + 3 * pulse)
    rig.pose.bones["spine"].rotation_euler.z = math.radians(1.5) * sob
    rig.pose.bones["chest"].rotation_euler.x = math.radians(8 + 2 * pulse)
    rig.pose.bones["neck"].rotation_euler.x = math.radians(10 + 4 * pulse)
    rig.pose.bones["head"].rotation_euler.x = math.radians(6 + 3 * pulse)
    rig.pose.bones["head"].rotation_euler.z = math.radians(3.5) * math.sin(phase - 0.35)
    for side, sign in (("L", 1), ("R", -1)):
        rig.pose.bones[f"thigh.{side}"].rotation_euler.x = math.radians(25 + 2 * pulse)
        rig.pose.bones[f"shin.{side}"].rotation_euler.x = math.radians(-44 - 2 * pulse)
        rig.pose.bones[f"foot.{side}"].rotation_euler.x = math.radians(8)
        rig.pose.bones[f"upper_arm.{side}"].rotation_euler.x = math.radians(-35 - 3 * pulse) + math.radians(1.8) * sob
        rig.pose.bones[f"upper_arm.{side}"].rotation_euler.z = sign * math.radians(-18 - 2 * pulse)
        rig.pose.bones[f"forearm.{side}"].rotation_euler.x = math.radians(-48 - 4 * pulse)
        rig.pose.bones[f"forearm.{side}"].rotation_euler.z = sign * math.radians(-18)
        rig.pose.bones[f"hand.{side}"].rotation_euler.x = math.radians(-8) + math.radians(2) * sob
    rig.pose.bones["tail"].rotation_euler.z = math.radians(3) * math.sin(phase - 0.5)

def sleep_pose(phase):
    reset_pose()
    rig.pose.bones["root"].rotation_euler.z = math.radians(78)
    rig.pose.bones["root"].location.x = 0.28
    rig.pose.bones["root"].location.z = -0.48 + 0.006 * math.sin(phase)
    rig.pose.bones["pelvis"].rotation_euler.z = math.radians(-3)
    rig.pose.bones["spine"].rotation_euler.z = math.radians(-5)
    rig.pose.bones["chest"].rotation_euler.z = math.radians(-2) + math.radians(0.8) * math.sin(phase)
    rig.pose.bones["neck"].rotation_euler.z = math.radians(14)
    rig.pose.bones["head"].rotation_euler.z = math.radians(10)
    for side in ("L", "R"):
        rig.pose.bones[f"thigh.{side}"].rotation_euler.x = math.radians(30)
        rig.pose.bones[f"shin.{side}"].rotation_euler.x = math.radians(-55)
        rig.pose.bones[f"upper_arm.{side}"].rotation_euler.x = math.radians(-25)
        rig.pose.bones[f"forearm.{side}"].rotation_euler.x = math.radians(-50)

def drag_pose(phase):
    reset_pose()
    sway = math.sin(phase)
    delayed = math.sin(phase - 0.55)
    rig.pose.bones["root"].location.z = 0.11
    rig.pose.bones["root"].rotation_euler.z = math.radians(2.0) * sway
    rig.pose.bones["pelvis"].rotation_euler.x = math.radians(-5)
    rig.pose.bones["pelvis"].rotation_euler.z = math.radians(2.5) * delayed
    rig.pose.bones["spine"].rotation_euler.x = math.radians(-5)
    rig.pose.bones["chest"].rotation_euler.z = math.radians(-2) * delayed
    rig.pose.bones["neck"].rotation_euler.x = math.radians(3)
    rig.pose.bones["neck"].rotation_euler.z = math.radians(3) * delayed
    rig.pose.bones["head"].rotation_euler.x = math.radians(9)
    rig.pose.bones["head"].rotation_euler.z = math.radians(11) + math.radians(4) * math.sin(phase - 0.85)
    for side, sign, offset in (("L", 1, 0), ("R", -1, math.pi)):
        rig.pose.bones[f"upper_arm.{side}"].rotation_euler.x = math.radians(-7) + math.radians(4) * math.sin(phase + offset - 0.7)
        rig.pose.bones[f"upper_arm.{side}"].rotation_euler.z = sign * math.radians(-2)
        rig.pose.bones[f"forearm.{side}"].rotation_euler.x = math.radians(-12) + math.radians(3) * math.sin(phase + offset - 1.0)
        rig.pose.bones[f"hand.{side}"].rotation_euler.x = math.radians(4) * math.sin(phase + offset - 1.25)
        rig.pose.bones[f"thigh.{side}"].rotation_euler.x = math.radians(26) + math.radians(6) * math.sin(phase + offset - 0.35)
        rig.pose.bones[f"shin.{side}"].rotation_euler.x = math.radians(-48) + math.radians(5) * math.sin(phase + offset - 0.75)
        rig.pose.bones[f"foot.{side}"].rotation_euler.x = math.radians(12) + math.radians(3) * math.sin(phase + offset - 1.0)
    rig.pose.bones["tail"].rotation_euler.x = math.radians(3) * delayed
    rig.pose.bones["tail"].rotation_euler.z = math.radians(7) * math.sin(phase - 1.0)

poses = (
    {"run": run_pose}
    if os.environ.get("NIULAI_WALK_ONLY") == "1"
    else {"idle": idle_pose, "run": run_pose, "cry": cry_pose, "sleep": sleep_pose, "drag": drag_pose}
)
for state, pose in poses.items():
    state_dir = os.path.join(OUT_DIR, state)
    os.makedirs(state_dir, exist_ok=True)
    for index in range(FRAME_COUNT):
        pose(index / FRAME_COUNT * math.tau)
        scene.render.filepath = os.path.join(state_dir, f"frame-{index:03d}.png")
        bpy.ops.render.render(write_still=True)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "niulai-coordinated-rig.blend"))
print(f"Rendered {len(poses)} x {FRAME_COUNT} coordinated frames to {OUT_DIR}; vertices={len(mesh.data.vertices)}")
