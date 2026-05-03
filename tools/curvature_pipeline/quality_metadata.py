from __future__ import annotations

import math
import re
from datetime import datetime, timezone
from typing import Any


FACILITY_PATTERN = re.compile(
    r"\b(kart|karting|drift|circuit|raceway|speedway|motorsport|autocross|pit\s?lane|paddock|test\s?track|trackday)\b",
    re.IGNORECASE,
)
BRIDGE_PATTERN = re.compile(r"\b(pont|bridge|viaduct|causeway)\b", re.IGNORECASE)
CONNECTOR_PATTERN = re.compile(
    r"\b(sortie|exit|ramp|bretelle|interchange|junction|connector)\b",
    re.IGNORECASE,
)
MAJOR_ROAD_PATTERN = re.compile(r"\b(boulevard|autoroute|highway)\b", re.IGNORECASE)
NUMERIC_NAME_PATTERN = re.compile(r"^[\d\-\s_]+$")


def normalize_route_name(name: str) -> str:
    return re.sub(r"\s+", " ", (name or "").strip())


def has_facility_like_name(name: str) -> bool:
    normalized = normalize_route_name(name)
    return bool(normalized and FACILITY_PATTERN.search(normalized))


def has_numeric_only_name(name: str) -> bool:
    normalized = normalize_route_name(name)
    return normalized == "" or (len(normalized) >= 5 and bool(NUMERIC_NAME_PATTERN.fullmatch(normalized)))


def is_bridge_like_route_name(name: str) -> bool:
    normalized = normalize_route_name(name)
    return bool(normalized and BRIDGE_PATTERN.search(normalized))


def is_connector_like_route_name(name: str) -> bool:
    normalized = normalize_route_name(name)
    return bool(normalized and CONNECTOR_PATTERN.search(normalized))


def is_major_road_like_route_name(name: str) -> bool:
    normalized = normalize_route_name(name)
    return bool(
        normalized
        and (
            MAJOR_ROAD_PATTERN.search(normalized)
            or BRIDGE_PATTERN.search(normalized)
            or CONNECTOR_PATTERN.search(normalized)
        )
    )


def route_flow_score(route: dict[str, Any]) -> float:
    raw = float(route.get("flow_score", 0.0) or 0.0)
    if raw > 0:
        return raw
    weighted_stops = int(route.get("stop_sign_count", 0) or 0) + (int(route.get("traffic_signal_count", 0) or 0) * 1.5)
    distance_km = max(float(route.get("distance_km", 0.0) or 0.0), 1.0)
    density = float(route.get("stop_control_density", 0.0) or 0.0)
    if density <= 0:
        density = weighted_stops / distance_km
    continuity_boost = 0.08 if float(route.get("max_continuous_km", 0.0) or 0.0) >= 1.5 else 0.0
    return max(0.15, min(1.0, 1.0 - density * 0.35 + continuity_boost))


def recommendation_score(route: dict[str, Any]) -> float:
    raw = float(route.get("route_rank_score", 0.0) or 0.0)
    if raw > 0:
        return raw
    fun = float(route.get("fun_score", 0.0) or 0.0)
    flow = route_flow_score(route)
    penalty = float(route.get("driveability_penalty", 1.0) or 1.0)
    residential_penalty = float(route.get("residential_penalty", 1.0) or 1.0)
    distance_km = float(route.get("distance_km", 0.0) or 0.0)
    distance_from_user = float(route.get("distance_from_user_km", 0.0) or route.get("distance_from_user", 0.0) or 0.0)
    stop_sign_count = int(route.get("stop_sign_count", 0) or 0)
    stop_density = float(route.get("stop_control_density", 0.0) or 0.0)
    max_cont = float(route.get("max_continuous_km", 0.0) or 0.0)
    context = 1.0
    if distance_km < 4:
        context *= 0.05
    elif distance_km < 8:
        context *= 0.82
    if distance_from_user > 15:
        if distance_from_user >= 80:
            context *= 0.45
        else:
            context *= max(0.45, 1.0 - ((distance_from_user - 15) / 65) * 0.55)
    if stop_sign_count >= 5 and distance_km < 12:
        context *= 0.15
    if stop_density >= 0.65 and max_cont < 1.2:
        context *= 0.2
    return fun * flow * penalty * residential_penalty * max(0.05, context)


def recommendation_tier(route: dict[str, Any]) -> str:
    if is_hard_rejected_recommendation(route):
        return "reject"
    if bool(route.get("is_bridge_like")) or bool(route.get("is_connector_like")):
        return "maybe"
    if bool(route.get("is_major_road_like")):
        return "maybe"
    if float(route.get("residential_penalty", 1.0) or 1.0) < 0.55:
        return "maybe"
    if route_flow_score(route) < 0.45:
        return "maybe"
    if recommendation_score(route) >= max(float(route.get("winding_score", 0.0) or 0.0) * 0.6, 3.0):
        return "keep"
    return "maybe"


def is_hard_rejected_recommendation(route: dict[str, Any]) -> bool:
    return bool(
        route.get("is_facility_like")
        or route.get("is_connector_like")
        or float(route.get("distance_km", 0.0) or 0.0) < 4.0
        or (has_numeric_only_name(str(route.get("name", ""))) and float(route.get("distance_km", 0.0) or 0.0) < 8.0)
        or (int(route.get("stop_sign_count", 0) or 0) >= 5 and float(route.get("distance_km", 0.0) or 0.0) < 12.0)
        or (
            float(route.get("stop_control_density", 0.0) or 0.0) >= 0.65
            and float(route.get("max_continuous_km", 0.0) or 0.0) < 1.2
        )
        or (
            float(route.get("residential_penalty", 1.0) or 1.0) <= 0.3
            and float(route.get("max_continuous_km", 0.0) or 0.0) < 1.2
        )
    )


def route_reject_reason(route: dict[str, Any]) -> str | None:
    name = str(route.get("name", ""))
    distance_km = float(route.get("distance_km", 0.0) or 0.0)
    if bool(route.get("is_facility_like")) or has_facility_like_name(name):
        return "시설/트랙 성격이 강해 추천 대상에서 제외"
    if bool(route.get("is_connector_like")) or is_connector_like_route_name(name):
        return "연결도로 성격이 강해 추천 대상에서 제외"
    if bool(route.get("is_bridge_like")) or is_bridge_like_route_name(name):
        return "브리지 중심 구간이라 추천 우선순위에서 제외"
    if distance_km < 4.0:
        return "너무 짧은 세그먼트라 추천 대상에서 제외"
    if has_numeric_only_name(name) and distance_km < 8.0:
        return "설명력이 낮은 짧은 숫자형 구간이라 제외"
    if int(route.get("stop_sign_count", 0) or 0) >= 5 and distance_km < 12.0:
        return "짧은 거리 대비 stop sign가 많아 흐름이 끊김"
    if float(route.get("stop_control_density", 0.0) or 0.0) >= 0.65 and float(route.get("max_continuous_km", 0.0) or 0.0) < 1.2:
        return "정지 제어 밀도가 높고 연속 흐름이 짧음"
    if float(route.get("residential_penalty", 1.0) or 1.0) <= 0.3 and float(route.get("max_continuous_km", 0.0) or 0.0) < 1.2:
        return "주거지와 로컬도로 비중이 높아 드라이브 흐름이 약함"
    return None


def derive_route_reason_tags(route: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    winding_score = float(route.get("winding_score", 0.0) or 0.0)
    distance_km = float(route.get("distance_km", 0.0) or 0.0)
    tight_curve_km = float(route.get("tight_curve_km", 0.0) or 0.0)
    medium_curve_km = float(route.get("medium_curve_km", 0.0) or 0.0)
    max_cont = float(route.get("max_continuous_km", 0.0) or 0.0)
    elevation = float(route.get("elevation_delta", 0.0) or 0.0)
    is_loop = bool(route.get("is_loop"))
    density = ((tight_curve_km + medium_curve_km) / distance_km) if distance_km > 0 else 0.0
    total = tight_curve_km + medium_curve_km
    tight_ratio = (tight_curve_km / total) if total > 0 else 0.0
    curve_style = "MIXED"
    if total >= 0.5:
        if tight_ratio > 0.55:
            curve_style = "SWITCHBACK"
        elif tight_ratio < 0.25:
            curve_style = "SWEEPER"
    if winding_score >= 6.0:
        reasons.append("high_score")
    if density >= 0.34:
        reasons.append("dense_corners")
    if curve_style == "SWITCHBACK" and tight_curve_km >= 1.4:
        reasons.append("switchbacks")
    if curve_style == "SWEEPER" and medium_curve_km >= 2.2:
        reasons.append("sweepers")
    if max_cont >= 1.25 and density >= 0.24:
        reasons.append("continuous_flow")
    if elevation >= 45 and density >= 0.18:
        reasons.append("elevation")
    if is_loop and distance_km >= 12 and density >= 0.24:
        reasons.append("loop")
    return reasons


def primary_route_reason(route: dict[str, Any]) -> str | None:
    reasons = derive_route_reason_tags(route)
    if "switchbacks" in reasons:
        return "타이트한 스위치백이 연속되는 기술적인 드라이브 루트예요."
    if "sweepers" in reasons:
        return "장쾌한 스위퍼 코너가 리듬감 있게 이어지는 루트예요."
    if "dense_corners" in reasons:
        return "코너가 쉼 없이 이어지는 밀도 높은 와인딩 코스예요."
    if "continuous_flow" in reasons:
        return "긴 호흡으로 몰입하기 좋은 연속 코너 루트예요."
    if "elevation" in reasons:
        return "오르막내리막이 살아있는 드라이브 코스예요."
    if "loop" in reasons:
        return "출발지로 자연스럽게 돌아오는 흐름 좋은 루프예요."
    if "high_score" in reasons:
        return "와인딩 점수가 높은 검증된 드라이빙 코스예요."
    return None


def route_character(route: dict[str, Any]) -> str:
    if route.get("route_character"):
        return str(route["route_character"])
    tight_curve_km = float(route.get("tight_curve_km", 0.0) or 0.0)
    medium_curve_km = float(route.get("medium_curve_km", 0.0) or 0.0)
    curvy_distance = tight_curve_km + medium_curve_km
    tight_ratio = (tight_curve_km / curvy_distance) if curvy_distance > 0 else 0.0
    medium_ratio = (medium_curve_km / curvy_distance) if curvy_distance > 0 else 0.0
    rhythm = float(route.get("max_continuous_km", 0.0) or 0.0) >= 1.35 and route_flow_score(route) >= 0.8
    if float(route.get("elevation_delta", 0.0) or 0.0) >= 90 and float(route.get("max_continuous_km", 0.0) or 0.0) >= 1.2:
        return "hill_climb"
    if tight_ratio >= 0.62 and tight_curve_km >= 1.6:
        return "tight_technical"
    if medium_ratio >= 0.68 and medium_curve_km >= 2.2 and float(route.get("max_continuous_km", 0.0) or 0.0) >= 1.4:
        return "fast_sweeper"
    if rhythm and curvy_distance >= 2.0:
        return "rhythmic_flow"
    return "mixed_touring"


def route_primary_reason(route: dict[str, Any]) -> str | None:
    character = route_character(route)
    road_names = [str(name) for name in route.get("road_names", []) if str(name).strip()]
    surface_summary = str(route.get("surface_summary", "") or "").strip()
    nearby_pois = route.get("nearby_pois", []) or []
    poi_names = [
        str(poi.get("name"))
        for poi in nearby_pois
        if isinstance(poi, dict) and str(poi.get("name", "")).strip()
    ]
    route_subject = road_names[0] if road_names else str(route.get("name", "") or "").strip()
    route_prefix = f"{route_subject} 기준으로 " if route_subject else ""
    if poi_names and character in {"fast_sweeper", "rhythmic_flow", "mixed_touring"}:
        return f"{route_prefix}{poi_names[0]} 주변 맥락과 코너 흐름을 같이 읽는 루트예요."
    if surface_summary and surface_summary not in {"asphalt", "paved"}:
        return f"{route_prefix}노면 정보({surface_summary})를 확인하면서 접근해야 하는 루트예요."
    if character == "tight_technical":
        return f"{route_prefix}타이트한 코너 비중이 높아 라인을 세밀하게 읽는 루트예요."
    if character == "fast_sweeper":
        return f"{route_prefix}길게 이어지는 스위퍼 코너가 리듬감 있게 이어지는 루트예요."
    if character == "rhythmic_flow":
        return f"{route_prefix}중간 정지가 적고 코너 리듬이 잘 이어지는 루트예요."
    if character == "hill_climb":
        return f"{route_prefix}고도 변화가 살아 있어 시야 전환을 같이 읽는 루트예요."
    return primary_route_reason(route) or "커브와 흐름의 균형이 괜찮은 투어링 성향 루트예요."


def route_caution_note(route: dict[str, Any]) -> str | None:
    stop_sign_count = int(route.get("stop_sign_count", 0) or 0)
    traffic_signal_count = int(route.get("traffic_signal_count", 0) or 0)
    residential_ratio = float(route.get("residential_ratio", 0.0) or 0.0)
    speed_limit_summary = str(route.get("speed_limit_summary", "") or "").strip()
    surface_summary = str(route.get("surface_summary", "") or "").strip()
    if surface_summary and surface_summary not in {"asphalt", "paved"}:
        return f"노면 정보가 {surface_summary}로 잡혀 실제 포장 상태를 먼저 확인"
    if stop_sign_count > 0 or traffic_signal_count > 0:
        parts: list[str] = []
        if stop_sign_count > 0:
            parts.append(f"stop sign {stop_sign_count}개")
        if traffic_signal_count > 0:
            parts.append(f"signal {traffic_signal_count}개")
        return f"중간 {', '.join(parts)}가 있어 흐름이 약간 끊길 수 있음"
    if residential_ratio >= 0.35:
        return "주거지 성격이 일부 섞여 있어 흐름이 약간 끊길 수 있음"
    name = str(route.get("name", ""))
    if bool(route.get("is_major_road_like")) or is_major_road_like_route_name(name):
        return "일부 구간은 간선도로 성격이 섞일 수 있음"
    if bool(route.get("is_bridge_like")) or is_bridge_like_route_name(name):
        return "브리지 연결 구간이 포함될 수 있음"
    if speed_limit_summary:
        return f"제한속도 표기가 {speed_limit_summary}로 섞여 현장 표지를 우선 확인"
    return None


def apply_quality_metadata(
    route: dict[str, Any],
    *,
    version: str = "quality-v1",
) -> dict[str, Any]:
    updated = dict(route)
    updated["quality_label"] = recommendation_tier(updated)
    updated["quality_reject_reason"] = route_reject_reason(updated)
    updated["route_character"] = route_character(updated)
    updated["primary_reason"] = route_primary_reason(updated)
    updated["caution_note"] = route_caution_note(updated)
    updated["quality_version"] = version
    updated["quality_enriched_at"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    return updated
