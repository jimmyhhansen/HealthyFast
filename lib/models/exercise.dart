/// A predefined exercise with guides and muscle group metadata.
class Exercise {
  final String name;
  final String muscleGroup;
  final List<String> steps;
  final List<String> imageIds;
  final String? videoUrl;
  final String? customImagePath;

  const Exercise({
    required this.name,
    required this.muscleGroup,
    required this.steps,
    this.imageIds = const [],
    this.videoUrl,
    this.customImagePath,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'muscleGroup': muscleGroup,
        'steps': steps,
        'imageIds': imageIds,
        'videoUrl': videoUrl,
        'customImagePath': customImagePath,
      };

  factory Exercise.fromJson(Map<String, dynamic> m) => Exercise(
        name: m['name'] as String? ?? 'Exercise',
        muscleGroup: m['muscleGroup'] as String? ?? 'Other',
        steps: (m['steps'] as List? ?? const []).cast<String>(),
        imageIds: (m['imageIds'] as List? ?? const []).cast<String>(),
        videoUrl: m['videoUrl'] as String?,
        customImagePath: m['customImagePath'] as String?,
      );

  /// Two frames per exercise (start/end position) from free-exercise-db.
  List<String> imageUrls(String id) => [
        'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/$id/0.jpg',
        'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/$id/1.jpg',
      ];

  bool get isCustom => customImagePath != null || (imageIds.isEmpty && steps.isNotEmpty && steps[0] == 'Imported via Excel');
}
