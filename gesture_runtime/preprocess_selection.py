"""在多个预处理分支之间做选择的启发式规则。

Web UI 同时支持直接 resize 和前景裁剪。用户选择 auto 时，本模块决定最终哪一个
分支送到板子上。策略故意偏保守，因为视觉上更干净的 crop 有时也可能裁掉模型
训练时依赖的上下文。
"""

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
        # 如果两个视角预测同一类，就选择置信度更高的那个。
        return best_variant, best_result

    plain_pair = next(((v, r) for v, r in scored if getattr(v, "mode", "") == "plain"), None)
    crop_pair = next(((v, r) for v, r in scored if getattr(v, "mode", "") == "crop"), None)
    if plain_pair is None or crop_pair is None:
        # 将来如果加入新的预处理模式，就退回通用的分数排序逻辑。
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
