#!/usr/bin/env python3
"""Export app-ready raster assets for raster-region coloring pages.

This script reads the approved Phase 2C metadata, selects CHILDREN_DETAILED
regions, and exports deterministic runtime artifacts for Flutter.
"""

from __future__ import annotations

import argparse
from array import array
import json
import re
import shutil
import time
from pathlib import Path
from typing import Any

from PIL import Image


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object at {path}")
    return data


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)
        fh.write("\n")


def _copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def _encode_color_key(r: int, g: int, b: int, a: int) -> int:
    return ((r & 0xFF) << 24) | ((g & 0xFF) << 16) | ((b & 0xFF) << 8) | (a & 0xFF)


def _neighbor_indices(index: int, width: int, height: int) -> list[int]:
    x = index % width
    y = index // width
    indices: list[int] = []
    for dy in (-1, 0, 1):
        ny = y + dy
        if ny < 0 or ny >= height:
            continue
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            nx = x + dx
            if nx < 0 or nx >= width:
                continue
            indices.append(ny * width + nx)
    return indices


def _adjacent_logical_owners(index: int, owners: array, width: int, height: int) -> set[int]:
    adjacent: set[int] = set()
    for neighbor in _neighbor_indices(index, width, height):
        owner = owners[neighbor]
        if owner >= 0:
            adjacent.add(owner)
    return adjacent


def _build_line_band_mask(
    foreground_rgba: bytes,
    width: int,
    height: int,
    radius: int,
) -> list[bool]:
    pixel_count = width * height
    line_pixels = [False] * pixel_count
    for i in range(pixel_count):
        if foreground_rgba[(i * 4) + 3] > 0:
            line_pixels[i] = True

    if radius <= 0:
        return line_pixels

    line_band = line_pixels.copy()
    for i, is_line in enumerate(line_pixels):
        if not is_line:
            continue
        x = i % width
        y = i // width
        for dy in range(-radius, radius + 1):
            ny = y + dy
            if ny < 0 or ny >= height:
                continue
            for dx in range(-radius, radius + 1):
                nx = x + dx
                if nx < 0 or nx >= width:
                    continue
                line_band[(ny * width) + nx] = True

    return line_band


def _build_logical_owner_map(
    region_map_rgba: bytes,
    width: int,
    height: int,
    region_entries: list[dict[str, Any]],
) -> array:
    color_to_region_index: dict[int, int] = {}
    for idx, entry in enumerate(region_entries):
        rgba = entry["mapColorRgba"]
        color_to_region_index[_encode_color_key(rgba[0], rgba[1], rgba[2], rgba[3])] = idx

    owners = array("i", [-1] * (width * height))
    for i in range(width * height):
        offset = i * 4
        key = _encode_color_key(
            region_map_rgba[offset],
            region_map_rgba[offset + 1],
            region_map_rgba[offset + 2],
            region_map_rgba[offset + 3],
        )
        owner = color_to_region_index.get(key)
        if owner is not None:
            owners[i] = owner
    return owners


def _expand_visual_fill_maps(
    logical_owners: array,
    eligible_mask: list[bool],
    width: int,
    height: int,
    max_expansion_px: int,
) -> tuple[dict[int, array], dict[int, dict[str, int]]]:
    variants: dict[int, array] = {0: array("i", logical_owners)}
    stats: dict[int, dict[str, int]] = {
        0: {
            "ambiguousPixels": 0,
            "reachedPixels": 0,
            "claimedPixels": 0,
        },
    }

    frontier: dict[int, set[int]] = {}
    for index, owner in enumerate(logical_owners):
        if owner < 0:
            continue
        for neighbor in _neighbor_indices(index, width, height):
            if logical_owners[neighbor] >= 0 or not eligible_mask[neighbor]:
                continue
            bucket = frontier.setdefault(neighbor, set())
            bucket.add(owner)

    reached_distance = array("H", [0] * (width * height))
    ambiguous_marker = array("b", [0] * (width * height))
    expanded_owners = array("i", logical_owners)

    cumulative_ambiguous = 0
    cumulative_reached = 0
    cumulative_claimed = 0
    current = frontier

    for distance in range(1, max_expansion_px + 1):
        if not current:
            variants[distance] = array("i", expanded_owners)
            stats[distance] = {
                "ambiguousPixels": cumulative_ambiguous,
                "reachedPixels": cumulative_reached,
                "claimedPixels": cumulative_claimed,
            }
            continue

        next_frontier: dict[int, set[int]] = {}
        unique_pixels: list[tuple[int, int]] = []

        for pixel, owners in current.items():
            existing_distance = reached_distance[pixel]
            if existing_distance != 0 and existing_distance < distance:
                continue

            if existing_distance == 0:
                reached_distance[pixel] = distance
                cumulative_reached += 1

            if len(owners) != 1:
                if ambiguous_marker[pixel] == 0:
                    ambiguous_marker[pixel] = 1
                    cumulative_ambiguous += 1
                continue

            owner = next(iter(owners))
            if expanded_owners[pixel] == -1:
                expanded_owners[pixel] = owner
                cumulative_claimed += 1
            if expanded_owners[pixel] == owner:
                unique_pixels.append((pixel, owner))

        if distance < max_expansion_px:
            for pixel, owner in unique_pixels:
                for neighbor in _neighbor_indices(pixel, width, height):
                    if logical_owners[neighbor] >= 0 or not eligible_mask[neighbor]:
                        continue

                    existing_distance = reached_distance[neighbor]
                    if existing_distance != 0 and existing_distance < distance + 1:
                        continue

                    bucket = next_frontier.setdefault(neighbor, set())
                    bucket.add(owner)

        variants[distance] = array("i", expanded_owners)
        stats[distance] = {
            "ambiguousPixels": cumulative_ambiguous,
            "reachedPixels": cumulative_reached,
            "claimedPixels": cumulative_claimed,
        }
        current = next_frontier

    return variants, stats


def _build_deterministic_palette(region_count: int) -> list[tuple[int, int, int, int]]:
    palette: list[tuple[int, int, int, int]] = []
    for index in range(region_count):
        # Deterministic strong colors spread around hue wheel.
        seed = (index * 137) % 360
        sector = seed // 60
        frac = (seed % 60) / 60.0

        v = 240
        p = 60
        q = int(v * (1 - frac))
        t = int(v * frac)

        if sector == 0:
            rgb = (v, t, p)
        elif sector == 1:
            rgb = (q, v, p)
        elif sector == 2:
            rgb = (p, v, t)
        elif sector == 3:
            rgb = (p, q, v)
        elif sector == 4:
            rgb = (t, p, v)
        else:
            rgb = (v, p, q)

        palette.append((rgb[0], rgb[1], rgb[2], 255))
    return palette


def _owners_to_region_map_rgba(
    owners: array,
    region_entries: list[dict[str, Any]],
) -> bytes:
    rgba = bytearray(len(owners) * 4)
    for i, owner in enumerate(owners):
        offset = i * 4
        if owner < 0:
            rgba[offset + 0] = 0
            rgba[offset + 1] = 0
            rgba[offset + 2] = 0
            rgba[offset + 3] = 0
            continue

        color = region_entries[owner]["mapColorRgba"]
        rgba[offset + 0] = color[0]
        rgba[offset + 1] = color[1]
        rgba[offset + 2] = color[2]
        rgba[offset + 3] = color[3]

    return bytes(rgba)


def _owners_to_preview_rgba(
    owners: array,
    palette: list[tuple[int, int, int, int]],
) -> bytes:
    rgba = bytearray(len(owners) * 4)
    for i, owner in enumerate(owners):
        offset = i * 4
        if owner < 0:
            rgba[offset + 0] = 255
            rgba[offset + 1] = 255
            rgba[offset + 2] = 255
            rgba[offset + 3] = 255
            continue

        color = palette[owner]
        rgba[offset + 0] = color[0]
        rgba[offset + 1] = color[1]
        rgba[offset + 2] = color[2]
        rgba[offset + 3] = color[3]

    return bytes(rgba)


def _count_bleed_risk_pixels(
    logical_owners: array,
    variant_owners: array,
    width: int,
    height: int,
) -> int:
    risky = 0
    for i, owner in enumerate(variant_owners):
        if owner < 0 or logical_owners[i] >= 0:
            continue
        adjacent = _adjacent_logical_owners(i, logical_owners, width, height)
        if len(adjacent) > 1:
            risky += 1
    return risky


def _build_halo_candidate_mask(
    logical_owners: array,
    line_band_mask: list[bool],
    foreground_rgba: bytes,
    width: int,
    height: int,
) -> list[bool]:
    halo_mask = [False] * (width * height)
    for i, owner in enumerate(logical_owners):
        if owner >= 0:
            continue
        if not _adjacent_logical_owners(i, logical_owners, width, height):
            continue

        offset = i * 4
        r = foreground_rgba[offset]
        g = foreground_rgba[offset + 1]
        b = foreground_rgba[offset + 2]
        a = foreground_rgba[offset + 3]
        brightness = (int(r) + int(g) + int(b)) / 3.0

        is_transparent_gap = a == 0 and line_band_mask[i]
        is_bright_foreground_fringe = a > 0 and brightness >= 170.0
        if is_transparent_gap or is_bright_foreground_fringe:
            halo_mask[i] = True
    return halo_mask


def _count_unresolved_halo_pixels(
    halo_mask: list[bool],
    variant_owners: array,
) -> int:
    unresolved = 0
    for i, is_halo in enumerate(halo_mask):
        if is_halo and variant_owners[i] < 0:
            unresolved += 1
    return unresolved


def _select_representative_halo_samples(
    logical_owners: array,
    line_band_mask: list[bool],
    foreground_rgba: bytes,
    width: int,
    height: int,
) -> list[dict[str, Any]]:
    # Approximate semantic areas: face/body center, tail side, lower paw/heart band.
    regions = [
        ("face_body_edge", 260, 240, 860, 760),
        ("tail_edge", 820, 430, 1120, 1120),
        ("paw_heart_edge", 280, 760, 860, 1330),
    ]

    samples: list[dict[str, Any]] = []
    for label, x0, y0, x1, y1 in regions:
        found: dict[str, Any] | None = None
        for y in range(y0, min(y1, height)):
            for x in range(x0, min(x1, width)):
                i = y * width + x
                if logical_owners[i] >= 0 or not line_band_mask[i]:
                    continue
                adjacent = sorted(_adjacent_logical_owners(i, logical_owners, width, height))
                if not adjacent:
                    continue

                r = foreground_rgba[i * 4]
                g = foreground_rgba[(i * 4) + 1]
                b = foreground_rgba[(i * 4) + 2]
                alpha = foreground_rgba[(i * 4) + 3]
                brightness = (int(r) + int(g) + int(b)) / 3.0
                is_transparent_gap = alpha == 0
                is_bright_foreground_fringe = alpha > 0 and brightness >= 170.0
                if not is_transparent_gap and not is_bright_foreground_fringe:
                    continue

                classification = "C" if is_transparent_gap else "B"

                found = {
                    "label": label,
                    "x": x,
                    "y": y,
                    "classification": classification,
                    "logicalOwner": None,
                    "foregroundRgba": [r, g, b, alpha],
                    "adjacentLogicalRegionIndexes": adjacent,
                }
                break
            if found is not None:
                break

        if found is not None:
            samples.append(found)

    return samples


def _build_difference_overlay(
    logical_owners: array,
    expanded_owners: array,
    width: int,
    height: int,
) -> bytes:
    rgba = bytearray(width * height * 4)
    for i in range(width * height):
        offset = i * 4
        if logical_owners[i] < 0 and expanded_owners[i] >= 0:
            rgba[offset + 0] = 255
            rgba[offset + 1] = 0
            rgba[offset + 2] = 0
            rgba[offset + 3] = 255
        else:
            rgba[offset + 0] = 0
            rgba[offset + 1] = 0
            rgba[offset + 2] = 0
            rgba[offset + 3] = 0
    return bytes(rgba)


def _save_rgba_image(path: Path, rgba: bytes, width: int, height: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.frombytes("RGBA", (width, height), rgba)
    image.save(path)


def _save_composed_preview(
    path: Path,
    owners: array,
    palette: list[tuple[int, int, int, int]],
    foreground_image: Image.Image,
    width: int,
    height: int,
) -> None:
    fill_rgba = _owners_to_preview_rgba(owners, palette)
    fill_image = Image.frombytes("RGBA", (width, height), fill_rgba)
    composed = Image.alpha_composite(fill_image, foreground_image)
    path.parent.mkdir(parents=True, exist_ok=True)
    composed.save(path)


def _build_visual_fill_assets(
    region_map_path: Path,
    line_art_foreground_path: Path,
    region_entries: list[dict[str, Any]],
    max_expansion_px: int,
    preferred_expansion_px: int,
    qa_dir: Path,
    runtime_fill_map_path: Path,
) -> dict[str, Any]:
    started = time.perf_counter()

    region_map_image = Image.open(region_map_path).convert("RGBA")
    width, height = region_map_image.size
    region_map_rgba = region_map_image.tobytes()

    line_foreground_image = Image.open(line_art_foreground_path).convert("RGBA")
    if line_foreground_image.size != (width, height):
        raise ValueError("Foreground and region map dimensions do not match")
    line_foreground_rgba = line_foreground_image.tobytes()

    logical_owners = _build_logical_owner_map(
        region_map_rgba=region_map_rgba,
        width=width,
        height=height,
        region_entries=region_entries,
    )

    line_band_radius_px = 1
    line_band_mask = _build_line_band_mask(
        foreground_rgba=line_foreground_rgba,
        width=width,
        height=height,
        radius=line_band_radius_px,
    )

    variants, raw_stats = _expand_visual_fill_maps(
        logical_owners=logical_owners,
        eligible_mask=line_band_mask,
        width=width,
        height=height,
        max_expansion_px=max_expansion_px,
    )

    for expansion in range(0, max_expansion_px + 1):
        if expansion not in variants:
            variants[expansion] = array("i", variants[max(variants.keys())])
            raw_stats[expansion] = dict(raw_stats[max(raw_stats.keys())])

    halo_mask = _build_halo_candidate_mask(
        logical_owners=logical_owners,
        line_band_mask=line_band_mask,
        foreground_rgba=line_foreground_rgba,
        width=width,
        height=height,
    )

    metrics_by_expansion: dict[str, Any] = {}
    palette = _build_deterministic_palette(len(region_entries))
    baseline_added = 0

    for expansion in range(0, max_expansion_px + 1):
        owners = variants[expansion]
        added_pixels = 0
        unchanged_owned = 0
        for i, owner in enumerate(owners):
            if owner >= 0 and logical_owners[i] >= 0:
                unchanged_owned += 1
            if owner >= 0 and logical_owners[i] < 0:
                added_pixels += 1

        if expansion == 0:
            baseline_added = added_pixels

        unresolved_halo_pixels = _count_unresolved_halo_pixels(halo_mask=halo_mask, variant_owners=owners)
        bleed_risk_pixels = _count_bleed_risk_pixels(
            logical_owners=logical_owners,
            variant_owners=owners,
            width=width,
            height=height,
        )

        if expansion == 0:
            preview_path = qa_dir / "halo_baseline_0px.png"
        else:
            preview_path = qa_dir / f"halo_expansion_{expansion}px.png"

        _save_composed_preview(
            path=preview_path,
            owners=owners,
            palette=palette,
            foreground_image=line_foreground_image,
            width=width,
            height=height,
        )

        metrics_by_expansion[str(expansion)] = {
            "addedPixels": added_pixels,
            "newlyAddedFromBaseline": added_pixels - baseline_added,
            "ambiguousPixels": raw_stats[expansion]["ambiguousPixels"],
            "reachedPixels": raw_stats[expansion]["reachedPixels"],
            "claimedPixels": raw_stats[expansion]["claimedPixels"],
            "unresolvedHaloPixels": unresolved_halo_pixels,
            "bleedRiskPixels": bleed_risk_pixels,
            "logicalOwnedPixels": unchanged_owned,
            "previewPath": str(preview_path),
        }

    recommended = preferred_expansion_px
    for expansion in range(1, max_expansion_px + 1):
        metric = metrics_by_expansion[str(expansion)]
        if metric["unresolvedHaloPixels"] == 0 and metric["bleedRiskPixels"] == 0:
            recommended = expansion
            break

    if metrics_by_expansion[str(recommended)]["unresolvedHaloPixels"] > 0:
        best = sorted(
            range(1, max_expansion_px + 1),
            key=lambda e: (
                metrics_by_expansion[str(e)]["unresolvedHaloPixels"],
                metrics_by_expansion[str(e)]["bleedRiskPixels"],
                e,
            ),
        )[0]
        recommended = best

    selected_owners = variants[recommended]
    fill_map_rgba = _owners_to_region_map_rgba(
        owners=selected_owners,
        region_entries=region_entries,
    )
    _save_rgba_image(runtime_fill_map_path, fill_map_rgba, width, height)

    logical_region_pixel_counts = [0] * len(region_entries)
    fill_region_pixel_counts = [0] * len(region_entries)
    for owner in logical_owners:
        if owner >= 0:
            logical_region_pixel_counts[owner] += 1
    for owner in selected_owners:
        if owner >= 0:
            fill_region_pixel_counts[owner] += 1

    logical_counts_by_region = {
        region_entries[idx]["regionId"]: logical_region_pixel_counts[idx]
        for idx in range(len(region_entries))
    }
    fill_counts_by_region = {
        region_entries[idx]["regionId"]: fill_region_pixel_counts[idx]
        for idx in range(len(region_entries))
    }

    difference_path = qa_dir / "halo_expansion_difference.png"
    difference_rgba = _build_difference_overlay(
        logical_owners=logical_owners,
        expanded_owners=selected_owners,
        width=width,
        height=height,
    )
    _save_rgba_image(difference_path, difference_rgba, width, height)

    samples = _select_representative_halo_samples(
        logical_owners=logical_owners,
        line_band_mask=line_band_mask,
        foreground_rgba=line_foreground_rgba,
        width=width,
        height=height,
    )

    boundary_candidates = 0
    boundary_cause_a = 0
    boundary_cause_b = 0
    boundary_cause_c = 0
    for i, owner in enumerate(logical_owners):
        if owner >= 0:
            continue
        if not _adjacent_logical_owners(i, logical_owners, width, height):
            continue

        offset = i * 4
        r = line_foreground_rgba[offset]
        g = line_foreground_rgba[offset + 1]
        b = line_foreground_rgba[offset + 2]
        a = line_foreground_rgba[offset + 3]
        brightness = (int(r) + int(g) + int(b)) / 3.0

        boundary_candidates += 1
        if a == 0 and line_band_mask[i]:
            boundary_cause_c += 1
        elif a > 0 and brightness >= 170.0:
            boundary_cause_b += 1
        else:
            boundary_cause_a += 1

    dominant = "A"
    if boundary_cause_b >= boundary_cause_a and boundary_cause_b >= boundary_cause_c:
        dominant = "B"
    elif boundary_cause_c >= boundary_cause_a and boundary_cause_c >= boundary_cause_b:
        dominant = "C"

    elapsed_ms = int((time.perf_counter() - started) * 1000)

    return {
        "recommendedExpansionPx": recommended,
        "lineBandRadiusPx": line_band_radius_px,
        "generationTimeMs": elapsed_ms,
        "fillMapAssetPath": str(runtime_fill_map_path),
        "fillMapFileSizeBytes": runtime_fill_map_path.stat().st_size,
        "qaArtifacts": {
            "baseline0": str(qa_dir / "halo_baseline_0px.png"),
            "expansion1": str(qa_dir / "halo_expansion_1px.png"),
            "expansion2": str(qa_dir / "halo_expansion_2px.png"),
            "expansion3": str(qa_dir / "halo_expansion_3px.png"),
            "expansion4": str(qa_dir / "halo_expansion_4px.png"),
            "difference": str(difference_path),
        },
        "metricsByExpansion": metrics_by_expansion,
        "haloRootCause": {
            "boundaryUnassignedPixels": boundary_candidates,
            "causeACount": boundary_cause_a,
            "causeBCount": boundary_cause_b,
            "causeCCount": boundary_cause_c,
            "classification": f"{dominant}-dominant",
            "samples": samples,
        },
        "logicalRegionPixelCounts": logical_counts_by_region,
        "fillRegionPixelCounts": fill_counts_by_region,
    }


def _build_transparent_line_foreground(src: Path, dst: Path) -> dict[str, int]:
    image = Image.open(src).convert("RGBA")
    pixels = list(image.getdata())

    replaced_white = 0
    preserved_dark = 0
    semi_transparent = 0
    opaque_black = 0
    out_pixels: list[tuple[int, int, int, int]] = []
    for r, g, b, a in pixels:
        if a == 0:
            out_pixels.append((r, g, b, 0))
            continue

        if r >= 245 and g >= 245 and b >= 245:
            replaced_white += 1
            out_pixels.append((0, 0, 0, 0))
        else:
            luminance = (int(r) + int(g) + int(b)) / 3.0
            # Convert surviving line art to black with luminance-driven alpha so
            # anti-aliased edge pixels tint over fill instead of rendering as gray halos.
            alpha = int((255.0 - luminance) * 2.0)
            if alpha < 24:
                alpha = 24
            if alpha > 255:
                alpha = 255

            if r <= 60 and g <= 60 and b <= 60:
                preserved_dark += 1
            if alpha < 255:
                semi_transparent += 1
            else:
                opaque_black += 1
            out_pixels.append((0, 0, 0, alpha))

    output = Image.new("RGBA", image.size)
    output.putdata(out_pixels)
    dst.parent.mkdir(parents=True, exist_ok=True)
    output.save(dst)

    return {
        "replacedWhitePixels": replaced_white,
        "preservedDarkPixels": preserved_dark,
        "semiTransparentLinePixels": semi_transparent,
        "opaqueBlackLinePixels": opaque_black,
        "totalPixels": image.size[0] * image.size[1],
    }


def _to_lower_camel(value: str) -> str:
    parts = [p for p in re.split(r"[^A-Za-z0-9]+", value) if p]
    if not parts:
        return "rasterPage"
    head = parts[0].lower()
    tail = "".join(part[:1].upper() + part[1:].lower() for part in parts[1:])
    return f"{head}{tail}"


def _build_regions_dart(entries: list[dict[str, Any]], symbol_prefix: str) -> str:
    regions_const = f"{symbol_prefix}RasterChildrenDetailedRegions"
    map_entries_const = f"{symbol_prefix}RasterMapEntries"

    lines: list[str] = []
    lines.append("import 'package:flutter/material.dart';")
    lines.append("")
    lines.append("import 'package:color_kingdom/features/coloring/models/coloring_page.dart';")
    lines.append("")
    lines.append("const Color kTransparentRegion = Color(0x00000000);")
    lines.append("")
    lines.append(f"const List<ColoringRegion> {regions_const} = [")
    for entry in entries:
        region_id = entry["regionId"]
        lines.append(
            "  ColoringRegion("
            f"id: '{region_id}', "
            f"name: '{region_id}', "
            "defaultColor: kTransparentRegion),"
        )
    lines.append("];\n")

    lines.append(f"const List<RasterRegionMapEntry> {map_entries_const} = [")
    for entry in entries:
        region_id = entry["regionId"]
        rgba = entry["mapColorRgba"]
        lines.append(
            "  RasterRegionMapEntry("
            f"regionId: '{region_id}', "
            f"rgba: <int>[{rgba[0]}, {rgba[1]}, {rgba[2]}, {rgba[3]}]),"
        )
    lines.append("];\n")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--regions-json", required=True)
    parser.add_argument("--region-map", required=True)
    parser.add_argument("--line-art", required=True)
    parser.add_argument("--profile-qa-debug", required=True)
    parser.add_argument("--profile-exclusions", required=True)
    parser.add_argument("--runtime-dir", required=True)
    parser.add_argument("--runtime-metadata", required=True)
    parser.add_argument("--regions-dart", required=True)
    parser.add_argument("--page-id", required=True)
    parser.add_argument("--asset-base-path", required=True)
    parser.add_argument("--dart-symbol-prefix", default=None)
    parser.add_argument("--content-version", required=True)
    parser.add_argument("--max-fill-expansion-px", type=int, default=4)
    parser.add_argument("--preferred-fill-expansion-px", type=int, default=2)
    args = parser.parse_args()

    regions_json = Path(args.regions_json)
    region_map = Path(args.region_map)
    line_art = Path(args.line_art)
    profile_qa_debug = Path(args.profile_qa_debug)
    profile_exclusions = Path(args.profile_exclusions)
    runtime_dir = Path(args.runtime_dir)
    runtime_metadata = Path(args.runtime_metadata)
    regions_dart = Path(args.regions_dart)
    page_id = str(args.page_id)
    asset_base_path = str(args.asset_base_path).rstrip("/")
    symbol_prefix = str(args.dart_symbol_prefix) if args.dart_symbol_prefix else _to_lower_camel(page_id)

    metadata = _load_json(regions_json)
    accepted = metadata.get("acceptedRegions")
    if not isinstance(accepted, list):
        raise ValueError("regions.json missing acceptedRegions array")

    selected_entries: list[dict[str, Any]] = []
    for region in accepted:
        if not isinstance(region, dict):
            continue

        profiles = region.get("profiles")
        if not isinstance(profiles, dict):
            continue
        detailed = profiles.get("childrenDetailed")
        if not isinstance(detailed, dict):
            continue
        if not bool(detailed.get("included")):
            continue

        region_id = region.get("id")
        map_color = region.get("mapColorRgba")
        if not isinstance(region_id, str) or not region_id:
            continue
        if not (
            isinstance(map_color, list)
            and len(map_color) == 4
            and all(isinstance(v, int) for v in map_color)
        ):
            continue

        selected_entries.append({
            "regionId": region_id,
            "mapColorRgba": map_color,
        })

    if not selected_entries:
        raise ValueError("No CHILDREN_DETAILED regions found")

    selected_entries.sort(key=lambda entry: entry["regionId"])

    source = metadata.get("source")
    if not isinstance(source, dict):
        raise ValueError("regions.json missing source metadata")
    image_width = source.get("width")
    image_height = source.get("height")
    if not isinstance(image_width, int) or not isinstance(image_height, int):
        raise ValueError("Invalid source width/height in regions.json")

    runtime_dir.mkdir(parents=True, exist_ok=True)
    line_art_dst = runtime_dir / "line_art.png"
    line_art_foreground_dst = runtime_dir / "line_art_foreground.png"
    region_map_dst = runtime_dir / "region_map.png"
    region_fill_map_dst = runtime_dir / "region_fill_map.png"

    _copy_file(line_art, line_art_dst)
    foreground_stats = _build_transparent_line_foreground(
        line_art,
        line_art_foreground_dst,
    )
    _copy_file(region_map, region_map_dst)

    qa_fullcolor = profile_qa_debug.parent / "regions_children_detailed_qa_fullcolor.png"
    if profile_qa_debug.resolve() != qa_fullcolor.resolve():
        _copy_file(profile_qa_debug, qa_fullcolor)

    qa_dir = profile_qa_debug.parent / "phase2e2_halo_qc"
    visual_fill = _build_visual_fill_assets(
        region_map_path=region_map_dst,
        line_art_foreground_path=line_art_foreground_dst,
        region_entries=selected_entries,
        max_expansion_px=args.max_fill_expansion_px,
        preferred_expansion_px=args.preferred_fill_expansion_px,
        qa_dir=qa_dir,
        runtime_fill_map_path=region_fill_map_dst,
    )

    runtime_payload = {
        "pageId": page_id,
        "profile": "childrenDetailed",
        "contentVersion": args.content_version,
        "imageWidth": image_width,
        "imageHeight": image_height,
        "lineArtAssetPath": f"{asset_base_path}/line_art_foreground.png",
        "lineArtOpaqueReferenceAssetPath": f"{asset_base_path}/line_art.png",
        "regionMapAssetPath": f"{asset_base_path}/region_map.png",
        "regionFillMapAssetPath": f"{asset_base_path}/region_fill_map.png",
        "regionCount": len(selected_entries),
        "regions": selected_entries,
        "lineArtForegroundStats": foreground_stats,
        "visualFillMap": {
            "recommendedExpansionPx": visual_fill["recommendedExpansionPx"],
            "lineBandRadiusPx": visual_fill["lineBandRadiusPx"],
            "generationTimeMs": visual_fill["generationTimeMs"],
            "fillMapFileSizeBytes": visual_fill["fillMapFileSizeBytes"],
            "metricsByExpansion": visual_fill["metricsByExpansion"],
            "haloRootCause": visual_fill["haloRootCause"],
        },
        "runtimeIntegrity": {
            "approvedChildrenDetailedRegionCount": len(selected_entries),
            "runtimeMetadataRegionCount": len(selected_entries),
            "logicalRegionCountWithPixels": len(
                [
                    region_id
                    for region_id, count in visual_fill["logicalRegionPixelCounts"].items()
                    if int(count) > 0
                ]
            ),
            "fillRegionCountWithPixels": len(
                [
                    region_id
                    for region_id, count in visual_fill["fillRegionPixelCounts"].items()
                    if int(count) > 0
                ]
            ),
            "missingLogicalRegionIds": [
                region_id
                for region_id, count in visual_fill["logicalRegionPixelCounts"].items()
                if int(count) <= 0
            ],
            "missingFillRegionIds": [
                region_id
                for region_id, count in visual_fill["fillRegionPixelCounts"].items()
                if int(count) <= 0
            ],
        },
        "runtimeAssetFileSizesBytes": {
            "lineArt": line_art_dst.stat().st_size,
            "lineArtForeground": line_art_foreground_dst.stat().st_size,
            "regionMap": region_map_dst.stat().st_size,
            "regionFillMap": region_fill_map_dst.stat().st_size,
            "metadataJson": 0,
            "regionsDart": 0,
        },
        "qaArtifacts": {
            "fullColor": str(qa_fullcolor),
            "exclusions": str(profile_exclusions),
            "haloBaseline0": visual_fill["qaArtifacts"]["baseline0"],
            "haloExpansion1": visual_fill["qaArtifacts"]["expansion1"],
            "haloExpansion2": visual_fill["qaArtifacts"]["expansion2"],
            "haloExpansion3": visual_fill["qaArtifacts"]["expansion3"],
            "haloExpansion4": visual_fill["qaArtifacts"]["expansion4"],
            "haloDifference": visual_fill["qaArtifacts"]["difference"],
        },
    }

    _write_json(runtime_metadata, runtime_payload)
    regions_dart.parent.mkdir(parents=True, exist_ok=True)
    regions_dart.write_text(_build_regions_dart(selected_entries, symbol_prefix=symbol_prefix), encoding="utf-8")

    runtime_payload["runtimeAssetFileSizesBytes"]["regionsDart"] = regions_dart.stat().st_size

    # Stabilize metadataJson size after embedding the measured size itself.
    for _ in range(2):
        runtime_payload["runtimeAssetFileSizesBytes"]["metadataJson"] = runtime_metadata.stat().st_size
        _write_json(runtime_metadata, runtime_payload)

    print("Export complete")
    print(f"Runtime dir: {runtime_dir}")
    print(f"Metadata: {runtime_metadata}")
    print(f"Regions generated: {len(selected_entries)}")
    print(f"Foreground stats: {foreground_stats}")
    print(f"Visual fill map: {region_fill_map_dst}")
    print(
        "Visual fill summary: "
        f"recommendedExpansionPx={visual_fill['recommendedExpansionPx']} "
        f"generationTimeMs={visual_fill['generationTimeMs']} "
        f"fillMapFileSizeBytes={visual_fill['fillMapFileSizeBytes']}"
    )
    print(f"QA full-color: {qa_fullcolor}")
    print(f"QA exclusions: {profile_exclusions}")
    print(f"Halo QA dir: {qa_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
