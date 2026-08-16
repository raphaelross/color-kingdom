from __future__ import annotations

from dataclasses import replace
import json
from pathlib import Path

from phase2g_build_pipeline import (
    compute_build_id,
    compute_config_hash,
    compute_source_hash,
    run_pipeline_for_manifest,
)
import phase2g_build_pipeline
from orchestrate_segmentation import run_operational_stage
from phase2g_manifest import load_manifest
from phase2g_models import CheckResult, CheckSeverity, LifecycleStatus


def _load_report(path: Path) -> dict[str, object]:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def test_deterministic_source_hash_for_manifest_source() -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())
    a = compute_source_hash(manifest.source_artwork_path)
    b = compute_source_hash(manifest.source_artwork_path)
    assert a == b


def test_deterministic_config_hash() -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())
    a = compute_config_hash(manifest)
    b = compute_config_hash(manifest)
    assert a == b


def test_deterministic_build_id() -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())
    a = compute_build_id(manifest)
    b = compute_build_id(manifest)
    assert a == b


def test_unapproved_lifecycle_blocks_build(tmp_path: Path) -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())
    blocked = replace(manifest, lifecycle_status=LifecycleStatus.AWAITING_ARTWORK_QA)

    report, code = run_pipeline_for_manifest(
        manifest=blocked,
        stage="build",
        workspace_root=tmp_path,
        build_id_override="blocked-build",
    )

    assert code == 1
    assert report["result"] == "FAIL"
    segment_checks = report["stages"]["segment"]
    assert any(c["code"] == "BUILD_BLOCKED_LIFECYCLE" for c in segment_checks)


def test_artwork_approved_allows_build(tmp_path: Path) -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())
    approved = replace(manifest, lifecycle_status=LifecycleStatus.ARTWORK_APPROVED)

    report, code = run_pipeline_for_manifest(
        manifest=approved,
        stage="build",
        workspace_root=tmp_path,
        build_id_override="approved-build",
    )

    assert code == 0
    assert report["result"] == "PASS"
    runtime = Path(report["workspace"]["runtime_candidate"])
    assert (runtime / "line_art.png").exists()
    assert (runtime / "line_art_foreground.png").exists()
    assert (runtime / "region_map.png").exists()
    assert (runtime / "region_fill_map.png").exists()
    assert (runtime / "metadata_children_detailed.json").exists()

    qa = report["qa"]
    assert Path(qa["fullColor"]).exists()
    assert Path(qa["exclusions"]).exists()

    timings = report["timingsMs"]
    counts = report["counts"]
    assert timings["preflight"] >= 0
    assert timings["segment"] >= 0
    assert timings["qa"] >= 0
    assert timings["export"] >= 0
    assert timings["validate"] >= 0
    assert timings["total"] >= 0
    assert counts["detectedCandidateRegions"] >= counts["masterAcceptedRegions"]
    assert counts["runtimeMetadataRegions"] == 77


def test_workspace_path_creation(tmp_path: Path) -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())

    report, code = run_pipeline_for_manifest(
        manifest=manifest,
        stage="preflight",
        workspace_root=tmp_path,
        build_id_override="ws-check",
    )

    assert code == 0
    workspace = report["workspace"]
    assert Path(workspace["root"]).exists()
    assert Path(workspace["manifest_snapshot"]).exists()


def test_invalid_segment_args_fail_fast(tmp_path: Path) -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())
    bad = replace(manifest, build_config={"segmentArgs": {"bad": "shape"}})

    report, code = run_pipeline_for_manifest(
        manifest=bad,
        stage="build",
        workspace_root=tmp_path,
        build_id_override="bad-seg-args",
    )

    assert code == 1
    assert any(c["code"] == "MANIFEST_SEGMENT_ARGS_INVALID" for c in report["stages"]["segment"])


def test_failure_does_not_modify_production_assets(tmp_path: Path) -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())
    prod_metadata_bytes = manifest.runtime_metadata_path.read_bytes()
    prod_map_bytes = (manifest.runtime_asset_dir / "region_map.png").read_bytes()

    blocked = replace(manifest, lifecycle_status=LifecycleStatus.AWAITING_ARTWORK_QA)
    _, code = run_pipeline_for_manifest(
        manifest=blocked,
        stage="build",
        workspace_root=tmp_path,
        build_id_override="no-overwrite",
    )

    assert code == 1
    assert manifest.runtime_metadata_path.read_bytes() == prod_metadata_bytes
    assert (manifest.runtime_asset_dir / "region_map.png").read_bytes() == prod_map_bytes


def test_kitten_reproduction_runtime_count_matches_canonical(tmp_path: Path) -> None:
    manifest = load_manifest(Path("manifests/lovely_kitten_raster_poc.page.json").resolve())

    report, code = run_pipeline_for_manifest(
        manifest=manifest,
        stage="build",
        workspace_root=tmp_path,
        build_id_override="kitten-repro",
    )

    assert code == 0
    assert report["counts"]["runtimeMetadataRegions"] == 175


def test_multi_manifest_result_isolation(tmp_path: Path) -> None:
    panda = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())
    kitten = load_manifest(Path("manifests/lovely_kitten_raster_poc.page.json").resolve())
    blocked = replace(kitten, lifecycle_status=LifecycleStatus.AWAITING_ARTWORK_QA)

    blocked_manifest_path = tmp_path / "blocked_kitten.page.json"
    blocked_payload = {
        "schemaVersion": blocked.schema_version,
        "pageId": blocked.page_id,
        "title": blocked.title,
        "categoryId": blocked.category_id,
        "lifecycleStatus": blocked.lifecycle_status.value,
        "renderer": blocked.renderer.value,
        "profile": blocked.profile.value,
        "sourceArtworkPath": str(blocked.source_artwork_path),
        "sourceArtworkVersion": blocked.source_artwork_version,
        "segmentationOutputDir": str(blocked.segmentation_output_dir),
        "runtimeAssetDir": str(blocked.runtime_asset_dir),
        "runtimeMetadataPath": str(blocked.runtime_metadata_path),
        "runtimeRegionsDartPath": str(blocked.runtime_regions_dart_path),
        "assetBasePath": blocked.asset_base_path,
        "runtimeContentVersion": blocked.runtime_content_version,
        "pipelineVersion": blocked.pipeline_version,
        "expectedImageWidth": blocked.expected_image_width,
        "expectedImageHeight": blocked.expected_image_height,
        "expectedOrientation": blocked.expected_orientation,
        "enforceMonochromeLineArt": blocked.enforce_monochrome_line_art,
        "buildConfig": blocked.build_config,
    }
    blocked_manifest_path.write_text(json.dumps(blocked_payload, indent=2), encoding="utf-8")

    payload, code = run_operational_stage(
        manifest_paths=[
            Path("manifests/cheerful_baby_panda.page.json").resolve(),
            blocked_manifest_path.resolve(),
        ],
        stage="build",
        workspace_root=tmp_path / "work",
        build_id_override="isolation",
    )

    assert code == 1
    assert payload["summary"]["pass"] == 1
    assert payload["summary"]["fail"] == 1


def test_no_duplicate_page_ids_in_build_batch(tmp_path: Path) -> None:
    panda_path = Path("manifests/cheerful_baby_panda.page.json").resolve()
    duplicate_path = tmp_path / "duplicate.page.json"
    duplicate_path.write_text(panda_path.read_text(encoding="utf-8"), encoding="utf-8")

    payload, code = run_operational_stage(
        manifest_paths=[panda_path, duplicate_path.resolve()],
        stage="build",
        workspace_root=tmp_path / "work",
        build_id_override="dup-id",
    )

    assert code == 1
    duplicate_reports = [
        page
        for page in payload["pages"]
        if isinstance(page, dict) and page.get("error", {}).get("code") == "DUPLICATE_PAGE_ID"
    ]
    assert len(duplicate_reports) == 1


def test_controlled_segmentation_failure_returns_nonzero(tmp_path: Path, monkeypatch) -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())

    original_run = phase2g_build_pipeline._run_command

    def fake_run(args: list[str], cwd: Path) -> dict[str, object]:
        if "segment_coloring_page.py" in " ".join(args):
            return {
                "args": args,
                "exitCode": 23,
                "stdout": "",
                "stderr": "simulated segment failure",
                "durationMs": 1.0,
            }
        return original_run(args, cwd)

    monkeypatch.setattr(phase2g_build_pipeline, "_run_command", fake_run)

    report, code = run_pipeline_for_manifest(
        manifest=manifest,
        stage="build",
        workspace_root=tmp_path,
        build_id_override="sim-segment-fail",
    )

    assert code == 1
    assert report["result"] == "FAIL"
    assert any(c["code"] == "SEGMENT_COMMAND_FAILED" for c in report["stages"]["segment"])


def test_controlled_integrity_failure_returns_nonzero(tmp_path: Path, monkeypatch) -> None:
    manifest = load_manifest(Path("manifests/cheerful_baby_panda.page.json").resolve())

    def fake_integrity(_manifest):
        return [
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="SIMULATED_INTEGRITY_FAIL",
                message="simulated integrity failure",
            )
        ]

    monkeypatch.setattr(phase2g_build_pipeline, "run_integrity_validation", fake_integrity)

    report, code = run_pipeline_for_manifest(
        manifest=manifest,
        stage="build",
        workspace_root=tmp_path,
        build_id_override="sim-integrity-fail",
    )

    assert code == 1
    assert report["result"] == "FAIL"
    assert any(c["code"] == "SIMULATED_INTEGRITY_FAIL" for c in report["stages"]["validate"])
