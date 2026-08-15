from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory

import cv2
import numpy as np
from PIL import Image

from segmentation_pipeline import SegmentationConfig, segment_image_array
from suitability_classifier import (
    ProfileThresholds,
    SuitabilityConfig,
    classify_segmentation_result,
    write_profile_artifacts,
)


def _blank(width: int = 140, height: int = 120) -> np.ndarray:
    return np.full((height, width, 3), 255, dtype=np.uint8)


def _box(img: np.ndarray, x: int, y: int, w: int, h: int, thickness: int = 1) -> None:
    cv2.rectangle(img, (x, y), (x + w - 1, y + h - 1), (0, 0, 0), thickness=thickness)


def _segment(img: np.ndarray):
    cfg = SegmentationConfig(
        threshold=200,
        morph_kernel=0,
        morph_iterations=1,
        dilate_iterations=0,
        min_region_area_pixels=8,
        min_region_area_percent=0.0,
        connectivity=8,
    )
    return segment_image_array(img, Path("synthetic.png"), cfg, variant_name="classifier-test")


def _config() -> SuitabilityConfig:
    return SuitabilityConfig(
        children_detailed=ProfileThresholds(
            min_area_percent=2.0,
            min_bounding_dimension_percent=8.0,
            min_tap_radius_percent=1.0,
            min_occupancy_ratio=0.18,
            min_aspect_ratio=0.08,
            min_compactness=0.01,
        ),
        children_simple=ProfileThresholds(
            min_area_percent=5.0,
            min_bounding_dimension_percent=13.0,
            min_tap_radius_percent=2.0,
            min_occupancy_ratio=0.2,
            min_aspect_ratio=0.12,
            min_compactness=0.01,
        ),
    )


def test_large_region_included_in_all_profiles() -> None:
    img = _blank()
    _box(img, 14, 14, 86, 82, thickness=2)

    seg = _segment(img)
    classify_segmentation_result(
        metadata=seg.metadata,
        labels=seg.artifacts.labels,
        barrier_mask=seg.artifacts.binary_repaired,
        exterior_mask=seg.artifacts.exterior_mask,
        config=_config(),
    )

    assert len(seg.metadata["acceptedRegions"]) == 1
    region = seg.metadata["acceptedRegions"][0]
    assert region["profiles"]["master"]["included"] is True
    assert region["profiles"]["childrenDetailed"]["included"] is True
    assert region["profiles"]["childrenSimple"]["included"] is True


def test_tiny_region_retained_in_master_excluded_for_children() -> None:
    img = _blank()
    _box(img, 10, 10, 70, 70, thickness=2)
    _box(img, 95, 10, 8, 8, thickness=1)

    seg = _segment(img)
    classify_segmentation_result(
        metadata=seg.metadata,
        labels=seg.artifacts.labels,
        barrier_mask=seg.artifacts.binary_repaired,
        exterior_mask=seg.artifacts.exterior_mask,
        config=_config(),
    )

    tiny = min(seg.metadata["acceptedRegions"], key=lambda r: r["areaPixels"])
    assert tiny["profiles"]["master"]["included"] is True
    assert tiny["profiles"]["childrenDetailed"]["included"] is False
    assert tiny["profiles"]["childrenSimple"]["included"] is False
    assert "AREA_TOO_SMALL" in tiny["profiles"]["childrenDetailed"]["reasons"]
    assert "BOUNDING_DIMENSION_TOO_SMALL" in tiny["profiles"]["childrenDetailed"]["reasons"]


def test_medium_region_included_detailed_excluded_simple() -> None:
    img = _blank()
    _box(img, 8, 8, 80, 80, thickness=2)
    _box(img, 98, 20, 26, 26, thickness=1)

    seg = _segment(img)
    classify_segmentation_result(
        metadata=seg.metadata,
        labels=seg.artifacts.labels,
        barrier_mask=seg.artifacts.binary_repaired,
        exterior_mask=seg.artifacts.exterior_mask,
        config=_config(),
    )

    by_size = sorted(seg.metadata["acceptedRegions"], key=lambda r: r["areaPixels"])
    medium = by_size[0]
    assert medium["profiles"]["childrenDetailed"]["included"] is True
    assert medium["profiles"]["childrenSimple"]["included"] is False


def test_tap_target_too_small_alone_does_not_exclude_children_detailed() -> None:
    img = _blank(220, 140)
    _box(img, 10, 10, 80, 80, thickness=2)
    _box(img, 120, 20, 90, 10, thickness=1)

    cfg = SuitabilityConfig(
        children_detailed=ProfileThresholds(
            min_area_percent=0.05,
            min_bounding_dimension_percent=2.0,
            min_tap_radius_percent=5.5,
            min_occupancy_ratio=0.18,
            min_aspect_ratio=0.08,
            min_compactness=0.01,
        ),
        children_simple=ProfileThresholds(
            min_area_percent=5.0,
            min_bounding_dimension_percent=13.0,
            min_tap_radius_percent=2.0,
            min_occupancy_ratio=0.2,
            min_aspect_ratio=0.12,
            min_compactness=0.01,
        ),
    )

    seg = _segment(img)
    classify_segmentation_result(
        metadata=seg.metadata,
        labels=seg.artifacts.labels,
        barrier_mask=seg.artifacts.binary_repaired,
        exterior_mask=seg.artifacts.exterior_mask,
        config=cfg,
    )

    sliver = min(seg.metadata["acceptedRegions"], key=lambda r: r["features"]["tapTargetRadiusPercent"])
    assert sliver["features"]["tapTargetRadiusPercent"] < cfg.children_detailed.min_tap_radius_percent
    assert sliver["profiles"]["childrenDetailed"]["included"] is True


def test_classification_is_deterministic_and_reasons_stable() -> None:
    img = _blank()
    _box(img, 12, 12, 62, 62, thickness=2)
    _box(img, 88, 12, 18, 18, thickness=1)
    _box(img, 88, 38, 28, 26, thickness=1)

    a = _segment(img)
    b = _segment(img)

    classify_segmentation_result(a.metadata, a.artifacts.labels, a.artifacts.binary_repaired, a.artifacts.exterior_mask, _config())
    classify_segmentation_result(b.metadata, b.artifacts.labels, b.artifacts.binary_repaired, b.artifacts.exterior_mask, _config())

    ar = a.metadata["acceptedRegions"]
    br = b.metadata["acceptedRegions"]

    assert [r["id"] for r in ar] == [r["id"] for r in br]
    assert [r["profiles"] for r in ar] == [r["profiles"] for r in br]


def test_profile_configuration_changes_results_predictably() -> None:
    img = _blank()
    _box(img, 10, 10, 80, 80, thickness=2)
    _box(img, 98, 20, 26, 26, thickness=1)

    seg_a = _segment(img)
    seg_b = _segment(img)

    loose = _config()
    strict = SuitabilityConfig(
        children_detailed=ProfileThresholds(
            min_area_percent=2.2,
            min_bounding_dimension_percent=9.0,
            min_tap_radius_percent=1.4,
            min_occupancy_ratio=0.2,
            min_aspect_ratio=0.1,
            min_compactness=0.02,
        ),
        children_simple=ProfileThresholds(
            min_area_percent=7.0,
            min_bounding_dimension_percent=15.0,
            min_tap_radius_percent=2.2,
            min_occupancy_ratio=0.24,
            min_aspect_ratio=0.14,
            min_compactness=0.02,
        ),
    )

    classify_segmentation_result(seg_a.metadata, seg_a.artifacts.labels, seg_a.artifacts.binary_repaired, seg_a.artifacts.exterior_mask, loose)
    classify_segmentation_result(seg_b.metadata, seg_b.artifacts.labels, seg_b.artifacts.binary_repaired, seg_b.artifacts.exterior_mask, strict)

    loose_count = seg_a.metadata["suitabilityProfiles"]["summaries"]["childrenDetailed"]["includedCount"]
    strict_count = seg_b.metadata["suitabilityProfiles"]["summaries"]["childrenDetailed"]["includedCount"]
    assert strict_count <= loose_count


def test_legitimate_small_region_survives_children_detailed() -> None:
    img = _blank(180, 120)
    _box(img, 10, 10, 70, 70, thickness=2)
    _box(img, 105, 20, 14, 14, thickness=1)

    seg = _segment(img)
    classify_segmentation_result(
        metadata=seg.metadata,
        labels=seg.artifacts.labels,
        barrier_mask=seg.artifacts.binary_repaired,
        exterior_mask=seg.artifacts.exterior_mask,
        config=_config(),
    )

    small = min(seg.metadata["acceptedRegions"], key=lambda r: r["areaPixels"])
    assert small["profiles"]["master"]["included"] is True
    assert small["profiles"]["childrenDetailed"]["included"] is True


def test_metadata_contains_profile_results_and_master_ids_unchanged() -> None:
    img = _blank()
    _box(img, 14, 14, 60, 60, thickness=2)
    _box(img, 80, 20, 30, 30, thickness=1)

    seg = _segment(img)
    original_ids = [r["id"] for r in seg.metadata["acceptedRegions"]]

    classify_segmentation_result(
        metadata=seg.metadata,
        labels=seg.artifacts.labels,
        barrier_mask=seg.artifacts.binary_repaired,
        exterior_mask=seg.artifacts.exterior_mask,
        config=_config(),
    )

    assert "suitabilityProfiles" in seg.metadata
    assert "openBoundaryDiagnostics" in seg.metadata
    assert [r["id"] for r in seg.metadata["acceptedRegions"]] == original_ids
    for region in seg.metadata["acceptedRegions"]:
        assert "features" in region
        assert "profiles" in region


def test_write_profile_artifacts_exports_canonical_qa_images() -> None:
    img = _blank(180, 120)
    _box(img, 10, 10, 70, 70, thickness=2)
    _box(img, 100, 10, 8, 8, thickness=1)

    seg = _segment(img)
    classify_segmentation_result(
        metadata=seg.metadata,
        labels=seg.artifacts.labels,
        barrier_mask=seg.artifacts.binary_repaired,
        exterior_mask=seg.artifacts.exterior_mask,
        config=_config(),
    )

    with TemporaryDirectory() as temp_dir:
        paths = write_profile_artifacts(
            Path(temp_dir),
            seg.metadata,
            seg.artifacts.labels,
            seg.artifacts.binary_repaired,
        )

        assert paths["master_qa_fullcolor"].exists()
        assert paths["children_detailed_qa_fullcolor"].exists()
        assert paths["master_vs_children_detailed_coverage"].exists()
        assert paths["master_vs_children_detailed_coverage_labeled"].exists()

        coverage = np.array(Image.open(paths["master_vs_children_detailed_coverage"]))
        assert np.any(np.all(coverage == np.array([0, 0, 0], dtype=np.uint8), axis=-1))
        assert np.any(np.all(coverage == np.array([255, 255, 255], dtype=np.uint8), axis=-1))
        assert np.any(coverage[:, :, 1] > coverage[:, :, 0])
        assert np.any(coverage[:, :, 0] > coverage[:, :, 1])
