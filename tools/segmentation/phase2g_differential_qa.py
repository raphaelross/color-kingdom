from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageColor, ImageDraw, ImageFont


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        payload = json.load(fh)
    if not isinstance(payload, dict):
        raise ValueError(f"Expected JSON object at {path}")
    return payload


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Phase 2G Part 2A differential QA artifact generator")
    parser.add_argument(
        "--build-report",
        default=str(Path(__file__).resolve().parent / "output" / "part2_build_report.json"),
        help="Path to part2 build report JSON",
    )
    parser.add_argument(
        "--page-id",
        default="lovely-kitten-raster-poc",
        help="Page id to analyze",
    )
    return parser.parse_args()


def _color_to_tuple(raw: Any) -> tuple[int, int, int, int] | None:
    if not isinstance(raw, list) or len(raw) != 4:
        return None
    if not all(isinstance(v, int) for v in raw):
        return None
    return (raw[0], raw[1], raw[2], raw[3])


def _get_page(report: dict[str, Any], page_id: str) -> dict[str, Any]:
    pages = report.get("pages", [])
    if not isinstance(pages, list):
        raise ValueError("Build report has invalid pages list")
    for page in pages:
        if isinstance(page, dict) and page.get("pageId") == page_id:
            return page
    raise ValueError(f"Could not find page '{page_id}' in build report")


def _region_maps_from_metadata(metadata: dict[str, Any]) -> tuple[dict[str, tuple[int, int, int, int]], dict[tuple[int, int, int, int], list[str]]]:
    id_to_color: dict[str, tuple[int, int, int, int]] = {}
    color_to_ids: dict[tuple[int, int, int, int], list[str]] = {}
    for region in metadata.get("regions", []):
        if not isinstance(region, dict):
            continue
        region_id = region.get("regionId")
        color = _color_to_tuple(region.get("mapColorRgba"))
        if not isinstance(region_id, str) or color is None:
            continue
        id_to_color[region_id] = color
        color_to_ids.setdefault(color, []).append(region_id)
    return id_to_color, color_to_ids


def _bbox_from_mask(mask: list[bool], width: int, height: int) -> tuple[int, int, int, int] | None:
    min_x = width
    min_y = height
    max_x = -1
    max_y = -1
    any_on = False
    for y in range(height):
        row_start = y * width
        for x in range(width):
            if not mask[row_start + x]:
                continue
            any_on = True
            if x < min_x:
                min_x = x
            if y < min_y:
                min_y = y
            if x > max_x:
                max_x = x
            if y > max_y:
                max_y = y
    if not any_on:
        return None
    return (min_x, min_y, max_x, max_y)


def _centroid_from_mask(mask: list[bool], width: int, height: int) -> tuple[float, float] | None:
    count = 0
    sx = 0
    sy = 0
    for y in range(height):
        row_start = y * width
        for x in range(width):
            if mask[row_start + x]:
                count += 1
                sx += x
                sy += y
    if count == 0:
        return None
    return (sx / count, sy / count)


def _touches_border(mask: list[bool], width: int, height: int) -> bool:
    if width == 0 or height == 0:
        return False
    for x in range(width):
        if mask[x] or mask[(height - 1) * width + x]:
            return True
    for y in range(height):
        row_start = y * width
        if mask[row_start] or mask[row_start + width - 1]:
            return True
    return False


def _mask_overlap(a: list[bool], b: list[bool]) -> int:
    return sum(1 for av, bv in zip(a, b) if av and bv)


def _mask_union(a: list[bool], b: list[bool]) -> int:
    return sum(1 for av, bv in zip(a, b) if av or bv)


def _build_masks_by_region(
    map_img: Image.Image,
    id_to_color: dict[str, tuple[int, int, int, int]],
) -> dict[str, list[bool]]:
    rgba = map_img.convert("RGBA")
    pixels = list(rgba.getdata())
    out: dict[str, list[bool]] = {}
    for region_id, color in id_to_color.items():
        out[region_id] = [p == color for p in pixels]
    return out


def analyze_spatial_differential(
    production_masks: dict[str, list[bool]],
    candidate_masks: dict[str, list[bool]],
    width: int,
    height: int,
) -> dict[str, dict[str, Any]]:
    del width, height
    analysis: dict[str, dict[str, Any]] = {}
    for cid, cmask in candidate_masks.items():
        c_area = sum(1 for v in cmask if v)
        best_region = None
        best_overlap = 0
        best_iou = 0.0
        for pid, pmask in production_masks.items():
            overlap = _mask_overlap(cmask, pmask)
            if overlap == 0:
                continue
            union = _mask_union(cmask, pmask)
            iou = (overlap / union) if union else 0.0
            if overlap > best_overlap:
                best_overlap = overlap
                best_iou = iou
                best_region = pid

        represented = best_region is not None and best_overlap > 0
        full_containment = represented and best_overlap == c_area
        analysis[cid] = {
            "candidateArea": c_area,
            "nearestProductionRegion": best_region,
            "nearestProductionOverlapPixels": best_overlap,
            "nearestProductionIoU": best_iou,
            "representedByProductionSpatially": represented,
            "fullyContainedInProductionRegion": full_containment,
        }
    return analysis


def _paint_region_overlay(
    base: Image.Image,
    mask: list[bool],
    color: tuple[int, int, int],
    alpha: int,
) -> None:
    width, height = base.size
    overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    opx = overlay.load()
    idx = 0
    for y in range(height):
        for x in range(width):
            if mask[idx]:
                opx[x, y] = (color[0], color[1], color[2], alpha)
            idx += 1
    base.alpha_composite(overlay)


def _draw_number_label(
    draw: ImageDraw.ImageDraw,
    number_text: str,
    bbox: tuple[int, int, int, int] | None,
    centroid: tuple[float, float] | None,
    width: int,
    height: int,
) -> tuple[int, int]:
    font = ImageFont.load_default()
    if bbox is None or centroid is None:
        x = 10
        y = 10
        draw.text((x, y), number_text, fill=(220, 0, 0), font=font)
        return (x, y)

    min_x, min_y, max_x, max_y = bbox
    bw = max_x - min_x + 1
    bh = max_y - min_y + 1

    if bw >= 20 and bh >= 14:
        x = int(centroid[0])
        y = int(centroid[1])
        draw.text((x, y), number_text, fill=(220, 0, 0), font=font)
        return (x, y)

    # Small regions get outside labels with leader lines.
    anchor_x = min(width - 20, max(4, max_x + 8))
    anchor_y = min(height - 12, max(4, min_y - 4))
    draw.line([(int(centroid[0]), int(centroid[1])), (anchor_x, anchor_y)], fill=(220, 0, 0), width=1)
    draw.text((anchor_x, anchor_y), number_text, fill=(220, 0, 0), font=font)
    return (anchor_x, anchor_y)


def _create_contact_sheet(
    line_art: Image.Image,
    differences: list[dict[str, Any]],
    masks_by_id: dict[str, list[bool]],
    out_path: Path,
) -> None:
    cols = 4
    cell_w = 360
    cell_h = 260
    rows = (len(differences) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell_w, max(1, rows) * cell_h), "white")
    draw_sheet = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()

    for idx, item in enumerate(differences):
        col = idx % cols
        row = idx // cols
        ox = col * cell_w
        oy = row * cell_h

        region_id = str(item["candidateRegionId"])
        bbox = item.get("boundingBox")
        if not isinstance(bbox, dict):
            continue
        min_x = int(bbox["x"])
        min_y = int(bbox["y"])
        bw = int(bbox["width"])
        bh = int(bbox["height"])
        max_x = min_x + bw - 1
        max_y = min_y + bh - 1

        pad = 24
        cx0 = max(0, min_x - pad)
        cy0 = max(0, min_y - pad)
        cx1 = min(line_art.width, max_x + pad + 1)
        cy1 = min(line_art.height, max_y + pad + 1)

        crop = line_art.crop((cx0, cy0, cx1, cy1)).convert("RGBA")
        local_w, local_h = crop.size
        local_mask = masks_by_id.get(region_id)
        if local_mask is not None:
            overlay = Image.new("RGBA", (local_w, local_h), (0, 0, 0, 0))
            opx = overlay.load()
            for y in range(local_h):
                for x in range(local_w):
                    global_idx = (cy0 + y) * line_art.width + (cx0 + x)
                    if local_mask[global_idx]:
                        opx[x, y] = (255, 70, 60, 150)
            crop.alpha_composite(overlay)

        thumb = crop.convert("RGB")
        thumb.thumbnail((cell_w - 8, cell_h - 58))
        sheet.paste(thumb, (ox + 4, oy + 4))

        text = (
            f"#{item['differenceNumber']} {region_id}  "
            f"area={item['pixelArea']}  "
            f"w={item['width']} h={item['height']}"
        )
        draw_sheet.text((ox + 4, oy + cell_h - 48), text, fill=(0, 0, 0), font=font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)


def _stable_palette(n: int) -> list[tuple[int, int, int]]:
    base = [
        "#e63946",
        "#2a9d8f",
        "#ffb703",
        "#3a86ff",
        "#f4a261",
        "#6a4c93",
        "#264653",
        "#ef476f",
        "#118ab2",
        "#06d6a0",
    ]
    out: list[tuple[int, int, int]] = []
    for i in range(n):
        out.append(ImageColor.getrgb(base[i % len(base)]))
    return out


def generate_differential_qa(build_report_path: Path, page_id: str) -> dict[str, Any]:
    report = _load_json(build_report_path)
    page = _get_page(report, page_id)

    workspace = page.get("workspace", {})
    if not isinstance(workspace, dict):
        raise ValueError("Invalid workspace in page report")

    runtime_candidate_dir = Path(str(workspace.get("runtime_candidate", "")))
    segmentation_dir = Path(str(workspace.get("segmentation", "")))
    page_root = Path(str(workspace.get("root", "")))
    qa_dir = page_root / "differential_qa"
    qa_dir.mkdir(parents=True, exist_ok=True)

    candidate_metadata = _load_json(runtime_candidate_dir / "metadata_children_detailed.json")

    manifest_snapshot = _load_json(Path(str(workspace.get("manifest_snapshot", ""))))
    production_metadata_path = Path(str(manifest_snapshot.get("runtimeMetadataPath", "")))
    source_artwork_path = Path(str(manifest_snapshot.get("sourceArtworkPath", "")))
    production_metadata = _load_json(production_metadata_path)

    production_region_map = Path(str(manifest_snapshot.get("runtimeAssetDir", ""))) / "region_map.png"
    production_fill_map = Path(str(manifest_snapshot.get("runtimeAssetDir", ""))) / "region_fill_map.png"
    candidate_region_map = runtime_candidate_dir / "region_map.png"
    candidate_fill_map = runtime_candidate_dir / "region_fill_map.png"

    seg_regions_payload = _load_json(segmentation_dir / "regions.json")
    seg_regions = seg_regions_payload.get("acceptedRegions", [])
    seg_by_id: dict[str, dict[str, Any]] = {}
    if isinstance(seg_regions, list):
        for item in seg_regions:
            if isinstance(item, dict) and isinstance(item.get("id"), str):
                seg_by_id[str(item["id"])] = item

    prod_id_to_color, prod_color_to_ids = _region_maps_from_metadata(production_metadata)
    cand_id_to_color, cand_color_to_ids = _region_maps_from_metadata(candidate_metadata)

    prod_map_img = Image.open(production_region_map).convert("RGBA")
    cand_map_img = Image.open(candidate_region_map).convert("RGBA")
    line_art = Image.open(source_artwork_path).convert("RGBA")

    if prod_map_img.size != cand_map_img.size:
        raise ValueError("Production and candidate logical maps differ in dimensions")
    if line_art.size != cand_map_img.size:
        line_art = line_art.resize(cand_map_img.size)

    width, height = cand_map_img.size

    prod_masks = _build_masks_by_region(prod_map_img, prod_id_to_color)
    cand_masks = _build_masks_by_region(cand_map_img, cand_id_to_color)
    spatial = analyze_spatial_differential(prod_masks, cand_masks, width, height)

    prod_ids = set(prod_id_to_color.keys())
    cand_ids = set(cand_id_to_color.keys())
    extra_ids = sorted(cand_ids - prod_ids)
    missing_ids = sorted(prod_ids - cand_ids)

    # Requested differential set: candidate IDs not in production metadata set.
    differences: list[dict[str, Any]] = []
    for idx, region_id in enumerate(extra_ids, start=1):
        cmask = cand_masks.get(region_id, [False] * (width * height))
        area = sum(1 for v in cmask if v)
        bbox = _bbox_from_mask(cmask, width, height)
        centroid = _centroid_from_mask(cmask, width, height)

        flags: list[str] = []
        color = cand_id_to_color.get(region_id)
        if color is None:
            flags.append("SUSPECT:MISSING_MAP_COLOR")
        else:
            owners = cand_color_to_ids.get(color, [])
            if len(owners) > 1:
                flags.append("SUSPECT:DUPLICATE_CANDIDATE_COLOR_OWNERSHIP")
            if color in prod_color_to_ids:
                flags.append("SUSPECT:COLOR_ALREADY_OWNED_IN_PRODUCTION")

        if area == 0:
            flags.append("SUSPECT:ZERO_PIXEL_AREA")
        if area <= 3:
            flags.append("SUSPECT:EXTREMELY_TINY_COMPONENT")
        if bbox is not None:
            bw = bbox[2] - bbox[0] + 1
            bh = bbox[3] - bbox[1] + 1
            if bw == 1 or bh == 1:
                flags.append("SUSPECT:SINGLE_PIXEL_SLIVER_DIMENSION")
        else:
            bw = 0
            bh = 0

        if _touches_border(cmask, width, height):
            flags.append("SUSPECT:TOUCHES_IMAGE_BORDER")

        seg_info = seg_by_id.get(region_id, {})
        profiles = seg_info.get("profiles", {}) if isinstance(seg_info, dict) else {}
        detailed = profiles.get("childrenDetailed", {}) if isinstance(profiles, dict) else {}

        spatial_item = spatial.get(region_id, {})
        represented = bool(spatial_item.get("representedByProductionSpatially", False))
        if represented:
            flags.append("SUSPECT:SPATIALLY_REPRESENTED_IN_PRODUCTION")

        suggested = "Review as legitimate unless objective artifact evidence is present"
        if area == 0 or "SUSPECT:DUPLICATE_CANDIDATE_COLOR_OWNERSHIP" in flags:
            suggested = "Review metadata/map ownership consistency first"

        diff_item: dict[str, Any] = {
            "differenceNumber": idx,
            "candidateRegionId": region_id,
            "pixelArea": area,
            "boundingBox": (
                {
                    "x": bbox[0],
                    "y": bbox[1],
                    "width": bw,
                    "height": bh,
                }
                if bbox is not None
                else None
            ),
            "centroid": (
                {"x": centroid[0], "y": centroid[1]}
                if centroid is not None
                else None
            ),
            "width": bw,
            "height": bh,
            "nearestProductionRegion": spatial_item.get("nearestProductionRegion"),
            "overlapPixelsWithNearestProduction": spatial_item.get("nearestProductionOverlapPixels", 0),
            "nearestProductionIoU": spatial_item.get("nearestProductionIoU", 0.0),
            "representedByProductionSpatially": represented,
            "fullyContainedInProductionRegion": bool(spatial_item.get("fullyContainedInProductionRegion", False)),
            "fullyEnclosedTopology": (not bool(seg_info.get("touchesBorder", False))) if isinstance(seg_info, dict) else None,
            "classificationState": {
                "childrenDetailedIncluded": detailed.get("included") if isinstance(detailed, dict) else None,
                "childrenDetailedReasons": detailed.get("reasons") if isinstance(detailed, dict) else [],
            },
            "technicalFlags": sorted(set(flags)),
            "suggestedHumanReview": suggested,
        }
        differences.append(diff_item)

    # 01 candidate full color (existing artifact copy)
    candidate_full_color_src = segmentation_dir / "regions_children_detailed_qa_fullcolor.png"
    candidate_full_color_out = qa_dir / "01_candidate_175_full_color.png"
    if candidate_full_color_src.exists():
        Image.open(candidate_full_color_src).save(candidate_full_color_out)
    else:
        # fallback reconstruct from map + line art
        img = Image.new("RGBA", (width, height), (255, 255, 255, 255))
        palette = _stable_palette(len(cand_ids))
        draw_map = ImageDraw.Draw(img)
        for i, region_id in enumerate(sorted(cand_ids)):
            mask = cand_masks.get(region_id)
            if mask is None:
                continue
            color = palette[i]
            _paint_region_overlay(img, mask, color, 180)
        img.alpha_composite(line_art)
        img.convert("RGB").save(candidate_full_color_out)

    # 02 production full color (reconstructed deterministically)
    production_full_color_out = qa_dir / "02_production_147_full_color.png"
    prod_full = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    prod_palette = _stable_palette(len(prod_ids))
    for i, region_id in enumerate(sorted(prod_ids)):
        mask = prod_masks.get(region_id)
        if mask is None:
            continue
        _paint_region_overlay(prod_full, mask, prod_palette[i], 170)
    prod_full.alpha_composite(line_art)
    prod_full.convert("RGB").save(production_full_color_out)

    # 03 additional-only overlay on line art
    additional_only_out = qa_dir / "03_additional_28_only.png"
    add_only = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    add_only.alpha_composite(line_art)
    add_palette = _stable_palette(max(1, len(differences)))
    for i, diff in enumerate(differences):
        rid = str(diff["candidateRegionId"])
        mask = cand_masks.get(rid)
        if mask is None:
            continue
        _paint_region_overlay(add_only, mask, add_palette[i], 180)
    add_only.alpha_composite(line_art)
    add_only.convert("RGB").save(additional_only_out)

    # 04 numbered additional regions
    numbered_out = qa_dir / "04_additional_28_numbered.png"
    numbered = add_only.copy()
    draw_num = ImageDraw.Draw(numbered)
    for diff in differences:
        rid = str(diff["candidateRegionId"])
        mask = cand_masks.get(rid)
        if mask is None:
            continue
        bbox_info = diff.get("boundingBox")
        centroid_info = diff.get("centroid")
        bbox_tuple = None
        centroid_tuple = None
        if isinstance(bbox_info, dict):
            bx = int(bbox_info["x"])
            by = int(bbox_info["y"])
            bw = int(bbox_info["width"])
            bh = int(bbox_info["height"])
            bbox_tuple = (bx, by, bx + bw - 1, by + bh - 1)
        if isinstance(centroid_info, dict):
            centroid_tuple = (float(centroid_info["x"]), float(centroid_info["y"]))
        _draw_number_label(draw_num, str(diff["differenceNumber"]), bbox_tuple, centroid_tuple, width, height)
    numbered.convert("RGB").save(numbered_out)

    # 05 contact sheet
    contact_out = qa_dir / "05_additional_regions_contact_sheet.png"
    _create_contact_sheet(line_art, differences, cand_masks, contact_out)

    comparison_to_production = page.get("comparisonToProduction", {})

    summary = {
        "pageId": page_id,
        "production": {
            "metadataPath": str(production_metadata_path),
            "logicalMapPath": str(production_region_map),
            "visualFillMapPath": str(production_fill_map),
            "regionCount": int(production_metadata.get("regionCount", 0)),
        },
        "candidate": {
            "metadataPath": str(runtime_candidate_dir / "metadata_children_detailed.json"),
            "logicalMapPath": str(candidate_region_map),
            "visualFillMapPath": str(candidate_fill_map),
            "regionCount": int(candidate_metadata.get("regionCount", 0)),
            "buildId": page.get("buildId"),
        },
        "difference": {
            "extraCandidateRegionIds": extra_ids,
            "missingCandidateRegionIds": missing_ids,
            "extraCountById": len(extra_ids),
            "missingCountById": len(missing_ids),
            "spatiallyUnrepresentedCandidateIds": [
                d["candidateRegionId"]
                for d in differences
                if not bool(d.get("representedByProductionSpatially", False))
            ],
            "spatiallyRepresentedCandidateIds": [
                d["candidateRegionId"]
                for d in differences
                if bool(d.get("representedByProductionSpatially", False))
            ],
        },
        "productionParity": (
            "MATCH"
            if comparison_to_production.get("metadataRegionSet", {}).get("status") == "MATCH"
            else "DIFFER_REVIEW_REQUIRED"
        ),
        "comparisonFromBuild": comparison_to_production,
        "additionalRegions": differences,
        "qaArtifacts": {
            "candidate175FullColor": str(candidate_full_color_out),
            "production147FullColor": str(production_full_color_out),
            "additionalOnly": str(additional_only_out),
            "additionalNumbered": str(numbered_out),
            "additionalContactSheet": str(contact_out),
        },
        "notes": [
            "Do not auto-reject small regions; inspect visually with zoom sheets.",
            "Technical flags are suspect signals only unless objectively proven invalid.",
        ],
    }

    out_report = qa_dir / "additional_regions_report.json"
    with out_report.open("w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
        fh.write("\n")

    return summary


def main() -> int:
    args = _parse_args()
    summary = generate_differential_qa(build_report_path=Path(args.build_report).resolve(), page_id=args.page_id)
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
