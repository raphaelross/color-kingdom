from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any
import json
import time
from collections import deque

import cv2
import numpy as np
from PIL import Image


@dataclass(frozen=True)
class SegmentationConfig:
    threshold: int = 185
    morph_kernel: int = 0
    morph_iterations: int = 1
    dilate_iterations: int = 0
    min_region_area_pixels: int = 250
    min_region_area_percent: float = 0.015
    connectivity: int = 8
    label_min_area_pixels: int = 1500
    huge_region_warn_percent: float = 35.0
    excessive_region_warn_count: int = 300
    narrow_aspect_ratio_warn: float = 0.08


@dataclass
class RegionRecord:
    componentLabel: int
    id: str
    classification: str
    mapColorRgba: list[int]
    areaPixels: int
    areaPercent: float
    bounds: dict[str, int]
    centroid: dict[str, float]
    touchesBorder: bool
    aspectRatio: float


@dataclass
class SegmentationArtifacts:
    source_rgb: np.ndarray
    grayscale: np.ndarray
    binary_raw: np.ndarray
    binary_repaired: np.ndarray
    exterior_mask: np.ndarray
    candidate_mask: np.ndarray
    labels: np.ndarray
    region_map_rgba: np.ndarray
    debug_overlay_bgr: np.ndarray
    labeled_overlay_bgr: np.ndarray


@dataclass
class SegmentationResult:
    metadata: dict[str, Any]
    artifacts: SegmentationArtifacts


def _load_image_rgb(image_path: Path) -> np.ndarray:
    with Image.open(image_path) as img:
        if img.mode in ("RGBA", "LA"):
            background = Image.new("RGBA", img.size, (255, 255, 255, 255))
            img = Image.alpha_composite(background, img.convert("RGBA")).convert("RGB")
        else:
            img = img.convert("RGB")
        arr = np.array(img, dtype=np.uint8)
    return arr


def _barrier_from_threshold(grayscale: np.ndarray, threshold: int) -> np.ndarray:
    # Barrier pixels are darker than threshold.
    return (grayscale <= threshold).astype(np.uint8)


def _apply_morphology(barrier_mask: np.ndarray, config: SegmentationConfig) -> np.ndarray:
    repaired = (barrier_mask.astype(np.uint8) * 255)
    if config.morph_kernel and config.morph_kernel > 1:
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (config.morph_kernel, config.morph_kernel))
        repaired = cv2.morphologyEx(repaired, cv2.MORPH_CLOSE, kernel, iterations=config.morph_iterations)
    if config.dilate_iterations and config.dilate_iterations > 0:
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        repaired = cv2.dilate(repaired, kernel, iterations=config.dilate_iterations)
    return (repaired > 0).astype(np.uint8)


def _flood_fill_exterior(open_mask: np.ndarray, connectivity: int) -> np.ndarray:
    h, w = open_mask.shape
    exterior = np.zeros((h, w), dtype=np.uint8)
    q: deque[tuple[int, int]] = deque()

    def maybe_enqueue(y: int, x: int) -> None:
        if open_mask[y, x] == 1 and exterior[y, x] == 0:
            exterior[y, x] = 1
            q.append((y, x))

    for x in range(w):
        maybe_enqueue(0, x)
        maybe_enqueue(h - 1, x)
    for y in range(h):
        maybe_enqueue(y, 0)
        maybe_enqueue(y, w - 1)

    if connectivity == 4:
        neighbors = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    else:
        neighbors = [
            (-1, 0),
            (1, 0),
            (0, -1),
            (0, 1),
            (-1, -1),
            (-1, 1),
            (1, -1),
            (1, 1),
        ]

    while q:
        y, x = q.popleft()
        for dy, dx in neighbors:
            ny, nx = y + dy, x + dx
            if ny < 0 or ny >= h or nx < 0 or nx >= w:
                continue
            if open_mask[ny, nx] == 1 and exterior[ny, nx] == 0:
                exterior[ny, nx] = 1
                q.append((ny, nx))

    return exterior


def _encode_region_color(index: int) -> list[int]:
    # Deterministic color generation for region-map and debug overlays.
    seed = (index * 2654435761) & 0xFFFFFFFF
    r = ((seed >> 16) & 0xFF) ^ 0x55
    g = ((seed >> 8) & 0xFF) ^ 0xAA
    b = (seed & 0xFF) ^ 0x33
    if r < 20 and g < 20 and b < 20:
        r = 40
    if r > 245 and g > 245 and b > 245:
        b = 180
    return [int(r), int(g), int(b), 255]


def _build_region_records(
    component_count: int,
    labels: np.ndarray,
    stats: np.ndarray,
    centroids: np.ndarray,
    image_shape: tuple[int, int],
    config: SegmentationConfig,
) -> tuple[list[RegionRecord], list[RegionRecord], list[dict[str, Any]]]:
    h, w = image_shape
    total_pixels = float(h * w)

    raw: list[dict[str, Any]] = []
    for label in range(1, component_count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        x = int(stats[label, cv2.CC_STAT_LEFT])
        y = int(stats[label, cv2.CC_STAT_TOP])
        bw = int(stats[label, cv2.CC_STAT_WIDTH])
        bh = int(stats[label, cv2.CC_STAT_HEIGHT])
        cx = float(centroids[label, 0])
        cy = float(centroids[label, 1])
        area_percent = (area / total_pixels) * 100.0
        touches_border = x == 0 or y == 0 or (x + bw) >= w or (y + bh) >= h
        aspect_ratio = (min(bw, bh) / max(bw, bh)) if max(bw, bh) > 0 else 0.0

        raw.append(
            {
                "componentLabel": label,
                "areaPixels": area,
                "areaPercent": area_percent,
                "bounds": {"x": x, "y": y, "width": bw, "height": bh},
                "centroid": {"x": cx, "y": cy},
                "touchesBorder": touches_border,
                "aspectRatio": aspect_ratio,
            }
        )

    # Deterministic ordering: centroid Y, then centroid X, then area descending, then component label.
    raw.sort(
        key=lambda r: (
            round(r["centroid"]["y"], 6),
            round(r["centroid"]["x"], 6),
            -r["areaPixels"],
            r["componentLabel"],
        )
    )

    accepted: list[RegionRecord] = []
    flagged: list[RegionRecord] = []

    for idx, item in enumerate(raw, start=1):
        area_ok = item["areaPixels"] >= config.min_region_area_pixels
        percent_ok = item["areaPercent"] >= config.min_region_area_percent
        classification = "ACCEPTED" if (area_ok and percent_ok) else "FLAGGED_TOO_SMALL"
        rid = f"region-{idx:03d}"
        color = _encode_region_color(idx)
        record = RegionRecord(
            componentLabel=int(item["componentLabel"]),
            id=rid,
            classification=classification,
            mapColorRgba=color,
            areaPixels=int(item["areaPixels"]),
            areaPercent=float(item["areaPercent"]),
            bounds=item["bounds"],
            centroid=item["centroid"],
            touchesBorder=bool(item["touchesBorder"]),
            aspectRatio=float(item["aspectRatio"]),
        )
        if classification == "ACCEPTED":
            accepted.append(record)
        else:
            flagged.append(record)

    return accepted, flagged, raw


def _render_region_map(
    labels: np.ndarray,
    accepted: list[RegionRecord],
    flagged: list[RegionRecord],
    barrier_mask: np.ndarray,
    exterior_mask: np.ndarray,
) -> np.ndarray:
    h, w = labels.shape
    out = np.zeros((h, w, 4), dtype=np.uint8)

    # Reserved values.
    barrier_color = np.array([0, 0, 0, 255], dtype=np.uint8)
    exterior_color = np.array([255, 255, 255, 0], dtype=np.uint8)

    out[exterior_mask == 1] = exterior_color
    out[barrier_mask == 1] = barrier_color

    records = accepted + flagged
    label_to_color = {r.componentLabel: np.array(r.mapColorRgba, dtype=np.uint8) for r in records}

    for label, color in label_to_color.items():
        out[labels == label] = color

    return out


def _render_debug_overlay(
    source_rgb: np.ndarray,
    barrier_mask: np.ndarray,
    labels: np.ndarray,
    accepted: list[RegionRecord],
    flagged: list[RegionRecord],
) -> tuple[np.ndarray, np.ndarray]:
    h, w, _ = source_rgb.shape
    base = np.full((h, w, 3), 255, dtype=np.uint8)
    colors = np.zeros_like(base)

    alpha_accepted = 0.62
    alpha_flagged = 0.5

    for rec in accepted:
        mask = labels == rec.componentLabel
        c = np.array(rec.mapColorRgba[:3], dtype=np.uint8)
        colors[mask] = c
        base[mask] = ((1.0 - alpha_accepted) * base[mask] + alpha_accepted * c).astype(np.uint8)

    for rec in flagged:
        mask = labels == rec.componentLabel
        c = np.array(rec.mapColorRgba[:3], dtype=np.uint8)
        colors[mask] = c
        base[mask] = ((1.0 - alpha_flagged) * base[mask] + alpha_flagged * c).astype(np.uint8)

    # Keep line art and barriers visible.
    base[barrier_mask == 1] = np.array([0, 0, 0], dtype=np.uint8)

    labeled = base.copy()
    for rec in accepted:
        if rec.areaPixels < 1:
            continue
        if rec.areaPixels < 500:
            continue
        x = int(round(rec.centroid["x"]))
        y = int(round(rec.centroid["y"]))
        x = max(0, min(w - 1, x))
        y = max(0, min(h - 1, y))
        cv2.putText(
            labeled,
            rec.id,
            (x, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.35,
            (30, 30, 30),
            1,
            cv2.LINE_AA,
        )

    return base, labeled


def segment_image_array(
    image_rgb: np.ndarray,
    source_path: Path,
    config: SegmentationConfig,
    schema_version: str = "1.0.0",
    variant_name: str | None = None,
    barrier_override: np.ndarray | None = None,
) -> SegmentationResult:
    if image_rgb.ndim != 3 or image_rgb.shape[2] != 3:
        raise ValueError("image_rgb must be an HxWx3 RGB array")

    start = time.perf_counter()

    h, w, _ = image_rgb.shape
    total_pixels = h * w
    grayscale = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2GRAY)

    binary_raw = _barrier_from_threshold(grayscale, config.threshold)
    binary_repaired = _apply_morphology(binary_raw, config)
    if barrier_override is not None:
        if barrier_override.shape != binary_repaired.shape:
            raise ValueError("barrier_override must match computed barrier mask shape")
        binary_repaired = (barrier_override > 0).astype(np.uint8)

    open_mask = (binary_repaired == 0).astype(np.uint8)
    exterior_mask = _flood_fill_exterior(open_mask, config.connectivity)

    candidate_mask = ((open_mask == 1) & (exterior_mask == 0)).astype(np.uint8)

    component_count, labels, stats, centroids = cv2.connectedComponentsWithStats(
        candidate_mask, connectivity=config.connectivity
    )

    accepted, flagged, raw_sorted = _build_region_records(
        component_count,
        labels,
        stats,
        centroids,
        (h, w),
        config,
    )

    region_map = _render_region_map(labels, accepted, flagged, binary_repaired, exterior_mask)
    debug_bgr, labeled_bgr = _render_debug_overlay(image_rgb, binary_repaired, labels, accepted, flagged)

    exterior_pixels = int(exterior_mask.sum())
    exterior_percent = (exterior_pixels / total_pixels) * 100.0

    warnings: list[dict[str, Any]] = []

    if len(raw_sorted) > config.excessive_region_warn_count:
        warnings.append(
            {
                "code": "EXCESSIVE_REGION_COUNT",
                "message": f"Detected {len(raw_sorted)} candidate regions; verify threshold and morphology.",
                "value": len(raw_sorted),
            }
        )

    if raw_sorted:
        largest = max(raw_sorted, key=lambda r: r["areaPixels"])
        if largest["areaPercent"] >= config.huge_region_warn_percent:
            warnings.append(
                {
                    "code": "HUGE_COMPONENT",
                    "message": "A very large non-exterior component was detected; likely leakage or merged zones.",
                    "value": round(float(largest["areaPercent"]), 4),
                }
            )

    border_touch_count = sum(1 for r in raw_sorted if r["touchesBorder"])
    if border_touch_count > 0:
        warnings.append(
            {
                "code": "BORDER_TOUCHING_COMPONENTS",
                "message": "Some non-exterior components touch image border; inspect for leakage.",
                "value": int(border_touch_count),
            }
        )

    narrow_count = sum(
        1
        for r in raw_sorted
        if r["aspectRatio"] < config.narrow_aspect_ratio_warn and r["areaPixels"] >= config.min_region_area_pixels
    )
    if narrow_count > 0:
        warnings.append(
            {
                "code": "NARROW_COMPONENTS",
                "message": "Detected narrow accepted components that may be artifacts.",
                "value": int(narrow_count),
            }
        )

    elapsed_ms = (time.perf_counter() - start) * 1000.0

    metadata = {
        "schemaVersion": schema_version,
        "variantName": variant_name,
        "source": {
            "filename": source_path.name,
            "path": str(source_path),
            "width": int(w),
            "height": int(h),
            "mode": "RGB",
            "totalPixels": int(total_pixels),
        },
        "settings": {
            "threshold": config.threshold,
            "morphology": {
                "kernel": config.morph_kernel,
                "iterations": config.morph_iterations,
                "dilateIterations": config.dilate_iterations,
            },
            "connectivity": config.connectivity,
            "minRegionAreaPixels": config.min_region_area_pixels,
            "minRegionAreaPercent": config.min_region_area_percent,
            "deterministicOrdering": "centroidY asc, centroidX asc, areaPixels desc, componentLabel asc",
        },
        "metrics": {
            "totalConnectedComponents": int(max(component_count - 1, 0)),
            "acceptedRegionCount": len(accepted),
            "flaggedTooSmallCount": len(flagged),
            "exterior": {
                "pixelCount": exterior_pixels,
                "percent": exterior_percent,
            },
            "runtimeMs": elapsed_ms,
        },
        "reservedMapColors": {
            "barrier": [0, 0, 0, 255],
            "exterior": [255, 255, 255, 0],
        },
        "warnings": warnings,
        "acceptedRegions": [asdict(r) for r in accepted],
        "flaggedTooSmallRegions": [asdict(r) for r in flagged],
    }

    artifacts = SegmentationArtifacts(
        source_rgb=image_rgb,
        grayscale=grayscale,
        binary_raw=binary_raw,
        binary_repaired=binary_repaired,
        exterior_mask=exterior_mask,
        candidate_mask=candidate_mask,
        labels=labels,
        region_map_rgba=region_map,
        debug_overlay_bgr=debug_bgr,
        labeled_overlay_bgr=labeled_bgr,
    )

    return SegmentationResult(metadata=metadata, artifacts=artifacts)


def segment_image_file(
    image_path: Path,
    config: SegmentationConfig,
    schema_version: str = "1.0.0",
    variant_name: str | None = None,
    barrier_override: np.ndarray | None = None,
) -> SegmentationResult:
    image_rgb = _load_image_rgb(image_path)
    return segment_image_array(
        image_rgb=image_rgb,
        source_path=image_path,
        config=config,
        schema_version=schema_version,
        variant_name=variant_name,
        barrier_override=barrier_override,
    )


def _save_u8_image(path: Path, arr: np.ndarray) -> None:
    if arr.dtype != np.uint8:
        arr = arr.astype(np.uint8)
    Image.fromarray(arr).save(path)


def write_artifacts(output_dir: Path, result: SegmentationResult) -> dict[str, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    art = result.artifacts

    grayscale_path = output_dir / "normalized_grayscale.png"
    binary_raw_path = output_dir / "binary_raw_barriers.png"
    binary_repaired_path = output_dir / "binary_repaired_barriers.png"
    exterior_path = output_dir / "exterior_mask.png"
    candidate_path = output_dir / "candidate_regions_mask.png"
    region_map_path = output_dir / "region_map.png"
    debug_path = output_dir / "regions_debug.png"
    labeled_path = output_dir / "regions_labeled.png"
    metadata_path = output_dir / "regions.json"

    _save_u8_image(grayscale_path, art.grayscale)
    _save_u8_image(binary_raw_path, np.where(art.binary_raw == 1, 0, 255).astype(np.uint8))
    _save_u8_image(binary_repaired_path, np.where(art.binary_repaired == 1, 0, 255).astype(np.uint8))
    _save_u8_image(exterior_path, np.where(art.exterior_mask == 1, 255, 0).astype(np.uint8))
    _save_u8_image(candidate_path, np.where(art.candidate_mask == 1, 255, 0).astype(np.uint8))
    _save_u8_image(region_map_path, art.region_map_rgba)

    # Convert RGB->BGR for cv2 write is not needed because we use PIL; keep output in RGB.
    _save_u8_image(debug_path, cv2.cvtColor(art.debug_overlay_bgr, cv2.COLOR_BGR2RGB))
    _save_u8_image(labeled_path, cv2.cvtColor(art.labeled_overlay_bgr, cv2.COLOR_BGR2RGB))

    with metadata_path.open("w", encoding="utf-8") as f:
        json.dump(result.metadata, f, indent=2, sort_keys=True)

    return {
        "grayscale": grayscale_path,
        "binary_raw": binary_raw_path,
        "binary_repaired": binary_repaired_path,
        "exterior_mask": exterior_path,
        "candidate_regions": candidate_path,
        "region_map": region_map_path,
        "regions_debug": debug_path,
        "regions_labeled": labeled_path,
        "metadata_json": metadata_path,
    }
