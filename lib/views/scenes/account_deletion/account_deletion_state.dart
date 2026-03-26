class AccountDeletionState {
  final bool isLoading;
  final String? checkoutUrl;
  final String? error;

  AccountDeletionState({this.isLoading = false, this.checkoutUrl, this.error});

  AccountDeletionState copyWith({
    bool? isLoading,
    String? checkoutUrl,
    String? error,
  }) {
    return AccountDeletionState(
      isLoading: isLoading ?? this.isLoading,
      checkoutUrl: checkoutUrl ?? this.checkoutUrl,
      error: error,
    );
  }
}
