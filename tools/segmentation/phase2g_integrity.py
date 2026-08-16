from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from PIL import Image

from phase2g_models import CheckResult, CheckSeverity, SegmentationPageManifest


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        payload = json.load(fh)
    if not isinstance(payload, dict):
        raise ValueError(f"Expected JSON object at {path}")
    return payload


def _rgba_key(rgba: list[int]) -> tuple[int, int, int, int]:
    return (int(rgba[0]), int(rgba[1]), int(rgba[2]), int(rgba[3]))


def _pixel_counts_by_color(image_path: Path) -> tuple[dict[tuple[int, int, int, int], int], tuple[int, int]]:
    with Image.open(image_path) as img:
        rgba = img.convert("RGBA")
        size = rgba.size
        raw = rgba.tobytes()
        counts: dict[tuple[int, int, int, int], int] = {}
        for i in range(0, len(raw), 4):
            key = (int(raw[i]), int(raw[i + 1]), int(raw[i + 2]), int(raw[i + 3]))
            counts[key] = counts.get(key, 0) + 1
    return counts, size


def run_integrity_validation(manifest: SegmentationPageManifest) -> list[CheckResult]:
    checks: list[CheckResult] = []

    if not manifest.runtime_metadata_path.exists() or not (manifest.segmentation_output_dir / "regions.json").exists():
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="INTEGRITY_PREREQUISITES_MISSING",
                message="Integrity requires both runtime metadata and segmentation regions.json",
                context={
                    "runtimeMetadataExists": manifest.runtime_metadata_path.exists(),
                    "regionsJsonExists": (manifest.segmentation_output_dir / "regions.json").exists(),
                },
            )
        )
        return checks

    runtime = _load_json(manifest.runtime_metadata_path)
    segmentation = _load_json(manifest.segmentation_output_dir / "regions.json")

    runtime_regions = runtime.get("regions")
    if not isinstance(runtime_regions, list):
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="RUNTIME_REGIONS_INVALID",
                message="Runtime metadata missing regions list",
            )
        )
        return checks

    runtime_region_ids = {
        r.get("regionId")
        for r in runtime_regions
        if isinstance(r, dict) and isinstance(r.get("regionId"), str)
    }

    runtime_region_color_map: dict[str, list[int]] = {}
    duplicate_runtime_region_ids: set[str] = set()
    duplicate_runtime_colors: set[tuple[int, int, int, int]] = set()
    seen_runtime_colors: set[tuple[int, int, int, int]] = set()
    for region in runtime_regions:
        if not isinstance(region, dict):
            continue
        region_id = region.get("regionId")
        color = region.get("mapColorRgba")
        if not isinstance(region_id, str):
            continue
        if region_id in runtime_region_color_map:
            duplicate_runtime_region_ids.add(region_id)
        if not (
            isinstance(color, list)
            and len(color) == 4
            and all(isinstance(v, int) and 0 <= v <= 255 for v in color)
        ):
            continue
        runtime_region_color_map[region_id] = color
        color_key = _rgba_key(color)
        if color_key in seen_runtime_colors:
            duplicate_runtime_colors.add(color_key)
        seen_runtime_colors.add(color_key)

    if duplicate_runtime_region_ids:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="RUNTIME_DUPLICATE_REGION_IDS",
                message="Runtime metadata contains duplicate regionId values",
                context={"duplicates": sorted(duplicate_runtime_region_ids)},
            )
        )
    if duplicate_runtime_colors:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="RUNTIME_DUPLICATE_REGION_COLORS",
                message="Runtime metadata contains duplicate mapColorRgba values",
                context={"duplicateColors": [list(c) for c in sorted(duplicate_runtime_colors)]},
            )
        )

    accepted = segmentation.get("acceptedRegions")
    if not isinstance(accepted, list):
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="SEGMENTATION_ACCEPTED_INVALID",
                message="Segmentation regions.json missing acceptedRegions",
            )
        )
        return checks

    approved_ids: set[str] = set()
    for region in accepted:
        if not isinstance(region, dict):
            continue
        region_id = region.get("id")
        profiles = region.get("profiles")
        if not isinstance(region_id, str) or not isinstance(profiles, dict):
            continue
        detailed = profiles.get("childrenDetailed")
        if isinstance(detailed, dict) and bool(detailed.get("included")):
            approved_ids.add(region_id)

    if not approved_ids:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="NO_APPROVED_CHILDREN_DETAILED_REGIONS",
                message="No approved CHILDREN_DETAILED regions found in segmentation metadata",
            )
        )
        return checks

    extra_runtime = sorted(runtime_region_ids - approved_ids)
    missing_runtime = sorted(approved_ids - runtime_region_ids)

    if extra_runtime or missing_runtime:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="RUNTIME_REGION_SET_MISMATCH",
                message="Runtime region ids do not match approved CHILDREN_DETAILED region ids",
                context={
                    "extraRuntimeIds": extra_runtime,
                    "missingRuntimeIds": missing_runtime,
                },
            )
        )
    else:
        checks.append(
            CheckResult(
                severity=CheckSeverity.PASS,
                code="RUNTIME_REGION_SET_MATCH",
                message="Runtime region ids match approved CHILDREN_DETAILED region ids",
                context={"regionCount": len(runtime_region_ids)},
            )
        )

    runtime_region_count = runtime.get("regionCount")
    if runtime_region_count != len(runtime_region_ids):
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="RUNTIME_REGION_COUNT_MISMATCH",
                message="runtime metadata regionCount does not match runtime regions length",
                context={
                    "regionCountField": runtime_region_count,
                    "regionsLength": len(runtime_region_ids),
                },
            )
        )
    else:
        checks.append(
            CheckResult(
                severity=CheckSeverity.PASS,
                code="RUNTIME_REGION_COUNT_MATCH",
                message="runtime metadata regionCount matches runtime regions length",
                context={"regionCount": runtime_region_count},
            )
        )

    expected_fill_path = f"{manifest.asset_base_path}/region_fill_map.png"
    expected_map_path = f"{manifest.asset_base_path}/region_map.png"
    checks.append(
        CheckResult(
            severity=(
                CheckSeverity.PASS
                if runtime.get("regionMapAssetPath") == expected_map_path
                and runtime.get("regionFillMapAssetPath") == expected_fill_path
                else CheckSeverity.WARN
            ),
            code="RUNTIME_ASSET_PATHS_EXPECTED",
            message="Runtime metadata asset paths checked against manifest asset base path",
            context={
                "expectedRegionMap": expected_map_path,
                "actualRegionMap": runtime.get("regionMapAssetPath"),
                "expectedRegionFillMap": expected_fill_path,
                "actualRegionFillMap": runtime.get("regionFillMapAssetPath"),
            },
        )
    )

    logical_map_path = manifest.runtime_asset_dir / "region_map.png"
    fill_map_path = manifest.runtime_asset_dir / "region_fill_map.png"
    if not logical_map_path.exists() or not fill_map_path.exists():
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="RUNTIME_MAPS_MISSING",
                message="Logical and fill maps are required for integrity map validation",
                context={
                    "logicalMapExists": logical_map_path.exists(),
                    "fillMapExists": fill_map_path.exists(),
                },
            )
        )
        return checks

    try:
        logical_counts, logical_size = _pixel_counts_by_color(logical_map_path)
        fill_counts, fill_size = _pixel_counts_by_color(fill_map_path)
    except Exception as error:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="RUNTIME_MAP_READ_FAILED",
                message=f"Failed reading runtime maps: {error}",
                context={
                    "logicalMap": str(logical_map_path),
                    "fillMap": str(fill_map_path),
                },
            )
        )
        return checks

    if logical_size != fill_size:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="RUNTIME_MAP_DIMENSION_MISMATCH",
                message="Logical map and fill map dimensions differ",
                context={"logicalSize": logical_size, "fillSize": fill_size},
            )
        )

    zero_pixel_logical: list[str] = []
    zero_pixel_fill: list[str] = []
    for region_id, rgba in sorted(runtime_region_color_map.items()):
        key = _rgba_key(rgba)
        logical_pixels = logical_counts.get(key, 0)
        fill_pixels = fill_counts.get(key, 0)
        if logical_pixels <= 0:
            zero_pixel_logical.append(region_id)
        if fill_pixels <= 0:
            zero_pixel_fill.append(region_id)

    if zero_pixel_logical:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="LOGICAL_MAP_ZERO_PIXEL_REGIONS",
                message="Metadata regions missing from logical region map",
                context={"regionIds": zero_pixel_logical},
            )
        )
    else:
        checks.append(
            CheckResult(
                severity=CheckSeverity.PASS,
                code="LOGICAL_MAP_ALL_METADATA_REGIONS_PRESENT",
                message="All metadata regions have logical map coverage",
                context={"regionCount": len(runtime_region_color_map)},
            )
        )

    if zero_pixel_fill:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="FILL_MAP_ZERO_PIXEL_REGIONS",
                message="Logical regions missing from visual fill map",
                context={"regionIds": zero_pixel_fill},
            )
        )
    else:
        checks.append(
            CheckResult(
                severity=CheckSeverity.PASS,
                code="FILL_MAP_ALL_METADATA_REGIONS_PRESENT",
                message="All metadata regions have visual fill map coverage",
                context={"regionCount": len(runtime_region_color_map)},
            )
        )

    return checks
