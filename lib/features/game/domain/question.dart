class Question {
  final String id;
  final String category;
  final String questionType;
  final String questionText;
  final String? imageUrl;
  final String? audioUrl;
  final String referenceAnswer;
  final String? judgeNotes;

  const Question({
    required this.id,
    required this.category,
    required this.questionType,
    required this.questionText,
    this.imageUrl,
    this.audioUrl,
    required this.referenceAnswer,
    this.judgeNotes,
  });

  bool get isTextQuestion => questionType == 'text';
  bool get isImageQuestion => questionType == 'image';
  bool get isAudioQuestion => questionType == 'audio';

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as String,
      category: json['category'] as String,
      questionType: json['question_type'] as String,
      questionText: json['question_text'] as String,
      imageUrl: json['image_url'] as String?,
      audioUrl: json['audio_url'] as String?,
      referenceAnswer: json['reference_answer'] as String,
      judgeNotes: json['judge_notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'question_type': questionType,
      'question_text': questionText,
      'image_url': imageUrl,
      'audio_url': audioUrl,
      'reference_answer': referenceAnswer,
      'judge_notes': judgeNotes,
    };
  }
}
