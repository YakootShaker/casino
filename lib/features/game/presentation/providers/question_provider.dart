import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/sound_service.dart';
import '../../data/game_repository.dart';
import '../../domain/question.dart';

final questionProvider =
    FutureProvider.family<Question?, String?>((ref, questionId) async {
  if (questionId == null) return null;

  final repo = ref.watch(gameRepositoryProvider);
  final question = await repo.getQuestion(questionId);

  // If question has audio clue, pre-load in sound service
  if (question != null && question.isAudioQuestion && question.audioUrl != null) {
    final sound = ref.read(soundServiceProvider);
    sound.loadAudioClue(question.audioUrl!);
  }

  return question;
});
