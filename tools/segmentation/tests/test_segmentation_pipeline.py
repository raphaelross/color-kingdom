from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np

from segmentation_pipeline import SegmentationConfig, segment_image_array


def _blank(width: int = 80, height: int = 80) -> np.ndarray:
    return np.full((height, width, 3), 255, dtype=np.uint8)


def _draw_box(img: np.ndarray, x: int, y: int, w: int, h: int, thickness: int = 1) -> np.ndarray:
    cv2.rectangle(img, (x, y), (x + w - 1, y + h - 1), (0, 0, 0), thickness=thickness)
    return img


def _run(img: np.ndarray, **kwargs):
    cfg = SegmentationConfig(
        threshold=200,
        morph_kernel=0,
        morph_iterations=1,
        dilate_iterations=0,
        min_region_area_pixels=kwargs.get("min_region_area_pixels", 10),
        min_region_area_percent=kwargs.get("min_region_area_percent", 0.0),
        connectivity=8,
    )
    return segment_image_array(img, Path("synthetic.png"), cfg, variant_name="test")


def test_single_enclosed_region_detected() -> None:
    img = _blank()
    _draw_box(img, 20, 20, 30, 30, thickness=1)
    res = _run(img)
    assert res.metadata["metrics"]["acceptedRegionCount"] == 1


def test_multiple_enclosed_regions_detected() -> None:
    img = _blank()
    _draw_box(img, 8, 8, 24, 24, thickness=1)
    _draw_box(img, 45, 45, 24, 24, thickness=1)
    res = _run(img)
    assert res.metadata["metrics"]["acceptedRegionCount"] == 2


def test_exterior_background_excluded() -> None:
    img = _blank()
    _draw_box(img, 15, 15, 50, 50, thickness=1)
    res = _run(img)
    exterior_percent = res.metadata["metrics"]["exterior"]["percent"]
    assert exterior_percent > 50.0
    assert res.metadata["metrics"]["acceptedRegionCount"] == 1


def test_open_boundary_leaks_to_exterior() -> None:
    img = _blank()
    _draw_box(img, 20, 20, 30, 30, thickness=1)
    img[20, 34:37] = 255  # Intentional top-edge gap
    res = _run(img)
    assert res.metadata["metrics"]["acceptedRegionCount"] == 0


def test_morphology_closes_small_gap() -> None:
    img = _blank()
    _draw_box(img, 20, 20, 30, 30, thickness=1)
    img[20, 35] = 255  # Intentional one-pixel top-edge gap

    base = _run(img)
    assert base.metadata["metrics"]["acceptedRegionCount"] == 0

    cfg = SegmentationConfig(
        threshold=200,
        morph_kernel=3,
        morph_iterations=1,
        dilate_iterations=1,
        min_region_area_pixels=10,
        min_region_area_percent=0.0,
        connectivity=4,
    )
    repaired = segment_image_array(img, Path("synthetic.png"), cfg, variant_name="morph")
    assert repaired.metadata["metrics"]["acceptedRegionCount"] >= 1


def test_small_region_flagged() -> None:
    img = _blank()
    _draw_box(img, 25, 25, 8, 8, thickness=1)
    res = _run(img, min_region_area_pixels=100)
    assert res.metadata["metrics"]["acceptedRegionCount"] == 0
    assert res.metadata["metrics"]["flaggedTooSmallCount"] == 1


def test_deterministic_region_ordering_ids() -> None:
    img = _blank(100, 100)
    _draw_box(img, 60, 15, 20, 20, thickness=1)  # higher region, should be first
    _draw_box(img, 10, 60, 20, 20, thickness=1)  # lower region, should be second
    res = _run(img)
    accepted = res.metadata["acceptedRegions"]
    assert accepted[0]["id"] == "region-001"
    assert accepted[1]["id"] == "region-002"
    assert accepted[0]["centroid"]["y"] < accepted[1]["centroid"]["y"]


def test_region_map_matches_metadata_color_at_centroids() -> None:
    img = _blank()
    _draw_box(img, 10, 10, 25, 25, thickness=1)
    _draw_box(img, 42, 42, 25, 25, thickness=1)
    res = _run(img)
    region_map = res.artifacts.region_map_rgba

    for reg in res.metadata["acceptedRegions"]:
        cx = int(round(reg["centroid"]["x"]))
        cy = int(round(reg["centroid"]["y"]))
        px = region_map[cy, cx].tolist()
        assert px == reg["mapColorRgba"]


def test_repeated_runs_are_identical() -> None:
    img = _blank()
    _draw_box(img, 10, 10, 20, 20, thickness=1)
    _draw_box(img, 38, 12, 20, 20, thickness=1)
    _draw_box(img, 20, 42, 24, 24, thickness=1)

    r1 = _run(img)
    r2 = _run(img)

    m1 = dict(r1.metadata["metrics"])
    m2 = dict(r2.metadata["metrics"])
    m1.pop("runtimeMs", None)
    m2.pop("runtimeMs", None)
    assert m1 == m2
    assert r1.metadata["acceptedRegions"] == r2.metadata["acceptedRegions"]
    assert r1.metadata["flaggedTooSmallRegions"] == r2.metadata["flaggedTooSmallRegions"]
    assert np.array_equal(r1.artifacts.region_map_rgba, r2.artifacts.region_map_rgba)
