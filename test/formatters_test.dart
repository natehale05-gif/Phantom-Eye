import 'package:flutter_test/flutter_test.dart';
import 'package:phantom_eye/src/core/utils/formatters.dart';
import 'package:phantom_eye/src/models/unit_system.dart';

void main() {
  test('distance formats feet vs miles crossover', () {
    expect(Formatters.distance(100, UnitSystem.imperial), '328 ft');
    expect(Formatters.distance(2000, UnitSystem.imperial), contains('mi'));
  });

  test('distance formats meters vs km crossover', () {
    expect(Formatters.distance(500, UnitSystem.metric), '500 m');
    expect(Formatters.distance(5000, UnitSystem.metric), '5.0 km');
  });

  test('duration formats hours and minutes', () {
    expect(Formatters.duration(const Duration(minutes: 45)), '45 min');
    expect(Formatters.duration(const Duration(hours: 1, minutes: 30)), '1 hr 30 min');
    expect(Formatters.duration(const Duration(hours: 2)), '2 hr');
  });

  test('compassDirection maps bearing buckets', () {
    expect(Formatters.compassDirection(0), 'N');
    expect(Formatters.compassDirection(90), 'E');
    expect(Formatters.compassDirection(180), 'S');
    expect(Formatters.compassDirection(270), 'W');
  });
}
