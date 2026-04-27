import 'package:intl/intl.dart';

String formatDateTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  return DateFormat.yMMMd().add_jm().format(parsed);
}
