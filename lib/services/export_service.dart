import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/firewall_log.dart';
import 'log_analysis_service.dart';


class ExportResult {
  final String filePath;
  final int exportedLogs;

  const ExportResult({
    required this.filePath,
    required this.exportedLogs,
  });
}

class ExportService {
  static const _channel =
      MethodChannel('com.example.firewall_log_analyzer/export');

  Future<ExportResult> exportCsv(List<FirewallLog> logs) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'firewall_report_$timestamp.csv';

    final rows = <List<String>>[
      const [
        'IP Address',
        'Timestamp',
        'Method',
        'Request Method',
        'Request',
        'Status',
        'Bytes',
        'User Agent',
        'Parameters',
        'URL',
        'Response Code',
        'Response Size',
        'Country',
        'Request Rate Anomaly',
        'Severity Score',
        'Risk Level',
      ],
      ...logs.map((log) {
        final analysis = LogAnalysisService.analyze(log);
        return [
          log.ipAddress,
          log.timestamp,
          log.method,
          log.requestMethod,
          log.request,
          log.status,
          log.bytes,
          log.userAgent,
          log.parameters,
          log.url,
          log.responseCode.toString(),
          log.responseSize.toString(),
          log.country,
          log.requestRateAnomaly.toString(),
          analysis.severityScore.toString(),
          analysis.riskLevel,
        ];
      }),
    ];

    final csvContent = rows.map(_toCsvRow).join('\n');
    final bytes = Uint8List.fromList(utf8.encode(csvContent));

    final resultPath = await _saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'text/csv',
      fallbackContent: csvContent,
    );

    return ExportResult(filePath: resultPath, exportedLogs: logs.length);
  }

  Future<ExportResult> exportPdf(List<FirewallLog> logs) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'firewall_report_$timestamp.pdf';

    final lines = <String>[
      'Firewall Log Report',
      'Generated: ${DateTime.now().toIso8601String()}',
      'Logs exported: ${logs.length}',
      LogAnalysisService.overview(logs),
      '',
      'Entries:',
      ...logs.map((log) {
        final analysis = LogAnalysisService.analyze(log);
        return '${log.timestamp} | ${log.ipAddress} | ${log.responseCode} | ${analysis.riskLevel} ${analysis.severityScore} | ${log.country} | ${log.url}';
      }),
    ];

    final pdfBytes = _buildSimplePdf(_wrapLines(lines, maxCharacters: 92));

    final resultPath = await _saveFile(
      fileName: fileName,
      bytes: pdfBytes,
      mimeType: 'application/pdf',
    );

    return ExportResult(filePath: resultPath, exportedLogs: logs.length);
  }

  Future<String> _saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? fallbackContent,
  }) async {
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('saveToDownloads', {
          'fileName': fileName,
          'bytes': bytes,
          'mimeType': mimeType,
        });
        if (path != null) return path;
      } catch (e) {
        debugPrint('Android MediaStore export failed: $e');
      }
    }

    // Fallback or non-Android
    final exportDirectory = await _ensureExportDirectory();
    final file = File(path.join(exportDirectory.path, fileName));
    if (fallbackContent != null) {
      await file.writeAsString(fallbackContent, flush: true);
    } else {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }

  Future<Directory> _ensureExportDirectory() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final exportDirectory =
        Directory(path.join(documentsDirectory.path, 'exports'));
    if (!await exportDirectory.exists()) {
      await exportDirectory.create(recursive: true);
    }
    return exportDirectory;
  }

  String _toCsvRow(List<String> fields) {
    return fields.map((field) => '"${field.replaceAll('"', '""')}"').join(',');
  }

  List<String> _wrapLines(List<String> lines, {required int maxCharacters}) {
    final wrapped = <String>[];

    for (final line in lines) {
      if (line.length <= maxCharacters) {
        wrapped.add(line);
        continue;
      }

      var remaining = line;
      while (remaining.length > maxCharacters) {
        wrapped.add(remaining.substring(0, maxCharacters));
        remaining = remaining.substring(maxCharacters);
      }
      if (remaining.isNotEmpty) {
        wrapped.add(remaining);
      }
    }

    return wrapped;
  }

  Uint8List _buildSimplePdf(List<String> lines) {
    const linesPerPage = 40;
    final pages = <List<String>>[];

    for (var index = 0; index < lines.length; index += linesPerPage) {
      pages.add(
        lines.sublist(
          index,
          index + linesPerPage > lines.length
              ? lines.length
              : index + linesPerPage,
        ),
      );
    }

    final objects = <String>[];
    final pageObjectNumbers = <int>[];
    final contentObjectNumbers = <int>[];
    const fontObjectNumber = 3;
    var nextObjectNumber = 4;

    for (final pageLines in pages) {
      final pageObjectNumber = nextObjectNumber++;
      final contentObjectNumber = nextObjectNumber++;
      pageObjectNumbers.add(pageObjectNumber);
      contentObjectNumbers.add(contentObjectNumber);

      final pageContent = StringBuffer()
        ..writeln('BT')
        ..writeln('/F1 10 Tf')
        ..writeln('50 780 Td')
        ..writeln('14 TL');

      for (final line in pageLines) {
        pageContent.writeln('(${_escapePdfText(line)}) Tj');
        pageContent.writeln('T*');
      }

      pageContent.writeln('ET');
      final stream = pageContent.toString();

      objects.add(
        '$pageObjectNumber 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 $fontObjectNumber 0 R >> >> /Contents $contentObjectNumber 0 R >>\nendobj\n',
      );
      objects.add(
        '$contentObjectNumber 0 obj\n<< /Length ${utf8.encode(stream).length} >>\nstream\n$stream\nendstream\nendobj\n',
      );
    }

    final pagesObject = StringBuffer()
      ..write(
          '2 0 obj\n<< /Type /Pages /Count ${pageObjectNumbers.length} /Kids [');
    for (final pageObjectNumber in pageObjectNumbers) {
      pagesObject.write('$pageObjectNumber 0 R ');
    }
    pagesObject.write('] >>\nendobj\n');

    final allObjects = <String>[
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
      pagesObject.toString(),
      '3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
      ...objects,
    ];

    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    var byteCount = utf8.encode(buffer.toString()).length;

    for (final object in allObjects) {
      offsets.add(byteCount);
      buffer.write(object);
      byteCount += utf8.encode(object).length;
    }

    final xrefStart = byteCount;
    buffer.writeln('xref');
    buffer.writeln('0 ${allObjects.length + 1}');
    buffer.writeln('0000000000 65535 f ');
    for (var index = 1; index < offsets.length; index++) {
      buffer.writeln('${offsets[index].toString().padLeft(10, '0')} 00000 n ');
    }
    buffer.writeln('trailer');
    buffer.writeln('<< /Size ${allObjects.length + 1} /Root 1 0 R >>');
    buffer.writeln('startxref');
    buffer.writeln(xrefStart);
    buffer.write('%%EOF');

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  String _escapePdfText(String value) {
    return value
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }
}
