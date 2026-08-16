from __future__ import annotations

import argparse
import json
from pathlib import Path
from time import perf_counter
from typing import Any

from phase2g_build_pipeline import run_pipeline_for_manifest
from phase2g_integrity import run_integrity_validation
from phase2g_manifest import load_manifest
from phase2g_models import CheckResult, CheckSeverity, OrchestrationReport, PageStageReport
from phase2g_preflight import run_preflight


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Phase 2G foundation orchestrator. "
            "Current scope is audit/report only and does not mutate segmentation outputs."
        )
    )
    parser.add_argument(
        "--manifest",
        action="append",
        required=True,
        help="Path to a page manifest JSON file. Repeat for multiple pages.",
    )
    parser.add_argument(
        "--stage",
        choices=["inventory", "preflight", "integrity", "all", "segment", "qa", "export", "validate", "build"],
        default="all",
        help=(
            "Audit stage to execute. 'all' means run all currently implemented audit stages "
            "(preflight + integrity) only; it does not run segmentation/export/build steps."
        ),
    )
    parser.add_argument(
        "--output-json",
        default=None,
        help="Optional path to write structured report JSON",
    )
    parser.add_argument(
        "--workspace-root",
        default=str((Path(__file__).resolve().parent / "work")),
        help="Workspace root for build-stage outputs (disposable/regenerable).",
    )
    parser.add_argument(
        "--build-id",
        default=None,
        help="Optional build id override. Defaults to deterministic id from source+config hashes.",
    )
    return parser.parse_args()


def _inventory_checks(manifest_path: Path) -> list[CheckResult]:
    exists = manifest_path.exists()
    return [
        CheckResult(
            severity=(CheckSeverity.PASS if exists else CheckSeverity.FAIL),
            code="MANIFEST_DISCOVERED",
            message=("Manifest found" if exists else "Manifest missing"),
            context={"path": str(manifest_path.resolve())},
        )
    ]


def _manifest_context(manifest) -> dict[str, object]:
    return {
        "title": manifest.title,
        "categoryId": manifest.category_id,
        "lifecycleStatus": manifest.lifecycle_status.value,
        "renderer": manifest.renderer.value,
        "profile": manifest.profile.value,
        "sourceArtworkPath": str(manifest.source_artwork_path),
        "segmentationOutputDir": str(manifest.segmentation_output_dir),
        "runtimeAssetDir": str(manifest.runtime_asset_dir),
        "runtimeMetadataPath": str(manifest.runtime_metadata_path),
        "runtimeRegionsDartPath": str(manifest.runtime_regions_dart_path),
        "assetBasePath": manifest.asset_base_path,
        "sourceArtworkVersion": manifest.source_artwork_version,
        "runtimeContentVersion": manifest.runtime_content_version,
        "pipelineVersion": manifest.pipeline_version,
    }


def build_stage_reports(manifest_paths: list[Path], stage: str) -> tuple[list[PageStageReport], dict[str, dict[str, object]]]:
    reports: list[PageStageReport] = []
    page_ids: dict[str, Path] = {}
    page_context_by_id: dict[str, dict[str, object]] = {}

    for manifest_path in manifest_paths:
        if stage == "inventory":
            checks = _inventory_checks(manifest_path)
            page_id = manifest_path.stem
            reports.append(PageStageReport(page_id=page_id, stage="inventory", checks=checks))
            continue

        manifest = load_manifest(manifest_path)
        if manifest.page_id in page_ids:
            first_manifest = page_ids[manifest.page_id]
            duplicate_checks = [
                CheckResult(
                    severity=CheckSeverity.FAIL,
                    code="DUPLICATE_PAGE_ID",
                    message="Duplicate pageId across manifests",
                    context={
                        "pageId": manifest.page_id,
                        "firstManifest": str(first_manifest),
                        "duplicateManifest": str(manifest_path),
                    },
                )
            ]
            reports.append(
                PageStageReport(
                    page_id=manifest.page_id,
                    stage=stage,
                    checks=duplicate_checks,
                )
            )
            continue

        page_ids[manifest.page_id] = manifest_path
        page_context_by_id[manifest.page_id] = _manifest_context(manifest)

        if stage == "preflight":
            reports.append(
                PageStageReport(
                    page_id=manifest.page_id,
                    stage="preflight",
                    checks=run_preflight(manifest),
                )
            )
            continue

        if stage == "integrity":
            reports.append(
                PageStageReport(
                    page_id=manifest.page_id,
                    stage="integrity",
                    checks=run_integrity_validation(manifest),
                )
            )
            continue

        all_checks = run_preflight(manifest) + run_integrity_validation(manifest)
        reports.append(
            PageStageReport(
                page_id=manifest.page_id,
                stage="all",
                checks=all_checks,
            )
        )

    return reports, page_context_by_id


def run_operational_stage(
    manifest_paths: list[Path],
    stage: str,
    workspace_root: Path,
    build_id_override: str | None,
) -> tuple[dict[str, Any], int]:
    reports: list[dict[str, Any]] = []
    summary_rows: list[dict[str, str]] = []
    page_ids: dict[str, Path] = {}
    exit_code = 0
    started = perf_counter()

    for manifest_path in manifest_paths:
        manifest = load_manifest(manifest_path)
        if manifest.page_id in page_ids:
            reports.append(
                {
                    "pageId": manifest.page_id,
                    "manifestPath": str(manifest_path),
                    "result": "FAIL",
                    "error": {
                        "code": "DUPLICATE_PAGE_ID",
                        "message": "Duplicate pageId across manifests",
                        "firstManifest": str(page_ids[manifest.page_id]),
                        "duplicateManifest": str(manifest_path),
                    },
                }
            )
            summary_rows.append(
                {
                    "page": manifest.page_id,
                    "preflight": "SKIPPED",
                    "segment": "FAIL",
                    "qa": "SKIPPED",
                    "export": "SKIPPED",
                    "validate": "SKIPPED",
                    "result": "FAIL",
                }
            )
            exit_code = 1
            continue

        page_ids[manifest.page_id] = manifest_path
        report, page_code = run_pipeline_for_manifest(
            manifest=manifest,
            stage=stage,
            workspace_root=workspace_root,
            build_id_override=build_id_override,
        )
        reports.append(report)
        status = report.get("stageStatus", {})
        summary_rows.append(
            {
                "page": manifest.page_id,
                "preflight": str(status.get("preflight", "SKIPPED")),
                "segment": str(status.get("segment", "SKIPPED")),
                "qa": str(status.get("qa", "SKIPPED")),
                "export": str(status.get("export", "SKIPPED")),
                "validate": str(status.get("validate", "SKIPPED")),
                "result": str(report.get("result", "FAIL")),
            }
        )
        if page_code != 0:
            exit_code = 1

    payload = {
        "stage": stage,
        "workspaceRoot": str(workspace_root.resolve()),
        "pages": reports,
        "summaryTable": summary_rows,
        "summary": {
            "totalPages": len(reports),
            "pass": sum(1 for r in reports if r.get("result") == "PASS"),
            "fail": sum(1 for r in reports if r.get("result") == "FAIL"),
            "durationMs": (perf_counter() - started) * 1000.0,
        },
    }
    return payload, exit_code


def main() -> int:
    args = _parse_args()

    manifest_paths = [Path(m).resolve() for m in args.manifest]
    if args.stage in {"inventory", "preflight", "integrity", "all"}:
        reports, page_context_by_id = build_stage_reports(manifest_paths=manifest_paths, stage=args.stage)

        report = OrchestrationReport(reports=reports)
        payload = report.to_json()

        for page in payload.get("pages", []):
            page_id = page.get("pageId")
            if isinstance(page_id, str) and page_id in page_context_by_id:
                page["manifest"] = page_context_by_id[page_id]
        exit_code = 0 if payload["summary"]["fail"] == 0 else 1
    else:
        payload, exit_code = run_operational_stage(
            manifest_paths=manifest_paths,
            stage=args.stage,
            workspace_root=Path(args.workspace_root).resolve(),
            build_id_override=args.build_id,
        )

    print(json.dumps(payload, indent=2))

    if args.output_json:
        out_path = Path(args.output_json).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2)
            fh.write("\n")

    if args.stage == "build":
        print("BUILD COMPLETE - HUMAN COVERAGE QA REQUIRED")
        for page in payload.get("pages", []):
            if page.get("result") != "PASS":
                continue
            msg = page.get("operatorMessage", {})
            page_id = page.get("pageId", "unknown-page")
            print(f"[{page_id}] Review full-color QA: {msg.get('reviewFullColorQa')}")
            print(f"[{page_id}] Optional labeled QA: {msg.get('reviewLabeledQa')}")
            print(f"[{page_id}] Runtime candidate: {msg.get('runtimeCandidatePath')}")
            print(f"[{page_id}] Next step: {msg.get('nextStep')}")

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
