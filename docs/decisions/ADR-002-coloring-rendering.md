# ADR-002: Coloring Rendering Strategy

## Status
Accepted for the current baseline and CK-002.1 foundation, with a planned future migration path.

## Context
The coloring engine must feel immediate and reliable for young children, while also supporting a growing content library and future AI-generated pages.

## Decision
Use named regions for coloring pages, keep rendering behind a renderer contract, and treat the current sample-page renderer as the baseline until the SVG asset pipeline is introduced.

## Current Baseline
The implemented engine stores and updates color state by region ID.
The current Happy Cat page is a deliberately simple test page that demonstrates the interaction model without requiring a full parser.
The controller now uses action-based history and an explicit loading/ready/error lifecycle.
The page source is abstracted by a repository interface.
The canvas validates renderer/page region mismatches and fails gracefully.

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
Move from the placeholder sample renderer to a true SVG-based named-region pipeline behind the existing renderer boundary.

Planned behavior:
- SVG assets define independently colorable regions.
- Region taps map to stable identifiers.
- The same Riverpod state model continues to manage fills and action history.
- Future exports and recoloring remain simple.

## Consequences
- The current engine remains a prototype baseline, not the final rendering system.
- Future content work should align with the SVG + named-region model.
- Any rendering change should be documented before it is implemented.
