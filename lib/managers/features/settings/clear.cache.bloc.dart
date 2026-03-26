import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/managers/users/user.manager.dart';

/// Define the event
abstract class ClearCacheEvent extends Equatable {
  @override
  List<Object> get props => [];
}

class ClearingCache extends ClearCacheEvent {}

/// Define the state
class ClearCacheState extends Equatable {
  final bool isClearing;
  final bool hasCache;

  const ClearCacheState({this.isClearing = false, this.hasCache = false});

  ClearCacheState copyWith({bool? isClearing, bool? hasCache}) {
    return ClearCacheState(
      isClearing: isClearing ?? this.isClearing,
      hasCache: hasCache ?? this.hasCache,
    );
  }

  @override
  List<Object> get props => [isClearing, hasCache];
}

/// Define the Bloc
class ClearCacheBloc extends Bloc<ClearCacheEvent, ClearCacheState> {
  final UserManager userManager;
  // final BDKTransactionDataProvider bdkTransactionDataProvider;
  // final UserDataProvider userDataProvider;

  /// initialize the bloc with the initial state
  ClearCacheBloc(
    this.userManager,
    // this.bdkTransactionDataProvider,
    // this.userDataProvider,
  ) : super(const ClearCacheState()) {
    on<ClearingCache>((event, emit) async {
      emit(state.copyWith(isClearing: true));

      final hasCache = true; //= bdkTransactionDataProvider.anyFullSyncedDone();

      /// only trigger clear local cache when at least one full sync done
      // if (hasCache) {
      //   /// clear bdk in-memory caches
      //   await bdkTransactionDataProvider.clear();

      //   /// clear user data provider caches to reload user info
      //   await userDataProvider.clear();

      //   /// clear bdk sqlite local caches
      //   await walletManager.cleanBDKCache();

      //   /// clear shared sharedpreference
      //   await userManager.clear();

      //   /// clear legacy sharedpreference
      //   await walletManager.cleanSharedPreference();

      //   bdkTransactionDataProvider.notifyCacheCleared();
      // }

      /// wait for UI loading effect
      await Future.delayed(const Duration(seconds: 1));

      /// disable db reset here and wait for rust migration
      // await DBHelper.reset();
      emit(state.copyWith(isClearing: false, hasCache: hasCache));
    });
  }
}
