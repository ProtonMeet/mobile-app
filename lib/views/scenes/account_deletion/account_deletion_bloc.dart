import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';

import 'account_deletion_event.dart';
import 'account_deletion_state.dart';

class AccountDeletionBloc
    extends Bloc<AccountDeletionEvent, AccountDeletionState> {
  final ManagerFactory managerFactory;

  AccountDeletionBloc({required this.managerFactory})
    : super(AccountDeletionState()) {
    on<StartAccountDeletion>(_onStartAccountDeletion);
    on<CloseAccountDeletion>(_onCloseAccountDeletion);
  }

  Future<void> _onStartAccountDeletion(
    StartAccountDeletion event,
    Emitter<AccountDeletionState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    try {
      final appCoreManager = managerFactory.get<AppCoreManager>();
      final selector = await appCoreManager.appCore.forkSelector(
        clientChild: 'web-account-lite',
      );

      // Add 1s delay after fork succeeds
      await Future.delayed(const Duration(seconds: 1));

      final uri = Uri.parse('https://account.proton.me/lite').replace(
        queryParameters: {'action': 'delete-account'},
        fragment: 'selector=${Uri.encodeComponent(selector)}',
      );
      final checkoutUrl = uri.toString();
      emit(state.copyWith(isLoading: false, checkoutUrl: checkoutUrl));
    } catch (e) {
      logger.e('Failed to fork selector for account deletion: $e');
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onCloseAccountDeletion(
    CloseAccountDeletion event,
    Emitter<AccountDeletionState> emit,
  ) {
    emit(AccountDeletionState());
  }
}
