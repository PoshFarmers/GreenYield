import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Generic role-info card used in OrderDetailScreen.
/// Shows an icon/avatar, a title, optional subtitle, and optional
/// action buttons (e.g. Chat, Call).
class InfoCard extends StatelessWidget {
  final IconData leadingIcon;
  final String title;
  final String? subtitle;
  final String? phone;
  final String? address;
  final String sectionLabel;

  /// Optional extra action alongside the default Call button.
  final Widget? extraAction;

  const InfoCard({
    super.key,
    required this.leadingIcon,
    required this.title,
    required this.sectionLabel,
    this.subtitle,
    this.phone,
    this.address,
    this.extraAction,
  });

  Future<void> _call() async {
    if (phone == null) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final outline = theme.colorScheme.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Row(
          children: [
            Icon(
              leadingIcon,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              sectionLabel.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Card body
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar circle
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(leadingIcon, size: 20, color: primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              if (address != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              if (phone != null || extraAction != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (extraAction != null) ...[
                      Expanded(child: extraAction!),
                      const SizedBox(width: 10),
                    ],
                    if (phone != null)
                      Expanded(
                        child: _ActionButton(
                          id: 'info_card_call_${title.replaceAll(' ', '_').toLowerCase()}',
                          icon: Icons.phone_outlined,
                          label: 'Call',
                          color: primary,
                          onTap: _call,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String id;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.id,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: ValueKey(id),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 38),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Reusable chat action button to pass as [InfoCard.extraAction].
class ChatActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final String id;

  const ChatActionButton({super.key, required this.onTap, required this.id});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      key: ValueKey(id),
      onPressed: onTap,
      icon: const Icon(Icons.chat_bubble_outline, size: 16),
      label: const Text('Message'),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 38),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
