import 'package:flutter/material.dart';

import '../models/composite_route.dart';
import '../models/revv_route.dart';
import '../services/route_service.dart';
import '../theme/colors.dart';
import 'ux_contracts.dart';

class RideContextSummary {
  final String label;
  final String detail;
  final Color color;

  const RideContextSummary({
    required this.label,
    required this.detail,
    required this.color,
  });
}

String describeRideProgressDetail({
  required bool isOffRoute,
  required bool wasOffRoute,
  required double minDistKm,
  required double progress,
}) {
  if (isOffRoute) {
    if (minDistKm > 1.0) return '루트와 거리가 꽤 벌어져 복귀 경로를 다시 계산하는 중';
    if (minDistKm > 0.5) return '루트 바깥으로 벗어나 복귀 라인을 확인하는 중';
    return '루트에서 살짝 벗어나 다시 합류하는 중';
  }
  if (wasOffRoute) return '루트로 복귀했어요. 흐름을 다시 이어가면 됩니다';
  if (progress >= 0.95) return '마지막 구간을 주행 중';
  if (progress >= 0.75) return '후반 구간에 들어왔어요';
  if (progress >= 0.35) return '본 루트 흐름을 안정적으로 타는 중';
  return '본 루트에 진입했어요';
}

String describeDriveStartSummary({
  required SprintStartMode startMode,
  required double routeGapKm,
  required double routeProgressPct,
}) {
  switch (startMode) {
    case SprintStartMode.joinFromCurrent:
      return routeGapKm > 0.4
          ? '현재 위치 기준으로 흐름에 합류하는 중'
          : '현재 위치에서 루트 흐름을 이어가는 중';
    case SprintStartMode.guideToStart:
      return routeProgressPct < 0.15
          ? '시작점 진입 후 초반 리듬을 만드는 중'
          : '시작점 안내 후 본 루트에 올라탔어요';
    case SprintStartMode.auto:
      return routeProgressPct < 0.15
          ? '자동 진입 후 루트 감각을 맞추는 중'
          : '자동 시작 후 본 루트 흐름을 유지하는 중';
  }
}

RideContextSummary? buildRideContextSummary({
  required RevvRoute? route,
  required CompositeRoute? composite,
  required SprintStartMode startMode,
  required double routeProgressPct,
  required double routeGapKm,
  required bool isOffRoute,
  required bool onRoute,
}) {
  if (isOffRoute && route != null) {
    final isKeep = route.qualityLabel == 'keep';
    final isMaybe = route.qualityLabel == 'maybe';
    final gapText = describeRouteGap(routeGapKm);
    return RideContextSummary(
      label: '복귀 우선 안내',
      detail: composite != null
          ? gapText.isEmpty
                ? '일반 재탐색을 하면 체인 흐름이 끊길 수 있어요. 현재 라인으로 다시 붙는 편이 좋습니다.'
                : '$gapText 상태예요. 일반 재탐색보다 현재 체인 라인 복귀를 먼저 권장합니다.'
          : isKeep
          ? '지금 루트 품질이 좋아서 새 길로 갈아타기보다 원래 라인 복귀가 더 유리해요.'
          : isMaybe
          ? '지금 루트 흐름을 최대한 살리려면 우선 복귀를 시도해보는 편이 좋아요.'
          : '재탐색을 하면 루트 성격이 조금 달라질 수 있어요.',
      color: const Color(0xFFF59E0B),
    );
  }

  if (composite == null) return null;

  if (!onRoute || routeProgressPct <= 0.02) {
    return RideContextSummary(
      label: startMode == SprintStartMode.joinFromCurrent
          ? '체인 합류 준비'
          : '체인 시작 준비',
      detail: startMode == SprintStartMode.joinFromCurrent
          ? '복합 루트 흐름에 현재 위치 기준으로 합류하는 중이에요.'
          : '첫 메인 구간으로 안정적으로 들어가기 위한 시작 안내를 진행 중이에요.',
      color: AppColors.cyan,
    );
  }

  final traveledKm = routeProgressPct * composite.totalDistanceKm;
  double cursor = composite.baseRoute.distanceKm;
  if (traveledKm <= cursor) {
    return RideContextSummary(
      label: '체인 1/${composite.chainedSegments.length + 1}',
      detail: '첫 메인 구간을 주행 중이에요. 이후 연결 구간이 자연스럽게 이어집니다.',
      color: AppColors.cyan,
    );
  }

  for (int i = 0; i < composite.connectorLegs.length; i++) {
    final connector = composite.connectorLegs[i];
    final connectorEnd = cursor + connector.distanceKm;
    if (traveledKm <= connectorEnd) {
      return RideContextSummary(
        label: '연결 구간',
        detail: '${i + 1}번째 연결 구간이에요. 다음 메인 구간으로 매끄럽게 이어지는 중입니다.',
        color: const Color(0xFFF59E0B),
      );
    }
    cursor = connectorEnd;
    final segment = composite.chainedSegments[i];
    final segmentEnd = cursor + segment.distanceKm;
    if (traveledKm <= segmentEnd) {
      return RideContextSummary(
        label: '체인 ${i + 2}/${composite.chainedSegments.length + 1}',
        detail: '${segment.name} 메인 구간을 주행 중이에요.',
        color: AppColors.cyan,
      );
    }
    cursor = segmentEnd;
  }

  return const RideContextSummary(
    label: '체인 후반',
    detail: '복합 루트 후반 흐름을 이어가는 중이에요.',
    color: AppColors.cyan,
  );
}
