import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class NavigationLog extends StatelessWidget {
  final List<String> entries;

  NavigationLog({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: entries.length,
        separatorBuilder: (context, index) => SizedBox(height: 4),
        itemBuilder: (context, index) => Text(
          '${index + 1}. ${entries[index]}',
          style: TextStyle(
            color: AppColors.onSurfaceMuted,
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
