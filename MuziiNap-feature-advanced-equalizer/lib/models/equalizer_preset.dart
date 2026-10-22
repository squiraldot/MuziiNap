import 'equalizer.dart';

class EqualizerPreset {
  final String id;
  final String name;
  final String author;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isBuiltIn;
  final EqualizerConfig config;

  EqualizerPreset({
    required this.id,
    required this.name,
    required this.author,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.isBuiltIn,
    required this.config,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Preset id must not be empty');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Preset name must not be empty');
    }
    if (author.trim().isEmpty) {
      throw ArgumentError.value(
        author,
        'author',
        'Preset author must not be empty',
      );
    }
  }

  EqualizerPreset copyWith({
    String? id,
    String? name,
    String? author,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isBuiltIn,
    EqualizerConfig? config,
  }) {
    return EqualizerPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      author: author ?? this.author,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      config: config ?? this.config,
    );
  }

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'author': author,
        'description': description,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'isBuiltIn': isBuiltIn,
        'config': config.toJson(),
      };

  factory EqualizerPreset.fromJson(Map<String, Object?> json) {
    final createdAt = DateTime.tryParse(_requireString(json, 'createdAt'));
    final updatedAt = DateTime.tryParse(_requireString(json, 'updatedAt'));
    if (createdAt == null || updatedAt == null) {
      throw const FormatException('Invalid preset timestamp');
    }

    final rawConfig = json['config'];
    if (rawConfig is! Map) {
      throw const FormatException('Preset config must be an object');
    }

    return EqualizerPreset(
      id: _requireString(json, 'id'),
      name: _requireString(json, 'name'),
      author: _requireString(json, 'author'),
      description: _requireString(json, 'description'),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      isBuiltIn: _requireBool(json, 'isBuiltIn'),
      config: EqualizerConfig.fromJson(
        Map<String, Object?>.from(rawConfig),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EqualizerPreset &&
        other.id == id &&
        other.name == name &&
        other.author == author &&
        other.description == description &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.isBuiltIn == isBuiltIn &&
        other.config == config;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        author,
        description,
        createdAt,
        updatedAt,
        isBuiltIn,
        config,
      );
}

class EqualizerBuiltInPresets {
  static final List<EqualizerPreset> all = List.unmodifiable([
    _preset('flat', 'Flat', [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
    _preset('bass-boost', 'Bass Boost', [5.0, 4.0, 3.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
    _preset('deep-bass', 'Deep Bass', [7.0, 5.0, 3.0, 1.0, 0.0, 0.0, 0.0, -1.0, -1.0, 0.0]),
    _preset('vocal', 'Vocal', [-3.0, -2.0, -1.0, 2.0, 4.0, 5.0, 4.0, 2.0, 0.0, -1.0]),
    _preset('pop', 'Pop', [1.0, 2.0, 1.0, 0.0, -1.0, 1.0, 2.0, 3.0, 2.0, 1.0]),
    _preset('rock', 'Rock', [4.0, 3.0, 2.0, 0.0, -2.0, -1.0, 2.0, 4.0, 5.0, 4.0]),
    _preset('jazz', 'Jazz', [2.0, 1.0, 0.0, 1.0, 2.0, 2.0, 1.0, 2.0, 3.0, 2.0]),
    _preset('classical', 'Classical', [2.0, 1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 3.0, 3.0, 2.0]),
    _preset('acoustic', 'Acoustic', [2.0, 2.0, 1.0, 0.0, 2.0, 3.0, 3.0, 2.0, 1.0, 1.0]),
    _preset('edm', 'EDM', [5.0, 4.0, 2.0, 0.0, -1.0, 1.0, 3.0, 4.0, 4.0, 3.0]),
    _preset('hip-hop', 'Hip-Hop', [5.0, 4.0, 2.0, 1.0, -1.0, 0.0, 1.0, 2.0, 2.0, 1.0]),
    _preset('metal', 'Metal', [4.0, 3.0, 1.0, -1.0, -2.0, 0.0, 2.0, 4.0, 3.0, 2.0]),
    _preset('podcast', 'Podcast', [-5.0, -3.0, -2.0, 2.0, 4.0, 5.0, 3.0, 1.0, 0.0, -1.0]),
    _preset('warm', 'Warm', [3.0, 2.0, 2.0, 1.0, 1.0, 0.0, -1.0, -2.0, -2.0, -1.0]),
    _preset('bright', 'Bright', [-2.0, -1.0, 0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 4.0, 3.0]),
    _preset('night', 'Night', [2.0, 1.0, 0.0, 1.0, 2.0, 2.0, 1.0, 0.0, -1.0, -2.0]),
    _preset('cinematic', 'Cinematic', [4.0, 2.0, 1.0, 0.0, -1.0, -1.0, 1.0, 3.0, 4.0, 3.0]),
    _preset('loud', 'Loud', [3.0, 2.0, 1.0, 0.0, -1.0, 0.0, 2.0, 3.0, 2.0, 1.0]),
  ]);

  static EqualizerPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static EqualizerPreset _preset(
    String id,
    String name,
    List<double> gains,
  ) {
    final base = EqualizerConfig.graphic10Band();
    final config = base.copyWith(
      bands: [
        for (var i = 0; i < gains.length; i++)
          base.bands[i].copyWith(gainDb: gains[i]),
      ],
    );
    final createdAt = DateTime.utc(2026, 1, 1);
    return EqualizerPreset(
      id: 'builtin-$id',
      name: name,
      author: 'MuziiNap',
      description: 'Curated MuziiNap ${name.toLowerCase()} profile.',
      createdAt: createdAt,
      updatedAt: createdAt,
      isBuiltIn: true,
      config: config,
    );
  }
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Expected string for $key');
  }
  return value;
}

bool _requireBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Expected boolean for $key');
}
