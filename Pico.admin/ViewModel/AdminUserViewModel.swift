//
//  AdminUserViewModel.swift
//  Pico
//
//  Created by 최하늘 on 10/6/23.
//

import Foundation
import RxSwift
import RxCocoa
import FirebaseFirestore

enum UserListType {
    case using
    case stop
    case unsubscribe
    
    var name: String {
        switch self {
        case .using:
            return "사용중인 회원"
        case .stop:
            return "정지된 회원"
        case .unsubscribe:
            return "탈퇴된 회원"
        }
    }
    
    var collectionId: Collections {
        switch self {
        case .using:
            return .users
        case .stop:
            return .stop
        case .unsubscribe:
            return .unsubscribe
        }
    }
}

enum UserSortType: CaseIterable {
    /// 가입일 내림차순
    case dateDescending
    /// 가입일 오름차순
    case dateAscending
    /// 이름 내림차순
    case nameDescending
    /// 이름 오름차순
    case nameAscending
    /// 나이 내림차순
    case ageDescending
    /// 나이 오름차순
    case ageAscending
    
    var name: String {
        switch self {
        case .dateDescending:
            return "가입일 내림차순"
        case .dateAscending:
            return "가입일 오름차순"
        case .nameDescending:
            return "이름 내림차순"
        case .nameAscending:
            return "이름 오름차순"
        case .ageDescending:
            return "나이 내림차순"
        case .ageAscending:
            return "나이 오름차순"
        }
    }
    
    var orderBy: (String, Bool) {
        switch self {
        case .dateDescending:
            return ("createdDate", true)
        case .dateAscending:
            return ("createdDate", false)
        case .nameDescending:
            return ("nickName", true)
        case .nameAscending:
            return ("nickName", false)
        case .ageDescending:
            return ("birth", true)
        case .ageAscending:
            return ("birth", false)
        }
    }
}

final class AdminUserViewModel: ViewModelType {
    
    struct Input {
        let viewDidLoad: Observable<Void>
        let viewWillAppear: Observable<Void>
        let sortedType: Observable<UserSortType>
        let userListType: Observable<UserListType>
        let searchButton: Observable<String>
        let tableViewOffset: Observable<Void>
        let refreshable: Observable<Void>
        let isUnsubscribe: Observable<User>
        let isReusing: Observable<(User, UserListType)>
    }
    
    struct Output {
        let resultToViewDidLoad: Observable<[User]>
        let resultSearchUserList: Observable<[User]>
        let resultPagingList: Observable<[User]>
        let resultEmptyList: Observable<Bool>
        let needToReload: Observable<Void>
        let resultUnsubscribe: Observable<Void>
        let resultReusing: Observable<Void>
    }
    
    private let itemsPerPage: Int = 20
    private var lastDocumentSnapshot: DocumentSnapshot?
    
    private(set) var userList: [User] = [] {
        didSet {
            isEmptyList.onNext(userList.isEmpty)
        }
    }
    
    private(set) var isEmptyList = PublishSubject<Bool>()
    private let reloadPublisher = PublishSubject<Void>()
    
    func transform(input: Input) -> Output {
        let merged = Observable.merge(input.viewDidLoad, input.viewWillAppear)
        
        let responseViewDidLoad = Observable.combineLatest(input.userListType, input.sortedType, merged)
            .withUnretained(self)
            .flatMap { viewModel, value in
                let (userListType, sortedType, _) = value
                return FirestoreService.shared.loadDocumentRx(collectionId: userListType.collectionId, dataType: User.self, orderBy: sortedType.orderBy, itemsPerPage: viewModel.itemsPerPage, lastDocumentSnapshot: nil)
            }
            .withUnretained(self)
            .map { viewModel, data in
                let (users, snapShot) = data
                viewModel.userList.removeAll()
                viewModel.userList = users
                viewModel.lastDocumentSnapshot = snapShot
                Loading.hideLoading()
                return viewModel.userList
            }
        
        _ = input.viewWillAppear
            .withUnretained(self)
            .subscribe(onNext: { viewModel, _ in
                viewModel.reloadPublisher.onNext(())
            })
        
        let sortedType = input.sortedType.asObservable()
        let userListType = input.userListType.asObservable()
        
        let responseTableViewPaging = input.tableViewOffset
            .withUnretained(self)
            .flatMap { (viewModel, _) -> Observable<[User]> in
                return sortedType
                    .map { sortType in
                        return userListType
                            .flatMap { usrListType in
                                return viewModel.loadNextPage(collectionId: usrListType.collectionId, orderBy: sortType.orderBy)
                            }
                    }
                    .switchLatest()
            }
            .map { users in
                self.userList = users
                return self.userList
            }
        
        let responseSearchButton = input.searchButton
            .withUnretained(self)
            .flatMap { viewModel, textFieldText in
                if textFieldText.isEmpty {
                    return Observable.just(viewModel.userList)
                } else {
                    return FirestoreService.shared.searchDocumentWithEqualFieldRx(collectionId: .users, field: "nickName", compareWith: textFieldText, dataType: User.self)
                }
            }
        
        let responseTextFieldSearch = input.searchButton
            .withUnretained(self)
            .flatMap { viewModel, textFieldText in
                return viewModel.searchListTextField(viewModel.userList, textFieldText)
            }
        
        let combinedResults = Observable.combineLatest(responseSearchButton, responseTextFieldSearch)
            .withUnretained(self)
            .map { viewModel, list in
                let (searchList, textFieldList) = list
                if searchList.count == viewModel.userList.count {
                    return viewModel.userList
                }
                let list = searchList + textFieldList
                let setList = Set(list)
                return Array(setList)
            }
        
        let responseUnsubscribe = input.isUnsubscribe
            .withUnretained(self)
            .flatMap { viewModel, user in
                let unsubscribe = Unsubscribe(createdDate: Date().timeIntervalSince1970, phoneNumber: user.phoneNumber, user: user)
                return FirestoreService.shared.saveDocumentRx(collectionId: .unsubscribe, documentId: user.id, data: unsubscribe)
                    .flatMap { _ in
                        return FirestoreService.shared.removeDocumentRx(collectionId: .users, documentId: user.id)
                    }
            }
        
        let responseReusing = input.isReusing
            .withUnretained(self)
            .flatMap { viewModel, data in
                let (user, userListType) = data
                return FirestoreService.shared.removeDocumentRx(collectionId: userListType.collectionId, documentId: user.id)
                    .flatMap { _ in
                        return FirestoreService.shared.saveDocumentRx(collectionId: .users, documentId: user.id, data: user)
                    }
            }
        
        return Output(
            resultToViewDidLoad: responseViewDidLoad,
            resultSearchUserList: combinedResults,
            resultPagingList: responseTableViewPaging,
            resultEmptyList: isEmptyList.asObservable(),
            needToReload: reloadPublisher.asObservable(),
            resultUnsubscribe: responseUnsubscribe,
            resultReusing: responseReusing
        )
    }
    
    private func searchListTextField(_ userList: [User], _ text: String) -> Observable<[User]> {
        return Observable.create { emitter in
            let users = userList.filter { sortedUser in
                sortedUser.nickName.contains(text)
            }
            emitter.onNext(users)
            return Disposables.create()
        }
    }
    
    private func loadNextPage(collectionId: Collections, orderBy: (String, Bool)) -> Observable<[User]> {
        let dbRef = Firestore.firestore()
        var query = dbRef.collection(collectionId.name)
            .order(by: orderBy.0, descending: orderBy.1)
            .limit(to: itemsPerPage)
        
        if let lastSnapshot = lastDocumentSnapshot {
            query = query.start(afterDocument: lastSnapshot)
        }
        
        return Observable.create { [weak self] emitter in
            guard let self = self else { return Disposables.create()}
            
            DispatchQueue.global().async {
                query.getDocuments { [weak self] snapshot, error in
                    guard let self = self else { return }
                    if let error = error {
                        emitter.onError(error)
                        return
                    }
                    guard let documents = snapshot?.documents else { return }
                    
                    if documents.isEmpty {
                        Loading.hideLoading()
                        return
                    }
                    
                    if lastDocumentSnapshot != documents.last {
                        lastDocumentSnapshot = documents.last
                        for document in documents {
                            if let data = try? document.data(as: User.self) {
                                userList.append(data)
                            }
                        }
                        emitter.onNext(userList)
                    }
                }
            }
            return Disposables.create()
        }
    }
}
