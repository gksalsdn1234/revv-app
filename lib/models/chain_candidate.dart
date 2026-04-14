import 'revv_route.dart';

enum ChainEntryMode { forward, reverse }

class ChainCandidate {
  final RevvRoute route;
  final ChainEntryMode entryMode;
  final double gapKm;
  final double headingDelta;
  final double connectorQualityScore;
  final double mergedFunScore;
  final double mergedFlowScore;
  final double mergedRankScore;
  final String? rejectReason;

  const ChainCandidate({
    required this.route,
    required this.entryMode,
    required this.gapKm,
    required this.headingDelta,
    required this.connectorQualityScore,
    required this.mergedFunScore,
    required this.mergedFlowScore,
    required this.mergedRankScore,
    this.rejectReason,
  });

  bool get isRejected => rejectReason != null;

  List<LatLng> orientedNodes() =>
      entryMode == ChainEntryMode.forward ? route.nodes : route.nodes.reversed.toList();
}
