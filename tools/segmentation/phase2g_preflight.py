from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from phase2g_models import CheckResult, CheckSeverity, SegmentationPageManifest


REQUIRED_SEGMENTATION_ARTIFACTS = (
    "regions.json",
    "region_map.png",
    "regions_children_detailed_qa_fullcolor.png",
    "regions_children_detailed_exclusions.png",
)

REQUIRED_RUNTIME_ASSETS = (
    "line_art_foreground.png",
    "line_art.png",
    "region_map.png",
    "region_fill_map.png",
    "metadata_children_detailed.json",
)


def run_preflight(manifest: SegmentationPageManifest) -> list[CheckResult]:
    checks: list[CheckResult] = []

    source_width: int | None = None
    source_height: int | None = None

    if manifest.source_artwork_path.exists():
        checks.append(
            CheckResult(
                severity=CheckSeverity.PASS,
                code="SOURCE_ARTWORK_EXISTS",
                message="Source artwork exists",
                context={"path": str(manifest.source_artwork_path)},
            )
        )

        try:
            with Image.open(manifest.source_artwork_path) as img:
                source_width, source_height = img.size
                rgb = img.convert("RGB")
                pixel_bytes = rgb.tobytes()

            checks.append(
                CheckResult(
                    severity=CheckSeverity.PASS,
                    code="SOURCE_IMAGE_READABLE",
                    message="Source artwork image can be opened and decoded",
                    context={"width": source_width, "height": source_height},
                )
            )

            if manifest.expected_image_width is not None and source_width != manifest.expected_image_width:
                checks.append(
                    CheckResult(
                        severity=CheckSeverity.FAIL,
                        code="SOURCE_WIDTH_MISMATCH",
                        message="Source artwork width does not match expected width",
                        context={
                            "expected": manifest.expected_image_width,
                            "actual": source_width,
                        },
                    )
                )
            if manifest.expected_image_height is not None and source_height != manifest.expected_image_height:
                checks.append(
                    CheckResult(
                        severity=CheckSeverity.FAIL,
                        code="SOURCE_HEIGHT_MISMATCH",
                        message="Source artwork height does not match expected height",
                        context={
                            "expected": manifest.expected_image_height,
                            "actual": source_height,
                        },
                    )
                )

            if manifest.expected_orientation:
                if source_width == source_height:
                    actual_orientation = "square"
                elif source_height > source_width:
                    actual_orientation = "portrait"
                else:
                    actual_orientation = "landscape"

                if actual_orientation != manifest.expected_orientation:
                    checks.append(
                        CheckResult(
                            severity=CheckSeverity.FAIL,
                            code="SOURCE_ORIENTATION_MISMATCH",
                            message="Source artwork orientation does not match expected orientation",
                            context={
                                "expected": manifest.expected_orientation,
                                "actual": actual_orientation,
                            },
                        )
                    )
                else:
                    checks.append(
                        CheckResult(
                            severity=CheckSeverity.PASS,
                            code="SOURCE_ORIENTATION_MATCH",
                            message="Source artwork orientation matches expected orientation",
                            context={"orientation": actual_orientation},
                        )
                    )

            if manifest.enforce_monochrome_line_art:
                total = source_width * source_height
                non_monochrome = 0
                for i in range(0, len(pixel_bytes), 3):
                    r = pixel_bytes[i]
                    g = pixel_bytes[i + 1]
                    b = pixel_bytes[i + 2]
                    if not (r == g == b):
                        non_monochrome += 1
                percent = (non_monochrome / total) * 100.0 if total > 0 else 0.0
                severity = CheckSeverity.PASS if percent <= 0.10 else CheckSeverity.FAIL
                checks.append(
                    CheckResult(
                        severity=severity,
                        code=(
                            "SOURCE_MONOCHROME_OK"
                            if severity == CheckSeverity.PASS
                            else "SOURCE_COLOR_CONTAMINATION"
                        ),
                        message=(
                            "Source artwork is monochrome within tolerance"
                            if severity == CheckSeverity.PASS
                            else "Source artwork contains non-monochrome color contamination"
                        ),
                        context={
                            "nonMonochromePixels": non_monochrome,
                            "totalPixels": total,
                            "percent": round(percent, 6),
                            "tolerancePercent": 0.10,
                        },
                    )
                )

        except Exception as error:
            checks.append(
                CheckResult(
                    severity=CheckSeverity.FAIL,
                    code="SOURCE_IMAGE_READ_FAILED",
                    message=f"Source artwork exists but cannot be decoded: {error}",
                    context={"path": str(manifest.source_artwork_path)},
                )
            )
    else:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="SOURCE_ARTWORK_MISSING",
                message="Source artwork file is missing",
                context={"path": str(manifest.source_artwork_path)},
            )
        )

    missing_segmentation = [
        name
        for name in REQUIRED_SEGMENTATION_ARTIFACTS
        if not (manifest.segmentation_output_dir / name).exists()
    ]
    checks.append(
        CheckResult(
            severity=CheckSeverity.PASS if not missing_segmentation else CheckSeverity.WARN,
            code="SEGMENTATION_ARTIFACTS_BASELINE",
            message=(
                "All required baseline segmentation artifacts found"
                if not missing_segmentation
                else "Some required baseline segmentation artifacts are missing"
            ),
            context={
                "outputDir": str(manifest.segmentation_output_dir),
                "missing": missing_segmentation,
            },
        )
    )

    missing_runtime = [
        name for name in REQUIRED_RUNTIME_ASSETS if not (manifest.runtime_asset_dir / name).exists()
    ]
    checks.append(
        CheckResult(
            severity=CheckSeverity.PASS if not missing_runtime else CheckSeverity.FAIL,
            code="RUNTIME_ASSETS_PRESENT",
            message=(
                "All required runtime assets found"
                if not missing_runtime
                else "Runtime assets are missing"
            ),
            context={"runtimeAssetDir": str(manifest.runtime_asset_dir), "missing": missing_runtime},
        )
    )

    if manifest.runtime_metadata_path.exists():
        try:
            with manifest.runtime_metadata_path.open("r", encoding="utf-8") as fh:
                metadata = json.load(fh)
            page_id = metadata.get("pageId")
            region_count = metadata.get("regionCount")
            if page_id != manifest.page_id:
                checks.append(
                    CheckResult(
                        severity=CheckSeverity.FAIL,
                        code="METADATA_PAGE_ID_MISMATCH",
                        message="Runtime metadata pageId does not match manifest pageId",
                        context={"metadataPageId": page_id, "manifestPageId": manifest.page_id},
                    )
                )
            elif not isinstance(region_count, int) or region_count <= 0:
                checks.append(
                    CheckResult(
                        severity=CheckSeverity.FAIL,
                        code="METADATA_REGION_COUNT_INVALID",
                        message="Runtime metadata regionCount is invalid",
                        context={"regionCount": region_count},
                    )
                )
            else:
                checks.append(
                    CheckResult(
                        severity=CheckSeverity.PASS,
                        code="METADATA_BASELINE_VALID",
                        message="Runtime metadata pageId and regionCount are valid",
                        context={"regionCount": region_count},
                    )
                )
        except Exception as error:
            checks.append(
                CheckResult(
                    severity=CheckSeverity.FAIL,
                    code="METADATA_READ_FAILED",
                    message=f"Failed to read runtime metadata: {error}",
                    context={"path": str(manifest.runtime_metadata_path)},
                )
            )
    else:
        checks.append(
            CheckResult(
                severity=CheckSeverity.FAIL,
                code="METADATA_MISSING",
                message="Runtime metadata file is missing",
                context={"path": str(manifest.runtime_metadata_path)},
            )
        )

    if manifest.runtime_regions_dart_path.exists():
        checks.append(
            CheckResult(
                severity=CheckSeverity.PASS,
                code="DART_REGIONS_FILE_PRESENT",
                message="Dart region mapping file exists",
                context={"path": str(manifest.runtime_regions_dart_path)},
            )
        )
    else:
        checks.append(
            CheckResult(
                severity=CheckSeverity.WARN,
                code="DART_REGIONS_FILE_MISSING",
                message="Dart region mapping file is missing",
                context={"path": str(manifest.runtime_regions_dart_path)},
            )
        )

    return checks
