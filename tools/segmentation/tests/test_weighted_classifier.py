from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np

from segmentation_pipeline import SegmentationConfig, segment_image_array
from suitability_classifier import (
    ProfileThresholds,
    SuitabilityConfig,
    WeightedChildrenDetailedConfig,
    classify_segmentation_result,
)


def _blank(width: int = 180, height: int = 140) -> np.ndarray:
    return np.full((height, width, 3), 255, dtype=np.uint8)


def _box(img: np.ndarray, x: int, y: int, w: int, h: int, thickness: int = 1) -> None:
    cv2.rectangle(img, (x, y), (x + w - 1, y + h - 1), (0, 0, 0), thickness=thickness)


def _seg(img: np.ndarray):
    cfg = SegmentationConfig(
        threshold=200,
        morph_kernel=0,
        morph_iterations=1,
        dilate_iterations=0,
        min_region_area_pixels=8,
        min_region_area_percent=0.0,
        connectivity=8,
    )
    return segment_image_array(img, Path("weighted.png"), cfg, variant_name="weighted-test")


def _weighted_config() -> SuitabilityConfig:
    return SuitabilityConfig(
        children_detailed=ProfileThresholds(
            min_area_percent=0.1,
            min_bounding_dimension_percent=1.5,
            min_tap_radius_percent=0.5,
            min_occupancy_ratio=0.2,
            min_aspect_ratio=0.08,
            min_compactness=0.01,
        ),
        children_simple=ProfileThresholds(
            min_area_percent=0.2,
            min_bounding_dimension_percent=2.0,
            min_tap_radius_percent=0.8,
            min_occupancy_ratio=0.28,
            min_aspect_ratio=0.1,
            min_compactness=0.02,
        ),
        children_detailed_mode="weighted",
        children_detailed_weighted=WeightedChildrenDetailedConfig(
            score_threshold=0.55,
            normalize_low_percentile=10.0,
            normalize_high_percentile=90.0,
            weight_area=0.20,
            weight_tap_target=0.30,
            weight_min_dimension=0.20,
            weight_occupancy=0.10,
            weight_compactness=0.10,
            weight_aspect_ratio=0.10,
            guardrail_min_area_percent=0.08,
            guardrail_min_bounding_dimension_percent=3.0,
            guardrail_min_tap_radius_percent=0.9,
        ),
    )


def _classify(img: np.ndarray):
    seg = _seg(img)
    classify_segmentation_result(
        metadata=seg.metadata,
        labels=seg.artifacts.labels,
        barrier_mask=seg.artifacts.binary_repaired,
        exterior_mask=seg.artifacts.exterior_mask,
        config=_weighted_config(),
    )
    return seg


def test_identical_features_produce_identical_scores() -> None:
    img = _blank(240, 120)
    _box(img, 20, 20, 40, 40, thickness=1)
    _box(img, 140, 20, 40, 40, thickness=1)

    seg = _classify(img)
    regions = sorted(seg.metadata["acceptedRegions"], key=lambda r: r["centroid"]["x"])

    assert len(regions) == 2
    s0 = regions[0]["childrenDetailedWeighted"]["score"]
    s1 = regions[1]["childrenDetailedWeighted"]["score"]
    assert abs(s0 - s1) < 1e-9


def test_scoring_is_deterministic() -> None:
    img = _blank()
    _box(img, 12, 12, 50, 50, thickness=1)
    _box(img, 90, 20, 30, 24, thickness=1)

    a = _classify(img)
    b = _classify(img)

    ar = [(r["id"], r["childrenDetailedWeighted"]["score"]) for r in a.metadata["acceptedRegions"]]
    br = [(r["id"], r["childrenDetailedWeighted"]["score"]) for r in b.metadata["acceptedRegions"]]
    assert ar == br


def test_score_in_range_zero_to_one() -> None:
    img = _blank()
    _box(img, 10, 10, 70, 70, thickness=1)
    _box(img, 90, 15, 22, 20, thickness=1)

    seg = _classify(img)
    for region in seg.metadata["acceptedRegions"]:
        score = region["childrenDetailedWeighted"]["score"]
        assert 0.0 <= score <= 1.0


def test_larger_tap_target_improves_suitability() -> None:
    img = _blank(260, 120)
    _box(img, 20, 20, 20, 20, thickness=1)
    _box(img, 120, 20, 50, 50, thickness=1)

    seg = _classify(img)
    by_area = sorted(seg.metadata["acceptedRegions"], key=lambda r: r["features"]["areaPixels"])
    tiny = by_area[0]
    large = by_area[-1]

    assert large["childrenDetailedWeighted"]["score"] >= tiny["childrenDetailedWeighted"]["score"]


def test_hard_guardrail_excludes_unusably_tiny_region() -> None:
    img = _blank(300, 120)
    _box(img, 20, 20, 70, 70, thickness=1)
    _box(img, 150, 30, 6, 6, thickness=1)

    seg = _classify(img)
    tiny = min(seg.metadata["acceptedRegions"], key=lambda r: r["features"]["areaPixels"])

    assert tiny["childrenDetailedWeighted"]["hardGuardrailPassed"] is False
    assert tiny["profiles"]["childrenDetailedWeighted"]["included"] is False


def test_master_remains_unaffected() -> None:
    img = _blank()
    _box(img, 12, 12, 60, 60, thickness=1)
    _box(img, 92, 22, 18, 16, thickness=1)

    seg = _classify(img)
    included = [r for r in seg.metadata["acceptedRegions"] if r["profiles"]["master"]["included"]]
    assert len(included) == len(seg.metadata["acceptedRegions"])


def test_weighted_children_detailed_reproducible() -> None:
    img = _blank(220, 130)
    _box(img, 15, 15, 56, 60, thickness=1)
    _box(img, 95, 16, 24, 24, thickness=1)
    _box(img, 140, 18, 16, 18, thickness=1)

    a = _classify(img)
    b = _classify(img)

    ap = [r["profiles"]["childrenDetailedWeighted"] for r in a.metadata["acceptedRegions"]]
    bp = [r["profiles"]["childrenDetailedWeighted"] for r in b.metadata["acceptedRegions"]]
    assert ap == bp


def test_weighted_metadata_contains_contributions() -> None:
    img = _blank()
    _box(img, 12, 12, 60, 60, thickness=1)

    seg = _classify(img)
    region = seg.metadata["acceptedRegions"][0]

    wd = region["childrenDetailedWeighted"]
    assert "contributions" in wd
    assert "normalizedFeatures" in wd
    assert set(wd["contributions"].keys()) == {
        "area",
        "tapTarget",
        "minDimension",
        "occupancy",
        "compactness",
        "aspectRatio",
    }
