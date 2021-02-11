//  Copyright © 2020 Storytelling Software. All rights reserved.
//

import Repositories
import ModalView
import Analytics
import ExpensoUI
import SwiftUI
import Domain
import Swinject

struct EnterAmount: View {
    private let keyboardTopPadding: CGFloat = 1

    @Environment(\.colorScheme) var colorScheme

    @EnvironmentObject var keyboardListener: KeyboardListener
    @EnvironmentObject var screenSizeProvider: ScreenSizeProvider

    @ObservedObject var viewModel: EnterAmountViewModel

    @State private var sheetPresented: Bool = false

    @State private var categorySelectionVisible: Bool = false

    @State private var newTransactionDate: Date?

    @State private var addCategoryModalVisible: Bool = false
    @State private var editCategoryModalVisible: Bool = false

    @State private var addCommentModalVisible: Bool = false
    @State private var commentDetailsModalVisible: Bool = false

    private var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            EnterAmountHeader(historyButtonAction: onHistoryButtonTapped,
                              settingsButtonAction: onSettingsButtonTapped,
                              spentToday: $viewModel.spentToday)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            TransactionsList(
                items: viewModel.todayTransactions,
                onDelete: deleteTransaction(_:),
                onSelected: transactionSelected(_:))

            EnteredAmountBar(categorySelectionVisible: $categorySelectionVisible, displayedAmount: $viewModel.currentAmount, transactionDateTime: $newTransactionDate, onSelectDate: onSelectDateTime)
                .fixedSize(horizontal: false, vertical: true)
                .animation(nil)

            Group {
                if categorySelectionVisible {
                    SelectCategory(categories: $viewModel.allCategories,
                                   selectedCategory: $viewModel.selectedCategory,
                                   onButtonTapped: onButtonTapped(_:),
                                   onCategoryAdd: onCategoryAdd,
                                   editActionTapped: onEditCategory(_:),
                                   deleteActionTapped: onDeleteCategory(_:))
                        .environmentObject(screenSizeProvider)
                } else {
                    OnscreenKeyboard(enterButtonEnabled: viewModel.isAmountValid,
                                     onButtonTapped: onButtonTapped(_:))
                        .environmentObject(screenSizeProvider)
                }
            }
            .layoutPriority(10)
            .transition(.opacity)
            .background(ExpensoUI.Asset.Color.Keyboard.background.color)
        }
        .background(Background())
        .edgesIgnoringSafeArea(.bottom)
        .modalView(visible: $addCategoryModalVisible, contentTransition: .move(edge: .bottom)) {
            createNewCategory()
        }
        .modalView(visible: $editCategoryModalVisible, contentTransition: .move(edge: .bottom), onDismiss: editCategoryDismissed) {
            editCategory()
        }
        .modalView(visible: $addCommentModalVisible, contentTransition: .move(edge: .bottom), onDismiss: addCommentBarDismissed) {
            AddCommentBar(isPresented: $addCommentModalVisible,
                          onAdd: {
                            commentDetailsModalVisible = true
                          })
                .padding(.bottom, bottomSafeAreaInset)
                .background(ExpensoUI.Asset.Color.AddCommentBar.background.color)
        }
        .modalView(visible: $commentDetailsModalVisible, contentTransition: .move(edge: .bottom)) {
            addComment()
                .environmentObject(keyboardListener)
        }
        .sheet(isPresented: $sheetPresented) {
            sheetView()
                .environmentObject(keyboardListener)
                .environment(\.colorScheme, colorScheme)
        }
    }

    private func onButtonTapped(_ action: KeyboardButton.ButtonAction) {
        withAnimation {
            switch action {
            case .enter:
                onEnterTapped()
            case .back:
                categorySelectionVisible = false
            default:
                viewModel.handleButtonAction(action)
            }
        }
    }

    private func onHistoryButtonTapped() {
        viewModel.showHistory()
    }

    private func onSettingsButtonTapped() {
        Analytics.shared.log(.settings)

        viewModel.showSettings()
    }

    private func onEnterTapped() {
        if categorySelectionVisible {
            Analytics.shared.log(.categorySelected(noCategory: viewModel.selectedCategory == nil))

            viewModel.addTransaction(for: viewModel.selectedCategory, at: newTransactionDate)

            Analytics.shared.log(.transactionCreated(isCustomDate: newTransactionDate != nil))

            showModal(.addComment)

            viewModel.selectedCategory = nil
            newTransactionDate = nil

            FeedbackGenerator.notifySuccess()
        } else {
            Analytics.shared.log(.enteredAmount)
        }

        withAnimation(.linear(duration: 0.2)) {
            categorySelectionVisible.toggle()
        }
    }

    private func onCategoryAdd() {
        addCategoryModalVisible = true
    }

    private func onEditCategory(_ category: Domain.Category) {
        Analytics.shared.log(.editCategory)

        withAnimation {
            viewModel.categoryForEdit = category
            showModal(.editCategory)
        }
    }

    private func editCategoryDismissed() {
        viewModel.categoryForEdit = nil
    }

    private func editCategory(_ category: Domain.Category, with newName: String) {
        let category = Category(id: category.id, name: newName)

        viewModel.editCategory(category)
    }

    private func onDeleteCategory(_ category: Domain.Category) {
        Analytics.shared.log(.deleteCategory)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            withAnimation {
                viewModel.deleteCategory(category)
                viewModel.selectedCategory = nil
            }
        }
    }

    private func deleteTransaction(_ transaction: Domain.Transaction) {
        Analytics.shared.log(.deleteTransaction)

        viewModel.deleteTransaction(transaction)
    }

    private func transactionSelected(_ transaction: Expenso.Transaction) {
        Analytics.shared.log(.transactionDetails)

        viewModel.showTransactionDetails(transaction)
    }

    private func onSelectDateTime() {
        Analytics.shared.log(.selectDateTimeForNewTransaction)

        showSheet(.selectDateTime)
    }

    private func calendarDoneCallback(dates: [Date]) {
        if let date = dates.first,
           Calendar.current.compare(date, to: Date(), toGranularity: .minute) == .orderedSame {
            newTransactionDate = nil

            return
        }

        newTransactionDate = dates.first
    }

    private func addCommentBarDismissed() {
        Analytics.shared.log(.addCommentBarDismissed(.outsideTap))
    }
}

private extension EnterAmount {
    enum Modal {
        case none
        case addCategory
        case editCategory
        case addComment
        case commentDetails
    }

    func showModal(_ modal: Modal) {
        switch modal {
        case .none:
            break
        case .addCategory:
            addCategoryModalVisible = true
        case .editCategory:
            editCategoryModalVisible = true
        case .addComment:
            addCommentModalVisible = true
        case .commentDetails:
            commentDetailsModalVisible = true
        }
    }

    func createNewCategory() -> some View {
        CategoryDetails(isPresented: $addCategoryModalVisible) { title in
            viewModel.addNewCategory(title)
        }
    }

    func editCategory() -> some View {
        guard let category = viewModel.categoryForEdit else { return EmptyView().erasedToAnyView() }

        return CategoryDetails(isPresented: $editCategoryModalVisible,
                               text: category.name) { title in
            var mutableCategory = category
            mutableCategory.name = title

            viewModel.editCategory(mutableCategory)
        }.erasedToAnyView()
    }

    func addComment() -> some View {
        guard let transaction = viewModel.lastCreatedTransaction else { return EmptyView().erasedToAnyView() }

        return CommentDetails(isPresented: $commentDetailsModalVisible) { comment in
            var mutableTransaction = transaction
            mutableTransaction.comment = comment

            Analytics.shared.log(.addCommentForCreatedTransaction)

            viewModel.editTransaction(mutableTransaction)

            viewModel.lastCreatedTransaction = nil
        }.erasedToAnyView()
    }
}

extension EnterAmount {
    enum Sheet {
        case none
        case selectDateTime
    }
}

private extension EnterAmount {
    func showSheet(_ sheet: Sheet) {
        viewModel.sheetToPresent = sheet
        sheetPresented = true
    }

    func sheetView() -> some View {
        switch viewModel.sheetToPresent {
        case .none:
            return EmptyView().erasedToAnyView()
        case .selectDateTime:
            let startDate = Calendar.current.firstDayOfPreviousMonth ?? Date()
            return CalendarView(startDate: startDate, multipleSelection: false, timeSelectionAllowed: true, doneCallback: calendarDoneCallback(dates:))
                .background(Background())
                .erasedToAnyView()
        }
    }
}

struct EnterAmount_Previews: PreviewProvider {
    static var container: Container {
        let container = Container()

        container.register(CategoriesRepository.self) { _ in
            FakeCategoriesRepository()
        }
        container.register(TransactionsRepository.self) { _ in
            FakeTransactionsRepository()
        }

        return container
    }

    static var viewModel: EnterAmountViewModel = .init(container: container, flow: .init())

    static var previews: some View {
        Group {
            EnterAmount(viewModel: viewModel)
                .previewDevice(.init(stringLiteral: "iPhone Xs Max"))
                .environment(\.colorScheme, .light)

            EnterAmount(viewModel: viewModel)
                .previewDevice(.init(stringLiteral: "iPhone 7"))

            EnterAmount(viewModel: viewModel)
                .previewDevice(.init(stringLiteral: "iPhone 7 Plus"))
        }
    }
}
