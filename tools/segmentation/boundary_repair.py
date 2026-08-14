from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
from collections import deque
import json
import time

import cv2
import numpy as np
from PIL import Image


@dataclass(frozen=True)
class BoundaryRepairConfig:
    enabled: bool = False
    diagnostics_only: bool = False
    max_gap_pixels: int = 6
    candidate_search_radius: int = 10
    min_new_region_area_pixels: int = 250
    max_repair_pixels: int = 8
    border_margin_percent: float = 2.0
    max_exterior_percent_delta: float = 1.0
    max_new_regions_per_candidate: int = 2
    max_candidates_to_validate: int = 80


@dataclass
class BoundaryRepairResult:
    barrier_before: np.ndarray
    barrier_after: np.ndarray
    candidates: list[dict[str, Any]]
    candidate_visualization: np.ndarray
    repair_difference: np.ndarray
    timings_ms: dict[str, float]
    summary: dict[str, Any]


def _save_u8_image(path: Path, arr: np.ndarray) -> None:
    if arr.dtype != np.uint8:
        arr = arr.astype(np.uint8)
    Image.fromarray(arr).save(path)


def _neighbor_offsets() -> list[tuple[int, int]]:
    return [
        (-1, -1),
        (-1, 0),
        (-1, 1),
        (0, -1),
        (0, 1),
        (1, -1),
        (1, 0),
        (1, 1),
    ]


def _flood_fill_exterior(open_mask: np.ndarray) -> np.ndarray:
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

    neighbors = _neighbor_offsets()
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


def _accepted_components(mask: np.ndarray, min_area: int) -> tuple[int, np.ndarray, np.ndarray]:
    cc, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    accepted = 0
    for idx in range(1, cc):
        if int(stats[idx, cv2.CC_STAT_AREA]) >= min_area:
            accepted += 1
    return accepted, labels, stats


def _compute_topology(barrier: np.ndarray, min_area: int) -> dict[str, Any]:
    open_mask = (barrier == 0).astype(np.uint8)
    exterior = _flood_fill_exterior(open_mask)
    candidate_mask = ((open_mask == 1) & (exterior == 0)).astype(np.uint8)
    accepted_count, labels, stats = _accepted_components(candidate_mask, min_area)
    total_pixels = float(barrier.shape[0] * barrier.shape[1])
    exterior_percent = float((exterior.sum() / total_pixels) * 100.0)
    return {
        "openMask": open_mask,
        "exteriorMask": exterior,
        "candidateMask": candidate_mask,
        "acceptedCount": int(accepted_count),
        "labels": labels,
        "stats": stats,
        "exteriorPercent": exterior_percent,
    }


def _find_endpoints(barrier: np.ndarray, margin_px: int) -> list[tuple[int, int]]:
    h, w = barrier.shape
    endpoints: list[tuple[int, int]] = []
    neighbors = _neighbor_offsets()

    for y in range(margin_px, h - margin_px):
        for x in range(margin_px, w - margin_px):
            if barrier[y, x] != 1:
                continue
            count = 0
            for dy, dx in neighbors:
                if barrier[y + dy, x + dx] == 1:
                    count += 1
            if count <= 2:
                endpoints.append((y, x))

    endpoints.sort()
    return endpoints


def _line_pixels(p1: tuple[int, int], p2: tuple[int, int], shape: tuple[int, int]) -> np.ndarray:
    canvas = np.zeros(shape, dtype=np.uint8)
    cv2.line(canvas, (p1[1], p1[0]), (p2[1], p2[0]), 1, 1)
    return canvas


def _touches_exterior_neighborhood(y: int, x: int, exterior: np.ndarray) -> bool:
    h, w = exterior.shape
    for dy, dx in _neighbor_offsets():
        ny, nx = y + dy, x + dx
        if ny < 0 or ny >= h or nx < 0 or nx >= w:
            continue
        if exterior[ny, nx] == 1:
            return True
    return False


def detect_and_repair_boundaries(
    barrier_mask: np.ndarray,
    config: BoundaryRepairConfig,
    min_region_area_pixels: int,
) -> BoundaryRepairResult:
    t_start = time.perf_counter()

    before = (barrier_mask > 0).astype(np.uint8)
    h, w = before.shape
    margin_px = max(2, int(round((min(h, w) * config.border_margin_percent) / 100.0)))

    topo_before = _compute_topology(before, min_region_area_pixels)

    t_detect_start = time.perf_counter()

    raw_candidates: list[dict[str, Any]] = []
    candidate_keys: set[tuple[int, int, int, int]] = set()

    def add_candidate(p1: tuple[int, int], p2: tuple[int, int], dist: float, gap_pixels: int) -> None:
        key = (min(p1[0], p2[0]), min(p1[1], p2[1]), max(p1[0], p2[0]), max(p1[1], p2[1]))
        if key in candidate_keys:
            return
        if len(candidate_keys) >= (config.max_candidates_to_validate * 4):
            return
        candidate_keys.add(key)
        raw_candidates.append(
            {
                "endpointA": {"x": int(p1[1]), "y": int(p1[0])},
                "endpointB": {"x": int(p2[1]), "y": int(p2[0])},
                "distancePixels": float(dist),
                "gapPixels": int(gap_pixels),
            }
        )
    # Supplemental deterministic gap scan for short horizontal/vertical openings.
    exterior = topo_before["exteriorMask"]
    for y in range(margin_px, h - margin_px):
        for x in range(margin_px + 1, w - margin_px - 1):
            if before[y, x] != 0 or exterior[y, x] != 1:
                continue

            for gap in range(1, config.max_gap_pixels + 1):
                lx = x - 1
                rx = x + gap
                if rx >= (w - margin_px):
                    break
                if before[y, lx] == 1 and before[y, rx] == 1:
                    segment = before[y, x:rx]
                    if np.all(segment == 0):
                        p1 = (y, lx)
                        p2 = (y, rx)
                        gp = int(gap)
                        if 0 < gp <= config.max_gap_pixels and gp <= config.max_repair_pixels:
                            add_candidate(p1, p2, float(gap), gp)
                    break

    for x in range(margin_px, w - margin_px):
        for y in range(margin_px + 1, h - margin_px - 1):
            if before[y, x] != 0 or exterior[y, x] != 1:
                continue

            for gap in range(1, config.max_gap_pixels + 1):
                ty = y - 1
                by = y + gap
                if by >= (h - margin_px):
                    break
                if before[ty, x] == 1 and before[by, x] == 1:
                    segment = before[y:by, x]
                    if np.all(segment == 0):
                        p1 = (ty, x)
                        p2 = (by, x)
                        gp = int(gap)
                        if 0 < gp <= config.max_gap_pixels and gp <= config.max_repair_pixels:
                            add_candidate(p1, p2, float(gap), gp)
                    break

    # Deterministic order and dedupe by endpoint pair.
    raw_candidates.sort(
        key=lambda c: (
            c["gapPixels"],
            round(c["distancePixels"], 6),
            c["endpointA"]["y"],
            c["endpointA"]["x"],
            c["endpointB"]["y"],
            c["endpointB"]["x"],
        )
    )
    if len(raw_candidates) > config.max_candidates_to_validate:
        raw_candidates = raw_candidates[: config.max_candidates_to_validate]
    t_detect_ms = (time.perf_counter() - t_detect_start) * 1000.0

    t_validate_start = time.perf_counter()
    after = before.copy()
    applied_count = 0
    candidates: list[dict[str, Any]] = []

    current_topology = topo_before

    for idx, cand in enumerate(raw_candidates, start=1):
        p1 = (int(cand["endpointA"]["y"]), int(cand["endpointA"]["x"]))
        p2 = (int(cand["endpointB"]["y"]), int(cand["endpointB"]["x"]))
        line = _line_pixels(p1, p2, before.shape)
        line_y, line_x = np.where((line == 1) & (after == 0))
        repair_pixels = int(line_y.size)

        rec: dict[str, Any] = {
            "candidateId": f"candidate-{idx:03d}",
            "endpointA": cand["endpointA"],
            "endpointB": cand["endpointB"],
            "gapPixels": int(cand["gapPixels"]),
            "distancePixels": float(cand["distancePixels"]),
            "repairPixelCount": repair_pixels,
            "status": "REJECTED",
            "reason": "UNSPECIFIED",
            "safetyChecks": {},
            "before": {
                "acceptedCount": int(current_topology["acceptedCount"]),
                "exteriorPercent": float(current_topology["exteriorPercent"]),
            },
        }

        if repair_pixels == 0:
            rec["reason"] = "NO_NEW_BARRIER_PIXELS"
            candidates.append(rec)
            continue

        if config.diagnostics_only:
            rec["status"] = "DETECTED"
            rec["reason"] = "DIAGNOSTICS_ONLY"
            rec["after"] = rec["before"]
            candidates.append(rec)
            continue

        test_barrier = after.copy()
        test_barrier[line_y, line_x] = 1
        topo_after = _compute_topology(test_barrier, min_region_area_pixels)

        delta_accepted = int(topo_after["acceptedCount"] - current_topology["acceptedCount"])
        delta_exterior = float(abs(topo_after["exteriorPercent"] - current_topology["exteriorPercent"]))

        safe_gap = cand["gapPixels"] <= config.max_gap_pixels
        safe_pixels = repair_pixels <= config.max_repair_pixels
        safe_delta_regions = 1 <= delta_accepted <= config.max_new_regions_per_candidate
        safe_exterior = delta_exterior <= config.max_exterior_percent_delta

        rec["safetyChecks"] = {
            "maxGapPassed": bool(safe_gap),
            "maxRepairPixelsPassed": bool(safe_pixels),
            "newRegionDeltaPassed": bool(safe_delta_regions),
            "exteriorDeltaPassed": bool(safe_exterior),
        }

        if not safe_gap:
            rec["reason"] = "MAX_GAP_EXCEEDED"
        elif not safe_pixels:
            rec["reason"] = "MAX_REPAIR_PIXELS_EXCEEDED"
        elif not safe_delta_regions:
            rec["reason"] = "UNSAFE_REGION_TOPOLOGY_CHANGE"
        elif not safe_exterior:
            rec["reason"] = "EXTERIOR_PERCENT_DELTA_TOO_HIGH"
        else:
            rec["status"] = "APPLIED"
            rec["reason"] = "SAFE_NEW_ENCLOSED_COMPONENT"
            rec["newAcceptedRegions"] = delta_accepted
            rec["exteriorDeltaPercent"] = delta_exterior
            after = test_barrier
            current_topology = topo_after
            applied_count += 1

        rec["after"] = {
            "acceptedCount": int(topo_after["acceptedCount"]),
            "exteriorPercent": float(topo_after["exteriorPercent"]),
        }
        candidates.append(rec)

    t_validate_ms = (time.perf_counter() - t_validate_start) * 1000.0

    t_apply_start = time.perf_counter()
    # apply stage was already integrated above; keep dedicated timing bucket for report consistency.
    t_apply_ms = (time.perf_counter() - t_apply_start) * 1000.0

    added_mask = ((after == 1) & (before == 0)).astype(np.uint8)

    # Candidate visualization.
    vis = np.full((h, w, 3), 255, dtype=np.uint8)
    vis[before == 1] = np.array([0, 0, 0], dtype=np.uint8)

    for rec in candidates:
        p1 = (int(rec["endpointA"]["x"]), int(rec["endpointA"]["y"]))
        p2 = (int(rec["endpointB"]["x"]), int(rec["endpointB"]["y"]))
        status = rec["status"]
        color = (230, 180, 40)
        if status == "APPLIED":
            color = (70, 180, 70)
        elif status == "REJECTED":
            color = (210, 80, 80)
        cv2.line(vis, p1, p2, color, 1)
        cv2.circle(vis, p1, 2, color, -1)
        cv2.circle(vis, p2, 2, color, -1)

    # Difference visualization highlights only newly added barrier pixels.
    diff = np.full((h, w, 3), 255, dtype=np.uint8)
    diff[before == 1] = np.array([0, 0, 0], dtype=np.uint8)
    diff[added_mask == 1] = np.array([220, 60, 60], dtype=np.uint8)

    timings_ms = {
        "candidateDetectionMs": t_detect_ms,
        "candidateValidationMs": t_validate_ms,
        "repairApplicationMs": t_apply_ms,
        "totalBoundaryRepairMs": (time.perf_counter() - t_start) * 1000.0,
    }

    summary = {
        "candidateCount": len(candidates),
        "appliedCount": applied_count,
        "rejectedCount": sum(1 for c in candidates if c["status"] == "REJECTED"),
        "detectedOnlyCount": sum(1 for c in candidates if c["status"] == "DETECTED"),
        "repairPixelsAdded": int(added_mask.sum()),
        "beforeAcceptedCount": int(topo_before["acceptedCount"]),
        "afterAcceptedCount": int(current_topology["acceptedCount"]),
        "beforeExteriorPercent": float(topo_before["exteriorPercent"]),
        "afterExteriorPercent": float(current_topology["exteriorPercent"]),
    }

    return BoundaryRepairResult(
        barrier_before=before,
        barrier_after=after,
        candidates=candidates,
        candidate_visualization=vis,
        repair_difference=diff,
        timings_ms=timings_ms,
        summary=summary,
    )


def write_boundary_repair_artifacts(output_dir: Path, result: BoundaryRepairResult) -> dict[str, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)

    before_path = output_dir / "binary_barriers_before_repair.png"
    candidate_path = output_dir / "boundary_repair_candidates.png"
    after_path = output_dir / "binary_barriers_after_repair.png"
    diff_path = output_dir / "boundary_repair_difference.png"
    metadata_path = output_dir / "boundary_repair_report.json"

    _save_u8_image(before_path, np.where(result.barrier_before == 1, 0, 255).astype(np.uint8))
    _save_u8_image(candidate_path, result.candidate_visualization)
    _save_u8_image(after_path, np.where(result.barrier_after == 1, 0, 255).astype(np.uint8))
    _save_u8_image(diff_path, result.repair_difference)

    payload = {
        "summary": result.summary,
        "timingsMs": result.timings_ms,
        "candidates": result.candidates,
    }
    with metadata_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True)

    return {
        "barriers_before": before_path,
        "candidates_visualization": candidate_path,
        "barriers_after": after_path,
        "difference_visualization": diff_path,
        "repair_metadata_json": metadata_path,
    }
