"""Assemble the current rendered turnaround; no source images are retouched."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
ART=Path(__file__).resolve().parent;OUT=ART/'renders'
info=json.loads((ART/'asset_manifest.json').read_text())
fontpath='/usr/share/fonts/google-noto-sans-cjk-vf-fonts/NotoSansCJK-VF.ttc'
font=ImageFont.truetype(fontpath,28);small=ImageFont.truetype(fontpath,22)
sheet=Image.new('RGB',(1920,760),'#eee7d8');draw=ImageDraw.Draw(sheet)
draw.text((28,20),f"田园女孩 · Low Poly v1     {info['triangles']:,} tris / 1.20 m / 1024²",font=font,fill='#49392d')
for i,(name,label) in enumerate([('front','正面'),('side','侧面'),('back','背面'),('perspective','透视')]):
    im=Image.open(OUT/(name+'.png')).convert('RGB')
    sheet.paste(im.resize((480,600),Image.Resampling.LANCZOS),(i*480,80))
    draw.text((i*480+205,700),label,font=small,fill='#49392d')
sheet.save(OUT/'turnaround.png')
