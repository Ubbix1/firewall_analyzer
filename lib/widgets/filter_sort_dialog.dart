import 'package:flutter/material.dart';

import '../controllers/home_screen_controller.dart';

/// Shows the filter & sort dialog as a modal, mutating [ctrl] state on change.
void showFilterSortDialog(
    BuildContext context, HomeScreenController ctrl) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Filter & Sort'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Filter by Status Code'),
            ),
            DropdownButton<String>(
              value: ctrl.statusFilter,
              hint: const Text('All'),
              isExpanded: true,
              items: ['200', '301', '302', '400', '401', '403', '404', '500']
                  .map((code) =>
                      DropdownMenuItem(value: code, child: Text(code)))
                  .toList(),
              onChanged: (value) {
                ctrl.setStatusFilter(value);
                setDialogState(() {});
              },
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Sort by'),
            ),
            DropdownButton<String>(
              value: ctrl.sortBy,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'timestamp', child: Text('Timestamp')),
                DropdownMenuItem(value: 'ipAddress', child: Text('IP Address')),
                DropdownMenuItem(
                    value: 'responseCode', child: Text('Response Code')),
                DropdownMenuItem(value: 'risk', child: Text('Risk Score')),
                DropdownMenuItem(value: 'url', child: Text('URL')),
              ],
              onChanged: (value) {
                if (value == null) return;
                ctrl.setSortBy(value);
                setDialogState(() {});
              },
            ),
            Row(
              children: [
                const Text('Ascending'),
                Checkbox(
                  value: ctrl.ascending,
                  onChanged: (value) {
                    if (value == null) return;
                    ctrl.setAscending(value);
                    setDialogState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );
}
