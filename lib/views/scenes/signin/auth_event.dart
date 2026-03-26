import 'package:meet/rust/proton_meet/models/user.dart';

abstract class AuthEvent {}

class AuthLoading extends AuthEvent {
  AuthLoading();
}

class AuthInitialized extends AuthLoading {
  AuthInitialized();
}

class LoginWithNative extends AuthEvent {
  LoginWithNative();
}

class ShowFlutterSignIn extends AuthEvent {
  ShowFlutterSignIn();
}

class SignupWithNative extends AuthEvent {
  SignupWithNative();
}

class SignOutUser extends AuthEvent {
  SignOutUser();
}

class LoggedInUser extends AuthEvent {
  final ProtonUser user;
  LoggedInUser(this.user);
}

class ResetLoadingState extends AuthEvent {
  final bool isLoggingIn;
  final bool isLoggingOut;
  ResetLoadingState({this.isLoggingIn = false, this.isLoggingOut = false});
}

class AuthCoreUnavailable extends AuthEvent {
  final String message;
  AuthCoreUnavailable(this.message);
}

// class UpdateDisplayName extends PreJoinEvent {
//   final String displayName;
//   UpdateDisplayName(this.displayName);
// }
