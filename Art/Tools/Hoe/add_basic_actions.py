"""Add five short, reproducible skeletal clips to the validated gameplay GLB.

The archived .blend files were saved by a newer Blender than the build runner.
This pass edits glTF animation data only; meshes, skin, materials and Hoe stay intact.
Run from the repository root with: python Art/Tools/Hoe/add_basic_actions.py
"""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / 'Assets/Tools/Hoe/forest_girl_tools.glb'
MAGIC, VERSION, _ = struct.unpack_from('<III', PATH.read_bytes())
assert MAGIC == 0x46546C67 and VERSION == 2
data = PATH.read_bytes()
json_len = struct.unpack_from('<I', data, 12)[0]
doc = json.loads(data[20:20 + json_len])
bin_start = 20 + json_len + 8
binary = bytearray(data[bin_start:])
previous = doc.get('extras', {}).get('hourbloom_basic_actions')
if previous:
    del binary[previous['buffer_length']:]
    del doc['bufferViews'][previous['view_count']:]
    del doc['accessors'][previous['accessor_count']:]
    doc['animations'] = [a for a in doc['animations'] if a['name'] not in previous['names']]
baseline = {'buffer_length': len(binary), 'view_count': len(doc['bufferViews']),
            'accessor_count': len(doc['accessors'])}
base = next(a for a in doc['animations'] if a['name'] == 'freehand_idle')
by_node = {n['name']: i for i, n in enumerate(doc['nodes']) if 'name' in n}


def accessor_values(index):
    a = doc['accessors'][index]
    view = doc['bufferViews'][a['bufferView']]
    size = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[a['type']]
    assert a['componentType'] == 5126 and 'byteStride' not in view
    start = view['byteOffset'] + a.get('byteOffset', 0)
    return struct.unpack_from('<' + 'f' * size, binary, start)


neutral = {}
for channel in base['channels']:
    sampler = base['samplers'][channel['sampler']]
    name = doc['nodes'][channel['target']['node']]['name']
    neutral[name, channel['target']['path']] = accessor_values(sampler['output'])


def multiply(a, b):
    x, y, z, w = a
    X, Y, Z, W = b
    return (w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X,
            w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z)


def axis_quat(axis, degrees):
    angle = math.radians(degrees) / 2
    s = math.sin(angle)
    return (s if axis == 'x' else 0, s if axis == 'y' else 0,
            s if axis == 'z' else 0, math.cos(angle))


def add_accessor(values, shape):
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    flat = [v for row in values for v in (row if isinstance(row, tuple) else (row,))]
    binary.extend(struct.pack('<' + 'f' * len(flat), *flat))
    view_id = len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': len(flat) * 4})
    acc_id = len(doc['accessors'])
    fields = {'bufferView': view_id, 'componentType': 5126, 'count': len(values), 'type': shape}
    if shape == 'SCALAR':
        fields.update(min=[min(flat)], max=[max(flat)])
    doc['accessors'].append(fields)
    return acc_id


# Peak poses expressed in local bone space, tapered by an ease-in/out envelope.
# Every clip begins/ends at the freehand idle pose for interruption safety.
specs = {
    'Seed': (.72, .40, {'pelvis': ('x', 15), 'chest': ('x', 27), 'head': ('x', -10),
                          'upper_arm.R': ('x', -48), 'forearm.R': ('x', 26), 'upper_arm.L': ('x', -17)}),
    'Harvest': (.72, .43, {'pelvis': ('x', 19), 'chest': ('x', 34), 'head': ('x', -12),
                             'upper_arm.R': ('x', -68), 'forearm.R': ('x', 37), 'upper_arm.L': ('x', -31)}),
    'Pickup': (.64, .38, {'pelvis': ('x', 25), 'chest': ('x', 45), 'head': ('x', -17),
                            'upper_arm.R': ('x', -62), 'upper_arm.L': ('x', -35)}),
    'Drop': (.64, .38, {'pelvis': ('x', 12), 'chest': ('x', 29), 'head': ('x', -8),
                          'upper_arm.R': ('x', -49), 'forearm.R': ('x', 22)}),
    'Interact': (.55, .30, {'chest': ('x', 8), 'upper_arm.R': ('x', -60),
                              'forearm.R': ('x', 23), 'head': ('x', -6)}),
}

doc['animations'] = [a for a in doc['animations'] if a['name'] not in specs]
for name, (duration, contact, peak) in specs.items():
    times = (0., .08, contact * .72, contact, duration - .12, duration)
    weights = (0., .30, .88, 1., .42, 0.)
    input_id = add_accessor(times, 'SCALAR')
    action = {'name': name, 'channels': [], 'samplers': []}
    for channel in base['channels']:
        node_id = channel['target']['node']
        bone = doc['nodes'][node_id]['name']
        path = channel['target']['path']
        original = neutral[bone, path]
        values = []
        for weight in weights:
            if path == 'rotation' and bone in peak:
                axis, degrees = peak[bone]
                value = multiply(original, axis_quat(axis, degrees * weight))
            elif path == 'translation' and bone == 'pelvis':
                depth = .10 if name in ('Pickup', 'Harvest') else .06 if name in ('Seed', 'Drop') else 0.
                value = (original[0], original[1], original[2] - depth * weight)
            else:
                value = original
            values.append(value)
        output_id = add_accessor(values, {'translation': 'VEC3', 'rotation': 'VEC4', 'scale': 'VEC3'}[path])
        action['channels'].append({'sampler': len(action['samplers']), 'target': {'node': node_id, 'path': path}})
        action['samplers'].append({'input': input_id, 'output': output_id, 'interpolation': 'LINEAR'})
    doc['animations'].append(action)

doc.setdefault('extras', {})['hourbloom_basic_actions'] = {**baseline, 'names': list(specs)}
doc['buffers'][0]['byteLength'] = len(binary)
json_bytes = json.dumps(doc, separators=(',', ':'), ensure_ascii=False).encode()
json_bytes += b' ' * (-len(json_bytes) % 4)
binary += b'\x00' * (-len(binary) % 4)
out = (struct.pack('<III', MAGIC, VERSION, 12 + 8 + len(json_bytes) + 8 + len(binary))
       + struct.pack('<II', len(json_bytes), 0x4E4F534A) + json_bytes
       + struct.pack('<II', len(binary), 0x004E4942) + binary)
PATH.write_bytes(out)
print('Added actions:', ', '.join(specs), 'total animations:', len(doc['animations']))
