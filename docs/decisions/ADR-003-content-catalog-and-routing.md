# ADR-003: Content Catalog And Routing Identity

## Status
Accepted.

## Context
CK-002.2 proved a single-page SVG coloring flow. CK-002.3 needs to scale this to multiple local pages while preserving the existing coloring architecture and keeping scope limited to local content.

## Decision
Use stable category IDs and stable page IDs as canonical navigation and repository identifiers, and keep repository ownership of catalog filtering and lookup.

## Scope
This decision applies to:
- Local category and page catalog modeling
- Home -> category -> page -> coloring route flow
- Renderer selection policy for local catalog pages

This decision intentionally excludes:
- User accounts
- Cloud synchronization
- Local persistence
- Premium/subscription logic
- AI-generated content

## Category Identity
Categories use stable IDs (for example: animals, dinosaurs, space, vehicles, unicorns, holidays) and separate display titles.

Minimum category data:
- categoryId
- title
- sortOrder
- optional emoji for current home UI

## Page Identity
Coloring pages use stable page IDs that are independent of titles and artwork labels.

Minimum page data:
- pageId (implemented as id)
- title
- categoryId
- svgAssetPath (implemented as assetPath)
- regions
- sortOrder
- rendererType

## Repository Ownership
`ColoringPageRepository` owns:
- category listing
- page listing
- category filtering
- page lookup by ID
- deterministic ordering
- basic local catalog validation

UI widgets do not perform source-of-truth filtering logic.

## Routing Flow
Canonical flow:

Home
  -> /category/:categoryId
  -> category page catalog
  -> /coloring/:pageId
  -> ColoringScreen

Category screen receives categoryId.
Coloring screen receives pageId.
No screen infers identity from display titles.

## Renderer Selection Policy
Renderer resolution is based on page metadata (renderer type), not page ID.

For CK-002.3:
- SVG pages resolve to `SvgColoringRenderer`
- No page-specific renderer classes are required for additional local SVG pages

## Local-Only Rationale For CK-002.3
Local content keeps the milestone focused on validating catalog architecture and route identity with minimal risk. Persistence and remote content are deferred to later milestones.

## Consequences
- Adding local pages is now mostly a content operation (model entry + SVG asset), not a renderer implementation task.
- Navigation and tests become deterministic through stable IDs.
- Stable page IDs now also serve as local persistence identity for coloring sessions.
- Future persistence and remote catalogs can layer on top of this without rewriting the core coloring pipeline.
