import 'dart:convert';

class RouteFeedback {
  final String id;
  final String runId;
  final String? routeId;
  final String routeName;
  final String feedbackType;
  final DateTime createdAt;

  const RouteFeedback({
    required this.id,
    required this.runId,
    required this.routeId,
    required this.routeName,
    required this.feedbackType,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'runId': runId,
    'routeId': routeId,
    'routeName': routeName,
    'feedbackType': feedbackType,
    'createdAt': createdAt.toIso8601String(),
  };

  factory RouteFeedback.fromJson(Map<String, dynamic> json) {
    return RouteFeedback(
      id: json['id'] as String,
      runId: json['runId'] as String,
      routeId: json['routeId'] as String?,
      routeName: json['routeName'] as String? ?? '',
      feedbackType: json['feedbackType'] as String? ?? 'liked',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static List<RouteFeedback> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list
        .whereType<Map>()
        .map((item) => RouteFeedback.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  static String listToJson(List<RouteFeedback> items) {
    return jsonEncode(items.map((item) => item.toJson()).toList());
  }
}
