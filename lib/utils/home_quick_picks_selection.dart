import '../models/quick_picks.dart';

class HomeQuickPicksSelection {
  const HomeQuickPicksSelection({
    required this.quickPicks,
    required this.remainingSections,
  });

  final QuickPicks? quickPicks;
  final List<dynamic> remainingSections;
}

/// Extract only the actual Quick picks shelf for the dedicated Home slot.
/// Other song shelves (for example Listen again) remain in their feed order.
HomeQuickPicksSelection selectHomeQuickPicks(List<dynamic> sections) {
  final index = sections.indexWhere((section) {
    if (section is! QuickPicks) return false;
    return section.title.trim().toLowerCase().contains('quick pick');
  });

  if (index < 0) {
    return HomeQuickPicksSelection(
      quickPicks: null,
      remainingSections: List<dynamic>.from(sections),
    );
  }

  final remaining = List<dynamic>.from(sections)..removeAt(index);
  return HomeQuickPicksSelection(
    quickPicks: sections[index] as QuickPicks,
    remainingSections: remaining,
  );
}
