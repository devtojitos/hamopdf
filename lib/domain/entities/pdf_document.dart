import 'dart:convert';

class PdfDocument {
  final String path;
  final String name;
  final DateTime lastOpened;
  final int lastPage;
  final int totalPages;

  const PdfDocument({
    required this.path,
    required this.name,
    required this.lastOpened,
    this.lastPage = 0,
    this.totalPages = 0,
  });

  double get progress =>
      totalPages > 0 ? (lastPage / totalPages).clamp(0.0, 1.0) : 0.0;

  PdfDocument copyWith({
    String? path,
    String? name,
    DateTime? lastOpened,
    int? lastPage,
    int? totalPages,
  }) {
    return PdfDocument(
      path: path ?? this.path,
      name: name ?? this.name,
      lastOpened: lastOpened ?? this.lastOpened,
      lastPage: lastPage ?? this.lastPage,
      totalPages: totalPages ?? this.totalPages,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'lastOpened': lastOpened.toIso8601String(),
        'lastPage': lastPage,
        'totalPages': totalPages,
      };

  factory PdfDocument.fromJson(Map<String, dynamic> json) => PdfDocument(
        path: json['path'] as String,
        name: json['name'] as String,
        lastOpened: DateTime.parse(json['lastOpened'] as String),
        lastPage: (json['lastPage'] as int?) ?? 0,
        totalPages: (json['totalPages'] as int?) ?? 0,
      );

  String toJsonString() => jsonEncode(toJson());

  factory PdfDocument.fromJsonString(String raw) =>
      PdfDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
