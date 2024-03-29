//
//  AdminUserDetailViewController.swift
//  Pico
//
//  Created by 최하늘 on 10/12/23.
//

import UIKit
import SnapKit
import RxSwift

struct UserImage {
    static let height: CGFloat = UIScreen.main.bounds.height * 0.6
}

final class AdminUserDetailViewController: UIViewController {
    
    private let topView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    private let backButton: UIButton = {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let backImage = UIImage(systemName: "chevron.left", withConfiguration: imageConfig)
        let button = UIButton(type: .system)
        button.setImage(backImage, for: .normal)
        button.tintColor = .picoBlue
        return button
    }()
    
    private let actionSheetButton: UIButton = {
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let backImage = UIImage(systemName: "ellipsis", withConfiguration: imageConfig)
        let button = UIButton(type: .system)
        button.setImage(backImage, for: .normal)
        button.tintColor = .picoBlue
        return button
    }()
    
    private let actionSheetController = UIAlertController()
    private let stopSheetController = UIAlertController()
    
    private let tableView: UITableView = UITableView()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .picoBlue
        indicator.hidesWhenStopped = true
        indicator.isHidden = true
        return indicator
    }()

    private var viewModel: AdminUserDetailViewModel
    private let disposeBag: DisposeBag = DisposeBag()
    
    private let viewDidLoadPublish = PublishSubject<Void>()
    private let selectedRecordTypePublish = PublishSubject<RecordType>()
    private let refreshablePublish = PublishSubject<RecordType>()
    private let unsubscribePublish = PublishSubject<Void>()
    private let stopPublish = PublishSubject<DuringType>()
    private let cellRecordTypePublish = PublishSubject<RecordType>()
    
    private var currentRecordType: RecordType = .matching {
        didSet {
            reloadRecordSection()
        }
    }
    
    init(viewModel: AdminUserDetailViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.configBackgroundColor()
        view.tappedDismissKeyboard()
        addViews()
        makeConstraints()
        configTableView()
        configButtons()
        configActionSheet()
        configStopSheet()
        bind()
        viewDidLoadPublish.onNext(())
    }
    
    private func configTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(cell: DetailUserImageTableViewCell.self)
        tableView.register(cell: DetailUserInfoTableViewCell.self)
        tableView.register(cell: RecordHeaderTableViewCell.self)
        tableView.register(cell: AdminUserTableViewCell.self)
        tableView.register(cell: EmptyTableViewCell.self)
        tableView.separatorStyle = .none
        tableView.tableFooterView = activityIndicator
    }
    
    private func configButtons() {
        backButton.addTarget(self, action: #selector(tappedBackButton), for: .touchUpInside)
        actionSheetButton.addTarget(self, action: #selector(tappedActionSheetButton), for: .touchUpInside)
    }
    
    @objc private func tappedBackButton(_ sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
    @objc private func tappedActionSheetButton(_ sender: UIButton) {
        self.present(actionSheetController, animated: true)
    }
    
    private func configActionSheet() {
        let actionStop = UIAlertAction(title: "정지", style: .destructive) { [weak self] _ in
            guard let self else { return }
            present(stopSheetController, animated: true)
        }
        actionSheetController.addAction(actionStop)
        
        let actionUnsubscribe = UIAlertAction(title: "탈퇴", style: .destructive) { [weak self] _ in
            guard let self else { return }
            showUnsubscribeAlert()
        }
        actionSheetController.addAction(actionUnsubscribe)
        
        let actionCancel = UIAlertAction(title: "취소", style: .cancel, handler: nil)
        actionSheetController.addAction(actionCancel)
    }
    
    private func configStopSheet() {
        for during in DuringType.allCases {
            let action = UIAlertAction(title: "\(during.name)", style: .destructive) { [weak self] _ in
                guard let self else { return }
                showStopAlert(duringType: during)
            }
            stopSheetController.addAction(action)
        }
        
        let actionCancel = UIAlertAction(title: "취소", style: .cancel, handler: nil)
        stopSheetController.addAction(actionCancel)
    }
    
    private func showStopAlert(duringType: DuringType) {
        showCustomAlert(
            alertType: .canCancel,
            titleText: "정지 알림",
            messageText: "\(duringType.name) 정지시키시겠습니까 ?",
            confirmButtonText: "정지",
            comfrimAction: { [weak self] in
                guard let self else { return }
                stopPublish.onNext(duringType)
            })
    }
    
    private func showUnsubscribeAlert() {
        showCustomAlert(
            alertType: .canCancel,
            titleText: "탈퇴 알림",
            messageText: "탈퇴시키시겠습니까 ?",
            confirmButtonText: "탈퇴",
            comfrimAction: { [weak self] in
                guard let self else { return }
                unsubscribePublish.onNext(())
            })
    }
    
    private func bind() {
        let input = AdminUserDetailViewModel.Input(
            viewDidLoad: viewDidLoadPublish.asObservable(),
            selectedRecordType: selectedRecordTypePublish.asObservable(),
            refreshable: refreshablePublish.asObservable(),
            isUnsubscribe: unsubscribePublish.asObservable(),
            isStop: stopPublish.asObservable()
        )
        let output = viewModel.transform(input: input)
        
        output.needToFirstLoad
            .withUnretained(self)
            .subscribe { viewController, _ in
                print("viewController.viewModel.matchingList \(viewController.viewModel.matchingList.count)")
                print("viewController.viewModel.reportList \(viewController.viewModel.reportList.count)")
            }
            .disposed(by: disposeBag)
        
        output.resultRecordType
            .withUnretained(self)
            .subscribe { viewController, recordType in
                print("selectedRecordType \(recordType)")
                viewController.currentRecordType = recordType
                viewController.scrollToRow()
            }
            .disposed(by: disposeBag)
        
        output.needToRefresh
            .withUnretained(self)
            .subscribe { viewController, _ in
                print("viewController 리프레시 도착")
            }
            .disposed(by: disposeBag)
        
        output.resultUnsubscribe
            .withUnretained(self)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { viewController, _ in
                viewController.showCustomAlert(alertType: .onlyConfirm, titleText: "알림", messageText: "탈퇴가 완료되었습니다.", confirmButtonText: "확인", comfrimAction: {
                    viewController.navigationController?.popViewController(animated: true)
                })
            })
            .disposed(by: disposeBag)
        
        output.resultStop
            .withUnretained(self)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { viewController, _ in
                viewController.showCustomAlert(alertType: .onlyConfirm, titleText: "알림", messageText: "정지가 완료되었습니다.", confirmButtonText: "확인", comfrimAction: {
                    viewController.navigationController?.popViewController(animated: true)
                })
            })
            .disposed(by: disposeBag)
        
        output.needToRecordReload
            .withUnretained(self)
            .subscribe(onNext: { viewController, _ in
                viewController.reloadRecordSection()
            })
            .disposed(by: disposeBag)
        
        cellRecordTypePublish
            .withUnretained(self)
            .subscribe(onNext: { viewController, recordType in
                viewController.selectedRecordTypePublish.onNext(recordType)
            })
            .disposed(by: disposeBag)
    }
    
    private func reloadRecordSection() {
        let emptyIndex: Int = TableViewCase.empty.rawValue
        let recordIndex: Int = TableViewCase.record.rawValue
        tableView.reloadSections(IndexSet(emptyIndex...recordIndex), with: .none)
        activityIndicator.stopAnimating()
    }
    
    private func scrollToRow() {
        let indexPath = IndexPath(row: 0, section: 1)
        tableView.scrollToRow(at: indexPath, at: .top, animated: true)
    }
}

extension AdminUserDetailViewController: UITableViewDelegate, UITableViewDataSource {
    enum TableViewCase: Int, CaseIterable {
        case image, info
        case recordHeader
        case empty
        case record
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let tableViewCase = TableViewCase.allCases[safe: section] else { return 0 }
        
        switch tableViewCase {
        case .image, .info, .recordHeader:
            return 1
        case .empty:
            return viewModel.isEmpty ? 1 : 0
        case .record:
            switch currentRecordType {
            case .matching:
                return viewModel.matchingList.count
            case .like:
                return viewModel.likeList.count
            case .dislike:
                return viewModel.dislikeList.count
            case .report:
                return viewModel.reportList.count
            case .block:
                return viewModel.blockList.count
            case .payment:
                return viewModel.paymentList.count
            }
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return TableViewCase.allCases.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let tableViewCase = TableViewCase.allCases[safe: indexPath.section] else { return UITableViewCell()}
        
        switch tableViewCase {
        // MARK: - image
        case .image:
            let cell = tableView.dequeueReusableCell(forIndexPath: indexPath, cellType: DetailUserImageTableViewCell.self)
            cell.config(images: viewModel.selectedUser.imageURLs)
            cell.selectionStyle = .none
            return cell
            
        // MARK: - info
        case .info:
            let cell = tableView.dequeueReusableCell(forIndexPath: indexPath, cellType: DetailUserInfoTableViewCell.self)
            cell.config(user: viewModel.selectedUser)
            cell.selectionStyle = .none
            return cell
            
        // MARK: - recordHeader
        case .recordHeader:
            let cell = tableView.dequeueReusableCell(forIndexPath: indexPath, cellType: RecordHeaderTableViewCell.self)
            cell.config(publisher: cellRecordTypePublish)
            cell.selectionStyle = .none
            return cell
            
        // MARK: - empty
        case .empty:
            let cell = tableView.dequeueReusableCell(forIndexPath: indexPath, cellType: EmptyTableViewCell.self)
            cell.selectionStyle = .none
            return cell
            
        // MARK: - record
        case .record:
            let cell = tableView.dequeueReusableCell(forIndexPath: indexPath, cellType: AdminUserTableViewCell.self)
            
            switch currentRecordType {
            // 매칭기록
            case .matching:
                guard let user = viewModel.matchingList[safe: indexPath.row] else { return UITableViewCell() }
                cell.configData(recordType: .matching, imageUrl: user.imageURL, nickName: user.nickName, age: user.age, mbti: user.mbti, createdDate: user.createdDate)
                
            // 좋아요기록
            case .like:
                guard let user = viewModel.likeList[safe: indexPath.row] else { return UITableViewCell() }
                cell.configData(recordType: .like, imageUrl: user.imageURL, nickName: user.nickName, age: user.age, mbti: user.mbti, createdDate: user.createdDate)
                
            // 싫어요기록
            case .dislike:
                guard let user = viewModel.dislikeList[safe: indexPath.row] else { return UITableViewCell() }
                cell.configData(recordType: .dislike, imageUrl: user.imageURL, nickName: user.nickName, age: user.age, mbti: user.mbti, createdDate: user.createdDate)
                
            // 신고기록
            case .report:
                guard let user = viewModel.reportList[safe: indexPath.row] else { return UITableViewCell() }
                cell.configData(recordType: .report, imageUrl: user.imageURL, nickName: user.nickName, age: user.age, mbti: user.mbti, createdDate: user.createdDate, reportReason: user.reason)
            
            // 차단기록
            case .block:
                guard let user = viewModel.blockList[safe: indexPath.row] else { return UITableViewCell() }
                cell.configData(recordType: .block, imageUrl: user.imageURL, nickName: user.nickName, age: user.age, mbti: user.mbti, createdDate: user.createdDate)
            
            // 결제기록
            case .payment:
                guard let payment = viewModel.paymentList[safe: indexPath.row] else { return UITableViewCell() }
                cell.configData(recordType: .payment, payment: payment)
            }
            
            cell.selectionStyle = .none
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let tableViewCase = TableViewCase.allCases[safe: indexPath.section] else { return 0 }
        
        switch tableViewCase {
        case .image:
            return UserImage.height
        case .info:
            return UITableView.automaticDimension
        case .recordHeader:
            return 70
        case .empty:
            return 280
        case .record:
            return 80
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y
        let maxAlpha = 0.8
        let maxHeight = UserImage.height
        
        switch offset {
        case ...0:
            topView.backgroundColor = .clear
        case 1...maxHeight:
            let alpha = offset * maxAlpha / maxHeight
            topView.backgroundColor = .secondarySystemBackground.withAlphaComponent(alpha)
        default:
            topView.backgroundColor = .secondarySystemBackground.withAlphaComponent(maxAlpha)
        }
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let offset = scrollView.contentOffset.y
        let contentHeight = tableView.contentSize.height
        let scrollViewHeight = scrollView.frame.size.height
        let size = contentHeight - scrollViewHeight
        if offset > size && !activityIndicator.isAnimating {
            activityIndicator.startAnimating()
            refreshablePublish.onNext(currentRecordType)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                activityIndicator.stopAnimating()
            }
        }
    }
}

extension AdminUserDetailViewController {
    private func addViews() {
        view.addSubview([tableView, topView])
        topView.addSubview([backButton, actionSheetButton])
    }
    
    private func makeConstraints() {
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        topView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(50)
        }
        
        backButton.snp.makeConstraints { make in
            make.top.leading.equalToSuperview()
            make.width.height.equalTo(topView.snp.height)
        }
        
        actionSheetButton.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview()
            make.width.height.equalTo(backButton.snp.height)
        }
    }
}
