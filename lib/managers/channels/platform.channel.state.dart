// Data States
import 'package:equatable/equatable.dart';
import 'package:meet/models/native.session.model.dart';

abstract class NativeLoginState extends Equatable {
  const NativeLoginState();
}

class NativeLoginInitial extends NativeLoginState {
  @override
  List<Object> get props => [];
}

class NativeLoginSuccess extends NativeLoginState {
  final UserInfo userInfo;
  const NativeLoginSuccess(this.userInfo);
  @override
  List<Object> get props => [userInfo];
}

class NativeLoginError extends NativeLoginState {
  final String error;
  const NativeLoginError(this.error);
  @override
  List<Object> get props => [error];
}
