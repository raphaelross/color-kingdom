from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from phase2g_integrity import run_integrity_validation
from phase2g_manifest import load_manifest
from orchestrate_segmentation import build_stage_reports
from phase2g_models import (
    CheckResult,
    CheckSeverity,
    LifecycleStatus,
    OrchestrationReport,
    PageStageReport,
    ProfileType,
    RendererType,
    SegmentationPageManifest,
)
from phase2g_preflight import run_preflight


def test_load_manifest_for_panda_page() -> None:
    manifest_path = Path("manifests/cheerful_baby_panda.page.json").resolve()
    manifest = load_manifest(manifest_path)

    assert manifest.page_id == "cheerful-baby-panda"
    assert manifest.lifecycle_status == LifecycleStatus.PRODUCTION_APPROVED
    assert manifest.renderer.value == "rasterRegion"
    assert manifest.profile.value == "childrenDetailed"
    assert manifest.asset_base_path == "assets/coloring_pages/animals/cheerful_baby_panda"


def test_preflight_has_no_failures_for_canonical_pages() -> None:
    manifest_paths = [
        Path("manifests/cheerful_baby_panda.page.json").resolve(),
        Path("manifests/lovely_kitten_raster_poc.page.json").resolve(),
    ]

    for manifest_path in manifest_paths:
        manifest = load_manifest(manifest_path)
        checks = run_preflight(manifest)
        assert all(check.severity != CheckSeverity.FAIL for check in checks)


def test_integrity_has_no_failures_for_canonical_pages() -> None:
    manifest_paths = [
        Path("manifests/cheerful_baby_panda.page.json").resolve(),
        Path("manifests/lovely_kitten_raster_poc.page.json").resolve(),
    ]

    for manifest_path in manifest_paths:
        manifest = load_manifest(manifest_path)
        checks = run_integrity_validation(manifest)
        assert any(check.code == "RUNTIME_REGION_SET_MATCH" for check in checks)
        assert all(check.severity != CheckSeverity.FAIL for check in checks)


def test_integrity_detects_runtime_region_mismatch(tmp_path: Path) -> None:
    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()

    segmentation_payload = {
        "acceptedRegions": [
            {
                "id": "region-001",
                "profiles": {
                    "childrenDetailed": {
                        "included": True,
                    }
                },
            }
        ]
    }
    runtime_payload = {
        "pageId": "fake-page",
        "regionCount": 1,
        "regionMapAssetPath": "assets/coloring_pages/fake/region_map.png",
        "regionFillMapAssetPath": "assets/coloring_pages/fake/region_fill_map.png",
        "regions": [
            {
                "regionId": "region-999",
                "mapColorRgba": [1, 2, 3, 255],
            }
        ],
    }

    (output_dir / "regions.json").write_text(json.dumps(segmentation_payload), encoding="utf-8")
    metadata_path = runtime_dir / "metadata_children_detailed.json"
    metadata_path.write_text(json.dumps(runtime_payload), encoding="utf-8")

    manifest = SegmentationPageManifest(
        schema_version="2.7.0",
        page_id="fake-page",
        title="Fake",
        category_id="animals",
        lifecycle_status=LifecycleStatus.PRODUCTION_APPROVED,
        renderer=RendererType.RASTER_REGION,
        profile=ProfileType.CHILDREN_DETAILED,
        source_artwork_path=tmp_path / "source.png",
        source_artwork_version="v1",
        segmentation_output_dir=output_dir,
        runtime_asset_dir=runtime_dir,
        runtime_metadata_path=metadata_path,
        runtime_regions_dart_path=tmp_path / "fake_regions.dart",
        asset_base_path="assets/coloring_pages/fake",
        runtime_content_version="v1",
        pipeline_version="phase2g-part1b",
    )

    checks = run_integrity_validation(manifest)
    mismatch = [c for c in checks if c.code == "RUNTIME_REGION_SET_MISMATCH"]

    assert len(mismatch) == 1
    assert mismatch[0].severity == CheckSeverity.FAIL


def test_preflight_fails_when_source_artwork_missing(tmp_path: Path) -> None:
    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()

    for name in [
        "regions.json",
        "region_map.png",
        "regions_children_detailed_qa_fullcolor.png",
        "regions_children_detailed_exclusions.png",
    ]:
        (output_dir / name).write_text("x", encoding="utf-8")

    for name in [
        "line_art_foreground.png",
        "line_art.png",
        "region_map.png",
        "region_fill_map.png",
    ]:
        (runtime_dir / name).write_text("x", encoding="utf-8")

    metadata_path = runtime_dir / "metadata_children_detailed.json"
    metadata_path.write_text(
        json.dumps({"pageId": "fake-page", "regionCount": 1, "regions": [{"regionId": "region-001"}]}),
        encoding="utf-8",
    )

    manifest = SegmentationPageManifest(
        schema_version="2.7.0",
        page_id="fake-page",
        title="Fake",
        category_id="animals",
        lifecycle_status=LifecycleStatus.PRODUCTION_APPROVED,
        renderer=RendererType.RASTER_REGION,
        profile=ProfileType.CHILDREN_DETAILED,
        source_artwork_path=tmp_path / "missing.png",
        source_artwork_version="v1",
        segmentation_output_dir=output_dir,
        runtime_asset_dir=runtime_dir,
        runtime_metadata_path=metadata_path,
        runtime_regions_dart_path=tmp_path / "fake_regions.dart",
        asset_base_path="assets/coloring_pages/fake",
        runtime_content_version="v1",
        pipeline_version="phase2g-part1b",
    )

    checks = run_preflight(manifest)
    missing_source = [c for c in checks if c.code == "SOURCE_ARTWORK_MISSING"]

    assert len(missing_source) == 1
    assert missing_source[0].severity == CheckSeverity.FAIL


def test_orchestration_report_summary_counts() -> None:
    reports = [
        PageStageReport(
            page_id="a",
            stage="preflight",
            checks=[CheckResult(CheckSeverity.PASS, "PASS_CODE", "ok")],
        ),
        PageStageReport(
            page_id="b",
            stage="preflight",
            checks=[CheckResult(CheckSeverity.WARN, "WARN_CODE", "warn")],
        ),
        PageStageReport(
            page_id="c",
            stage="preflight",
            checks=[CheckResult(CheckSeverity.FAIL, "FAIL_CODE", "fail")],
        ),
    ]

    payload = OrchestrationReport(reports).to_json()
    assert payload["summary"] == {"totalPages": 3, "pass": 1, "warn": 1, "fail": 1}


def test_orchestration_report_is_deterministic() -> None:
    reports = [
        PageStageReport(
            page_id="a",
            stage="all",
            checks=[
                CheckResult(CheckSeverity.PASS, "A", "ok", {"x": 1}),
                CheckResult(CheckSeverity.WARN, "B", "warn", {"y": 2}),
            ],
        )
    ]
    payload_a = OrchestrationReport(reports).to_json()
    payload_b = OrchestrationReport(reports).to_json()
    assert payload_a == payload_b


def test_manifest_rejects_missing_required_field(tmp_path: Path) -> None:
    manifest_path = tmp_path / "bad.page.json"
    manifest_path.write_text(
        json.dumps(
            {
                "schemaVersion": "2.7.0",
                "pageId": "bad",
                "title": "Bad",
            }
        ),
        encoding="utf-8",
    )

    try:
        load_manifest(manifest_path)
        assert False, "Expected ValueError"
    except ValueError:
        assert True


def test_manifest_rejects_unsupported_renderer(tmp_path: Path) -> None:
    manifest_path = tmp_path / "bad_renderer.page.json"
    manifest_path.write_text(
        json.dumps(
            {
                "schemaVersion": "2.7.0",
                "pageId": "bad",
                "title": "Bad",
                "categoryId": "animals",
                "lifecycleStatus": "PLANNED",
                "renderer": "unknownRenderer",
                "profile": "childrenDetailed",
                "sourceArtworkPath": "assets/source_artwork/animals/lovely_kitten_master.png",
                "sourceArtworkVersion": "v1",
                "segmentationOutputDir": "tools/segmentation/output/lovely_kitten/phase2c_tuned",
                "runtimeAssetDir": "assets/coloring_pages/animals/lovely_kitten_raster_poc",
                "runtimeMetadataPath": "assets/coloring_pages/animals/lovely_kitten_raster_poc/metadata_children_detailed.json",
                "runtimeRegionsDartPath": "lib/features/coloring/data/lovely_kitten_raster_regions.dart",
                "assetBasePath": "assets/coloring_pages/animals/lovely_kitten_raster_poc",
                "runtimeContentVersion": "v1",
                "pipelineVersion": "p1",
            }
        ),
        encoding="utf-8",
    )

    try:
        load_manifest(manifest_path)
        assert False, "Expected ValueError"
    except ValueError as error:
        assert "renderer" in str(error)


def test_manifest_rejects_unsupported_profile(tmp_path: Path) -> None:
    manifest_path = tmp_path / "bad_profile.page.json"
    manifest_path.write_text(
        json.dumps(
            {
                "schemaVersion": "2.7.0",
                "pageId": "bad",
                "title": "Bad",
                "categoryId": "animals",
                "lifecycleStatus": "PLANNED",
                "renderer": "rasterRegion",
                "profile": "invalidProfile",
                "sourceArtworkPath": "assets/source_artwork/animals/lovely_kitten_master.png",
                "sourceArtworkVersion": "v1",
                "segmentationOutputDir": "tools/segmentation/output/lovely_kitten/phase2c_tuned",
                "runtimeAssetDir": "assets/coloring_pages/animals/lovely_kitten_raster_poc",
                "runtimeMetadataPath": "assets/coloring_pages/animals/lovely_kitten_raster_poc/metadata_children_detailed.json",
                "runtimeRegionsDartPath": "lib/features/coloring/data/lovely_kitten_raster_regions.dart",
                "assetBasePath": "assets/coloring_pages/animals/lovely_kitten_raster_poc",
                "runtimeContentVersion": "v1",
                "pipelineVersion": "p1",
            }
        ),
        encoding="utf-8",
    )

    try:
        load_manifest(manifest_path)
        assert False, "Expected ValueError"
    except ValueError as error:
        assert "profile" in str(error)


def test_duplicate_page_id_detected_across_manifests(tmp_path: Path) -> None:
    source = tmp_path / "source.png"
    Image.new("RGB", (10, 10), (255, 255, 255)).save(source)

    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()

    (output_dir / "regions.json").write_text(
        json.dumps({"acceptedRegions": [{"id": "region-001", "profiles": {"childrenDetailed": {"included": True}}}]}),
        encoding="utf-8",
    )
    for name in ["region_map.png", "regions_children_detailed_qa_fullcolor.png", "regions_children_detailed_exclusions.png"]:
        (output_dir / name).write_text("x", encoding="utf-8")

    Image.new("RGBA", (10, 10), (255, 0, 0, 255)).save(runtime_dir / "region_map.png")
    Image.new("RGBA", (10, 10), (255, 0, 0, 255)).save(runtime_dir / "region_fill_map.png")
    for name in ["line_art_foreground.png", "line_art.png"]:
        (runtime_dir / name).write_text("x", encoding="utf-8")
    (runtime_dir / "metadata_children_detailed.json").write_text(
        json.dumps(
            {
                "pageId": "dup-page",
                "regionCount": 1,
                "regionMapAssetPath": "assets/coloring_pages/dup/region_map.png",
                "regionFillMapAssetPath": "assets/coloring_pages/dup/region_fill_map.png",
                "regions": [{"regionId": "region-001", "mapColorRgba": [255, 0, 0, 255]}],
            }
        ),
        encoding="utf-8",
    )

    base_payload = {
        "schemaVersion": "2.7.0",
        "pageId": "dup-page",
        "title": "Dup",
        "categoryId": "animals",
        "lifecycleStatus": "PLANNED",
        "renderer": "rasterRegion",
        "profile": "childrenDetailed",
        "sourceArtworkPath": str(source),
        "sourceArtworkVersion": "v1",
        "segmentationOutputDir": str(output_dir),
        "runtimeAssetDir": str(runtime_dir),
        "runtimeMetadataPath": str(runtime_dir / "metadata_children_detailed.json"),
        "runtimeRegionsDartPath": str(tmp_path / "d.dart"),
        "assetBasePath": "assets/coloring_pages/dup",
        "runtimeContentVersion": "v1",
        "pipelineVersion": "p1",
    }

    m1 = tmp_path / "one.page.json"
    m2 = tmp_path / "two.page.json"
    m1.write_text(json.dumps(base_payload), encoding="utf-8")
    m2.write_text(json.dumps(base_payload), encoding="utf-8")

    reports, _ = build_stage_reports([m1.resolve(), m2.resolve()], "all")
    assert any(any(c.code == "DUPLICATE_PAGE_ID" for c in report.checks) for report in reports)


def test_preflight_is_deterministic(tmp_path: Path) -> None:
    source = tmp_path / "mono.png"
    img = Image.new("RGB", (10, 12), (255, 255, 255))
    img.save(source)

    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()
    for name in [
        "regions.json",
        "region_map.png",
        "regions_children_detailed_qa_fullcolor.png",
        "regions_children_detailed_exclusions.png",
    ]:
        (output_dir / name).write_text("x", encoding="utf-8")
    for name in [
        "line_art_foreground.png",
        "line_art.png",
        "region_map.png",
        "region_fill_map.png",
    ]:
        (runtime_dir / name).write_text("x", encoding="utf-8")
    metadata_path = runtime_dir / "metadata_children_detailed.json"
    metadata_path.write_text(
        json.dumps({"pageId": "det-page", "regionCount": 1, "regions": [{"regionId": "region-001"}]}),
        encoding="utf-8",
    )

    manifest = SegmentationPageManifest(
        schema_version="2.7.0",
        page_id="det-page",
        title="Deterministic",
        category_id="animals",
        lifecycle_status=LifecycleStatus.PRODUCTION_APPROVED,
        renderer=RendererType.RASTER_REGION,
        profile=ProfileType.CHILDREN_DETAILED,
        source_artwork_path=source,
        source_artwork_version="v1",
        segmentation_output_dir=output_dir,
        runtime_asset_dir=runtime_dir,
        runtime_metadata_path=metadata_path,
        runtime_regions_dart_path=tmp_path / "d.dart",
        asset_base_path="assets/coloring_pages/det",
        runtime_content_version="v1",
        pipeline_version="p1",
        expected_image_width=10,
        expected_image_height=12,
        expected_orientation="portrait",
        enforce_monochrome_line_art=True,
    )

    a = run_preflight(manifest)
    b = run_preflight(manifest)
    assert [(c.code, c.severity, c.message) for c in a] == [(c.code, c.severity, c.message) for c in b]


def test_preflight_detects_color_contamination(tmp_path: Path) -> None:
    source = tmp_path / "colored.png"
    img = Image.new("RGB", (20, 20), (255, 255, 255))
    img.putpixel((0, 0), (255, 0, 0))
    img.save(source)

    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()
    for name in [
        "regions.json",
        "region_map.png",
        "regions_children_detailed_qa_fullcolor.png",
        "regions_children_detailed_exclusions.png",
    ]:
        (output_dir / name).write_text("x", encoding="utf-8")
    for name in [
        "line_art_foreground.png",
        "line_art.png",
        "region_map.png",
        "region_fill_map.png",
    ]:
        (runtime_dir / name).write_text("x", encoding="utf-8")
    metadata_path = runtime_dir / "metadata_children_detailed.json"
    metadata_path.write_text(
        json.dumps({"pageId": "contam-page", "regionCount": 1, "regions": [{"regionId": "region-001"}]}),
        encoding="utf-8",
    )

    manifest = SegmentationPageManifest(
        schema_version="2.7.0",
        page_id="contam-page",
        title="Contaminated",
        category_id="animals",
        lifecycle_status=LifecycleStatus.PRODUCTION_APPROVED,
        renderer=RendererType.RASTER_REGION,
        profile=ProfileType.CHILDREN_DETAILED,
        source_artwork_path=source,
        source_artwork_version="v1",
        segmentation_output_dir=output_dir,
        runtime_asset_dir=runtime_dir,
        runtime_metadata_path=metadata_path,
        runtime_regions_dart_path=tmp_path / "d.dart",
        asset_base_path="assets/coloring_pages/contam",
        runtime_content_version="v1",
        pipeline_version="p1",
        enforce_monochrome_line_art=True,
    )

    checks = run_preflight(manifest)
    assert any(c.code == "SOURCE_COLOR_CONTAMINATION" and c.severity == CheckSeverity.FAIL for c in checks)


def test_preflight_detects_corrupt_image(tmp_path: Path) -> None:
    source = tmp_path / "corrupt.png"
    source.write_bytes(b"not-a-real-image")

    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()
    metadata_path = runtime_dir / "metadata_children_detailed.json"
    metadata_path.write_text(
        json.dumps({"pageId": "corrupt-page", "regionCount": 1, "regions": [{"regionId": "region-001"}]}),
        encoding="utf-8",
    )

    manifest = SegmentationPageManifest(
        schema_version="2.7.0",
        page_id="corrupt-page",
        title="Corrupt",
        category_id="animals",
        lifecycle_status=LifecycleStatus.PRODUCTION_APPROVED,
        renderer=RendererType.RASTER_REGION,
        profile=ProfileType.CHILDREN_DETAILED,
        source_artwork_path=source,
        source_artwork_version="v1",
        segmentation_output_dir=output_dir,
        runtime_asset_dir=runtime_dir,
        runtime_metadata_path=metadata_path,
        runtime_regions_dart_path=tmp_path / "d.dart",
        asset_base_path="assets/coloring_pages/corrupt",
        runtime_content_version="v1",
        pipeline_version="p1",
    )

    checks = run_preflight(manifest)
    assert any(c.code == "SOURCE_IMAGE_READ_FAILED" and c.severity == CheckSeverity.FAIL for c in checks)


def test_preflight_detects_dimension_and_orientation_mismatch(tmp_path: Path) -> None:
    source = tmp_path / "source.png"
    Image.new("RGB", (20, 10), (255, 255, 255)).save(source)

    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()

    for name in [
        "regions.json",
        "region_map.png",
        "regions_children_detailed_qa_fullcolor.png",
        "regions_children_detailed_exclusions.png",
    ]:
        (output_dir / name).write_text("x", encoding="utf-8")
    for name in [
        "line_art_foreground.png",
        "line_art.png",
        "region_map.png",
        "region_fill_map.png",
    ]:
        (runtime_dir / name).write_text("x", encoding="utf-8")
    metadata_path = runtime_dir / "metadata_children_detailed.json"
    metadata_path.write_text(
        json.dumps({"pageId": "shape-page", "regionCount": 1, "regions": [{"regionId": "region-001"}]}),
        encoding="utf-8",
    )

    manifest = SegmentationPageManifest(
        schema_version="2.7.0",
        page_id="shape-page",
        title="Shape",
        category_id="animals",
        lifecycle_status=LifecycleStatus.PRODUCTION_APPROVED,
        renderer=RendererType.RASTER_REGION,
        profile=ProfileType.CHILDREN_DETAILED,
        source_artwork_path=source,
        source_artwork_version="v1",
        segmentation_output_dir=output_dir,
        runtime_asset_dir=runtime_dir,
        runtime_metadata_path=metadata_path,
        runtime_regions_dart_path=tmp_path / "d.dart",
        asset_base_path="assets/coloring_pages/shape",
        runtime_content_version="v1",
        pipeline_version="p1",
        expected_image_width=10,
        expected_image_height=20,
        expected_orientation="portrait",
    )

    checks = run_preflight(manifest)
    assert any(c.code == "SOURCE_WIDTH_MISMATCH" and c.severity == CheckSeverity.FAIL for c in checks)
    assert any(c.code == "SOURCE_HEIGHT_MISMATCH" and c.severity == CheckSeverity.FAIL for c in checks)
    assert any(c.code == "SOURCE_ORIENTATION_MISMATCH" and c.severity == CheckSeverity.FAIL for c in checks)


def test_integrity_detects_zero_pixel_regions_in_maps(tmp_path: Path) -> None:
    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()

    segmentation_payload = {
        "acceptedRegions": [
            {"id": "region-001", "profiles": {"childrenDetailed": {"included": True}}},
            {"id": "region-002", "profiles": {"childrenDetailed": {"included": True}}},
        ]
    }
    (output_dir / "regions.json").write_text(json.dumps(segmentation_payload), encoding="utf-8")

    runtime_payload = {
        "pageId": "map-page",
        "regionCount": 2,
        "regionMapAssetPath": "assets/coloring_pages/map/region_map.png",
        "regionFillMapAssetPath": "assets/coloring_pages/map/region_fill_map.png",
        "regions": [
            {"regionId": "region-001", "mapColorRgba": [255, 0, 0, 255]},
            {"regionId": "region-002", "mapColorRgba": [0, 255, 0, 255]},
        ],
    }
    metadata_path = runtime_dir / "metadata_children_detailed.json"
    metadata_path.write_text(json.dumps(runtime_payload), encoding="utf-8")

    logical = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
    logical.putpixel((0, 0), (255, 0, 0, 255))
    logical.save(runtime_dir / "region_map.png")

    fill = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
    fill.putpixel((0, 0), (255, 0, 0, 255))
    fill.save(runtime_dir / "region_fill_map.png")

    manifest = SegmentationPageManifest(
        schema_version="2.7.0",
        page_id="map-page",
        title="Map",
        category_id="animals",
        lifecycle_status=LifecycleStatus.PRODUCTION_APPROVED,
        renderer=RendererType.RASTER_REGION,
        profile=ProfileType.CHILDREN_DETAILED,
        source_artwork_path=tmp_path / "source.png",
        source_artwork_version="v1",
        segmentation_output_dir=output_dir,
        runtime_asset_dir=runtime_dir,
        runtime_metadata_path=metadata_path,
        runtime_regions_dart_path=tmp_path / "d.dart",
        asset_base_path="assets/coloring_pages/map",
        runtime_content_version="v1",
        pipeline_version="p1",
    )

    checks = run_integrity_validation(manifest)
    assert any(c.code == "LOGICAL_MAP_ZERO_PIXEL_REGIONS" and c.severity == CheckSeverity.FAIL for c in checks)
    assert any(c.code == "FILL_MAP_ZERO_PIXEL_REGIONS" and c.severity == CheckSeverity.FAIL for c in checks)


def test_integrity_detects_duplicate_region_colors(tmp_path: Path) -> None:
    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()

    segmentation_payload = {
        "acceptedRegions": [
            {"id": "region-001", "profiles": {"childrenDetailed": {"included": True}}},
            {"id": "region-002", "profiles": {"childrenDetailed": {"included": True}}},
        ]
    }
    (output_dir / "regions.json").write_text(json.dumps(segmentation_payload), encoding="utf-8")

    runtime_payload = {
        "pageId": "dup-color-page",
        "regionCount": 2,
        "regionMapAssetPath": "assets/coloring_pages/dup/region_map.png",
        "regionFillMapAssetPath": "assets/coloring_pages/dup/region_fill_map.png",
        "regions": [
            {"regionId": "region-001", "mapColorRgba": [255, 0, 0, 255]},
            {"regionId": "region-002", "mapColorRgba": [255, 0, 0, 255]},
        ],
    }
    metadata_path = runtime_dir / "metadata_children_detailed.json"
    metadata_path.write_text(json.dumps(runtime_payload), encoding="utf-8")

    Image.new("RGBA", (2, 2), (255, 0, 0, 255)).save(runtime_dir / "region_map.png")
    Image.new("RGBA", (2, 2), (255, 0, 0, 255)).save(runtime_dir / "region_fill_map.png")

    manifest = SegmentationPageManifest(
        schema_version="2.7.0",
        page_id="dup-color-page",
        title="Duplicate Color",
        category_id="animals",
        lifecycle_status=LifecycleStatus.PRODUCTION_APPROVED,
        renderer=RendererType.RASTER_REGION,
        profile=ProfileType.CHILDREN_DETAILED,
        source_artwork_path=tmp_path / "source.png",
        source_artwork_version="v1",
        segmentation_output_dir=output_dir,
        runtime_asset_dir=runtime_dir,
        runtime_metadata_path=metadata_path,
        runtime_regions_dart_path=tmp_path / "d.dart",
        asset_base_path="assets/coloring_pages/dup",
        runtime_content_version="v1",
        pipeline_version="p1",
    )

    checks = run_integrity_validation(manifest)
    assert any(c.code == "RUNTIME_DUPLICATE_REGION_COLORS" and c.severity == CheckSeverity.FAIL for c in checks)


def test_integrity_detects_region_count_mismatch(tmp_path: Path) -> None:
    output_dir = tmp_path / "output"
    runtime_dir = tmp_path / "runtime"
    output_dir.mkdir()
    runtime_dir.mkdir()

    (output_dir / "regions.json").write_text(
        json.dumps({"acceptedRegions": [{"id": "region-001", "profiles": {"childrenDetailed": {"included": True}}}]}),
        encoding="utf-8",
    )
    Image.new("RGBA", (2, 2), (255, 0, 0, 255)).save(runtime_dir / "region_map.png")
    Image.new("RGBA", (2, 2), (255, 0, 0, 255)).save(runtime_dir / "region_fill_map.png")

    metadata_payload = {
        "pageId": "count-page",
        "regionCount": 99,
        "regionMapAssetPath": "assets/coloring_pages/count/region_map.png",
        "regionFillMapAssetPath": "assets/coloring_pages/count/region_fill_map.png",
        "regions": [{"regionId": "region-001", "mapColorRgba": [255, 0, 0, 255]}],
    }
    metadata_path = runtime_dir / "metadata_children_detailed.json"
    metadata_path.write_text(json.dumps(metadata_payload), encoding="utf-8")

    manifest = SegmentationPageManifest(
        schema_version="2.7.0",
        page_id="count-page",
        title="Count",
        category_id="animals",
        lifecycle_status=LifecycleStatus.PRODUCTION_APPROVED,
        renderer=RendererType.RASTER_REGION,
        profile=ProfileType.CHILDREN_DETAILED,
        source_artwork_path=tmp_path / "source.png",
        source_artwork_version="v1",
        segmentation_output_dir=output_dir,
        runtime_asset_dir=runtime_dir,
        runtime_metadata_path=metadata_path,
        runtime_regions_dart_path=tmp_path / "d.dart",
        asset_base_path="assets/coloring_pages/count",
        runtime_content_version="v1",
        pipeline_version="p1",
    )

    checks = run_integrity_validation(manifest)
    assert any(c.code == "RUNTIME_REGION_COUNT_MISMATCH" and c.severity == CheckSeverity.FAIL for c in checks)
