"""Independent expression/group insertion checks (psd-tools + numpy)."""
import json, sys
from pathlib import Path
import numpy as np
from psd_tools import PSDImage
folder=Path(sys.argv[1]); source=PSDImage.open(sys.argv[2]); count=0
def check(value,message):
 global count
 count+=1
 if not value: raise AssertionError(message)
def find(p,name):
 return next(l for l in p.descendants() if l.name==name)
for filename in ['parts_new.psd','parts_switched.psd','aiueo_parts.psd','aiueo_parts_switched.psd']:
 p=PSDImage.open(folder/filename)
 imported=filename.startswith('aiueo')
 container=find(p,'追加表情' if imported else '表情')
 check(container.is_group(),'Container is not a group')
 normal=find(container,'*通常')
 check(normal.is_group() and len(normal)==1,'Normal expression structure')
 switched='switched' in filename
 if switched or not imported:
  happy=find(container,'*喜')
  check(happy.is_group() and len(happy)==1,'Happy expression structure')
  check(happy.visible==switched and normal.visible!=switched,'Exclusive selection not saved')
 else: check(normal.visible,'Initial expression hidden')
 for layer in [normal]+([happy] if switched or not imported else []):
  image=list(layer)[0]
  from PIL import Image
  expected=Image.open(folder/('追加パーツ.png' if layer==normal else '置換.png')).convert('RGBA')
  check(image.topil().convert('RGBA').tobytes()==expected.tobytes(),'Part pixels differ')
 if not imported:
  hand=find(p,'手'); check(len(hand)==2,'Independent hand family lost')
  check(find(hand,'*開く').visible and not find(hand,'*握る').visible,'Independent hand state changed')
 else:
  check(source.image_resources.tobytes()==p.image_resources.tobytes(),'Image resources changed')
  by_id={l.layer_id:l for l in p.descendants()}
  ids=[l.layer_id for l in p.descendants() if l.layer_id>=0]
  check(len(ids)==len(set(ids)),'Layer IDs collide')
  for old in source.descendants():
   new=by_id[old.layer_id]
   check(old.name==new.name and old.visible==new.visible and old.opacity==new.opacity,'Source attributes changed')
   check((old._record.top,old._record.left,old._record.bottom,old._record.right)==(new._record.top,new._record.left,new._record.bottom,new._record.right),'Source record bounds changed')
   for key,block in old.tagged_blocks.items():
    check(key in new.tagged_blocks and block.tobytes()==new.tagged_blocks[key].tobytes(),'Source tag changed')
   if not old.is_group(): check(old.topil().convert('RGBA').tobytes()==new.topil().convert('RGBA').tobytes(),'Source pixels changed')
   check(old.parent.name==new.parent.name,'Source parent changed')
 rgba=np.array(p.composite(force=True,apply_icc=False).convert('RGBA'),dtype=np.int32)
 alpha=rgba[:,:,3]
 white=(rgba[:,:,:3]*alpha[:,:,None]+255*(255-alpha[:,:,None])+127)//255
 planes=p._record.image_data.get_data(p._record.header)
 rgb=np.stack([np.frombuffer(x,np.uint8).reshape(p.height,p.width) for x in planes[:3]],axis=-1)
 check(np.max(np.abs(rgb.astype(int)-white))<=2,'Independent RGB composite differs')
 check(np.max(np.abs(np.frombuffer(planes[3],np.uint8).reshape(p.height,p.width).astype(int)-alpha))<=1,'Independent alpha composite differs')
report={'status':'PASS','assertions':count,'files':4}
(folder/'stage12_independent_verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
