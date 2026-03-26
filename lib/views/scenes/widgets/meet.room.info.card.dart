import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class RoomInfoCard extends StatelessWidget {
  const RoomInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final roomKey = "";
    final epoch = "";

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxMobileSheetWidth),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.backgroundNorm.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
          ),
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Room Key: ', roomKey),
              const SizedBox(height: 12),
              _buildInfoRow('Epoch: $epoch', ''),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
