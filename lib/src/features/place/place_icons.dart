import 'package:flutter/material.dart';

import '../../models/place.dart';

IconData placeIconFor(PlaceCategory category) {
  switch (category) {
    case PlaceCategory.address:
      return Icons.home_rounded;
    case PlaceCategory.business:
      return Icons.storefront_rounded;
    case PlaceCategory.food:
      return Icons.restaurant_rounded;
    case PlaceCategory.gas:
      return Icons.local_gas_station_rounded;
    case PlaceCategory.parking:
      return Icons.local_parking_rounded;
    case PlaceCategory.lodging:
      return Icons.hotel_rounded;
    case PlaceCategory.trailhead:
      return Icons.hiking_rounded;
    case PlaceCategory.summit:
      return Icons.landscape_rounded;
    case PlaceCategory.campground:
      return Icons.forest_rounded;
    case PlaceCategory.water:
      return Icons.water_drop_rounded;
    case PlaceCategory.other:
      return Icons.place_rounded;
  }
}
