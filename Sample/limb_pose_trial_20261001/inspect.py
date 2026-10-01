from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
P=Path(__file__).resolve().parent
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',12)
for name, origin in [('original_body',(65,274)),('accepted_pose_body',(109,274))]:
    im=Image.open(P/(name+'.png')).convert('RGBA')
    canvas=Image.new('RGBA',(1024,1536))
    canvas.paste(im,origin)
    for region, box in [('arms',(260,285,760,835)),('hem',(380,970,650,1090))]:
        crop=Image.alpha_composite(Image.new('RGBA',canvas.size,(190,190,190,255)),canvas).crop(box).resize(((box[2]-box[0])*2,(box[3]-box[1])*2))
        draw=ImageDraw.Draw(crop)
        for x in range((box[0]//25+1)*25,box[2],25):
            px=(x-box[0])*2
            draw.line((px,0,px,crop.height), fill=(200,50,50,90),width=1)
            draw.text((px+2,2),str(x),fill='red',font=font)
        for y in range((box[1]//25+1)*25,box[3],25):
            py=(y-box[1])*2
            draw.line((0,py,crop.width,py),fill=(200,50,50,90),width=1)
            draw.text((2,py+2),str(y),fill='red',font=font)
        crop.save(P/(name+'_'+region+'_coordinates.png'))
