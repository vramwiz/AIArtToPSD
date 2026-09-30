"""Create tiny PNG inputs for UiSmoke; originals in PSD_Data are never changed."""
from pathlib import Path
import struct
import sys
from PIL import Image
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
a=Image.new('RGBA',(32,24));a.putdata([((x*17)%256,(y*23)%256,(x+y)*7%256,[0,64,128,255][(x+y)%4]) for y in range(24) for x in range(32)]);a.save(out/'素材ベース.png')
b=Image.new('RGBA',(7,5));b.putdata([(255,x*25,y*40,[0,127,255][(x+y)%3]) for y in range(5) for x in range(7)]);b.save(out/'追加パーツ.png')
c=Image.new('LA',(9,6));c.putdata([((x*21+y*3)%256,[0,64,200,255][(x+y)%4]) for y in range(6) for x in range(9)]);c.save(out/'置換.png')
pal=Image.new('P',(8,4));pal.putpalette([v for i in range(256) for v in (i,255-i,i//2)]);pal.putdata([i%4 for i in range(32)]);pal.info['transparency']=bytes([0,64,128,255]);pal.save(out/'palette.png');pal.save(out/'palette2.png',bits=2)
g=Image.new('1',(8,4));g.putdata([i%2 for i in range(32)]);g.save(out/'mono.png')
(out/'bad_png.fixture').write_bytes(b'not PNG data at all'*3)
(out/'huge_png.fixture').write_bytes(b'\x89PNG\r\n\x1a\n'+struct.pack('>I',13)+b'IHDR'+struct.pack('>II',30000,30000))
print('Prepared stage 11 PNG fixtures')
