"""Independent checks for PNG decoding and stage 11 PSD composition saves."""
from pathlib import Path
import json
import sys
import numpy as np
from PIL import Image
from psd_tools import PSDImage

folder=Path(sys.argv[1])
source=PSDImage.open(sys.argv[2])
checks=0

def check(value,message):
    global checks
    checks+=1
    if not value: raise AssertionError(message)

for name in ['素材ベース.png','追加パーツ.png','置換.png','palette.png','palette2.png','mono.png']:
    expected=Image.open(folder/name).convert('RGBA')
    actual=(folder/(name+'.rgba')).read_bytes()
    check(actual==expected.tobytes(),'PNG decoded bytes differ: '+name)

def find(psd,name):
    return next(l for l in psd.descendants() if l.name==name)

def pixels(layer,png):
    check(layer.topil().convert('RGBA').tobytes()==Image.open(folder/png).convert('RGBA').tobytes(),'Layer PNG pixels differ: '+layer.name)

for filename in ['png_workflow.psd','png_workflow_added.psd','png_workflow_replaced.psd','aiueo_png_added.psd','aiueo_png_replaced.psd']:
    psd=PSDImage.open(folder/filename)
    if filename.startswith('png_workflow'):
        check(psd.size==(32,24),'PNG canvas dimensions changed')
        part=find(psd,'*パーツ:flipxy'); check(part.bbox==(-2,3,7,9),'Original part placement changed')
        check(part.opacity==191,'Part opacity changed'); pixels(part,'置換.png')
        base=find(psd,'素材ベース'); pixels(base,'素材ベース.png')
        if filename=='png_workflow_added.psd':
            part=find(psd,'追加パーツ'); check(part.bbox==(11,8,18,13),'Added PNG placement'); pixels(part,'追加パーツ.png')
        if filename=='png_workflow_replaced.psd':
            part=find(psd,'追加パーツ'); check(part.bbox==(12,9,21,15),'Replaced PNG placement'); pixels(part,'置換.png')
    else:
        check(psd.image_resources.tobytes()==source.image_resources.tobytes(),'Source resources not preserved')
        check(psd._record.layer_and_mask_information.tagged_blocks.tobytes()==source._record.layer_and_mask_information.tagged_blocks.tobytes(),'Outer metadata not preserved')
        by_id={l.layer_id:l for l in psd.descendants()}
        ids=[l.layer_id for l in psd.descendants()]
        check(len(ids)==len(set(ids)),'Duplicate new layer ID')
        for original in source.descendants():
            layer=by_id[original.layer_id]
            check(layer.name==original.name,'Original layer name changed')
            check(layer.opacity==original.opacity and layer.visible==original.visible,'Original attributes changed')
            check(layer.bbox==original.bbox,'Original layer bounds changed')
            for key,block in original.tagged_blocks.items():
                check(key in layer.tagged_blocks and block.tobytes()==layer.tagged_blocks[key].tobytes(),'Original tag changed: '+str(key))
            if not original.is_group():
                check(layer.topil().convert('RGBA').tobytes()==original.topil().convert('RGBA').tobytes(),'Original layer pixels changed')
        part=find(psd,'!追加素材:flipy'); check(part.opacity==173,'Imported PNG opacity changed')
        if filename=='aiueo_png_added.psd':
            check(part.bbox==(5,6,12,11),'Real PSD added position'); pixels(part,'追加パーツ.png')
        else:
            check(part.bbox==(8,9,17,15),'Real PSD replacement position'); pixels(part,'置換.png')
    rgba=np.array(psd.composite(force=True,apply_icc=False).convert('RGBA'),dtype=np.int32)
    alpha=rgba[:,:,3]
    white=(rgba[:,:,:3]*alpha[:,:,None]+255*(255-alpha[:,:,None])+127)//255
    planes=psd._record.image_data.get_data(psd._record.header)
    merged=np.stack([np.frombuffer(plane,np.uint8).reshape(psd.height,psd.width) for plane in planes[:3]],axis=-1)
    check(np.max(np.abs(merged.astype(int)-white))<=2,'Independent composite differs: '+filename)
    check(np.max(np.abs(np.frombuffer(planes[3],np.uint8).reshape(psd.height,psd.width).astype(int)-alpha))<=1,'Merged alpha differs: '+filename)
report={'status':'PASS','assertions':checks,'files':5,'png_formats':6}
(folder/'stage11_independent_verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
