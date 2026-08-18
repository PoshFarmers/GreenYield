class Crop {
  final String id;
  final String name;
  final String category; // 'vegetable' | 'fruit'

  const Crop({required this.id, required this.name, required this.category});

  factory Crop.fromMap(Map<String, dynamic> map) {
    return Crop(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
    );
  }
}

class FarmerProfile {
  final String profileId;
  final List<Crop> crops;

  const FarmerProfile({required this.profileId, this.crops = const []});
}
