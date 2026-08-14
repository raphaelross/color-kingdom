# CK-002.6 Phase 2C Segmentation + Suitability Tooling

Offline deterministic prototype for converting polished raster line art into master region maps plus profile suitability diagnostics.

This tooling is isolated from the Flutter runtime and is intended for experimentation only.

## Purpose

Given a raster line-art image (for example Lovely Kitten master PNG), produce:

- normalized grayscale image
- binary barrier images (raw and repaired)
- exterior/background mask
- candidate region mask
- deterministic region map
- debug and labeled visualizations
- profile suitability classification for:
  - MASTER
  - CHILDREN_DETAILED
  - CHILDREN_SIMPLE
- per-profile QA visualizations and exclusion overlays
- machine-readable metadata JSON

## Setup

Windows example:

```powershell
Set-Location c:\Users\rross\color_kingdom\tools\segmentation
"C:\Users\rross\AppData\Local\Programs\Python\Python311\python.exe" -m venv .venv
.\.venv\Scripts\python.exe -m pip install -U pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## CLI

```powershell
.\.venv\Scripts\python.exe .\segment_coloring_page.py \
  --input ..\..\assets\source_artwork\animals\lovely_kitten_master.png \
  --output-dir .\output\lovely_kitten\baseline \
  --variant-name baseline \
  --threshold 185 \
  --morph-kernel 0 \
  --morph-iterations 1 \
  --dilate-iterations 0 \
  --min-region-area 250 \
  --min-region-percent 0.015 \
  --connectivity 8 \
  --children-detailed-min-area-percent 0.04 \
  --children-detailed-min-bounding-dimension-percent 1.2 \
  --children-detailed-min-tap-radius-percent 0.42 \
  --children-detailed-min-occupancy 0.24 \
  --children-simple-min-area-percent 0.11 \
  --children-simple-min-bounding-dimension-percent 2.1 \
  --children-simple-min-tap-radius-percent 0.8 \
  --children-simple-min-occupancy 0.28
```

Run `--help` for all options.

## Algorithm

1. Load RGB raster master.
2. Convert to grayscale.
3. Threshold to derive barrier pixels (dark outlines).
4. Optionally apply morphological close and light dilation for gap repair.
5. Flood fill from image borders through non-barrier pixels to mark exterior.
6. Connected-component label enclosed non-exterior pixels.
7. Sort components deterministically by centroid Y, then centroid X, then area descending, then component label.
8. Assign stable IDs `region-001`, `region-002`, and so on.
9. Classify each region as `ACCEPTED` or `FLAGGED_TOO_SMALL` based on area thresholds.
10. Compute suitability features for accepted master regions.
11. Apply deterministic profile rules for children-focused suitability.
12. Generate profile QA visualizations, warnings, and JSON report.

## Suitability Profiles

- `MASTER`: all accepted segmentation regions are included.
- `CHILDREN_DETAILED`: removes impractical tiny/sliver/tap-hostile regions while preserving visual richness.
- `CHILDREN_SIMPLE`: stricter filtering for larger/easier regions and lower coloring workload.

The profile layer does not modify region geometry. It only classifies inclusion per profile.

### Weighted Children Detailed (Phase 2C.1)

An experimental weighted model is available for `CHILDREN_DETAILED`:

1. Hard guardrails reject unusably tiny regions.
2. Remaining regions get normalized feature scores (0.0-1.0) using configurable percentiles.
3. Weighted contributions are averaged into a final suitability score (0.0-1.0).
4. Region is included when score is at or above a configurable threshold.

Output stores:

- `childrenDetailedWeighted.score`
- `childrenDetailedWeighted.contributions`
- `childrenDetailedWeighted.normalizedFeatures`
- `childrenDetailedWeighted.hardGuardrailPassed`
- weighted and baseline profile summaries for direct comparison

## Region Features

Each accepted master region records deterministic geometry features:

- area in pixels and percent
- bounding box width/height/area and percentages
- centroid
- minimum bounding dimension
- aspect ratio
- occupancy ratio (area / bounding-box area)
- perimeter
- compactness
- max inscribed radius (distance-transform approximation)
- tap target diameter/radius metrics

## Exclusion Reason Codes

- `AREA_TOO_SMALL`
- `BOUNDING_DIMENSION_TOO_SMALL`
- `TAP_TARGET_TOO_SMALL`
- `TOO_THIN`
- `LOW_OCCUPANCY`
- `FLAGGED_SEGMENTATION_ARTIFACT`
- `SCORE_BELOW_THRESHOLD`
- `GUARDRAIL_AREA_TOO_SMALL`
- `GUARDRAIL_BOUNDING_DIMENSION_TOO_SMALL`
- `GUARDRAIL_TAP_TARGET_TOO_SMALL`

## Output Artifacts

Each run writes these files in the chosen output directory:

- `normalized_grayscale.png`
- `binary_raw_barriers.png`
- `binary_repaired_barriers.png`
- `exterior_mask.png`
- `candidate_regions_mask.png`
- `region_map.png`
- `regions_debug.png`
- `regions_labeled.png`
- `regions_master_debug.png`
- `regions_children_detailed_debug.png`
- `regions_children_detailed_qa_fullcolor.png` (canonical Human QA full-color artifact)
- `regions_children_detailed_exclusions.png`
- `regions_children_detailed_baseline_debug.png`
- `regions_children_detailed_weighted_debug.png`
- `regions_children_detailed_baseline_exclusions.png`
- `regions_children_detailed_weighted_exclusions.png`
- `regions_children_detailed_comparison.png`
- `regions_children_simple_debug.png`
- `regions_children_simple_exclusions.png`
- `regions.json`

## Human QA Preview Policy

For every processed raster page/profile, produce a full-color profile preview where
every included region has a distinct deterministic color.

Canonical artifact name:

- `regions_children_detailed_qa_fullcolor.png`

This preview is used for Human QA to spot:

- intended regions that are not enclosed
- intended regions not detected
- accidental region merges
- tiny unwanted included regions
- partially enclosed regions

Always keep a separate exclusions visualization alongside the full-color QA file:

- `regions_children_detailed_exclusions.png`

## QA Regeneration Policy

If Human QA finds:

- a few isolated boundary defects: local/manual repair may be acceptable
- multiple repeated defects: consider regeneration of source artwork
- systematic widespread boundary failures: regenerate source artwork instead of manually repairing many regions

The objective is minimizing human editing effort. Automatic artwork regeneration is
out of scope for this tooling stage.

## Known Limitations

- Thresholding and morphology are global and may require per-art tuning.
- Semantic region naming is not attempted.
- Very intricate anti-aliased art can still produce tiny artifacts.
- Warnings are heuristic QA signals, not semantic correctness checks.
- Open-boundary diagnostics are exploratory heuristics and require human QA.

## Phase 2E.2 Halo-Safe Raster Contract

Runtime raster assets now separate logical identity from visual coverage:

- `region_map.png`: logical region ownership only
  - source of truth for hit testing and stable region identity
- `region_fill_map.png`: halo-safe visual fill ownership
  - bounded expansion around region boundaries for rendering coverage
- `line_art_foreground.png`: foreground line art drawn on top
  - exported as black with luminance-derived alpha for anti-aliased outlines

Pipeline contract:

1. Approved raster master artwork
2. Segmentation + profile classification
3. Human QA full-color verification
4. Logical region map export (`region_map.png`)
5. Halo-safe visual fill map export (`region_fill_map.png`)
6. Transparent/alpha foreground line export (`line_art_foreground.png`)
7. Runtime metadata export (`metadata_children_detailed.json`)

Visual fill expansion policy:

- Expansion is bounded (`0..N` px) and deterministic.
- Only non-logical pixels are eligible for claims.
- Logical ownership is never overwritten.
- Competing claims at equal distance are left unassigned (ambiguous).

Human QA artifacts generated for comparison:

- `halo_baseline_0px.png`
- `halo_expansion_1px.png`
- `halo_expansion_2px.png`
- `halo_expansion_3px.png`
- `halo_expansion_4px.png`
- `halo_expansion_difference.png`
