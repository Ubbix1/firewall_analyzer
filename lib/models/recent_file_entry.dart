class RecentFileEntry {
  final int? id;
  final String path;
  final String fileName;
  final String lastOpened;
  final int logCount;

  const RecentFileEntry({
    this.id,
    required this.path,
    required this.fileName,
    required this.lastOpened,
    required this.logCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'fileName': fileName,
      'lastOpened': lastOpened,
      'logCount': logCount,
    };
  }

  static RecentFileEntry fromMap(Map<String, dynamic> map) {
    return RecentFileEntry(
      id: map['id'] as int?,
      path: map['path']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      lastOpened: map['lastOpened']?.toString() ?? '',
      logCount: map['logCount'] is int
          ? map['logCount'] as int
          : int.tryParse(map['logCount']?.toString() ?? '') ?? 0,
    );
  }
}
