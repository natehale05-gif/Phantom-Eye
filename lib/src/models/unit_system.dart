enum UnitSystem { imperial, metric }

extension UnitSystemX on UnitSystem {
  bool get isImperial => this == UnitSystem.imperial;
}
