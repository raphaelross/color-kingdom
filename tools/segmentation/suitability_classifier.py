from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
import json
import math
import time

import cv2
import numpy as np
from PIL import Image


PROFILE_MASTER = "MASTER"
PROFILE_CHILDREN_DETAILED = "CHILDREN_DETAILED"
PROFILE_CHILDREN_SIMPLE = "CHILDREN_SIMPLE"

REASON_AREA_TOO_SMALL = "AREA_TOO_SMALL"
REASON_BOUNDING_DIMENSION_TOO_SMALL = "BOUNDING_DIMENSION_TOO_SMALL"
REASON_TAP_TARGET_TOO_SMALL = "TAP_TARGET_TOO_SMALL"
REASON_TOO_THIN = "TOO_THIN"
REASON_LOW_OCCUPANCY = "LOW_OCCUPANCY"
REASON_FLAGGED_SEGMENTATION_ARTIFACT = "FLAGGED_SEGMENTATION_ARTIFACT"
REASON_SCORE_BELOW_THRESHOLD = "SCORE_BELOW_THRESHOLD"
REASON_GUARDRAIL_AREA_TOO_SMALL = "GUARDRAIL_AREA_TOO_SMALL"
REASON_GUARDRAIL_BOUNDING_DIMENSION_TOO_SMALL = "GUARDRAIL_BOUNDING_DIMENSION_TOO_SMALL"
REASON_GUARDRAIL_TAP_TARGET_TOO_SMALL = "GUARDRAIL_TAP_TARGET_TOO_SMALL"


@dataclass(frozen=True)
class ProfileThresholds:
    min_area_percent: float
    min_bounding_dimension_percent: float
    min_tap_radius_percent: float
    min_occupancy_ratio: float
    min_aspect_ratio: float
    min_compactness: float


@dataclass(frozen=True)
class WeightedChildrenDetailedConfig:
    score_threshold: float
    normalize_low_percentile: float
    normalize_high_percentile: float
    weight_area: float
    weight_tap_target: float
    weight_min_dimension: float
    weight_occupancy: float
    weight_compactness: float
    weight_aspect_ratio: float
    guardrail_min_area_percent: float
    guardrail_min_bounding_dimension_percent: float
    guardrail_min_tap_radius_percent: float


@dataclass(frozen=True)
class SuitabilityConfig:
    children_detailed: ProfileThresholds
    children_simple: ProfileThresholds
    children_detailed_mode: str = "threshold"
    children_detailed_weighted: WeightedChildrenDetailedConfig | None = None
    artifact_compactness_floor: float = 0.012
    artifact_min_dimension_percent_floor: float = 0.18


def default_suitability_config() -> SuitabilityConfig:
    # These defaults are tuned for a children's-first profile split while preserving master detail.
    return SuitabilityConfig(
        children_detailed=ProfileThresholds(
            min_area_percent=0.04,
            min_bounding_dimension_percent=1.2,
            min_tap_radius_percent=0.42,
            min_occupancy_ratio=0.24,
            min_aspect_ratio=0.09,
            min_compactness=0.02,
        ),
        children_simple=ProfileThresholds(
            min_area_percent=0.11,
            min_bounding_dimension_percent=2.1,
            min_tap_radius_percent=0.8,
            min_occupancy_ratio=0.28,
            min_aspect_ratio=0.13,
            min_compactness=0.03,
        ),
        children_detailed_weighted=WeightedChildrenDetailedConfig(
            score_threshold=0.58,
            normalize_low_percentile=10.0,
            normalize_high_percentile=90.0,
            weight_area=0.20,
            weight_tap_target=0.30,
            weight_min_dimension=0.20,
            weight_occupancy=0.10,
            weight_compactness=0.10,
            weight_aspect_ratio=0.10,
            guardrail_min_area_percent=0.02,
            guardrail_min_bounding_dimension_percent=2.0,
            guardrail_min_tap_radius_percent=0.50,
        ),
    )


def _save_u8_image(path: Path, arr: np.ndarray) -> None:
    if arr.dtype != np.uint8:
        arr = arr.astype(np.uint8)
    Image.fromarray(arr).save(path)


def _calc_features_for_region(
    labels: np.ndarray,
    component_label: int,
    area_pixels: int,
    bounds: dict[str, int],
    centroid: dict[str, float],
    image_w: int,
    image_h: int,
) -> dict[str, Any]:
    region_mask = (labels == component_label).astype(np.uint8)

    bbox_w = int(bounds["width"])
    bbox_h = int(bounds["height"])
    bbox_area = int(bbox_w * bbox_h)

    min_dim_px = float(min(bbox_w, bbox_h))
    aspect_ratio = float((min_dim_px / max(bbox_w, bbox_h)) if max(bbox_w, bbox_h) > 0 else 0.0)
    occupancy_ratio = float((area_pixels / bbox_area) if bbox_area > 0 else 0.0)

    contours, _ = cv2.findContours(region_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    perimeter = float(sum(cv2.arcLength(cnt, True) for cnt in contours))
    compactness = float((4.0 * math.pi * area_pixels) / (perimeter * perimeter) if perimeter > 0.0 else 0.0)

    dist = cv2.distanceTransform(region_mask, cv2.DIST_L2, 3)
    max_inscribed_radius_px = float(dist.max()) if dist.size > 0 else 0.0
    tap_target_diameter_px = float(max_inscribed_radius_px * 2.0)

    min_image_dim = float(min(image_w, image_h))

    return {
        "areaPixels": int(area_pixels),
        "areaPercent": float((area_pixels / float(image_w * image_h)) * 100.0),
        "boundingBoxWidthPixels": int(bbox_w),
        "boundingBoxHeightPixels": int(bbox_h),
        "boundingBoxAreaPixels": int(bbox_area),
        "boundingBoxWidthPercent": float((bbox_w / image_w) * 100.0),
        "boundingBoxHeightPercent": float((bbox_h / image_h) * 100.0),
        "centroid": {"x": float(centroid["x"]), "y": float(centroid["y"])},
        "minBoundingDimensionPixels": float(min_dim_px),
        "minBoundingDimensionPercent": float((min_dim_px / min_image_dim) * 100.0),
        "aspectRatio": aspect_ratio,
        "occupancyRatio": occupancy_ratio,
        "perimeterPixels": perimeter,
        "compactness": compactness,
        "maxInscribedRadiusPixels": max_inscribed_radius_px,
        "tapTargetDiameterPixels": tap_target_diameter_px,
        "tapTargetRadiusPercent": float((max_inscribed_radius_px / min_image_dim) * 100.0),
        "tapTargetDiameterPercent": float((tap_target_diameter_px / min_image_dim) * 100.0),
    }


def _classify_profile(features: dict[str, Any], thresholds: ProfileThresholds) -> list[str]:
    reasons: list[str] = []

    if features["areaPercent"] < thresholds.min_area_percent:
        reasons.append(REASON_AREA_TOO_SMALL)
    if features["minBoundingDimensionPercent"] < thresholds.min_bounding_dimension_percent:
        reasons.append(REASON_BOUNDING_DIMENSION_TOO_SMALL)
    if features["tapTargetRadiusPercent"] < thresholds.min_tap_radius_percent:
        reasons.append(REASON_TAP_TARGET_TOO_SMALL)
    if features["aspectRatio"] < thresholds.min_aspect_ratio:
        reasons.append(REASON_TOO_THIN)
    if thresholds.min_occupancy_ratio > 0 and features["occupancyRatio"] < thresholds.min_occupancy_ratio:
        reasons.append(REASON_LOW_OCCUPANCY)
    if features["compactness"] < thresholds.min_compactness:
        reasons.append(REASON_FLAGGED_SEGMENTATION_ARTIFACT)

    return reasons


def _compute_feature_distribution(
    regions: list[dict[str, Any]],
    feature_key: str,
    low_percentile: float,
    high_percentile: float,
) -> tuple[float, float]:
    vals = np.array([float(r["features"][feature_key]) for r in regions], dtype=np.float64)
    low = float(np.percentile(vals, low_percentile))
    high = float(np.percentile(vals, high_percentile))
    if high <= low:
        high = low + 1e-9
    return low, high


def _normalize_clamped(value: float, low: float, high: float) -> float:
    if high <= low:
        return 0.0
    n = (value - low) / (high - low)
    return float(max(0.0, min(1.0, n)))


def _classify_children_detailed_weighted(
    features: dict[str, Any],
    weighted: WeightedChildrenDetailedConfig,
    distributions: dict[str, tuple[float, float]],
) -> dict[str, Any]:
    guardrail_reasons: list[str] = []
    if features["areaPercent"] < weighted.guardrail_min_area_percent:
        guardrail_reasons.append(REASON_GUARDRAIL_AREA_TOO_SMALL)
    if features["minBoundingDimensionPercent"] < weighted.guardrail_min_bounding_dimension_percent:
        guardrail_reasons.append(REASON_GUARDRAIL_BOUNDING_DIMENSION_TOO_SMALL)
    if features["tapTargetRadiusPercent"] < weighted.guardrail_min_tap_radius_percent:
        guardrail_reasons.append(REASON_GUARDRAIL_TAP_TARGET_TOO_SMALL)

    weights = {
        "area": float(weighted.weight_area),
        "tapTarget": float(weighted.weight_tap_target),
        "minDimension": float(weighted.weight_min_dimension),
        "occupancy": float(weighted.weight_occupancy),
        "compactness": float(weighted.weight_compactness),
        "aspectRatio": float(weighted.weight_aspect_ratio),
    }

    total_weight = float(sum(weights.values()))
    if total_weight <= 0.0:
        raise ValueError("children_detailed weighted score requires a positive total feature weight")

    normalized = {
        "area": _normalize_clamped(features["areaPercent"], *distributions["areaPercent"]),
        "tapTarget": _normalize_clamped(features["tapTargetRadiusPercent"], *distributions["tapTargetRadiusPercent"]),
        "minDimension": _normalize_clamped(
            features["minBoundingDimensionPercent"], *distributions["minBoundingDimensionPercent"]
        ),
        "occupancy": _normalize_clamped(features["occupancyRatio"], *distributions["occupancyRatio"]),
        "compactness": _normalize_clamped(features["compactness"], *distributions["compactness"]),
        "aspectRatio": _normalize_clamped(features["aspectRatio"], *distributions["aspectRatio"]),
    }

    contributions = {k: float(normalized[k] * weights[k]) for k in normalized}
    score = float(sum(contributions.values()) / total_weight)

    pass_guardrail = len(guardrail_reasons) == 0
    if not pass_guardrail:
        return {
            "included": False,
            "score": score,
            "threshold": float(weighted.score_threshold),
            "hardGuardrailPassed": False,
            "reasons": guardrail_reasons,
            "contributions": contributions,
            "normalizedFeatures": normalized,
        }

    if score < float(weighted.score_threshold):
        return {
            "included": False,
            "score": score,
            "threshold": float(weighted.score_threshold),
            "hardGuardrailPassed": True,
            "reasons": [REASON_SCORE_BELOW_THRESHOLD],
            "contributions": contributions,
            "normalizedFeatures": normalized,
        }

    return {
        "included": True,
        "score": score,
        "threshold": float(weighted.score_threshold),
        "hardGuardrailPassed": True,
        "reasons": [],
        "contributions": contributions,
        "normalizedFeatures": normalized,
    }


def _build_profile_summary(regions: list[dict[str, Any]], profile_key: str) -> dict[str, Any]:
    included = [r for r in regions if r["profiles"][profile_key]["included"]]
    excluded = [r for r in regions if not r["profiles"][profile_key]["included"]]

    reason_counts: dict[str, int] = {}
    for region in excluded:
        for reason in region["profiles"][profile_key].get("reasons", []):
            reason_counts[reason] = reason_counts.get(reason, 0) + 1

    areas = sorted([r["features"]["areaPixels"] for r in included])
    tap_radii = sorted([r["features"]["maxInscribedRadiusPixels"] for r in included])

    if areas:
        smallest = int(areas[0])
        median = float(np.median(np.array(areas, dtype=np.float64)))
        largest = int(areas[-1])
    else:
        smallest = 0
        median = 0.0
        largest = 0

    smallest_tap_radius_px = float(tap_radii[0]) if tap_radii else 0.0

    return {
        "includedCount": int(len(included)),
        "excludedCount": int(len(excluded)),
        "exclusionReasonCounts": reason_counts,
        "smallestIncludedAreaPixels": smallest,
        "medianIncludedAreaPixels": median,
        "largestIncludedAreaPixels": largest,
        "smallestIncludedTapRadiusPixels": smallest_tap_radius_px,
    }


def _render_profile_debug(
    labels: np.ndarray,
    barrier_mask: np.ndarray,
    regions: list[dict[str, Any]],
    profile_key: str,
) -> np.ndarray:
    h, w = labels.shape
    canvas = np.full((h, w, 3), 255, dtype=np.uint8)

    for region in regions:
        mask = labels == int(region["componentLabel"])
        included = bool(region["profiles"][profile_key]["included"])
        if included:
            color = np.array(region["mapColorRgba"][:3], dtype=np.uint8)
            canvas[mask] = ((0.38 * canvas[mask]) + (0.62 * color)).astype(np.uint8)
        else:
            # Keep excluded regions visible but clearly de-emphasized.
            gray = np.array([225, 225, 225], dtype=np.uint8)
            canvas[mask] = ((0.55 * canvas[mask]) + (0.45 * gray)).astype(np.uint8)

    canvas[barrier_mask == 1] = np.array([0, 0, 0], dtype=np.uint8)
    return canvas


def _render_profile_exclusions(
    labels: np.ndarray,
    barrier_mask: np.ndarray,
    regions: list[dict[str, Any]],
    profile_key: str,
) -> np.ndarray:
    h, w = labels.shape
    canvas = np.full((h, w, 3), 255, dtype=np.uint8)

    green = np.array([95, 190, 110], dtype=np.uint8)
    gray = np.array([170, 170, 170], dtype=np.uint8)

    for region in regions:
        mask = labels == int(region["componentLabel"])
        included = bool(region["profiles"][profile_key]["included"])
        color = green if included else gray
        alpha = 0.62 if included else 0.55
        canvas[mask] = ((1.0 - alpha) * canvas[mask] + alpha * color).astype(np.uint8)

    canvas[barrier_mask == 1] = np.array([0, 0, 0], dtype=np.uint8)
    return canvas


def _render_profile_comparison(
    labels: np.ndarray,
    barrier_mask: np.ndarray,
    regions: list[dict[str, Any]],
    baseline_key: str,
    weighted_key: str,
) -> np.ndarray:
    h, w = labels.shape
    canvas = np.full((h, w, 3), 255, dtype=np.uint8)

    # Legend:
    # both included: blue
    # both excluded: light gray
    # newly included by weighted: green
    # newly excluded by weighted: orange
    both_included = np.array([100, 140, 230], dtype=np.uint8)
    both_excluded = np.array([220, 220, 220], dtype=np.uint8)
    newly_included = np.array([90, 190, 105], dtype=np.uint8)
    newly_excluded = np.array([225, 150, 85], dtype=np.uint8)

    for region in regions:
        mask = labels == int(region["componentLabel"])
        baseline = bool(region["profiles"][baseline_key]["included"])
        weighted = bool(region["profiles"][weighted_key]["included"])

        if baseline and weighted:
            color = both_included
        elif (not baseline) and (not weighted):
            color = both_excluded
        elif (not baseline) and weighted:
            color = newly_included
        else:
            color = newly_excluded

        canvas[mask] = ((0.4 * canvas[mask]) + (0.6 * color)).astype(np.uint8)

    canvas[barrier_mask == 1] = np.array([0, 0, 0], dtype=np.uint8)
    return canvas


def _compute_open_boundary_diagnostics(
    barrier_mask: np.ndarray,
    exterior_mask: np.ndarray,
    image_w: int,
    image_h: int,
) -> dict[str, Any]:
    diagnostics: dict[str, Any] = {
        "humanQaRequired": True,
        "notes": "Heuristic only: likely leaks need manual QA confirmation.",
    }

    ext = (exterior_mask == 1).astype(np.uint8)
    interior_roi = np.zeros_like(ext)
    margin_x = max(8, int(round(image_w * 0.05)))
    margin_y = max(8, int(round(image_h * 0.05)))
    interior_roi[margin_y : image_h - margin_y, margin_x : image_w - margin_x] = 1

    deep_exterior = ((ext == 1) & (interior_roi == 1)).astype(np.uint8)

    n_labels, cc_labels, cc_stats, _ = cv2.connectedComponentsWithStats(deep_exterior, connectivity=8)

    suspicious_components: list[dict[str, Any]] = []
    area_threshold = int((image_w * image_h) * 0.002)

    for label in range(1, n_labels):
        area = int(cc_stats[label, cv2.CC_STAT_AREA])
        if area < area_threshold:
            continue

        x = int(cc_stats[label, cv2.CC_STAT_LEFT])
        y = int(cc_stats[label, cv2.CC_STAT_TOP])
        w = int(cc_stats[label, cv2.CC_STAT_WIDTH])
        h = int(cc_stats[label, cv2.CC_STAT_HEIGHT])

        comp_mask = (cc_labels == label).astype(np.uint8)
        channel_width = cv2.distanceTransform(comp_mask, cv2.DIST_L2, 3)
        median_radius = float(np.median(channel_width[channel_width > 0])) if np.any(channel_width > 0) else 0.0

        if median_radius < 2.0:
            suspicious_components.append(
                {
                    "label": int(label),
                    "areaPixels": area,
                    "bounds": {"x": x, "y": y, "width": w, "height": h},
                    "medianExteriorChannelRadiusPixels": median_radius,
                }
            )

    diagnostics["deepExteriorComponentCount"] = int(n_labels - 1)
    diagnostics["suspiciousDeepExteriorComponents"] = suspicious_components
    diagnostics["suspiciousCount"] = int(len(suspicious_components))

    return diagnostics


def classify_segmentation_result(
    metadata: dict[str, Any],
    labels: np.ndarray,
    barrier_mask: np.ndarray,
    exterior_mask: np.ndarray,
    config: SuitabilityConfig,
) -> dict[str, Any]:
    h = int(metadata["source"]["height"])
    w = int(metadata["source"]["width"])

    accepted_regions = metadata.get("acceptedRegions", [])

    t0 = time.perf_counter()
    enriched_regions: list[dict[str, Any]] = []

    for region in accepted_regions:
        features = _calc_features_for_region(
            labels=labels,
            component_label=int(region["componentLabel"]),
            area_pixels=int(region["areaPixels"]),
            bounds=region["bounds"],
            centroid=region["centroid"],
            image_w=w,
            image_h=h,
        )
        enriched = dict(region)
        enriched["features"] = features
        enriched_regions.append(enriched)

    feature_ms = (time.perf_counter() - t0) * 1000.0

    weighted_cfg = config.children_detailed_weighted or default_suitability_config().children_detailed_weighted
    if weighted_cfg is None:
        raise ValueError("children_detailed weighted config is required")

    distributions = {
        "areaPercent": _compute_feature_distribution(
            enriched_regions,
            "areaPercent",
            weighted_cfg.normalize_low_percentile,
            weighted_cfg.normalize_high_percentile,
        ),
        "tapTargetRadiusPercent": _compute_feature_distribution(
            enriched_regions,
            "tapTargetRadiusPercent",
            weighted_cfg.normalize_low_percentile,
            weighted_cfg.normalize_high_percentile,
        ),
        "minBoundingDimensionPercent": _compute_feature_distribution(
            enriched_regions,
            "minBoundingDimensionPercent",
            weighted_cfg.normalize_low_percentile,
            weighted_cfg.normalize_high_percentile,
        ),
        "occupancyRatio": _compute_feature_distribution(
            enriched_regions,
            "occupancyRatio",
            weighted_cfg.normalize_low_percentile,
            weighted_cfg.normalize_high_percentile,
        ),
        "compactness": _compute_feature_distribution(
            enriched_regions,
            "compactness",
            weighted_cfg.normalize_low_percentile,
            weighted_cfg.normalize_high_percentile,
        ),
        "aspectRatio": _compute_feature_distribution(
            enriched_regions,
            "aspectRatio",
            weighted_cfg.normalize_low_percentile,
            weighted_cfg.normalize_high_percentile,
        ),
    }

    t1 = time.perf_counter()
    for region in enriched_regions:
        features = region["features"]

        detailed_thresholds = ProfileThresholds(
            min_area_percent=config.children_detailed.min_area_percent,
            min_bounding_dimension_percent=config.children_detailed.min_bounding_dimension_percent,
            min_tap_radius_percent=config.children_detailed.min_tap_radius_percent,
            min_occupancy_ratio=0.0,
            min_aspect_ratio=config.children_detailed.min_aspect_ratio,
            min_compactness=config.children_detailed.min_compactness,
        )

        detailed_reasons = _classify_profile(features, detailed_thresholds)
        simple_reasons = _classify_profile(features, config.children_simple)
        detailed_weighted = _classify_children_detailed_weighted(features, weighted_cfg, distributions)

        detailed_active = {
            "included": bool(detailed_weighted["included"]),
            "reasons": list(detailed_weighted["reasons"]),
        }
        if config.children_detailed_mode != "weighted":
            detailed_active = {
                "included": len(detailed_reasons) == 0,
                "reasons": detailed_reasons,
            }

        region["profiles"] = {
            "master": {"included": True, "reasons": []},
            "childrenDetailed": detailed_active,
            "childrenDetailedBaseline": {
                "included": len(detailed_reasons) == 0,
                "reasons": detailed_reasons,
            },
            "childrenDetailedWeighted": {
                "included": bool(detailed_weighted["included"]),
                "reasons": list(detailed_weighted["reasons"]),
            },
            "childrenSimple": {
                "included": len(simple_reasons) == 0,
                "reasons": simple_reasons,
            },
        }
        region["childrenDetailedWeighted"] = detailed_weighted

    class_ms = (time.perf_counter() - t1) * 1000.0

    profile_summaries = {
        "master": _build_profile_summary(enriched_regions, "master"),
        "childrenDetailed": _build_profile_summary(enriched_regions, "childrenDetailed"),
        "childrenDetailedBaseline": _build_profile_summary(enriched_regions, "childrenDetailedBaseline"),
        "childrenDetailedWeighted": _build_profile_summary(enriched_regions, "childrenDetailedWeighted"),
        "childrenSimple": _build_profile_summary(enriched_regions, "childrenSimple"),
    }

    weighted_scores = np.array(
        [float(r["childrenDetailedWeighted"]["score"]) for r in enriched_regions], dtype=np.float64
    )
    score_distribution = {
        "min": float(np.min(weighted_scores)) if weighted_scores.size else 0.0,
        "p10": float(np.percentile(weighted_scores, 10)) if weighted_scores.size else 0.0,
        "p25": float(np.percentile(weighted_scores, 25)) if weighted_scores.size else 0.0,
        "median": float(np.percentile(weighted_scores, 50)) if weighted_scores.size else 0.0,
        "p75": float(np.percentile(weighted_scores, 75)) if weighted_scores.size else 0.0,
        "p90": float(np.percentile(weighted_scores, 90)) if weighted_scores.size else 0.0,
        "max": float(np.max(weighted_scores)) if weighted_scores.size else 0.0,
    }

    diagnostics = _compute_open_boundary_diagnostics(
        barrier_mask=barrier_mask,
        exterior_mask=exterior_mask,
        image_w=w,
        image_h=h,
    )

    metadata["acceptedRegions"] = enriched_regions
    metadata["suitabilityProfiles"] = {
        "schemaVersion": "1.0.0",
        "childrenDetailedMode": config.children_detailed_mode,
        "profiles": {
            "master": {
                "description": "High-detail master profile preserving all accepted segmentation regions.",
            },
            "childrenDetailed": {
                "description": "Children profile with moderate detail and practical tap targets.",
                "thresholds": {
                    "minAreaPercent": config.children_detailed.min_area_percent,
                    "minBoundingDimensionPercent": config.children_detailed.min_bounding_dimension_percent,
                    "minTapRadiusPercent": config.children_detailed.min_tap_radius_percent,
                    "minOccupancyRatio": config.children_detailed.min_occupancy_ratio,
                    "minAspectRatio": config.children_detailed.min_aspect_ratio,
                    "minCompactness": config.children_detailed.min_compactness,
                },
            },
            "childrenDetailedWeighted": {
                "description": "Weighted children-detailed profile with hard guardrails plus weighted score.",
                "scoreRange": "0.0-1.0",
                "scoreThreshold": weighted_cfg.score_threshold,
                "normalizeLowPercentile": weighted_cfg.normalize_low_percentile,
                "normalizeHighPercentile": weighted_cfg.normalize_high_percentile,
                "weights": {
                    "area": weighted_cfg.weight_area,
                    "tapTarget": weighted_cfg.weight_tap_target,
                    "minDimension": weighted_cfg.weight_min_dimension,
                    "occupancy": weighted_cfg.weight_occupancy,
                    "compactness": weighted_cfg.weight_compactness,
                    "aspectRatio": weighted_cfg.weight_aspect_ratio,
                },
                "hardGuardrails": {
                    "minAreaPercent": weighted_cfg.guardrail_min_area_percent,
                    "minBoundingDimensionPercent": weighted_cfg.guardrail_min_bounding_dimension_percent,
                    "minTapRadiusPercent": weighted_cfg.guardrail_min_tap_radius_percent,
                },
                "featureNormalizationRanges": {
                    k: {"low": float(v[0]), "high": float(v[1])} for k, v in distributions.items()
                },
                "scoreDistribution": score_distribution,
            },
            "childrenSimple": {
                "description": "Children profile prioritizing larger/easier targets and lower coloring workload.",
                "thresholds": {
                    "minAreaPercent": config.children_simple.min_area_percent,
                    "minBoundingDimensionPercent": config.children_simple.min_bounding_dimension_percent,
                    "minTapRadiusPercent": config.children_simple.min_tap_radius_percent,
                    "minOccupancyRatio": config.children_simple.min_occupancy_ratio,
                    "minAspectRatio": config.children_simple.min_aspect_ratio,
                    "minCompactness": config.children_simple.min_compactness,
                },
            },
        },
        "reasonCodes": [
            REASON_AREA_TOO_SMALL,
            REASON_BOUNDING_DIMENSION_TOO_SMALL,
            REASON_TAP_TARGET_TOO_SMALL,
            REASON_TOO_THIN,
            REASON_LOW_OCCUPANCY,
            REASON_FLAGGED_SEGMENTATION_ARTIFACT,
            REASON_SCORE_BELOW_THRESHOLD,
            REASON_GUARDRAIL_AREA_TOO_SMALL,
            REASON_GUARDRAIL_BOUNDING_DIMENSION_TOO_SMALL,
            REASON_GUARDRAIL_TAP_TARGET_TOO_SMALL,
        ],
        "summaries": profile_summaries,
    }

    metadata["openBoundaryDiagnostics"] = diagnostics
    metadata["suitabilityTimingMs"] = {
        "featureExtractionMs": feature_ms,
        "classificationMs": class_ms,
    }

    return {
        "featureExtractionMs": feature_ms,
        "classificationMs": class_ms,
        "profileSummaries": profile_summaries,
        "openBoundaryDiagnostics": diagnostics,
    }


def write_profile_artifacts(output_dir: Path, metadata: dict[str, Any], labels: np.ndarray, barrier_mask: np.ndarray) -> dict[str, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)

    accepted_regions = metadata["acceptedRegions"]

    master_debug = _render_profile_debug(labels, barrier_mask, accepted_regions, "master")
    children_detailed_debug = _render_profile_debug(labels, barrier_mask, accepted_regions, "childrenDetailed")
    children_detailed_baseline_debug = _render_profile_debug(
        labels, barrier_mask, accepted_regions, "childrenDetailedBaseline"
    )
    children_detailed_weighted_debug = _render_profile_debug(
        labels, barrier_mask, accepted_regions, "childrenDetailedWeighted"
    )
    children_simple_debug = _render_profile_debug(labels, barrier_mask, accepted_regions, "childrenSimple")

    children_detailed_exclusions = _render_profile_exclusions(
        labels, barrier_mask, accepted_regions, "childrenDetailed"
    )
    children_detailed_baseline_exclusions = _render_profile_exclusions(
        labels, barrier_mask, accepted_regions, "childrenDetailedBaseline"
    )
    children_detailed_weighted_exclusions = _render_profile_exclusions(
        labels, barrier_mask, accepted_regions, "childrenDetailedWeighted"
    )
    children_simple_exclusions = _render_profile_exclusions(
        labels, barrier_mask, accepted_regions, "childrenSimple"
    )
    children_detailed_comparison = _render_profile_comparison(
        labels,
        barrier_mask,
        accepted_regions,
        "childrenDetailedBaseline",
        "childrenDetailedWeighted",
    )

    master_debug_path = output_dir / "regions_master_debug.png"
    children_detailed_debug_path = output_dir / "regions_children_detailed_debug.png"
    children_detailed_baseline_debug_path = output_dir / "regions_children_detailed_baseline_debug.png"
    children_detailed_weighted_debug_path = output_dir / "regions_children_detailed_weighted_debug.png"
    children_detailed_exclusions_path = output_dir / "regions_children_detailed_exclusions.png"
    children_detailed_baseline_exclusions_path = output_dir / "regions_children_detailed_baseline_exclusions.png"
    children_detailed_weighted_exclusions_path = output_dir / "regions_children_detailed_weighted_exclusions.png"
    children_detailed_comparison_path = output_dir / "regions_children_detailed_comparison.png"
    children_simple_debug_path = output_dir / "regions_children_simple_debug.png"
    children_simple_exclusions_path = output_dir / "regions_children_simple_exclusions.png"

    _save_u8_image(master_debug_path, master_debug)
    _save_u8_image(children_detailed_debug_path, children_detailed_debug)
    _save_u8_image(children_detailed_baseline_debug_path, children_detailed_baseline_debug)
    _save_u8_image(children_detailed_weighted_debug_path, children_detailed_weighted_debug)
    _save_u8_image(children_detailed_exclusions_path, children_detailed_exclusions)
    _save_u8_image(children_detailed_baseline_exclusions_path, children_detailed_baseline_exclusions)
    _save_u8_image(children_detailed_weighted_exclusions_path, children_detailed_weighted_exclusions)
    _save_u8_image(children_detailed_comparison_path, children_detailed_comparison)
    _save_u8_image(children_simple_debug_path, children_simple_debug)
    _save_u8_image(children_simple_exclusions_path, children_simple_exclusions)

    metadata_path = output_dir / "regions.json"
    with metadata_path.open("w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, sort_keys=True)

    return {
        "master_debug": master_debug_path,
        "children_detailed_debug": children_detailed_debug_path,
        "children_detailed_baseline_debug": children_detailed_baseline_debug_path,
        "children_detailed_weighted_debug": children_detailed_weighted_debug_path,
        "children_detailed_exclusions": children_detailed_exclusions_path,
        "children_detailed_baseline_exclusions": children_detailed_baseline_exclusions_path,
        "children_detailed_weighted_exclusions": children_detailed_weighted_exclusions_path,
        "children_detailed_comparison": children_detailed_comparison_path,
        "children_simple_debug": children_simple_debug_path,
        "children_simple_exclusions": children_simple_exclusions_path,
        "metadata_json": metadata_path,
    }
