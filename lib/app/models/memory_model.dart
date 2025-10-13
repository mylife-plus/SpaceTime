class MemoryModel {
  final int? id;
  final String description;
  final String imagePath;
  final String audioPath;
  final String date;
  final String time;
  final String location;
  final String? locationCountry;
  final String? locationCity;
  final String? locationName;
  final String? locationAddress;
  final String? locationFlag;
  final double? locationLatitude;
  final double? locationLongitude;
  final List<String> tags;
  final List<String> mentions;

  MemoryModel({
    this.id,
    required this.description,
    required this.imagePath,
    required this.audioPath,
    required this.date,
    required this.time,
    required this.location,
    this.locationCountry,
    this.locationCity,
    this.locationName,
    this.locationAddress,
    this.locationFlag,
    this.locationLatitude,
    this.locationLongitude,
    required this.tags,
    required this.mentions,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'description': description,
      'imagePath': imagePath,
      'audioPath': audioPath,
      'date': date,
      'time': time,
      'location': location,
      'location_country': locationCountry,
      'location_city': locationCity,
      'location_name': locationName,
      'location_address': locationAddress,
      'location_flag': locationFlag,
      'location_latitude': locationLatitude,
      'location_longitude': locationLongitude,
      'tags': tags.join(','),
      'mentions': mentions.join(','),
    };
  }

  factory MemoryModel.fromMap(Map<String, dynamic> map) {
    return MemoryModel(
      id: map['id'],
      description: map['description'] ?? '',
      imagePath: map['imagePath'] ?? '',
      audioPath: map['audioPath'] ?? '',
      date: map['date'] ?? '',
      time: map['time'] ?? '',
      location: map['location'] ?? '',
      locationCountry: map['location_country'],
      locationCity: map['location_city'],
      locationName: map['location_name'],
      locationAddress: map['location_address'],
      locationFlag: map['location_flag'],
      locationLatitude: map['location_latitude']?.toDouble(),
      locationLongitude: map['location_longitude']?.toDouble(),
      tags: map['tags'] != null ? map['tags'].split(',') : [],
      mentions: map['mentions'] != null ? map['mentions'].split(',') : [],
    );
  }
}
