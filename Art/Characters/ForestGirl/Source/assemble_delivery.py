"""Assemble rendered previews and the editable delivery package without altering model imagery."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from zipfile import ZipFile, ZIP_DEFLATED

P=Path(__file__).resolve().parent
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
font=ImageFont.truetype(FONT,22)
small=ImageFont.truetype(FONT,15)

paths=sorted((P/'motion_frames').glob('*.png'))
assert len(paths)==12
assert min(p.stat().st_mtime for p in paths)>= (P/'forest_girl.glb').stat().st_mtime, 'Motion frames must all match the current GLB.'
frames=[Image.open(p).convert('RGB') for p in paths]
palette=frames[0].quantize(colors=192)
frames=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
frames[0].save(P/'walk_preview.gif',save_all=True,append_images=frames[1:],duration=[80,80,90]*4,loop=0,disposal=2)

canvas=Image.new('RGB',(1500,545),'#faf7ef');draw=ImageDraw.Draw(canvas)
draw.text((28,16),'FOREST GIRL / V3 — GARMENT DETAIL & WALK REFINEMENT',font=font,fill='#423b32')
for i,(name,label) in enumerate([('three_quarter','THREE-QUARTER'),('front','FRONT'),('side','SIDE'),('back','BACK')]):
    im=Image.open(P/f'preview_{name}.png').convert('RGB');im.thumbnail((375,438))
    canvas.paste(im,(i*375,65));draw.text((i*375+20,519),label,font=small,fill='#423b32')
canvas.save(P/'model_overview.png')

canvas=Image.new('RGB',(1200,815),'#faf7ef');draw=ImageDraw.Draw(canvas)
draw.text((28,18),'V2 / V3 — SAME CAMERA, LIGHTING & COLOR MANAGEMENT',font=font,fill='#423b32')
for i,(name,label) in enumerate([('comparison_v2.png','V2  /  BEFORE'),('preview_three_quarter.png','V3  /  REFINED')]):
    im=Image.open(P/name).convert('RGB');im.thumbnail((600,700))
    canvas.paste(im,(i*600,65));draw.text((i*600+28,784),label,font=font,fill='#423b32')
canvas.save(P/'before_after_v3.png')

files=['forest_girl.glb','forest_girl.blend','README.md','build_character.py','render_motion.py',
       'check_glb.py','check_hand_clearance.py','assemble_delivery.py','model_stats.json','validation.json',
       'preview_three_quarter.png','preview_front.png','preview_side.png','preview_back.png',
       'comparison_v2.png','model_overview.png','before_after_v3.png','walk_preview.gif','walk_contact_check.json','hand_clearance_check.json']
with ZipFile(P/'forest_girl_package.zip','w',ZIP_DEFLATED) as z:
    for name in files:z.write(P/name,'forest_girl/'+name)
print('V3 package assembled:', (P/'forest_girl_package.zip').stat().st_size, 'bytes')
