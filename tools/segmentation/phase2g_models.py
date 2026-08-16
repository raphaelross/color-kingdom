from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any


class CheckSeverity(str, Enum):
    PASS = "PASS"
    WARN = "WARN"
    FAIL = "FAIL"


class LifecycleStatus(str, Enum):
    CONCEPT = "CONCEPT"
    PLANNED = "PLANNED"
    ARTWORK_GENERATED = "ARTWORK_GENERATED"
    AWAITING_ARTWORK_QA = "AWAITING_ARTWORK_QA"
    ARTWORK_APPROVED = "ARTWORK_APPROVED"
    SEGMENTED = "SEGMENTED"
    AWAITING_COVERAGE_QA = "AWAITING_COVERAGE_QA"
    COVERAGE_APPROVED = "COVERAGE_APPROVED"
    RUNTIME_EXPORTED = "RUNTIME_EXPORTED"
    RUNTIME_VALIDATED = "RUNTIME_VALIDATED"
    PRODUCTION_APPROVED = "PRODUCTION_APPROVED"


class RendererType(str, Enum):
    RASTER_REGION = "rasterRegion"
    SVG = "svg"


class ProfileType(str, Enum):
    CHILDREN_DETAILED = "childrenDetailed"
    CHILDREN_SIMPLE = "childrenSimple"
    MASTER = "master"


@dataclass(frozen=True)
class SegmentationPageManifest:
    schema_version: str
    page_id: str
    title: str
    category_id: str
    lifecycle_status: LifecycleStatus
    renderer: RendererType
    profile: ProfileType
    source_artwork_path: Path
    source_artwork_version: str
    segmentation_output_dir: Path
    runtime_asset_dir: Path
    runtime_metadata_path: Path
    runtime_regions_dart_path: Path
    asset_base_path: str
    runtime_content_version: str
    pipeline_version: str
    expected_image_width: int | None = None
    expected_image_height: int | None = None
    expected_orientation: str | None = None
    enforce_monochrome_line_art: bool = False
    build_config: dict[str, Any] = field(default_factory=dict)
    dart_symbol_prefix: str | None = None
    notes: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class CheckResult:
    severity: CheckSeverity
    code: str
    message: str
    context: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class PageStageReport:
    page_id: str
    stage: str
    checks: list[CheckResult]

    @property
    def worst_severity(self) -> CheckSeverity:
        if any(c.severity == CheckSeverity.FAIL for c in self.checks):
            return CheckSeverity.FAIL
        if any(c.severity == CheckSeverity.WARN for c in self.checks):
            return CheckSeverity.WARN
        return CheckSeverity.PASS


@dataclass(frozen=True)
class OrchestrationReport:
    reports: list[PageStageReport]

    def to_json(self) -> dict[str, Any]:
        return {
            "pages": [
                {
                    "pageId": report.page_id,
                    "stage": report.stage,
                    "worstSeverity": report.worst_severity.value,
                    "checks": [
                        {
                            "severity": check.severity.value,
                            "code": check.code,
                            "message": check.message,
                            "context": check.context,
                        }
                        for check in report.checks
                    ],
                }
                for report in self.reports
            ],
            "summary": {
                "totalPages": len(self.reports),
                "pass": sum(1 for r in self.reports if r.worst_severity == CheckSeverity.PASS),
                "warn": sum(1 for r in self.reports if r.worst_severity == CheckSeverity.WARN),
                "fail": sum(1 for r in self.reports if r.worst_severity == CheckSeverity.FAIL),
            },
        }
