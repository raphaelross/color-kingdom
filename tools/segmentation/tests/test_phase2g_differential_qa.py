from __future__ import annotations

from phase2g_differential_qa import analyze_spatial_differential


def _mask(width: int, height: int, points: list[tuple[int, int]]) -> list[bool]:
    out = [False] * (width * height)
    for x, y in points:
        out[y * width + x] = True
    return out


def test_spatial_analysis_marks_represented_when_overlapping() -> None:
    width = 4
    height = 4
    production_masks = {
        "prod-a": _mask(width, height, [(1, 1), (2, 1), (1, 2)]),
    }
    candidate_masks = {
        "cand-a": _mask(width, height, [(1, 1), (2, 1)]),
    }

    result = analyze_spatial_differential(production_masks, candidate_masks, width, height)
    cand = result["cand-a"]

    assert cand["representedByProductionSpatially"] is True
    assert cand["nearestProductionRegion"] == "prod-a"
    assert cand["nearestProductionOverlapPixels"] == 2


def test_spatial_analysis_marks_unrepresented_when_disjoint() -> None:
    width = 4
    height = 4
    production_masks = {
        "prod-a": _mask(width, height, [(0, 0)]),
    }
    candidate_masks = {
        "cand-a": _mask(width, height, [(3, 3)]),
    }

    result = analyze_spatial_differential(production_masks, candidate_masks, width, height)
    cand = result["cand-a"]

    assert cand["representedByProductionSpatially"] is False
    assert cand["nearestProductionRegion"] is None
    assert cand["nearestProductionOverlapPixels"] == 0
