from __future__ import annotations

import json
from pathlib import Path

from phase2g_models import (
    LifecycleStatus,
    ProfileType,
    RendererType,
    SegmentationPageManifest,
)


REPO_ROOT = Path(__file__).resolve().parents[2]


def _require_str(raw: dict[str, object], key: str) -> str:
    value = raw.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Manifest field '{key}' must be a non-empty string")
    return value.strip()


def _resolve_repo_path(raw_path: str) -> Path:
    path = Path(raw_path)
    if path.is_absolute():
        return path
    return (REPO_ROOT / path).resolve()


def _optional_positive_int(raw: dict[str, object], key: str) -> int | None:
    value = raw.get(key)
    if value is None:
        return None
    if not isinstance(value, int) or value <= 0:
        raise ValueError(f"Manifest field '{key}' must be a positive integer when present")
    return value


def _optional_expected_orientation(raw: dict[str, object]) -> str | None:
    value = raw.get("expectedOrientation")
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError("Manifest field 'expectedOrientation' must be a string when present")
    normalized = value.strip().lower()
    if normalized not in ("portrait", "landscape", "square"):
        raise ValueError("expectedOrientation must be one of: portrait, landscape, square")
    return normalized


def load_manifest(path: Path) -> SegmentationPageManifest:
    with path.open("r", encoding="utf-8") as fh:
        payload = json.load(fh)

    if not isinstance(payload, dict):
        raise ValueError(f"Manifest at {path} must be a JSON object")

    lifecycle_raw = _require_str(payload, "lifecycleStatus")
    try:
        lifecycle = LifecycleStatus(lifecycle_raw)
    except ValueError as error:
        valid = ", ".join(s.value for s in LifecycleStatus)
        raise ValueError(
            f"Invalid lifecycleStatus '{lifecycle_raw}' in {path}. Valid values: {valid}"
        ) from error

    renderer_raw = _require_str(payload, "renderer")
    try:
        renderer = RendererType(renderer_raw)
    except ValueError as error:
        valid = ", ".join(s.value for s in RendererType)
        raise ValueError(
            f"Invalid renderer '{renderer_raw}' in {path}. Valid values: {valid}"
        ) from error

    profile_raw = _require_str(payload, "profile")
    try:
        profile = ProfileType(profile_raw)
    except ValueError as error:
        valid = ", ".join(s.value for s in ProfileType)
        raise ValueError(
            f"Invalid profile '{profile_raw}' in {path}. Valid values: {valid}"
        ) from error

    notes = payload.get("notes", [])
    if not isinstance(notes, list) or any(not isinstance(n, str) for n in notes):
        raise ValueError(f"Manifest field 'notes' must be a string array in {path}")

    build_config = payload.get("buildConfig", {})
    if not isinstance(build_config, dict):
        raise ValueError(f"Manifest field 'buildConfig' must be an object in {path}")

    manifest = SegmentationPageManifest(
        schema_version=_require_str(payload, "schemaVersion"),
        page_id=_require_str(payload, "pageId"),
        title=_require_str(payload, "title"),
        category_id=_require_str(payload, "categoryId"),
        lifecycle_status=lifecycle,
        renderer=renderer,
        profile=profile,
        source_artwork_path=_resolve_repo_path(_require_str(payload, "sourceArtworkPath")),
        source_artwork_version=_require_str(payload, "sourceArtworkVersion"),
        segmentation_output_dir=_resolve_repo_path(_require_str(payload, "segmentationOutputDir")),
        runtime_asset_dir=_resolve_repo_path(_require_str(payload, "runtimeAssetDir")),
        runtime_metadata_path=_resolve_repo_path(_require_str(payload, "runtimeMetadataPath")),
        runtime_regions_dart_path=_resolve_repo_path(_require_str(payload, "runtimeRegionsDartPath")),
        asset_base_path=_require_str(payload, "assetBasePath"),
        runtime_content_version=_require_str(payload, "runtimeContentVersion"),
        pipeline_version=_require_str(payload, "pipelineVersion"),
        expected_image_width=_optional_positive_int(payload, "expectedImageWidth"),
        expected_image_height=_optional_positive_int(payload, "expectedImageHeight"),
        expected_orientation=_optional_expected_orientation(payload),
        enforce_monochrome_line_art=bool(payload.get("enforceMonochromeLineArt", False)),
        build_config=build_config,
        dart_symbol_prefix=payload.get("dartSymbolPrefix") if isinstance(payload.get("dartSymbolPrefix"), str) else None,
        notes=[n for n in notes],
    )

    if not manifest.asset_base_path.startswith("assets/"):
        raise ValueError(
            f"assetBasePath must be an assets/ path, got '{manifest.asset_base_path}' in {path}"
        )

    return manifest
