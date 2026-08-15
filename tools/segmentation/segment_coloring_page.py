from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from time import perf_counter
import copy

from segmentation_pipeline import SegmentationConfig, segment_image_file, write_artifacts
from boundary_repair import (
    BoundaryRepairConfig,
    detect_and_repair_boundaries,
    write_boundary_repair_artifacts,
)
from suitability_classifier import (
    SuitabilityConfig,
    ProfileThresholds,
    WeightedChildrenDetailedConfig,
    classify_segmentation_result,
    default_suitability_config,
    write_profile_artifacts,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Offline deterministic segmentation tool for coloring-page raster line art."
    )
    parser.add_argument("--input", required=True, help="Path to source raster line-art image")
    parser.add_argument("--output-dir", required=True, help="Directory for generated outputs")
    parser.add_argument("--variant-name", default=None, help="Optional variant label for reports")

    parser.add_argument("--threshold", type=int, default=185, help="Barrier threshold (0-255), darker pixels become barriers")
    parser.add_argument("--morph-kernel", type=int, default=0, help="Morphology close kernel size (0 or 1 disables)")
    parser.add_argument("--morph-iterations", type=int, default=1, help="Morphology close iteration count")
    parser.add_argument("--dilate-iterations", type=int, default=0, help="Optional extra barrier dilation iterations")
    parser.add_argument("--min-region-area", type=int, default=250, help="Minimum region area in pixels for ACCEPTED")
    parser.add_argument(
        "--min-region-percent",
        type=float,
        default=0.015,
        help="Minimum percent of image area for ACCEPTED",
    )
    parser.add_argument("--connectivity", type=int, choices=[4, 8], default=8, help="Connected-component connectivity")
    parser.add_argument(
        "--boundary-repair",
        choices=["off", "diagnostics", "conservative"],
        default="off",
        help="Boundary integrity mode",
    )
    parser.add_argument("--max-gap-pixels", type=int, default=6, help="Max gap pixels allowed for a repair bridge")
    parser.add_argument(
        "--candidate-search-radius",
        type=int,
        default=10,
        help="Endpoint pairing search radius in pixels",
    )
    parser.add_argument(
        "--min-new-region-area",
        type=int,
        default=250,
        help="Minimum area for newly created accepted regions during repair validation",
    )
    parser.add_argument(
        "--max-repair-pixels",
        type=int,
        default=8,
        help="Maximum number of barrier pixels allowed per candidate repair",
    )
    parser.add_argument(
        "--border-margin-percent",
        type=float,
        default=2.0,
        help="Percent border margin where repairs are not allowed",
    )
    parser.add_argument(
        "--max-exterior-percent-delta",
        type=float,
        default=1.0,
        help="Maximum allowed exterior percentage delta per applied candidate",
    )
    parser.add_argument(
        "--max-new-regions-per-candidate",
        type=int,
        default=2,
        help="Maximum accepted-region increase allowed per candidate",
    )
    parser.add_argument(
        "--max-candidates-to-validate",
        type=int,
        default=80,
        help="Maximum number of boundary-repair candidates to validate",
    )

    defaults = default_suitability_config()

    parser.add_argument(
        "--children-detailed-min-area-percent",
        type=float,
        default=defaults.children_detailed.min_area_percent,
        help="Children detailed minimum region area percent",
    )
    parser.add_argument(
        "--children-detailed-min-bounding-dimension-percent",
        type=float,
        default=defaults.children_detailed.min_bounding_dimension_percent,
        help="Children detailed minimum bounding dimension percent",
    )
    parser.add_argument(
        "--children-detailed-min-tap-radius-percent",
        type=float,
        default=defaults.children_detailed.min_tap_radius_percent,
        help="Children detailed minimum tap target radius percent",
    )
    parser.add_argument(
        "--children-detailed-min-occupancy",
        type=float,
        default=defaults.children_detailed.min_occupancy_ratio,
        help="Children detailed minimum occupancy ratio",
    )
    parser.add_argument(
        "--children-detailed-min-aspect-ratio",
        type=float,
        default=defaults.children_detailed.min_aspect_ratio,
        help="Children detailed minimum aspect ratio",
    )
    parser.add_argument(
        "--children-detailed-min-compactness",
        type=float,
        default=defaults.children_detailed.min_compactness,
        help="Children detailed minimum compactness",
    )
    parser.add_argument(
        "--children-detailed-mode",
        choices=["threshold", "weighted"],
        default="threshold",
        help="Children detailed classification mode",
    )
    parser.add_argument(
        "--weighted-score-threshold",
        type=float,
        default=defaults.children_detailed_weighted.score_threshold,
        help="Weighted children detailed score threshold in range 0.0-1.0",
    )
    parser.add_argument(
        "--weighted-normalize-low-percentile",
        type=float,
        default=defaults.children_detailed_weighted.normalize_low_percentile,
        help="Low percentile for weighted feature normalization",
    )
    parser.add_argument(
        "--weighted-normalize-high-percentile",
        type=float,
        default=defaults.children_detailed_weighted.normalize_high_percentile,
        help="High percentile for weighted feature normalization",
    )
    parser.add_argument(
        "--weighted-weight-area",
        type=float,
        default=defaults.children_detailed_weighted.weight_area,
        help="Weighted contribution for area score",
    )
    parser.add_argument(
        "--weighted-weight-tap-target",
        type=float,
        default=defaults.children_detailed_weighted.weight_tap_target,
        help="Weighted contribution for tap target score",
    )
    parser.add_argument(
        "--weighted-weight-min-dimension",
        type=float,
        default=defaults.children_detailed_weighted.weight_min_dimension,
        help="Weighted contribution for minimum dimension score",
    )
    parser.add_argument(
        "--weighted-weight-occupancy",
        type=float,
        default=defaults.children_detailed_weighted.weight_occupancy,
        help="Weighted contribution for occupancy score",
    )
    parser.add_argument(
        "--weighted-weight-compactness",
        type=float,
        default=defaults.children_detailed_weighted.weight_compactness,
        help="Weighted contribution for compactness score",
    )
    parser.add_argument(
        "--weighted-weight-aspect-ratio",
        type=float,
        default=defaults.children_detailed_weighted.weight_aspect_ratio,
        help="Weighted contribution for aspect ratio score",
    )
    parser.add_argument(
        "--weighted-guardrail-min-area-percent",
        type=float,
        default=defaults.children_detailed_weighted.guardrail_min_area_percent,
        help="Hard guardrail minimum area percent",
    )
    parser.add_argument(
        "--weighted-guardrail-min-bounding-dimension-percent",
        type=float,
        default=defaults.children_detailed_weighted.guardrail_min_bounding_dimension_percent,
        help="Hard guardrail minimum min-bounding-dimension percent",
    )
    parser.add_argument(
        "--weighted-guardrail-min-tap-radius-percent",
        type=float,
        default=defaults.children_detailed_weighted.guardrail_min_tap_radius_percent,
        help="Hard guardrail minimum tap-radius percent",
    )

    parser.add_argument(
        "--children-simple-min-area-percent",
        type=float,
        default=defaults.children_simple.min_area_percent,
        help="Children simple minimum region area percent",
    )
    parser.add_argument(
        "--children-simple-min-bounding-dimension-percent",
        type=float,
        default=defaults.children_simple.min_bounding_dimension_percent,
        help="Children simple minimum bounding dimension percent",
    )
    parser.add_argument(
        "--children-simple-min-tap-radius-percent",
        type=float,
        default=defaults.children_simple.min_tap_radius_percent,
        help="Children simple minimum tap target radius percent",
    )
    parser.add_argument(
        "--children-simple-min-occupancy",
        type=float,
        default=defaults.children_simple.min_occupancy_ratio,
        help="Children simple minimum occupancy ratio",
    )
    parser.add_argument(
        "--children-simple-min-aspect-ratio",
        type=float,
        default=defaults.children_simple.min_aspect_ratio,
        help="Children simple minimum aspect ratio",
    )
    parser.add_argument(
        "--children-simple-min-compactness",
        type=float,
        default=defaults.children_simple.min_compactness,
        help="Children simple minimum compactness",
    )

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    input_path = Path(args.input).resolve()
    output_dir = Path(args.output_dir).resolve()

    if not input_path.exists():
        parser.error(f"Input image not found: {input_path}")

    config = SegmentationConfig(
        threshold=args.threshold,
        morph_kernel=args.morph_kernel,
        morph_iterations=args.morph_iterations,
        dilate_iterations=args.dilate_iterations,
        min_region_area_pixels=args.min_region_area,
        min_region_area_percent=args.min_region_percent,
        connectivity=args.connectivity,
    )

    suitability = SuitabilityConfig(
        children_detailed=ProfileThresholds(
            min_area_percent=args.children_detailed_min_area_percent,
            min_bounding_dimension_percent=args.children_detailed_min_bounding_dimension_percent,
            min_tap_radius_percent=args.children_detailed_min_tap_radius_percent,
            min_occupancy_ratio=args.children_detailed_min_occupancy,
            min_aspect_ratio=args.children_detailed_min_aspect_ratio,
            min_compactness=args.children_detailed_min_compactness,
        ),
        children_simple=ProfileThresholds(
            min_area_percent=args.children_simple_min_area_percent,
            min_bounding_dimension_percent=args.children_simple_min_bounding_dimension_percent,
            min_tap_radius_percent=args.children_simple_min_tap_radius_percent,
            min_occupancy_ratio=args.children_simple_min_occupancy,
            min_aspect_ratio=args.children_simple_min_aspect_ratio,
            min_compactness=args.children_simple_min_compactness,
        ),
        children_detailed_mode=args.children_detailed_mode,
        children_detailed_weighted=WeightedChildrenDetailedConfig(
            score_threshold=args.weighted_score_threshold,
            normalize_low_percentile=args.weighted_normalize_low_percentile,
            normalize_high_percentile=args.weighted_normalize_high_percentile,
            weight_area=args.weighted_weight_area,
            weight_tap_target=args.weighted_weight_tap_target,
            weight_min_dimension=args.weighted_weight_min_dimension,
            weight_occupancy=args.weighted_weight_occupancy,
            weight_compactness=args.weighted_weight_compactness,
            weight_aspect_ratio=args.weighted_weight_aspect_ratio,
            guardrail_min_area_percent=args.weighted_guardrail_min_area_percent,
            guardrail_min_bounding_dimension_percent=args.weighted_guardrail_min_bounding_dimension_percent,
            guardrail_min_tap_radius_percent=args.weighted_guardrail_min_tap_radius_percent,
        ),
    )

    started = perf_counter()
    baseline_result = segment_image_file(
        image_path=input_path,
        config=config,
        schema_version="1.0.0",
        variant_name=args.variant_name,
    )

    boundary_cfg = BoundaryRepairConfig(
        enabled=args.boundary_repair != "off",
        diagnostics_only=args.boundary_repair == "diagnostics",
        max_gap_pixels=args.max_gap_pixels,
        candidate_search_radius=args.candidate_search_radius,
        min_new_region_area_pixels=args.min_new_region_area,
        max_repair_pixels=args.max_repair_pixels,
        border_margin_percent=args.border_margin_percent,
        max_exterior_percent_delta=args.max_exterior_percent_delta,
        max_new_regions_per_candidate=args.max_new_regions_per_candidate,
        max_candidates_to_validate=args.max_candidates_to_validate,
    )

    boundary_result = None
    working_barrier = baseline_result.artifacts.binary_repaired
    if boundary_cfg.enabled:
        boundary_result = detect_and_repair_boundaries(
            barrier_mask=baseline_result.artifacts.binary_repaired,
            config=boundary_cfg,
            min_region_area_pixels=config.min_region_area_pixels,
        )
        working_barrier = boundary_result.barrier_after

    result = segment_image_file(
        image_path=input_path,
        config=config,
        schema_version="1.0.0",
        variant_name=args.variant_name,
        barrier_override=working_barrier,
    )

    classify_info = classify_segmentation_result(
        metadata=result.metadata,
        labels=result.artifacts.labels,
        barrier_mask=result.artifacts.binary_repaired,
        exterior_mask=result.artifacts.exterior_mask,
        config=suitability,
    )

    artifact_started = perf_counter()
    paths = write_artifacts(output_dir, result)
    artifact_write_ms = (perf_counter() - artifact_started) * 1000.0

    boundary_started = perf_counter()
    boundary_paths = {}
    if boundary_result is not None:
        boundary_paths = write_boundary_repair_artifacts(output_dir, boundary_result)
    boundary_artifact_ms = (perf_counter() - boundary_started) * 1000.0

    qa_started = perf_counter()
    profile_paths = write_profile_artifacts(
        output_dir=output_dir,
        metadata=result.metadata,
        labels=result.artifacts.labels,
        barrier_mask=result.artifacts.binary_repaired,
    )
    qa_generation_ms = (perf_counter() - qa_started) * 1000.0

    # Additional Phase 2D aliases.
    shutil.copyfile(str(profile_paths["master_debug"]), str(output_dir / "regions_master_after_repair.png"))
    shutil.copyfile(
        str(profile_paths["children_detailed_debug"]),
        str(output_dir / "regions_children_detailed_after_repair.png"),
    )

    # Baseline-vs-after topology summary for boundary repair runs.
    if boundary_result is not None:
        baseline_meta = copy.deepcopy(baseline_result.metadata)
        baseline_classify = classify_segmentation_result(
            metadata=baseline_meta,
            labels=baseline_result.artifacts.labels,
            barrier_mask=baseline_result.artifacts.binary_repaired,
            exterior_mask=baseline_result.artifacts.exterior_mask,
            config=suitability,
        )
        result.metadata["boundaryRepair"] = {
            "mode": args.boundary_repair,
            "config": {
                "maxGapPixels": args.max_gap_pixels,
                "candidateSearchRadius": args.candidate_search_radius,
                "minNewRegionArea": args.min_new_region_area,
                "maxRepairPixels": args.max_repair_pixels,
                "borderMarginPercent": args.border_margin_percent,
                "maxExteriorPercentDelta": args.max_exterior_percent_delta,
                "maxNewRegionsPerCandidate": args.max_new_regions_per_candidate,
                "maxCandidatesToValidate": args.max_candidates_to_validate,
            },
            "timingsMs": boundary_result.timings_ms,
            "summary": boundary_result.summary,
            "before": {
                "masterAcceptedCount": baseline_meta["metrics"]["acceptedRegionCount"],
                "childrenDetailedCount": baseline_meta["suitabilityProfiles"]["summaries"]["childrenDetailed"][
                    "includedCount"
                ],
                "exteriorPercent": baseline_meta["metrics"]["exterior"]["percent"],
            },
            "after": {
                "masterAcceptedCount": result.metadata["metrics"]["acceptedRegionCount"],
                "childrenDetailedCount": result.metadata["suitabilityProfiles"]["summaries"]["childrenDetailed"][
                    "includedCount"
                ],
                "exteriorPercent": result.metadata["metrics"]["exterior"]["percent"],
            },
            "baselineClassificationTimingMs": baseline_classify["classificationMs"],
        }

        with (output_dir / "regions.json").open("w", encoding="utf-8") as f:
            json.dump(result.metadata, f, indent=2, sort_keys=True)

    wall_ms = (perf_counter() - started) * 1000.0

    summary = {
        "variant": args.variant_name,
        "source": str(input_path),
        "outputDir": str(output_dir),
        "accepted": result.metadata["metrics"]["acceptedRegionCount"],
        "flaggedTooSmall": result.metadata["metrics"]["flaggedTooSmallCount"],
        "totalCandidates": result.metadata["metrics"]["totalConnectedComponents"],
        "exteriorPercent": round(result.metadata["metrics"]["exterior"]["percent"], 4),
        "runtimeMs": round(result.metadata["metrics"]["runtimeMs"], 2),
        "featureExtractionMs": round(classify_info["featureExtractionMs"], 2),
        "classificationMs": round(classify_info["classificationMs"], 2),
        "wallRuntimeMs": round(wall_ms, 2),
        "warnings": result.metadata["warnings"],
        "childrenDetailedMode": result.metadata["suitabilityProfiles"]["childrenDetailedMode"],
        "boundaryRepairMode": args.boundary_repair,
        "openBoundaryDiagnostics": classify_info["openBoundaryDiagnostics"],
        "weightedScoreDistribution": result.metadata["suitabilityProfiles"]["profiles"]["childrenDetailedWeighted"]["scoreDistribution"],
        "profiles": result.metadata["suitabilityProfiles"]["summaries"],
        "artifacts": {k: str(v) for k, v in paths.items()},
        "boundaryArtifacts": {k: str(v) for k, v in boundary_paths.items()},
        "profileArtifacts": {k: str(v) for k, v in profile_paths.items()},
    }

    if boundary_result is not None:
        summary["boundaryRepairSummary"] = boundary_result.summary
        summary["boundaryRepairTimingsMs"] = boundary_result.timings_ms

    result.metadata["pipelineTimingsMs"] = {
        "segmentationRuntimeMs": float(result.metadata["metrics"]["runtimeMs"]),
        "featureExtractionMs": float(classify_info["featureExtractionMs"]),
        "classificationMs": float(classify_info["classificationMs"]),
        "artifactWriteMs": float(artifact_write_ms),
        "boundaryArtifactWriteMs": float(boundary_artifact_ms),
        "qaArtifactGenerationMs": float(qa_generation_ms),
        "wallRuntimeMs": float(wall_ms),
    }

    with (output_dir / "regions.json").open("w", encoding="utf-8") as f:
        json.dump(result.metadata, f, indent=2, sort_keys=True)

    summary["pipelineTimingsMs"] = result.metadata["pipelineTimingsMs"]

    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
