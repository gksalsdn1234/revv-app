import 'package:flutter/material.dart';
import 'revv_route.dart';

class NavStep {
  final String koreanInstruction;
  final String type;       // depart, turn, arrive, merge, fork, roundabout ...
  final String? modifier;  // left, right, slight left, slight right, sharp left, sharp right, straight, uturn
  final String streetName;
  final LatLng location;   // maneuver 발생 지점

  const NavStep({
    required this.koreanInstruction,
    required this.type,
    this.modifier,
    required this.streetName,
    required this.location,
  });

  /// Mapbox steps JSON → NavStep
  factory NavStep.fromJson(Map<String, dynamic> json) {
    final maneuver = json['maneuver'] as Map<String, dynamic>;
    final loc = maneuver['location'] as List;
    final type = (maneuver['type'] as String?) ?? 'turn';
    final modifier = maneuver['modifier'] as String?;
    final streetName = (json['name'] as String?) ?? '';

    return NavStep(
      koreanInstruction: _buildKorean(type, modifier, streetName),
      type: type,
      modifier: modifier,
      streetName: streetName,
      location: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
    );
  }

  static String _buildKorean(String type, String? modifier, String streetName) {
    final dirStr = switch (modifier) {
      'left'        => '좌회전',
      'right'       => '우회전',
      'slight left' => '좌측방향',
      'slight right'=> '우측방향',
      'sharp left'  => '급좌회전',
      'sharp right' => '급우회전',
      'uturn'       => 'U턴',
      _             => '직진',
    };

    return switch (type) {
      'depart'                          => '안내를 시작합니다',
      'arrive'                          => '목적지에 도착했습니다',
      'turn' || 'end of road'           => streetName.isNotEmpty ? '$dirStr, $streetName' : dirStr,
      'merge'                           => '$dirStr으로 합류',
      'roundabout' || 'rotary'          => '로터리 진입 후 $dirStr',
      'exit roundabout' || 'exit rotary'=> '로터리 진출',
      'fork'                            => '$dirStr 방향',
      'new name'                        => streetName.isNotEmpty ? '$streetName 진입' : '계속 직진',
      _                                 => streetName.isNotEmpty ? '$dirStr, $streetName' : dirStr,
    };
  }

  IconData get icon {
    if (type == 'depart') return Icons.directions_car;
    if (type == 'arrive') return Icons.flag;
    if (type == 'roundabout' || type == 'rotary') return Icons.roundabout_right;
    return switch (modifier) {
      'left'         => Icons.turn_left,
      'right'        => Icons.turn_right,
      'slight left'  => Icons.turn_slight_left,
      'slight right' => Icons.turn_slight_right,
      'sharp left'   => Icons.turn_sharp_left,
      'sharp right'  => Icons.turn_sharp_right,
      'uturn'        => Icons.u_turn_left,
      _              => Icons.straight,
    };
  }
}
