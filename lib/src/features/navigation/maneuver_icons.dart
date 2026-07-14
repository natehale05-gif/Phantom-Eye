import 'package:flutter/material.dart';

import '../../models/route_result.dart';

IconData maneuverIconFor(ManeuverType type) {
  switch (type) {
    case ManeuverType.depart:
      return Icons.trip_origin_rounded;
    case ManeuverType.arrive:
      return Icons.flag_rounded;
    case ManeuverType.straight:
      return Icons.straight_rounded;
    case ManeuverType.turnLeft:
      return Icons.turn_left_rounded;
    case ManeuverType.turnRight:
      return Icons.turn_right_rounded;
    case ManeuverType.turnSlightLeft:
      return Icons.turn_slight_left_rounded;
    case ManeuverType.turnSlightRight:
      return Icons.turn_slight_right_rounded;
    case ManeuverType.turnSharpLeft:
      return Icons.turn_sharp_left_rounded;
    case ManeuverType.turnSharpRight:
      return Icons.turn_sharp_right_rounded;
    case ManeuverType.uturn:
      return Icons.u_turn_left_rounded;
    case ManeuverType.merge:
      return Icons.merge_rounded;
    case ManeuverType.roundabout:
      return Icons.roundabout_left_rounded;
    case ManeuverType.fork:
      return Icons.call_split_rounded;
    case ManeuverType.keepLeft:
      return Icons.turn_slight_left_rounded;
    case ManeuverType.keepRight:
      return Icons.turn_slight_right_rounded;
  }
}
