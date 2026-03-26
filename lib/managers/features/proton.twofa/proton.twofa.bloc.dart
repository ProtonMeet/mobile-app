// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:meet/managers/features/proton.recovery/proton.recovery.state.dart';
// import 'package:meet/managers/features/proton.twofa/proton.twofa.event.dart';
// import 'package:meet/managers/features/proton.twofa/proton.twofa.state.dart';
// import 'package:meet/managers/providers/user.data.provider.dart';
// import 'package:meet/managers/users/user.manager.dart';
// import 'package:meet/rust/api/api_service/proton_settings_client.dart';
// import 'package:meet/rust/api/api_service/proton_users_client.dart';

// /// Define the Bloc
// class ProtonTwoFaBloc extends Bloc<ProtonTwoFaEvent, ProtonTwoFaState> {
//   final UserManager userManager;
//   final ProtonUsersClient protonUsersApi;
//   final ProtonSettingsClient protonSettingsApi;
//   final UserDataProvider userDataProvider;

//   /// initialize the bloc with the initial state
//   ProtonTwoFaBloc(
//     this.userManager,
//     this.protonUsersApi,
//     this.userDataProvider,
//     this.protonSettingsApi,
//   ) : super(const ProtonTwoFaState()) {
//     on<LoadingTwoFa>((event, emit) async {
//       emit(state.copyWith(
//           isLoading: true,
//           error: "",
//           isRecoveryEnabled: false,
//           mnemonic: "",
//           requireAuthModel: const RequireAuthModel()));

//       final userInfo = await protonUsersApi.getUserInfo();
//       final status = userInfo.mnemonicStatus == 3;

//       emit(state.copyWith(isLoading: false, isRecoveryEnabled: status));
//     });

//     on<EnableTwoFa>((event, emit) async {
//       emit(state.copyWith(isLoading: true, error: ""));
//     });

//     on<DisableTwoFa>((event, emit) async {
//       emit(state.copyWith(isLoading: true, error: ""));
//     });
//   }
// }
