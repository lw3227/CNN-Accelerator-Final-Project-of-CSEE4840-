"""Heuristics for choosing between preprocessing variants."""

from __future__ import annotations

from typing import Any, Iterable, Tuple


def choose_best_variant(scored: Iterable[Tuple[Any, Any]]) -> Tuple[Any, Any]:
    """Choose a preprocess branch using a conservative disagreement policy.

    The background-removed crop branch can occasionally become overconfident on
    the wrong class. We therefore keep the old "pick by margin" behavior when
    both branches agree, but when they disagree we only trust `crop` if it is
    *obviously* stronger while the `plain` branch looks weak.
    """

    scored = list(scored)
    if not scored:
        raise ValueError("scored variants cannot be empty")

    if len(scored) == 1:
        return scored[0]

    ordered = sorted(
        scored,
        key=lambda item: (item[1].margin, item[1].top_score),
        reverse=True,
    )
    best_variant, best_result = ordered[0]
    second_variant, second_result = ordered[1]

    if best_result.predicted_class == second_result.predicted_class:
        return best_variant, best_result

    plain_pair = next(((v, r) for v, r in scored if getattr(v, "mode", "") == "plain"), None)
    crop_pair = next(((v, r) for v, r in scored if getattr(v, "mode", "") == "crop"), None)
    if plain_pair is None or crop_pair is None:
        return best_variant, best_result

    plain_variant, plain_result = plain_pair
    crop_variant, crop_result = crop_pair

    # If crop saturates near the int8 ceiling while plain is weak, trust crop.
    if crop_result.top_score >= 120.0 and plain_result.top_score < 60.0:
        return crop_variant, crop_result

    # If plain is already reasonably confident, prefer its more literal view.
    if plain_result.margin >= 60.0:
        return plain_variant, plain_result

    # Otherwise fall back to the stronger-scoring branch.
    return best_variant, best_result
