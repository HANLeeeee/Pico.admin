//
//  AdminUserDetailViewModel.swift
//  Pico
//
//  Created by 최하늘 on 10/15/23.
//

import Foundation
import RxSwift
import RxCocoa
import FirebaseFirestore

final class AdminUserDetailViewModel: ViewModelType {
    struct Input {
        let viewDidLoad: Observable<Void>
        let selectedRecordType: Observable<RecordType>
        let refreshable: Observable<RecordType>
        let isUnsubscribe: Observable<Void>
        let isStop: Observable<DuringType>
    }
    
    struct Output {
        let needToFirstLoad: Observable<Void>
        let resultRecordType: Observable<RecordType>
        let needToRefresh: Observable<Void>
        let resultUnsubscribe: Observable<Void>
        let resultStop: Observable<Void>
        let needToRecordReload: Observable<Void>
    }
    
    private(set) var likeList: [Like.LikeInfo] = [] {
        didSet {
            isEmpty = likeList.isEmpty
            recordReloadPublisher.onNext(())
        }
    }
    private(set) var dislikeList: [Like.LikeInfo] = [] {
        didSet {
            recordReloadPublisher.onNext(())
        }
    }
    private(set) var reportList: [Report.ReportInfo] = [] {
        didSet {
            recordReloadPublisher.onNext(())
        }
    }
    private(set) var blockList: [Block.BlockInfo] = [] {
        didSet {
            recordReloadPublisher.onNext(())
        }
    }
    private(set) var paymentList: [Payment.PaymentInfo] = [] {
        didSet {
            recordReloadPublisher.onNext(())
        }
    }
    private let recordReloadPublisher = PublishSubject<Void>()
    
    var selectedUser: User
    var isEmpty: Bool = true
    private let pageSize = 7
    private var startLikeIndex = 0
    private var startDislikeIndex = 0
    private var startReportIndex = 0
    private var startBlockIndex = 0
    private var startPaymentIndex = 0
    
    init(selectedUser: User) {
        self.selectedUser = selectedUser
    }
    
    private func resetList() {
        startLikeIndex = 0
        likeList.removeAll()
        
        startDislikeIndex = 0
        dislikeList.removeAll()
        
        startReportIndex = 0
        reportList.removeAll()
        
        startBlockIndex = 0
        blockList.removeAll()
        
        startPaymentIndex = 0
        paymentList.removeAll()
    }
    
    func transform(input: Input) -> Output {
        let responseViewDidLoad = input.viewDidLoad
            .withUnretained(self)
            .flatMap { viewModel, _ -> Observable<Void> in
                let fetchLikes = viewModel.fetchLikes(likeType: .like)
                let fetchDislikes = viewModel.fetchLikes(likeType: .dislike)
                let fetchReports = viewModel.fetchReports()
                let fetchBlocks = viewModel.fetchBlocks()
                let fetchPayments = viewModel.fetchPayments()
                
                return Observable.zip(fetchLikes, fetchDislikes, fetchReports, fetchBlocks, fetchPayments)
                    .map { _ in return () }
            }
        
        let responseRecordType = input.selectedRecordType
            .withUnretained(self)
            .map { viewModel, recordType in
                switch recordType {
                case .like:
                    viewModel.isEmpty = viewModel.likeList.isEmpty
                case .dislike:
                    viewModel.isEmpty = viewModel.dislikeList.isEmpty
                case .report:
                    viewModel.isEmpty = viewModel.reportList.isEmpty
                case .block:
                    viewModel.isEmpty = viewModel.blockList.isEmpty
                case .payment:
                    viewModel.isEmpty = viewModel.paymentList.isEmpty
                }
                return recordType
            }
        
        let responseRefresh = input.refreshable
            .withUnretained(self)
            .flatMap { viewModel, recordType in
                print("refreshable")
                switch recordType {
                case .like:
                    return viewModel.fetchLikes(likeType: .like)
                case .dislike:
                    return viewModel.fetchLikes(likeType: .dislike)
                case .report:
                    return viewModel.fetchReports()
                case .block:
                    return viewModel.fetchBlocks()
                case .payment:
                    return viewModel.fetchPayments()
                }
            }
        
        let responseUnsubscribe = input.isUnsubscribe
            .withUnretained(self)
            .flatMap { viewModel, _ in
                let unsubscribe = Unsubscribe(createdDate: Date().timeIntervalSince1970, phoneNumber: viewModel.selectedUser.phoneNumber, user: viewModel.selectedUser)
                return FirestoreService.shared.saveDocumentRx(collectionId: .unsubscribe, documentId: viewModel.selectedUser.id, data: unsubscribe)
            }
            .withUnretained(self)
            .flatMap { viewModel, _ in
                return FirestoreService.shared.removeDocumentRx(collectionId: .users, documentId: viewModel.selectedUser.id)
            }
        
        let responseStop = input.isStop
            .withUnretained(self)
            .flatMap { viewModel, duringType in
                let stop = Stop(createdDate: Date().timeIntervalSince1970, during: duringType.number, phoneNumber: viewModel.selectedUser.phoneNumber, user: viewModel.selectedUser)
                return FirestoreService.shared.saveDocumentRx(collectionId: .stop, documentId: viewModel.selectedUser.id, data: stop)
            }
            .withUnretained(self)
            .flatMap { viewModel, _ in
                return FirestoreService.shared.removeDocumentRx(collectionId: .users, documentId: viewModel.selectedUser.id)
            }
        
        return Output(
            needToFirstLoad: responseViewDidLoad,
            resultRecordType: responseRecordType,
            needToRefresh: responseRefresh,
            resultUnsubscribe: responseUnsubscribe,
            resultStop: responseStop,
            needToRecordReload: recordReloadPublisher.asObservable()
        )
    }
    
    // MARK: - 좋아요 패치
    private func fetchLikes(likeType: Like.LikeType) -> Observable<Void> {
        let dbRef = Firestore.firestore()
            .collection(Collections.likes.name)
            .document(selectedUser.id)
        
        var likeIndex: Int = 0
        if likeType == .like {
            likeIndex = startLikeIndex
        } else if likeType == .dislike {
            likeIndex = startDislikeIndex
        }
        
        let endIndex = likeIndex + pageSize
        
        return Observable.create { [weak self] emitter in
            guard let self else { return Disposables.create() }
            DispatchQueue.global().async {
                dbRef.getDocument { [weak self] document, error in
                    guard let self else { return }
                    if let error {
                        emitter.onError(error)
                    }
                    if let document {
                        if let datas = try? document.data(as: Like.self).recivedlikes {
                            if likeType == .like {
                                let filtered = datas.filter { $0.likeType == likeType || $0.likeType == .matching }
                                let sorted = filtered.sorted {
                                    return $0.createdDate > $1.createdDate
                                }
                                if startLikeIndex > sorted.count - 1 {
                                    emitter.onNext(())
                                } else {
                                    let currentPageDatas: [Like.LikeInfo] = Array(sorted[startLikeIndex..<min(endIndex, sorted.count)])
                                    
                                    likeList.append(contentsOf: currentPageDatas)
                                    startLikeIndex += currentPageDatas.count
                                    emitter.onNext(())
                                }
                                
                            } else if likeType == .dislike {
                                let filtered = datas.filter { $0.likeType == likeType || $0.likeType == .matching }
                                let sorted = filtered.sorted {
                                    return $0.createdDate > $1.createdDate
                                }
                                if startDislikeIndex > sorted.count - 1 {
                                    emitter.onNext(())
                                } else {
                                    let currentPageDatas: [Like.LikeInfo] = Array(sorted[startDislikeIndex..<min(endIndex, sorted.count)])
                                    
                                    dislikeList.append(contentsOf: currentPageDatas)
                                    startDislikeIndex += currentPageDatas.count
                                    emitter.onNext(())
                                }
                            }
                        }
                    } else {
                        emitter.onNext(())
                    }
                    emitter.onCompleted()
                }
            }
            return Disposables.create()
        }
    }
    
    // MARK: - 신고 패치
    private func fetchReports() -> Observable<Void> {
        let dbRef = Firestore.firestore()
            .collection(Collections.users.name)
            .document(selectedUser.id)
            .collection(Collections.report.name)
            .document(selectedUser.id)
        
        let endIndex = startReportIndex + pageSize
        
        return Observable.create { [weak self] observer in
            guard let self else { return Disposables.create() }
            
            DispatchQueue.global().async {
                dbRef.getDocument { [weak self] document, error in
                    guard let self else { return }
                    if let error {
                        observer.onError(error)
                    }
                    
                    if let document {
                        if let datas = try? document.data(as: Report.self).recivedReport {
                            let sorted = datas.sorted {
                                return $0.createdDate > $1.createdDate
                            }
                            if startReportIndex > sorted.count - 1 {
                                observer.onNext(())
                            } else {
                                let currentPageDatas: [Report.ReportInfo] = Array(sorted[startReportIndex..<min(endIndex, sorted.count)])
                                reportList.append(contentsOf: currentPageDatas)
                                startReportIndex += currentPageDatas.count
                                observer.onNext(())
                            }
                        }
                    } else {
                        observer.onNext(())
                    }
                    observer.onCompleted()
                }
            }
            return Disposables.create()
        }
    }
    
    // MARK: - 차단 패치
    private func fetchBlocks() -> Observable<Void> {
        let dbRef = Firestore.firestore()
            .collection(Collections.users.name)
            .document(selectedUser.id)
            .collection(Collections.block.name)
            .document(selectedUser.id)
        
        let endIndex = startBlockIndex + pageSize
        
        return Observable.create { [weak self] observer in
            guard let self else { return Disposables.create() }
            
            DispatchQueue.global().async {
                dbRef.getDocument { [weak self] document, error in
                    guard let self else { return }
                    if let error {
                        observer.onError(error)
                    }
                    
                    if let document {
                        if let datas = try? document.data(as: Block.self).recivedBlock {
                            let sorted = datas.sorted {
                                return $0.createdDate > $1.createdDate
                            }
                            if startBlockIndex > sorted.count - 1 {
                                observer.onNext(())
                            } else {
                                let currentPageDatas: [Block.BlockInfo] = Array(sorted[startBlockIndex..<min(endIndex, sorted.count)])
                                blockList.append(contentsOf: currentPageDatas)
                                startBlockIndex += currentPageDatas.count
                                observer.onNext(())
                            }
                        }
                    } else {
                        observer.onNext(())
                    }
                    observer.onCompleted()
                }
            }
            return Disposables.create()
        }
    }
    
    // MARK: - 결제정보 패치
    private func fetchPayments() -> Observable<Void> {
        let dbRef = Firestore.firestore()
            .collection(Collections.payment.name)
            .document(selectedUser.id)
        
        let endIndex = startPaymentIndex + pageSize
        
        return Observable.create { [weak self] emitter in
            guard let self = self else { return Disposables.create()}
            
            DispatchQueue.global().async {
                dbRef.getDocument { [weak self] document, error in
                    guard let self else { return }
                    if let error {
                        emitter.onError(error)
                    }
                    
                    if let document {
                        if let datas = try? document.data(as: Payment.self).paymentInfos {
                            let sorted = datas.sorted {
                                return $0.purchasedDate > $1.purchasedDate
                            }
                            if startPaymentIndex > sorted.count - 1 {
                                emitter.onNext(())
                            } else {
                                let currentPageDatas: [Payment.PaymentInfo] = Array(sorted[startPaymentIndex..<min(endIndex, sorted.count)])
                                paymentList.append(contentsOf: currentPageDatas)
                                startPaymentIndex += currentPageDatas.count
                                emitter.onNext(())
                            }
                        }
                    } else {
                        emitter.onNext(())
                    }
                    emitter.onCompleted()
                }
            }
            return Disposables.create()
        }
    }
}
