import 'package:equatable/equatable.dart';

/// Participant detail with name and uuid to avoid name duplication issues
class ParticipantDetail extends Equatable {
  final String name;
  final String uuid;

  const ParticipantDetail({required this.name, required this.uuid});

  @override
  List<Object?> get props => [name, uuid];
}
