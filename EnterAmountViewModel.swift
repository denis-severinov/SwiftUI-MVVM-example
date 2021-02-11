//  Copyright © 2020 Storytelling Software. All rights reserved.
//

import Repositories
import Foundation
import Validators
import Analytics
import Swinject
import SwiftUI
import Combine
import Domain

class EnterAmountViewModel: ViewModel {
    struct Flow {
        var showHistory: (() -> Void)?
        var showTransactionDetails: ((Transaction) -> Void)?
        var showSettings: (() -> Void)?
    }

    private let emptyAmountValue: String = "0"
    private let validator: StringValidator = .init(rules: [.validAmount])

    private lazy var decimalSeparator: String = {
        Locale.current.decimalSeparator ?? "."
    }()

    let flow: Flow

    private var cancelBag: Set<AnyCancellable> = []

    @Published var todayTransactions: [Transaction] = []
    @Published var currentAmount: String
    @Published private(set) var isAmountValid: Bool
    @Published var spentToday: Double
    @Published var allCategories: [Category] = []
    @Published var selectedCategory: Category?
    @Published var sheetToPresent: EnterAmount.Sheet = .none

    var categoryForEdit: Category?

    var lastCreatedTransaction: Transaction?

    private let container: Container

    var categoriesRepository: CategoriesRepository? {
        container.resolve(CategoriesRepository.self)
    }

    var transactionsRepository: TransactionsRepository? {
        container.resolve(TransactionsRepository.self)
    }

    init(container: Container, flow: Flow) {
        self.container = container
        self.flow = flow

        currentAmount = emptyAmountValue
        isAmountValid = validator.validate(emptyAmountValue)
        spentToday = 0

        let todayTransactionsPublisher = transactionsRepository?.todayTransactions

        todayTransactionsPublisher?
            .map { $0.reduce(Double(0)) { $0 + $1.amount } }
            .assign(to: \.spentToday, on: self)
            .store(in: &cancelBag)

        categoriesRepository?.allCategories
            .assign(to: \.allCategories, on: self)
            .store(in: &cancelBag)

        todayTransactionsPublisher?
            .assign(to: \.todayTransactions, on: self)
            .store(in: &cancelBag)

        $currentAmount
            .map { self.validator.validate($0) }
            .assign(to: \.isAmountValid, on: self)
            .store(in: &cancelBag)

        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in
                if self.currentAmount.hasSuffix(self.decimalSeparator) {
                    self.currentAmount = String(self.currentAmount.dropLast())
                }
            }
            .store(in: &cancelBag)
    }

    func handleButtonAction(_ action: KeyboardButton.ButtonAction) {
        currentAmount = EnterAmountKeyboardActionReducer.reduce(currentValue: currentAmount, action: action)
    }

    func addNewCategory(_ categoryName: String) {
        let category = Category(name: categoryName)

        guard let addedCategory = try? categoriesRepository?.add(category) else { return }

        selectedCategory = addedCategory

        Analytics.shared.log(.categoryCreated)
    }

    func addTransaction(for category: Category?, at transactionDate: Date?) {
        guard let amount = NumberFormatter.amountFormatter.number(from: currentAmount)?.doubleValue else {
            return
        }

        let date = transactionDate ?? Date()

        let transactionToAdd = Transaction(amount: amount, createdAt: date, category: category ?? Category.empty())

        lastCreatedTransaction = try? transactionsRepository?.add(transactionToAdd)

        currentAmount = emptyAmountValue
    }

    func editTransaction(_ transaction: Transaction) {
        try? transactionsRepository?.update(transaction)
    }

    func deleteTransaction(_ transaction: Transaction) {
        try? transactionsRepository?.delete(transaction)
    }

    func editCategory(_ category: Category) {
        try? categoriesRepository?.update(category)

        Analytics.shared.log(.categoryRenamed)
    }

    func deleteCategory(_ category: Category) {
        try? categoriesRepository?.delete(category)
    }

    func showHistory() {
        flow.showHistory?()
    }

    func showSettings() {
        flow.showSettings?()
    }

    func showTransactionDetails(_ transaction: Transaction) {
        flow.showTransactionDetails?(transaction)
    }
}
