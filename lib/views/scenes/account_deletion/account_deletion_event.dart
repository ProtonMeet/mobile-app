abstract class AccountDeletionEvent {}

class StartAccountDeletion extends AccountDeletionEvent {
  StartAccountDeletion();
}

class CloseAccountDeletion extends AccountDeletionEvent {
  CloseAccountDeletion();
}
