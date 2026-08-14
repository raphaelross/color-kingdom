from __future__ import annotations

import copy

import cv2
import numpy as np

from boundary_repair import BoundaryRepairConfig, detect_and_repair_boundaries


def _blank_barrier(width: int = 120, height: int = 120) -> np.ndarray:
    return np.zeros((height, width), dtype=np.uint8)


def _box(barrier: np.ndarray, x: int, y: int, w: int, h: int, thickness: int = 1) -> None:
    cv2.rectangle(barrier, (x, y), (x + w - 1, y + h - 1), 1, thickness=thickness)


def test_small_open_gap_detected() -> None:
    b = _blank_barrier()
    _box(b, 20, 20, 40, 40, 1)
    b[20, 37:40] = 0  # small opening

    cfg = BoundaryRepairConfig(enabled=True, diagnostics_only=True, max_gap_pixels=6, candidate_search_radius=12)
    res = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)

    assert res.summary["candidateCount"] > 0


def test_safe_short_gap_can_be_closed() -> None:
    b = _blank_barrier()
    _box(b, 20, 20, 40, 40, 1)
    b[20, 38] = 0

    cfg = BoundaryRepairConfig(
        enabled=True,
        diagnostics_only=False,
        max_gap_pixels=6,
        candidate_search_radius=10,
        min_new_region_area_pixels=20,
        max_repair_pixels=8,
        border_margin_percent=1.0,
        max_exterior_percent_delta=20.0,
        max_new_regions_per_candidate=2,
    )
    res = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)

    assert res.summary["appliedCount"] >= 1
    assert res.summary["afterAcceptedCount"] >= res.summary["beforeAcceptedCount"] + 1


def test_large_gap_is_rejected() -> None:
    b = _blank_barrier()
    _box(b, 20, 20, 40, 40, 1)
    b[20, 30:45] = 0  # too wide for conservative repair

    cfg = BoundaryRepairConfig(enabled=True, diagnostics_only=False, max_gap_pixels=4, candidate_search_radius=20)
    res = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)

    assert res.summary["appliedCount"] == 0


def test_border_opening_is_rejected() -> None:
    b = _blank_barrier()
    _box(b, 2, 20, 32, 40, 1)
    b[20, 15] = 0

    cfg = BoundaryRepairConfig(enabled=True, diagnostics_only=False, max_gap_pixels=6, candidate_search_radius=10, border_margin_percent=4.0)
    res = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)

    assert res.summary["appliedCount"] == 0


def test_repair_creates_expected_enclosed_component() -> None:
    b = _blank_barrier()
    _box(b, 30, 30, 50, 50, 1)
    b[30, 52] = 0

    cfg = BoundaryRepairConfig(
        enabled=True,
        diagnostics_only=False,
        max_gap_pixels=6,
        candidate_search_radius=10,
        max_exterior_percent_delta=20.0,
    )
    res = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)

    assert res.summary["beforeAcceptedCount"] == 0
    assert res.summary["afterAcceptedCount"] >= 1


def test_repair_does_not_merge_neighboring_valid_regions() -> None:
    b = _blank_barrier()
    _box(b, 10, 15, 26, 26, 1)
    _box(b, 45, 15, 26, 26, 1)
    _box(b, 80, 15, 26, 26, 1)
    b[15, 92] = 0  # only third box has gap

    cfg = BoundaryRepairConfig(
        enabled=True,
        diagnostics_only=False,
        max_gap_pixels=6,
        candidate_search_radius=10,
        max_exterior_percent_delta=20.0,
    )
    res = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)

    assert res.summary["beforeAcceptedCount"] == 2
    assert res.summary["afterAcceptedCount"] == 3


def test_deterministic_candidate_detection() -> None:
    b = _blank_barrier()
    _box(b, 20, 20, 40, 40, 1)
    b[20, 38] = 0

    cfg = BoundaryRepairConfig(enabled=True, diagnostics_only=True, max_gap_pixels=6, candidate_search_radius=10)
    a = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)
    c = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)

    def simple(cands):
        return [
            (x["candidateId"], x["endpointA"]["x"], x["endpointA"]["y"], x["endpointB"]["x"], x["endpointB"]["y"], x["gapPixels"])
            for x in cands
        ]

    assert simple(a.candidates) == simple(c.candidates)


def test_deterministic_repair_result_and_metadata() -> None:
    b = _blank_barrier()
    _box(b, 20, 20, 40, 40, 1)
    b[20, 38] = 0

    cfg = BoundaryRepairConfig(enabled=True, diagnostics_only=False, max_gap_pixels=6, candidate_search_radius=10)
    a = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)
    c = detect_and_repair_boundaries(b, cfg, min_region_area_pixels=20)

    assert np.array_equal(a.barrier_after, c.barrier_after)

    sa = copy.deepcopy(a.summary)
    sc = copy.deepcopy(c.summary)
    assert sa == sc

    ca = copy.deepcopy(a.candidates)
    cc = copy.deepcopy(c.candidates)
    assert ca == cc
