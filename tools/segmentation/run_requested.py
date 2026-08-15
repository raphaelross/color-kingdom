from pathlib import Path
import segmentation_pipeline as sp
config=sp.SegmentationConfig(min_region_area_pixels=250, min_region_area_percent=0.015)
result=sp.segment_image_file(Path(r'c:/Users/rross/color_kingdom/assets/source_artwork/animals/cheerful_baby_panda_master.png'), config)
print(type(result))
print(result)
print(vars(result))
