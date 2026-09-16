//
//  PaymentsManager.swift
//

import Combine
import Foundation
import ProtonCoreLog
import ProtonCorePaymentsUIV2
import ProtonCorePaymentsV2
import ProtonCoreServices

final class PaymentsManager {
    typealias PaymentsResult = Result<Bool, Error>

    private let apiService: APIService
    private let paymentsV2 = PaymentsV2()
    private var cancellables = Set<AnyCancellable>()
    private var hasReportedCompletion = false

    init(apiService: APIService) {
        self.apiService = apiService
    }

    func stopTransactionObserver() {
        TransactionsObserver.shared.stop()
    }

    func manageSubscription(completion: @escaping (PaymentsResult) -> Void) {
        guard !Bundle.main.isFromTestFlight else { return }
        presentPlans(hideCurrentPlan: false, completion: completion)
    }

    func upgradeSubscription(completion: @escaping (PaymentsResult) -> Void) {
        guard !Bundle.main.isFromTestFlight else { return }
        presentPlans(hideCurrentPlan: true, completion: completion)
    }

    private func presentPlans(hideCurrentPlan: Bool, completion: @escaping (PaymentsResult) -> Void) {
        hasReportedCompletion = false
        cancellables.removeAll()

        Task { @MainActor in
            do {
                try await ensureTransactionObserverStarted()
                try paymentsV2.showAvailablePlans(
                    presentationMode: .modal,
                    hideCurrentPlan: hideCurrentPlan,
                    apiService: apiService
                )
            } catch {
                reportCompletionOnce(.failure(error), completion: completion)
                return
            }

            paymentsV2.transactionProgress
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .transactionCompleted:
                        reportCompletionOnce(.success(true), completion: completion)
                        paymentsV2.dismissPayments()
                    case .transactionCancelledByUser:
                        reportCompletionOnce(.success(false), completion: completion)
                        paymentsV2.dismissPayments()
                    case .mismatchTransactionIDs,
                         .transactionProcessError,
                         .transactionProcessErrorInvalidReq,
                         .unableToGetUserTransactionUUID,
                         .unknownError:
                        reportCompletionOnce(
                            .failure(PaymentsV2PresentationError.transactionFailed(state)),
                            completion: completion
                        )
                    default:
                        break
                    }
                }
                .store(in: &cancellables)

            paymentsV2.viewCycleState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self, state == .dismissed else { return }
                    reportCompletionOnce(.success(false), completion: completion)
                }
                .store(in: &cancellables)
        }
    }

    private func ensureTransactionObserverStarted() async throws {
        if TransactionsObserver.shared.isON {
            return
        }

        let configuration = TransactionsObserverConfiguration(
            remoteManager: RemoteManager(apiService: apiService)
        )
        TransactionsObserver.shared.setConfiguration(configuration)
        try await TransactionsObserver.shared.start()
    }

    private func reportCompletionOnce(
        _ result: PaymentsResult,
        completion: @escaping (PaymentsResult) -> Void
    ) {
        guard !hasReportedCompletion else { return }
        hasReportedCompletion = true
        completion(result)
    }
}

private enum PaymentsV2PresentationError: LocalizedError {
    case transactionFailed(TransactionHandlerState)

    var errorDescription: String? {
        switch self {
        case .transactionFailed(let state):
            return "Payments V2 transaction failed: \(state)"
        }
    }
}
