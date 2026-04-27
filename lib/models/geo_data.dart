class GeoData {
  final String country;
  final double? latitude;
  final double? longitude;

  const GeoData({
    required this.country,
    this.latitude,
    this.longitude,
  });

  factory GeoData.unknown() {
    return const GeoData(country: 'Unknown');
  }

  bool get hasCoordinates => latitude != null && longitude != null;
}
