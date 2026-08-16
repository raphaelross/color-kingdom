from __future__ import annotations

from dataclasses import replace
from hashlib import sha256
import json
from pathlib import Path
import shutil
import subprocess
import sys
from time import perf_counter
from typing import Any

from PIL import Image

from phase2g_integrity import run_integrity_validation
from phase2g_models import CheckSeverity, LifecycleStatus, SegmentationPageManifest
from phase2g_preflight import run_preflight


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = Path(__file__).resolve().parent

BUILD_LIFECYCLE_ALLOWED = {
    LifecycleStatus.ARTWORK_APPROVED,
    LifecycleStatus.SEGMENTED,
    LifecycleStatus.AWAITING_COVERAGE_QA,
    LifecycleStatus.COVERAGE_APPROVED,
    LifecycleStatus.RUNTIME_EXPORTED,
    LifecycleStatus.RUNTIME_VALIDATED,
    LifecycleStatus.PRODUCTION_APPROVED,
}

DEFAULT_SEGMENT_ARGS = [
    "--threshold",
    "185",
    "--morph-kernel",
    "0",
    "--morph-iterations",
    "1",
    "--dilate-iterations",
    "0",
    "--min-region-area",
    "250",
    "--min-region-percent",
    "0.015",
    "--connectivity",
    "8",
    "--children-detailed-min-area-percent",
    "0.04",
    "--children-detailed-min-bounding-dimension-percent",
    "1.2",
    "--children-detailed-min-tap-radius-percent",
    "0.42",
    "--children-detailed-min-occupancy",
    "0.24",
    "--children-detailed-min-aspect-ratio",
    "0.09",
    "--children-detailed-min-compactness",
    "0.02",
    "--children-detailed-mode",
    "threshold",
    "--children-simple-min-area-percent",
    "0.11",
    "--children-simple-min-bounding-dimension-percent",
    "2.1",
    "--children-simple-min-tap-radius-percent",
    "0.8",
    "--children-simple-min-occupancy",
    "0.28",
    "--children-simple-min-aspect-ratio",
    "0.13",
    "--children-simple-min-compactness",
    "0.03",
]


def _json_hash(payload: dict[str, Any]) -> str:
    blob = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return sha256(blob.encode("utf-8")).hexdigest()


def compute_source_hash(path: Path) -> str:
    h = sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def compute_config_hash(manifest: SegmentationPageManifest) -> str:
    payload = {
        "schemaVersion": manifest.schema_version,
        "pageId": manifest.page_id,
        "renderer": manifest.renderer.value,
        "profile": manifest.profile.value,
        "sourceArtworkVersion": manifest.source_artwork_version,
        "runtimeContentVersion": manifest.runtime_content_version,
        "pipelineVersion": manifest.pipeline_version,
        "expectedImageWidth": manifest.expected_image_width,
        "expectedImageHeight": manifest.expected_image_height,
        "expectedOrientation": manifest.expected_orientation,
        "enforceMonochromeLineArt": manifest.enforce_monochrome_line_art,
        "buildConfig": manifest.build_config,
    }
    return _json_hash(payload)


def compute_build_id(manifest: SegmentationPageManifest) -> tuple[str, str, str]:
    source_hash = compute_source_hash(manifest.source_artwork_path)
    config_hash = compute_config_hash(manifest)
    identity = {
        "pageId": manifest.page_id,
        "sourceHash": source_hash,
        "configHash": config_hash,
        "pipelineVersion": manifest.pipeline_version,
    }
    build_hash = _json_hash(identity)[:16]
    return source_hash, config_hash, f"{manifest.page_id}-{build_hash}"


def _run_command(args: list[str], cwd: Path) -> dict[str, Any]:
    started = perf_counter()
    proc = subprocess.run(
        args,
        cwd=str(cwd),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    elapsed_ms = (perf_counter() - started) * 1000.0
    return {
        "args": args,
        "exitCode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "durationMs": elapsed_ms,
    }


def _dir_size_bytes(path: Path) -> int:
    total = 0
    if not path.exists():
        return 0
    for file in path.rglob("*"):
        if file.is_file():
            total += file.stat().st_size
    return total


def _sha256_file(path: Path) -> str:
    h = sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        payload = json.load(fh)
    if not isinstance(payload, dict):
        raise ValueError(f"Expected JSON object at {path}")
    return payload


def _pixel_counts_by_region(
    image_path: Path,
    metadata_regions: list[dict[str, Any]],
) -> dict[str, int]:
    color_to_region: dict[tuple[int, int, int, int], str] = {}
    for region in metadata_regions:
        region_id = region.get("regionId")
        rgba = region.get("mapColorRgba")
        if not isinstance(region_id, str):
            continue
        if not (
            isinstance(rgba, list)
            and len(rgba) == 4
            and all(isinstance(v, int) for v in rgba)
        ):
            continue
        color_to_region[(rgba[0], rgba[1], rgba[2], rgba[3])] = region_id

    counts = {rid: 0 for rid in color_to_region.values()}
    with Image.open(image_path) as img:
        raw = img.convert("RGBA").tobytes()
        for i in range(0, len(raw), 4):
            key = (raw[i], raw[i + 1], raw[i + 2], raw[i + 3])
            region_id = color_to_region.get(key)
            if region_id is not None:
                counts[region_id] += 1
    return counts


def _compare_runtime_assets(
    production_dir: Path,
    candidate_dir: Path,
    production_metadata: dict[str, Any],
    candidate_metadata: dict[str, Any],
) -> dict[str, Any]:
    production_regions = production_metadata.get("regions", [])
    candidate_regions = candidate_metadata.get("regions", [])

    production_region_ids = {
        r.get("regionId")
        for r in production_regions
        if isinstance(r, dict) and isinstance(r.get("regionId"), str)
    }
    candidate_region_ids = {
        r.get("regionId")
        for r in candidate_regions
        if isinstance(r, dict) and isinstance(r.get("regionId"), str)
    }

    region_set_match = production_region_ids == candidate_region_ids

    logical_prod = production_dir / "region_map.png"
    logical_cand = candidate_dir / "region_map.png"
    fill_prod = production_dir / "region_fill_map.png"
    fill_cand = candidate_dir / "region_fill_map.png"
    fg_prod = production_dir / "line_art_foreground.png"
    fg_cand = candidate_dir / "line_art_foreground.png"

    logical_exact = _sha256_file(logical_prod) == _sha256_file(logical_cand)
    fill_exact = _sha256_file(fill_prod) == _sha256_file(fill_cand)
    fg_exact = _sha256_file(fg_prod) == _sha256_file(fg_cand)

    logical_status = "MATCH"
    fill_status = "MATCH"
    foreground_status = "MATCH"

    if not logical_exact:
        prod_counts = _pixel_counts_by_region(logical_prod, production_regions)
        cand_counts = _pixel_counts_by_region(logical_cand, candidate_regions)
        logical_status = "SEMANTICALLY_EQUIVALENT" if prod_counts == cand_counts else "DIFFER"

    if not fill_exact:
        prod_counts = _pixel_counts_by_region(fill_prod, production_regions)
        cand_counts = _pixel_counts_by_region(fill_cand, candidate_regions)
        fill_status = "SEMANTICALLY_EQUIVALENT" if prod_counts == cand_counts else "DIFFER"

    if not fg_exact:
        foreground_status = "DIFFER"

    return {
        "metadataRegionSet": {
            "status": "MATCH" if region_set_match else "DIFFER",
            "productionCount": len(production_region_ids),
            "candidateCount": len(candidate_region_ids),
            "missingInCandidate": sorted(production_region_ids - candidate_region_ids),
            "extraInCandidate": sorted(candidate_region_ids - production_region_ids),
        },
        "logicalMap": {
            "status": logical_status,
            "productionSha256": _sha256_file(logical_prod),
            "candidateSha256": _sha256_file(logical_cand),
        },
        "visualFillMap": {
            "status": fill_status,
            "productionSha256": _sha256_file(fill_prod),
            "candidateSha256": _sha256_file(fill_cand),
        },
        "foreground": {
            "status": foreground_status,
            "productionSha256": _sha256_file(fg_prod),
            "candidateSha256": _sha256_file(fg_cand),
        },
    }


def _summarize_exclusions(segmentation_metadata: dict[str, Any]) -> dict[str, Any]:
    accepted = segmentation_metadata.get("acceptedRegions", [])
    reasons: dict[str, int] = {}
    excluded = 0
    for region in accepted:
        if not isinstance(region, dict):
            continue
        profiles = region.get("profiles")
        if not isinstance(profiles, dict):
            continue
        detailed = profiles.get("childrenDetailed")
        if not isinstance(detailed, dict):
            continue
        if bool(detailed.get("included")):
            continue
        excluded += 1
        for reason in detailed.get("reasons", []):
            if isinstance(reason, str):
                reasons[reason] = reasons.get(reason, 0) + 1

    return {
        "excludedRegionCount": excluded,
        "reasonCounts": reasons,
    }


def _stage_status_from_checks(checks: list[dict[str, Any]]) -> str:
    severities = [c.get("severity") for c in checks]
    if "FAIL" in severities:
        return "FAIL"
    if "WARN" in severities:
        return "WARN"
    return "PASS"


def _build_workspace_paths(workspace_root: Path, page_id: str, build_id: str) -> dict[str, Path]:
    page_root = workspace_root / page_id / build_id
    return {
        "root": page_root,
        "segmentation": page_root / "segmentation",
        "qa": page_root / "qa",
        "runtime_candidate": page_root / "runtime_candidate",
        "report": page_root / "report.json",
        "comparison": page_root / "comparison_to_production.json",
        "manifest_snapshot": page_root / "manifest_snapshot.json",
    }


def _to_check_dict(severity: CheckSeverity, code: str, message: str, context: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "severity": severity.value,
        "code": code,
        "message": message,
        "context": context or {},
    }


def run_pipeline_for_manifest(
    manifest: SegmentationPageManifest,
    stage: str,
    workspace_root: Path,
    build_id_override: str | None = None,
) -> tuple[dict[str, Any], int]:
    source_hash, config_hash, computed_build_id = compute_build_id(manifest)
    build_id = build_id_override or computed_build_id
    paths = _build_workspace_paths(workspace_root=workspace_root, page_id=manifest.page_id, build_id=build_id)

    timings_ms: dict[str, float] = {}
    stage_checks: dict[str, list[dict[str, Any]]] = {
        "preflight": [],
        "segment": [],
        "qa": [],
        "export": [],
        "validate": [],
    }

    paths["root"].mkdir(parents=True, exist_ok=True)
    paths["segmentation"].mkdir(parents=True, exist_ok=True)
    paths["qa"].mkdir(parents=True, exist_ok=True)
    paths["runtime_candidate"].mkdir(parents=True, exist_ok=True)

    manifest_payload = {
        "schemaVersion": manifest.schema_version,
        "pageId": manifest.page_id,
        "title": manifest.title,
        "categoryId": manifest.category_id,
        "lifecycleStatus": manifest.lifecycle_status.value,
        "renderer": manifest.renderer.value,
        "profile": manifest.profile.value,
        "sourceArtworkPath": str(manifest.source_artwork_path),
        "sourceArtworkVersion": manifest.source_artwork_version,
        "runtimeAssetDir": str(manifest.runtime_asset_dir),
        "runtimeMetadataPath": str(manifest.runtime_metadata_path),
        "runtimeRegionsDartPath": str(manifest.runtime_regions_dart_path),
        "assetBasePath": manifest.asset_base_path,
        "runtimeContentVersion": manifest.runtime_content_version,
        "pipelineVersion": manifest.pipeline_version,
        "buildConfig": manifest.build_config,
    }
    with paths["manifest_snapshot"].open("w", encoding="utf-8") as fh:
        json.dump(manifest_payload, fh, indent=2)
        fh.write("\n")

    total_started = perf_counter()

    # Stage: preflight
    preflight_started = perf_counter()
    preflight_checks = [
        {
            "severity": c.severity.value,
            "code": c.code,
            "message": c.message,
            "context": c.context,
        }
        for c in run_preflight(manifest)
    ]
    stage_checks["preflight"] = preflight_checks
    timings_ms["preflight"] = (perf_counter() - preflight_started) * 1000.0

    preflight_status = _stage_status_from_checks(preflight_checks)
    if preflight_status == "FAIL":
        report = {
            "pageId": manifest.page_id,
            "stage": stage,
            "result": "FAIL",
            "buildId": build_id,
            "sourceHash": source_hash,
            "configHash": config_hash,
            "workspace": {k: str(v) for k, v in paths.items()},
            "stages": stage_checks,
            "stageStatus": {
                "preflight": preflight_status,
                "segment": "SKIPPED",
                "qa": "SKIPPED",
                "export": "SKIPPED",
                "validate": "SKIPPED",
            },
            "timingsMs": {
                **timings_ms,
                "total": (perf_counter() - total_started) * 1000.0,
            },
        }
        return report, 1

    if stage == "preflight":
        report = {
            "pageId": manifest.page_id,
            "stage": stage,
            "result": "PASS",
            "buildId": build_id,
            "sourceHash": source_hash,
            "configHash": config_hash,
            "workspace": {k: str(v) for k, v in paths.items()},
            "stages": stage_checks,
            "stageStatus": {
                "preflight": preflight_status,
                "segment": "SKIPPED",
                "qa": "SKIPPED",
                "export": "SKIPPED",
                "validate": "SKIPPED",
            },
            "timingsMs": {
                **timings_ms,
                "total": (perf_counter() - total_started) * 1000.0,
            },
        }
        with paths["report"].open("w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
        return report, 0

    # Human gate enforcement for build stages.
    if manifest.lifecycle_status not in BUILD_LIFECYCLE_ALLOWED:
        stage_checks["segment"] = [
            _to_check_dict(
                CheckSeverity.FAIL,
                "BUILD_BLOCKED_LIFECYCLE",
                f"BUILD BLOCKED: {manifest.page_id} is {manifest.lifecycle_status.value}. Set lifecycle to ARTWORK_APPROVED after Human Artwork QA.",
            )
        ]
        report = {
            "pageId": manifest.page_id,
            "stage": stage,
            "result": "FAIL",
            "buildId": build_id,
            "sourceHash": source_hash,
            "configHash": config_hash,
            "workspace": {k: str(v) for k, v in paths.items()},
            "stages": stage_checks,
            "stageStatus": {
                "preflight": preflight_status,
                "segment": "FAIL",
                "qa": "SKIPPED",
                "export": "SKIPPED",
                "validate": "SKIPPED",
            },
            "timingsMs": {
                **timings_ms,
                "total": (perf_counter() - total_started) * 1000.0,
            },
        }
        with paths["report"].open("w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
        return report, 1

    segment_args = manifest.build_config.get("segmentArgs", DEFAULT_SEGMENT_ARGS)
    if not isinstance(segment_args, list) or any(not isinstance(a, str) for a in segment_args):
        stage_checks["segment"] = [
            _to_check_dict(
                CheckSeverity.FAIL,
                "MANIFEST_SEGMENT_ARGS_INVALID",
                "buildConfig.segmentArgs must be a list of strings",
            )
        ]
        report = {
            "pageId": manifest.page_id,
            "stage": stage,
            "result": "FAIL",
            "buildId": build_id,
            "sourceHash": source_hash,
            "configHash": config_hash,
            "workspace": {k: str(v) for k, v in paths.items()},
            "stages": stage_checks,
            "stageStatus": {
                "preflight": preflight_status,
                "segment": "FAIL",
                "qa": "SKIPPED",
                "export": "SKIPPED",
                "validate": "SKIPPED",
            },
            "timingsMs": {
                **timings_ms,
                "total": (perf_counter() - total_started) * 1000.0,
            },
        }
        with paths["report"].open("w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
        return report, 1

    # Stage: segment
    segment_started = perf_counter()
    segment_cmd = [
        sys.executable,
        str(SCRIPT_DIR / "segment_coloring_page.py"),
        "--input",
        str(manifest.source_artwork_path),
        "--output-dir",
        str(paths["segmentation"]),
        "--variant-name",
        build_id,
    ] + segment_args
    segment_result = _run_command(segment_cmd, cwd=SCRIPT_DIR)
    timings_ms["segment"] = (perf_counter() - segment_started) * 1000.0

    if segment_result["exitCode"] != 0:
        stage_checks["segment"] = [
            _to_check_dict(
                CheckSeverity.FAIL,
                "SEGMENT_COMMAND_FAILED",
                "Segmentation command failed",
                {
                    "exitCode": segment_result["exitCode"],
                    "stderrTail": segment_result["stderr"][-2000:],
                },
            )
        ]
        report = {
            "pageId": manifest.page_id,
            "stage": stage,
            "result": "FAIL",
            "buildId": build_id,
            "sourceHash": source_hash,
            "configHash": config_hash,
            "workspace": {k: str(v) for k, v in paths.items()},
            "commandLog": {"segment": segment_result},
            "stages": stage_checks,
            "stageStatus": {
                "preflight": preflight_status,
                "segment": "FAIL",
                "qa": "SKIPPED",
                "export": "SKIPPED",
                "validate": "SKIPPED",
            },
            "timingsMs": {
                **timings_ms,
                "total": (perf_counter() - total_started) * 1000.0,
            },
        }
        with paths["report"].open("w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
        return report, 1

    stage_checks["segment"] = [_to_check_dict(CheckSeverity.PASS, "SEGMENT_COMPLETED", "Segmentation stage completed")]

    if stage == "segment":
        report = {
            "pageId": manifest.page_id,
            "stage": stage,
            "result": "PASS",
            "buildId": build_id,
            "sourceHash": source_hash,
            "configHash": config_hash,
            "workspace": {k: str(v) for k, v in paths.items()},
            "commandLog": {"segment": segment_result},
            "stages": stage_checks,
            "stageStatus": {
                "preflight": preflight_status,
                "segment": "PASS",
                "qa": "SKIPPED",
                "export": "SKIPPED",
                "validate": "SKIPPED",
            },
            "timingsMs": {
                **timings_ms,
                "total": (perf_counter() - total_started) * 1000.0,
            },
        }
        with paths["report"].open("w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
        return report, 0

    segmentation_metadata = _load_json(paths["segmentation"] / "regions.json")

    # Stage: qa package
    qa_started = perf_counter()
    qa_fullcolor = paths["segmentation"] / "regions_children_detailed_qa_fullcolor.png"
    qa_exclusions = paths["segmentation"] / "regions_children_detailed_exclusions.png"
    qa_labeled = paths["segmentation"] / "regions_labeled.png"
    qa_master_coverage = paths["segmentation"] / "master_vs_children_detailed_coverage.png"

    qa_fullcolor_dst = paths["qa"] / "regions_children_detailed_qa_fullcolor.png"
    qa_exclusions_dst = paths["qa"] / "regions_children_detailed_exclusions.png"
    qa_labeled_dst = paths["qa"] / "regions_labeled.png"
    qa_coverage_dst = paths["qa"] / "master_vs_children_detailed_coverage.png"

    for src, dst in (
        (qa_fullcolor, qa_fullcolor_dst),
        (qa_exclusions, qa_exclusions_dst),
        (qa_labeled, qa_labeled_dst),
        (qa_master_coverage, qa_coverage_dst),
    ):
        if src.exists():
            shutil.copy2(src, dst)

    qa_summary = {
        "pageId": manifest.page_id,
        "fullColor": str(qa_fullcolor_dst),
        "exclusions": str(qa_exclusions_dst),
        "labeled": str(qa_labeled_dst),
        "coverage": str(qa_coverage_dst),
        "exclusionsSummary": _summarize_exclusions(segmentation_metadata),
    }
    with (paths["qa"] / "qa_summary.json").open("w", encoding="utf-8") as fh:
        json.dump(qa_summary, fh, indent=2)
        fh.write("\n")

    timings_ms["qa"] = (perf_counter() - qa_started) * 1000.0
    stage_checks["qa"] = [_to_check_dict(CheckSeverity.PASS, "QA_PACKAGE_READY", "QA package generated")]

    if stage == "qa":
        report = {
            "pageId": manifest.page_id,
            "stage": stage,
            "result": "PASS",
            "buildId": build_id,
            "sourceHash": source_hash,
            "configHash": config_hash,
            "workspace": {k: str(v) for k, v in paths.items()},
            "commandLog": {"segment": segment_result},
            "qa": qa_summary,
            "stages": stage_checks,
            "stageStatus": {
                "preflight": preflight_status,
                "segment": "PASS",
                "qa": "PASS",
                "export": "SKIPPED",
                "validate": "SKIPPED",
            },
            "timingsMs": {
                **timings_ms,
                "total": (perf_counter() - total_started) * 1000.0,
            },
        }
        with paths["report"].open("w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
        return report, 0

    # Stage: export
    export_started = perf_counter()
    runtime_metadata_candidate = paths["runtime_candidate"] / "metadata_children_detailed.json"
    runtime_regions_candidate = paths["runtime_candidate"] / f"{manifest.page_id}_raster_regions.dart"

    export_cfg = manifest.build_config.get("export", {})
    max_fill = export_cfg.get("maxFillExpansionPx", 4)
    pref_fill = export_cfg.get("preferredFillExpansionPx", 2)

    export_cmd = [
        sys.executable,
        str(SCRIPT_DIR / "export_raster_poc_assets.py"),
        "--regions-json",
        str(paths["segmentation"] / "regions.json"),
        "--region-map",
        str(paths["segmentation"] / "region_map.png"),
        "--line-art",
        str(manifest.source_artwork_path),
        "--profile-qa-debug",
        str(paths["segmentation"] / "regions_children_detailed_qa_fullcolor.png"),
        "--profile-exclusions",
        str(paths["segmentation"] / "regions_children_detailed_exclusions.png"),
        "--runtime-dir",
        str(paths["runtime_candidate"]),
        "--runtime-metadata",
        str(runtime_metadata_candidate),
        "--regions-dart",
        str(runtime_regions_candidate),
        "--page-id",
        manifest.page_id,
        "--asset-base-path",
        manifest.asset_base_path,
        "--dart-symbol-prefix",
        manifest.dart_symbol_prefix or manifest.page_id,
        "--content-version",
        manifest.runtime_content_version,
        "--max-fill-expansion-px",
        str(max_fill),
        "--preferred-fill-expansion-px",
        str(pref_fill),
    ]
    export_result = _run_command(export_cmd, cwd=SCRIPT_DIR)
    timings_ms["export"] = (perf_counter() - export_started) * 1000.0

    if export_result["exitCode"] != 0:
        stage_checks["export"] = [
            _to_check_dict(
                CheckSeverity.FAIL,
                "EXPORT_COMMAND_FAILED",
                "Runtime export command failed",
                {
                    "exitCode": export_result["exitCode"],
                    "stderrTail": export_result["stderr"][-2000:],
                },
            )
        ]
        report = {
            "pageId": manifest.page_id,
            "stage": stage,
            "result": "FAIL",
            "buildId": build_id,
            "sourceHash": source_hash,
            "configHash": config_hash,
            "workspace": {k: str(v) for k, v in paths.items()},
            "commandLog": {"segment": segment_result, "export": export_result},
            "qa": qa_summary,
            "stages": stage_checks,
            "stageStatus": {
                "preflight": preflight_status,
                "segment": "PASS",
                "qa": "PASS",
                "export": "FAIL",
                "validate": "SKIPPED",
            },
            "timingsMs": {
                **timings_ms,
                "total": (perf_counter() - total_started) * 1000.0,
            },
        }
        with paths["report"].open("w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
        return report, 1

    stage_checks["export"] = [_to_check_dict(CheckSeverity.PASS, "EXPORT_COMPLETED", "Runtime candidate export completed")]

    if stage == "export":
        report = {
            "pageId": manifest.page_id,
            "stage": stage,
            "result": "PASS",
            "buildId": build_id,
            "sourceHash": source_hash,
            "configHash": config_hash,
            "workspace": {k: str(v) for k, v in paths.items()},
            "commandLog": {"segment": segment_result, "export": export_result},
            "qa": qa_summary,
            "stages": stage_checks,
            "stageStatus": {
                "preflight": preflight_status,
                "segment": "PASS",
                "qa": "PASS",
                "export": "PASS",
                "validate": "SKIPPED",
            },
            "timingsMs": {
                **timings_ms,
                "total": (perf_counter() - total_started) * 1000.0,
            },
        }
        with paths["report"].open("w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
        return report, 0

    # Stage: validate candidate integrity
    validate_started = perf_counter()
    candidate_manifest = replace(
        manifest,
        segmentation_output_dir=paths["segmentation"],
        runtime_asset_dir=paths["runtime_candidate"],
        runtime_metadata_path=runtime_metadata_candidate,
        runtime_regions_dart_path=runtime_regions_candidate,
    )
    integrity_checks = run_integrity_validation(candidate_manifest)
    stage_checks["validate"] = [
        {
            "severity": c.severity.value,
            "code": c.code,
            "message": c.message,
            "context": c.context,
        }
        for c in integrity_checks
    ]
    timings_ms["validate"] = (perf_counter() - validate_started) * 1000.0

    validate_status = _stage_status_from_checks(stage_checks["validate"])

    candidate_metadata = _load_json(runtime_metadata_candidate)
    production_metadata = _load_json(manifest.runtime_metadata_path)
    comparison = _compare_runtime_assets(
        production_dir=manifest.runtime_asset_dir,
        candidate_dir=paths["runtime_candidate"],
        production_metadata=production_metadata,
        candidate_metadata=candidate_metadata,
    )
    with paths["comparison"].open("w", encoding="utf-8") as fh:
        json.dump(comparison, fh, indent=2)
        fh.write("\n")

    detected = int(segmentation_metadata.get("metrics", {}).get("totalConnectedComponents", 0))
    master_accepted = int(segmentation_metadata.get("metrics", {}).get("acceptedRegionCount", 0))
    summaries = segmentation_metadata.get("suitabilityProfiles", {}).get("summaries", {})
    children_detailed_summary = summaries.get("childrenDetailed", {}) if isinstance(summaries, dict) else {}
    profile_accepted = int(children_detailed_summary.get("includedCount", 0))
    excluded_count = int(children_detailed_summary.get("excludedCount", 0))
    runtime_regions = int(candidate_metadata.get("regionCount", 0))

    with Image.open(manifest.source_artwork_path) as src_img:
        source_width, source_height = src_img.size

    performance = {
        "source": {
            "width": source_width,
            "height": source_height,
            "sizeBytes": manifest.source_artwork_path.stat().st_size,
        },
        "workspaceSizeBytes": _dir_size_bytes(paths["root"]),
        "runtimeCandidateSizeBytes": _dir_size_bytes(paths["runtime_candidate"]),
        "qaPackageSizeBytes": _dir_size_bytes(paths["qa"]),
    }

    report = {
        "pageId": manifest.page_id,
        "title": manifest.title,
        "stage": stage,
        "result": "PASS" if validate_status == "PASS" else "FAIL",
        "buildId": build_id,
        "sourceHash": source_hash,
        "configHash": config_hash,
        "buildIdentity": {
            "strategy": "sha256(pageId + sourceHash + configHash + pipelineVersion)",
            "sourceHash": source_hash,
            "configHash": config_hash,
            "buildId": build_id,
        },
        "workspace": {k: str(v) for k, v in paths.items()},
        "commandLog": {"segment": segment_result, "export": export_result},
        "qa": qa_summary,
        "counts": {
            "detectedCandidateRegions": detected,
            "masterAcceptedRegions": master_accepted,
            "profileAcceptedRegions": profile_accepted,
            "excludedProfileRegions": excluded_count,
            "runtimeMetadataRegions": runtime_regions,
        },
        "exclusionSummary": _summarize_exclusions(segmentation_metadata),
        "comparisonToProduction": comparison,
        "stages": stage_checks,
        "stageStatus": {
            "preflight": preflight_status,
            "segment": "PASS",
            "qa": "PASS",
            "export": "PASS",
            "validate": validate_status,
        },
        "timingsMs": {
            **timings_ms,
            "total": (perf_counter() - total_started) * 1000.0,
        },
        "performance": performance,
        "operatorMessage": {
            "headline": "BUILD COMPLETE - HUMAN COVERAGE QA REQUIRED",
            "reviewFullColorQa": str(qa_fullcolor_dst),
            "reviewLabeledQa": str(qa_labeled_dst),
            "runtimeCandidatePath": str(paths["runtime_candidate"]),
            "nextStep": (
                "After Human Coverage QA approval, mark lifecycle as COVERAGE_APPROVED. "
                "Production promotion is intentionally not performed in Part 2."
            ),
        },
    }

    with paths["report"].open("w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")

    return report, 0 if validate_status == "PASS" else 1
