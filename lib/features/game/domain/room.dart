class Room {
  final String id;
  final String roomPin;
  final String refereeUid;
  final String? consoleUid;
  final List<String> selectedCategories;
  final DateTime createdAt;
  final DateTime roomExpiresAt;

  const Room({
    required this.id,
    required this.roomPin,
    required this.refereeUid,
    this.consoleUid,
    this.selectedCategories = const [],
    required this.createdAt,
    required this.roomExpiresAt,
  });

  bool get isConsoleConnected => consoleUid != null;

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String,
      roomPin: json['room_pin'] as String,
      refereeUid: json['referee_uid'] as String,
      consoleUid: json['console_uid'] as String?,
      selectedCategories: (json['selected_categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: DateTime.parse(json['created_at'] as String),
      roomExpiresAt: DateTime.parse(json['room_expires_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'room_pin': roomPin,
      'referee_uid': refereeUid,
      'console_uid': consoleUid,
      'selected_categories': selectedCategories,
      'created_at': createdAt.toIso8601String(),
      'room_expires_at': roomExpiresAt.toIso8601String(),
    };
  }
}
