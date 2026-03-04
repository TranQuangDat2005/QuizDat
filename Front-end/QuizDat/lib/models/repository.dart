class Repository {
  final String repositoryId;
  final String name;
  final String description;

  // Constructor
  Repository({
    required this.repositoryId,
    required this.name,
    required this.description,
  });

  factory Repository.fromJson(Map<String, dynamic> json) {
    return Repository(
      repositoryId: json['repository_id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
    );
  }
}
