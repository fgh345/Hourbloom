"""Local rest-mesh edits in Blender source units; keep the delivered GLB intact.

The character faces -Y. Only Y changes, preserving front/back X/Z outlines,
weights, topology, bone rests and the authored animation curves.
"""
def interpolate(value, knots):
    for (a, left), (b, right) in zip(knots, knots[1:]):
        if value <= b:
            t = max(0.0, min(1.0, (value - a) / (b - a)))
            return left + (right - left) * t
    return knots[-1][1]


def body_y(p):
    factor = interpolate(p.z, [(.65, 1.0), (.88, 1.62), (1.20, 1.55),
                               (1.55, 1.48), (1.90, 1.38), (2.15, 1.20)])
    # Keep hands and the outer sleeves close to their original thickness.
    central = interpolate(abs(p.x), [(0.0, 1.0), (.35, 1.0), (.72, .25)])
    return p.y * (1.0 + (factor - 1.0) * central)


def bag_y(y):
    # Offset the satchel enough to clear the expanded jacket, without moving
    # its front attachment behind the coat and hiding the shoulder strap.
    return -.31 + (y + .225) * 1.25


def reshape(meshes):
    report = {}
    for obj in meshes:
        name = obj.name
        before = [obj.matrix_world @ v.co for v in obj.data.vertices]
        inverse = obj.matrix_world.inverted()
        after = []
        for p in before:
            q = p.copy()
            if name.startswith(('Head', 'Hair', 'Eye', 'Ear', 'Mouth', 'Nose')):
                # A fuller cranium and a little more cheek/face projection.
                q.y = p.y * (1.28 if p.y < 0.0 else 1.36)
            elif name.startswith('Hat'):
                q.y = p.y * 1.16
            elif name.startswith('Bag') and 'strap' not in name and 'adjuster' not in name:
                q.y = bag_y(p.y)
            elif name.startswith('Bag') and 'fastening strap' in name:
                q.y = bag_y(p.y)
            elif name.startswith('Bag') and 'strap front' in name:
                q.y = body_y(p)
            elif name.startswith('Bag') and 'strap' in name:
                attach = interpolate(p.z, [(1.25, 1.0), (1.55, 0.0)])
                q.y = body_y(p) * (1.0 - attach) + bag_y(p.y) * attach
            elif name.startswith(('Dress', 'Jacket', 'Linen', 'Scarf', 'Neck', 'Arm', 'Hand', 'Bag')):
                q.y = body_y(p)
            # Legs and boots retain their authored contact and proportions.
            after.append(q)
        for vertex, p in zip(obj.data.vertices, after):
            vertex.co = inverse @ p
        # Imported custom normals describe the old flattened surfaces. Let
        # Blender recalculate them using the retained sharp/smooth face flags.
        if obj.data.has_custom_normals:
            obj.data.normals_split_custom_set([(0.0, 0.0, 0.0)] * len(obj.data.loops))
        obj.data.update()
        actual = [obj.matrix_world @ v.co for v in obj.data.vertices]
        assert all(abs(a.x-b.x) < 1e-6 and abs(a.z-b.z) < 1e-6
                   for a, b in zip(before, actual))
        if name.startswith(('Head', 'Dress • fitted', 'Dress • shaped', 'Bag • satchel')):
            report[name] = {
                'depth_before': max(p.y for p in before) - min(p.y for p in before),
                'depth_after': max(p.y for p in after) - min(p.y for p in after),
            }
    return {'front_back_vertex_xz_preserved': True, 'parts': report}
