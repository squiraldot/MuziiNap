/// Read-only preflight for Gallery pin requests. Native SQLite remains authoritative.
class ThemeWidgetAvailability {
  const ThemeWidgetAvailability({
    required this.activeCount,
    required this.pendingCount,
    required this.remainingCapacity,
    required this.recoveryConflict,
    required this.registeredIdentities,
    required this.pendingIdentities,
  });

  final int activeCount;
  final int pendingCount;
  final int remainingCapacity;
  final bool recoveryConflict;
  final Set<String> registeredIdentities;
  final Set<String> pendingIdentities;

  factory ThemeWidgetAvailability.fromStatus(Map<String, dynamic> status) {
    final widgets = (status['widgets'] as List?)?.whereType<Map>().toList() ?? const [];
    final active = (status['activeCount'] as num?)?.toInt() ?? widgets.length;
    final pending = (status['pendingCount'] as num?)?.toInt() ?? 0;
    final identities = widgets.map((item) =>
      '${item['themeId'] ?? ''}/${item['designId'] ?? ''}').toSet();
    final pendingItems = (status['pendingWidgets'] as List?)?.whereType<Map>().toList() ?? const [];
    final pendingIdentities = pendingItems.map((item) =>
      '${item['themeId'] ?? ''}/${item['designId'] ?? ''}').toSet();
    return ThemeWidgetAvailability(
      activeCount: active,
      pendingCount: pending,
      remainingCapacity: (status['remainingCapacity'] as num?)?.toInt() ??
          (2 - active - pending).clamp(0, 2).toInt(),
      recoveryConflict: status['recoveryConflict'] == true,
      registeredIdentities: identities,
      pendingIdentities: pendingIdentities,
    );
  }

  bool canAdd(String themeId, String designId) {
    final identity = '$themeId/$designId';
    return !recoveryConflict &&
        remainingCapacity > 0 &&
        !registeredIdentities.contains(identity) &&
        !pendingIdentities.contains(identity);
  }

  String? reasonFor(String themeId, String designId) {
    if (recoveryConflict) return 'Resolve the widget recovery conflict before adding another widget.';
    final identity = '$themeId/$designId';
    if (registeredIdentities.contains(identity) || pendingIdentities.contains(identity)) {
      return 'This design is already installed or has a pending pin request.';
    }
    if (remainingCapacity <= 0) return 'Both theme widget slots are occupied.';
    return null;
  }
}
