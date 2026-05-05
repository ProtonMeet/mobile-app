// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_activity.model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserActivityPersistedV1 _$UserActivityPersistedV1FromJson(
  Map<String, dynamic> json,
) => UserActivityPersistedV1(
  version: (json['v'] as num?)?.toInt() ?? 3,
  meetingsCreatedCount: (json['mc'] as num?)?.toInt() ?? 0,
  meetingsCompletedCount: (json['mco'] as num?)?.toInt() ?? 0,
  createdAtEpochSec: json['ca'] == null
      ? const []
      : _intListFromJson(json['ca']),
  completedAtEpochSec: json['co'] == null
      ? const []
      : _intListFromJson(json['co']),
  completedFeedbackScores: json['cfs'] == null
      ? const []
      : _intListFromJson(json['cfs']),
  completedHadBadConnection: json['cbc'] == null
      ? const []
      : _intListFromJson(json['cbc']),
  completedWasInterrupted: json['cwi'] == null
      ? const []
      : _intListFromJson(json['cwi']),
  feedbackAtEpochSec: json['fa'] == null
      ? const []
      : _intListFromJson(json['fa']),
  feedbackScores: json['fs'] == null ? const [] : _intListFromJson(json['fs']),
  hasSubmittedFeedbackBelow5Stars: json['h5'] as bool? ?? false,
  pendingDeferredStoreReview: json['pd'] as bool? ?? false,
  lastPreRatingNegativeEpochSec: (json['pn'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$UserActivityPersistedV1ToJson(
  UserActivityPersistedV1 instance,
) => <String, dynamic>{
  'v': instance.version,
  'mc': instance.meetingsCreatedCount,
  'mco': instance.meetingsCompletedCount,
  'ca': _intListToJson(instance.createdAtEpochSec),
  'co': _intListToJson(instance.completedAtEpochSec),
  'cfs': _intListToJson(instance.completedFeedbackScores),
  'cbc': _intListToJson(instance.completedHadBadConnection),
  'cwi': _intListToJson(instance.completedWasInterrupted),
  'fa': _intListToJson(instance.feedbackAtEpochSec),
  'fs': _intListToJson(instance.feedbackScores),
  'h5': instance.hasSubmittedFeedbackBelow5Stars,
  'pd': instance.pendingDeferredStoreReview,
  'pn': instance.lastPreRatingNegativeEpochSec,
};
