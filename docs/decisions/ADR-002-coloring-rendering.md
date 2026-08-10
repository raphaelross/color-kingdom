# ADR-002: Coloring Rendering Strategy

## Status
Accepted and implemented for the current baseline, CK-002.1 foundation, and CK-002.2 Happy Cat SVG renderer.

## Context
The coloring engine must feel immediate and reliable for young children, while also supporting a growing content library and future AI-generated pages.

## Decision
Use named regions for coloring pages, keep rendering behind a renderer contract, and implement SVG interaction with public parsing/geometry APIs.

## Current Baseline
The implemented engine stores and updates color state by region ID.
The Happy Cat page now renders from an SVG asset with `data-role` metadata.
The controller uses action-based history and an explicit loading/ready/error lifecycle.
The page source is abstracted by a repository interface.
The canvas validates renderer/page region mismatches and fails gracefully.
The SVG renderer parses once, caches by page/asset key, renders by z-order, and performs region hit testing in SVG coordinates.
Renderer selection is metadata-driven (renderer type), avoiding page-id specific renderer mappings for SVG pages.

## Why Named Regions
- Tap-to-fill is simpler than pixel-based flood fill.
- Region-based coloring is easier to test.
- State changes are straightforward for undo and redo.
- The approach is resolution independent when backed by SVG.
- It scales well to tablets and future content generation.

## Why The Current Placeholder Approach Exists
- It validates the interaction model now.
- It allows the app to progress before a production SVG pipeline is built.
- It keeps the current baseline offline-friendly and easy to debug.

## Planned Transition
Continue expanding from the first SVG renderer to a scalable multi-page SVG pipeline behind the existing renderer boundary.

Planned behavior:
- SVG assets define independently colorable regions.
- Region taps map to stable identifiers.
- The same Riverpod state model manages fills and action history.
- Future exports and recoloring remain simple.
- Additional SVG pages should not require new renderer classes.

## Dependency Choice
- `xml` is used for SVG XML parsing.
- `path_drawing` is used to parse SVG path geometry into Flutter paths.
- This avoids reliance on private or undocumented APIs and keeps the interaction layer inside the renderer boundary.

## Consequences
- The current engine remains a prototype baseline, not the final rendering system.
- Future content work should align with the SVG + named-region model.
- Any rendering change should be documented before it is implemented.
