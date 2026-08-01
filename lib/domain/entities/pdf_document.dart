import 'dart:convert';

/// The kind of document a [PdfDocument] entry points to.
enum DocType {
  pdf,
  docx,
  markdown;

  static DocType fromExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.docx')) return DocType.docx;
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return DocType.markdown;
    }
    return DocType.pdf;
  }

  static DocType fromName(String? name) {
    return DocType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => DocType.pdf,
    );
  }
}

class PdfDocument {
  final String path;
  final String name;
  final DateTime lastOpened;
  final int lastPage;
  final int totalPages;
  final DocType type;

  const PdfDocument({
    required this.path,
    required this.name,
    required this.lastOpened,
    this.lastPage = 0,
    this.totalPages = 0,
    this.type = DocType.pdf,
  });

  double get progress =>
      totalPages > 0 ? (lastPage / totalPages).clamp(0.0, 1.0) : 0.0;

  PdfDocument copyWith({
    String? path,
    String? name,
    DateTime? lastOpened,
    int? lastPage,
    int? totalPages,
    DocType? type,
  }) {
    return PdfDocument(
      path: path ?? this.path,
      name: name ?? this.name,
      lastOpened: lastOpened ?? this.lastOpened,
      lastPage: lastPage ?? this.lastPage,
      totalPages: totalPages ?? this.totalPages,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'lastOpened': lastOpened.toIso8601String(),
        'lastPage': lastPage,
        'totalPages': totalPages,
        'type': type.name,
      };

  factory PdfDocument.fromJson(Map<String, dynamic> json) => PdfDocument(
        path: json['path'] as String,
        name: json['name'] as String,
        lastOpened: DateTime.parse(json['lastOpened'] as String),
        lastPage: (json['lastPage'] as int?) ?? 0,
        totalPages: (json['totalPages'] as int?) ?? 0,
        type: DocType.fromName(json['type'] as String?),
      );

  String toJsonString() => jsonEncode(toJson());

  factory PdfDocument.fromJsonString(String raw) =>
      PdfDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
