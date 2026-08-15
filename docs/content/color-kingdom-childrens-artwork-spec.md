# Color Kingdom Children's Artwork Specification

## Purpose

This specification defines how to create child-friendly raster line art that can pass the Color Kingdom automatic segmentation pipeline through strong artwork selection and regeneration discipline rather than routine manual repair.

## Intended Audience

- content designers
- image-generation operators
- human QA reviewers

## Target Child Experience

- intended age range: approximately 4-8
- visually clear, friendly, and approachable
- simple coloring-book style with practical tap targets
- moderate detail without overwhelming micro-regions

## Complexity Target

- prefer materially simpler pages than high-detail benchmark content
- treat region counts as qualitative signals, not pass/fail quotas
- do not force counts through destructive filtering
- control complexity primarily during artwork generation, not by discarding valid MASTER regions later

## Scalable Production Workflow

`CONCEPT`

`AI GENERATES MULTIPLE CANDIDATES`

`HUMAN ARTISTIC/TOPOLOGY QA`

`AI REGENERATE/REFINE`

`REPEAT AS NEEDED`

`APPROVED RASTER MASTER`

`AUTOMATED SEGMENTATION`

`MASTER - PRESERVE VALID TOPOLOGY`

`CHILDREN_DETAILED - REMOVE ONLY CLEAR ARTIFACT/NOISE`

`FULL-COLOR QA ARTIFACTS`

`HUMAN SEGMENTATION/COVERAGE QA`

`APPROVE OR RETURN TO ARTWORK/PIPELINE`

`HALO-SAFE RUNTIME EXPORT`

`FLUTTER INTEGRATION`

`RUNTIME QA`

Human effort should focus on creative direction, visual review, approval, and exception handling rather than repetitive manual region drawing or pixel repair.

Artwork generation is the primary control point for child-friendly complexity. Classification should preserve legitimate interactivity.

## Required Design Principles

- one large central character or object
- clearly enclosed regions
- thick, continuous outlines
- simple secondary decorations
- clear visual hierarchy
- generous spacing between major areas
- practical touch target sizing for mobile and tablet use

## Avoid

- hundreds of tiny enclosed areas
- intricate adult-coloring-style patterns
- dense fragmented foliage or texture fields
- excessive internal micro-lines
- intentional outline gaps
- shading and grayscale washes
- gradients and cross-hatching
- sketchy or ambiguous/open contours

## Closed-Region Topology Requirements

- every intended coloring area must be fully enclosed
- no unintended line breaks in boundary loops
- no open boundaries in intended colorable shapes
- no overlapping ambiguous boundaries
- no near-touching boundary gaps that create flood-fill leaks

## Line-Art Format Requirements

- black line art on white background
- consistent outline weight
- anti-aliasing is acceptable
- no color fills
- no shading
- no gradients
- no semi-transparent decorative overlays

## Human QA Gate #1: Artistic + Topology QA (Mandatory)

Before segmentation, Human QA must confirm:

- professional Color Kingdom visual quality
- age-appropriate complexity
- strong central subject and clear visual hierarchy
- no obvious generation artifacts or malformed decorative objects
- no obvious unintended open contours or line breaks
- intended coloring regions appear enclosed
- no excessive micro-detail or adult-coloring density

Approved artwork enters segmentation unchanged.

## Human QA Gate #2: Segmentation + Coverage QA (Mandatory)

Before runtime integration, reviewers must inspect generated QA artifacts and confirm:

- obvious large and medium intended areas are colorable
- meaningful regions are retained in CHILDREN_DETAILED
- tiny/frustrating regions are reduced to acceptable levels
- no widespread open-boundary failures
- no severe merge/split errors that harm child usability
- overall page complexity is child-appropriate
- if a region looks like an intentional enclosed coloring space, it is generally colorable in `CHILDREN_DETAILED`

## Regeneration Policy

- default to AI regeneration or refinement when artwork quality or topology is weak
- repeated defects across many regions: prefer artwork regeneration
- systematic open-boundary problems: regenerate artwork
- excessive meaningful-region complexity: simplify/regenerate artwork, do not hide complexity via aggressive profile filtering
- manual repair is exceptional, not normal production policy
- do not choose manual repair by default merely because there are only one or two defects

Manual repair may be considered only when preserving that exact artwork is unusually important, repeated AI refinement has failed, and the fix is genuinely trivial.

Keep defect ownership explicit:

- visible open contour in source: artwork defect
- closed source contour missed by MASTER: segmentation defect
- MASTER region excluded by `CHILDREN_DETAILED`: classifier defect
- region present in QA but missing later: export/runtime defect

## Classifier Philosophy For Children Detailed

`CHILDREN_DETAILED` is preservation-oriented:

- include legitimate enclosed `MASTER` regions by default
- exclude only clear artifact/noise (microscopic specks, accidental debris, non-semantic slivers)
- treat tap target, occupancy, compactness, and aspect ratio as diagnostic metrics unless there is specific artifact evidence
- avoid disabling legitimate details merely because they are small

Zoom-aware policy:

- small at 1x does not mean unusable at zoomed-in levels
- small region does not imply invalid region
- runtime zoom allows intentional fine details to remain colorable

Profile distinction:

- `MASTER`: all accepted enclosed topology regions
- `CHILDREN_DETAILED`: `MASTER` minus clear artifacts/noise
- `CHILDREN_SIMPLE`: optional future stronger simplification profile

This policy also preserves compatibility with future adult-coloring content where legitimate small regions are expected.

## Reusable Generation Prompt Template

Use this template for AI-assisted artwork generation:

"Create a polished professional black-and-white coloring-book line art page for children ages 4-8. Subject: <SUBJECT>. Composition: one large central <SUBJECT> with simple child-friendly proportions and a few secondary decorative elements. Keep moderate complexity with fewer, larger enclosed coloring regions, clear visual hierarchy, and generous spacing. Use thick continuous black outlines on a clean white background. Every intended coloring area must be fully enclosed with no unintended line breaks or open contours. No shading, no grayscale, no gradients, no cross-hatching, and no color fills. Avoid dense micro-details, tiny dots, narrow slivers, and highly fragmented textures. Output as high-resolution raster PNG line art only."

## Human QA Checklist

- page feels simpler than high-detail benchmark content
- major body regions are large and clearly enclosed
- secondary decorations are readable and not fragmented
- no obvious leak paths from interior regions to exterior
- automatic segmentation preview is coherent without manual redrawing
- production should not require vectorization, manual SVG region authoring, manual stable IDs, or manual region drawing before baseline validation