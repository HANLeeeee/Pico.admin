//
//  AdminUserViewController.swift
//  Pico
//
//  Created by 최하늘 on 10/4/23.
//

import UIKit
import SnapKit
import RxCocoa
import RxSwift

final class AdminUserViewController: UIViewController {
    
    private lazy var sortedMenu: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        button.tintColor = .picoFontGray
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        return button
    }()
    
    private lazy var menu = UIMenu(title: "구분", children: [
        usingMenu, stopMenu, unsubscribedMenu, sortTypeMenu
    ])
    
    private lazy var usingMenu = UIAction(title: "사용중인 회원", image: UIImage(), handler: { [weak self] _ in
        guard let self = self else { return }
        selectedUserListType(to: .using)
    })
    
    private lazy var stopMenu = UIAction(title: "정지된 회원", image: UIImage(), handler: { [weak self] _ in
        guard let self = self else { return }
        selectedUserListType(to: .stop)
    })
    
    private lazy var unsubscribedMenu = UIAction(title: "탈퇴된 회원", image: UIImage(), handler: { [weak self] _ in
        guard let self = self else { return }
        selectedUserListType(to: .unsubscribe)
    })
    
    private lazy var sortTypeMenu = UIMenu(title: "정렬 구분", options: .displayInline, children: sortMenus)
    
    private lazy var sortMenus = UserSortType.allCases.map { sortType in
        return UIAction(title: sortType.name, image: UIImage(), handler: { [weak self] _ in
            guard let self = self else { return }
            sortedTypeBehavior.onNext(sortType)
            scrollToTop()
        })
    }
    
    private let textFieldView: CommonTextField = CommonTextField()
    
    private let searchButton: UIButton = {
        let button = UIButton()
        button.setTitle("검색", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .picoButtonFont
        button.backgroundColor = .picoBlue
        button.layer.cornerRadius = 10
        return button
    }()
    
    private let emptyView = EmptyView()
    private let tableView = UITableView()
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .picoBlue
        indicator.hidesWhenStopped = true
        indicator.isHidden = true
        return indicator
    }()
    
    private var viewModel: AdminUserViewModel
    private let disposeBag: DisposeBag = DisposeBag()
    
    private let viewDidLoadPublisher = PublishSubject<Void>()
    private let viewWillAppearPublisher = PublishSubject<Void>()
    private let sortedTypeBehavior = BehaviorSubject(value: UserSortType.dateDescending)
    private let userListTypeBehavior = BehaviorSubject(value: UserListType.using)
    private let searchButtonPublisher = PublishSubject<String>()
    private let tableViewOffsetPublisher = PublishSubject<Void>()
    private let refreshablePublisher = PublishSubject<Void>()
    private let unsubscribePublish = PublishSubject<User>()
    private let reusingPublish = PublishSubject<(User, UserListType)>()
    
    private let refreshControl = UIRefreshControl()
    private let padding: CGFloat = 10
    private var userListType: UserListType = .using
    
    init(viewModel: AdminUserViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.tappedDismissKeyboard()
        Loading.showLoading()
        addViews()
        makeConstraints()
        configRefresh()
        configButtons()
        configTableView()
        configTableViewDatasource()
        selectedUserListType(to: userListType)
        bind()
        viewDidLoadPublisher.onNext(())
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = true
        viewWillAppearPublisher.onNext(())
    }
    
    private func configRefresh() {
        refreshControl.addTarget(self, action: #selector(refreshTable), for: .valueChanged)
        refreshControl.tintColor = .picoBlue
    }
    
    private func configButtons() {
        textFieldView.removeAllButtonPublisher
            .withUnretained(self)
            .subscribe(onNext: { viewController, _ in
                viewController.searchButtonPublisher.onNext("")
                viewController.scrollToTop()
            })
            .disposed(by: disposeBag)
        
        textFieldView.textInputPublisher
            .withUnretained(self)
            .subscribe(onNext: { viewController, text in
                viewController.searchButtonPublisher.onNext(text)
                viewController.scrollToTop()
            })
            .disposed(by: disposeBag)
        
        searchButton.rx.tap
            .withUnretained(self)
            .subscribe(onNext: { viewController, _ in
                let text = viewController.textFieldView.textField.text
                viewController.searchButtonPublisher.onNext(text ?? "")
                viewController.scrollToTop()
            })
            .disposed(by: disposeBag)
    }
    
    private func configTableView() {
        tableView.showsVerticalScrollIndicator = false
        tableView.refreshControl = refreshControl
        tableView.register(cell: AdminUserTableViewCell.self)
        tableView.rowHeight = 80
        tableView.tableFooterView = activityIndicator
    }
    
    private func selectedUserListType(to userListType: UserListType) {
        self.userListType = userListType
        textFieldView.textField.placeholder = "\"\(userListType.name)\"의 이름을 입력하세요"
        userListTypeBehavior.onNext(userListType)
        scrollToTop()
    }
    
    private func bind() {
        let input = AdminUserViewModel.Input(
            viewDidLoad: viewDidLoadPublisher.asObservable(),
            viewWillAppear: viewWillAppearPublisher.asObservable(),
            sortedType: sortedTypeBehavior.asObservable(),
            userListType: userListTypeBehavior.asObservable(),
            searchButton: searchButtonPublisher.asObservable(),
            tableViewOffset: tableViewOffsetPublisher.asObservable(),
            refreshable: refreshablePublisher.asObservable(),
            isUnsubscribe: unsubscribePublish.asObservable(),
            isReusing: reusingPublish.asObservable()
        )
        let output = viewModel.transform(input: input)
        
        let mergedData = Observable.merge(output.resultToViewDidLoad, output.resultSearchUserList, output.resultPagingList)
        
        mergedData
            .bind(to: tableView.rx.items(cellIdentifier: AdminUserTableViewCell.reuseIdentifier, cellType: AdminUserTableViewCell.self)) { _, item, cell in
                guard let imageURL = item.imageURLs[safe: 0] else { return }
                cell.configData(imageUrl: imageURL, nickName: item.nickName, age: item.age, mbti: item.mbti, createdDate: item.createdDate)
            }
            .disposed(by: disposeBag)
        
        output.resultEmptyList
            .withUnretained(self)
            .subscribe(onNext: { viewController, isEmpty in
                if isEmpty {
                    viewController.view.addSubview([viewController.emptyView])
                    viewController.emptyView.snp.makeConstraints { [weak self] make in
                        guard let self else { return }
                        make.top.equalTo(textFieldView.snp.bottom).offset(100)
                        make.leading.trailing.bottom.equalToSuperview()
                    }
                } else {
                    viewController.view.addSubview([viewController.tableView])
                    viewController.tableView.snp.makeConstraints { [weak self] make in
                        guard let self else { return }
                        make.top.equalTo(textFieldView.snp.bottom).offset(padding)
                        make.leading.trailing.bottom.equalToSuperview()
                    }
                }
            })
            .disposed(by: disposeBag)
        
        output.needToReload
            .withUnretained(self)
            .subscribe(onNext: { viewController, _ in
                viewController.tableView.reloadData()
            })
            .disposed(by: disposeBag)
        
        output.resultUnsubscribe
            .withUnretained(self)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { viewController, _ in
                viewController.showCustomAlert(alertType: .onlyConfirm, titleText: "알림", messageText: "탈퇴가 완료되었습니다.", confirmButtonText: "확인", comfrimAction: {
                    viewController.viewWillAppearPublisher.onNext(())
                })
            })
            .disposed(by: disposeBag)
        
        output.resultReusing
            .withUnretained(self)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { viewController, _ in
                viewController.showCustomAlert(alertType: .onlyConfirm, titleText: "알림", messageText: "복구가 완료되었습니다.", confirmButtonText: "확인", comfrimAction: {
                    viewController.viewWillAppearPublisher.onNext(())
                })
            })
            .disposed(by: disposeBag)
    }
    
    private func scrollToTop() {
        if !viewModel.userList.isEmpty {
            let indexPath = IndexPath(row: 0, section: 0)
            tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        }
    }
    
    @objc private func refreshTable(_ refresh: UIRefreshControl) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if let currentSortType = try? self.sortedTypeBehavior.value() {
                self.sortedTypeBehavior.onNext(currentSortType)
            }
            refreshablePublisher.onNext(())
            refresh.endRefreshing()
        }
    }
}

// MARK: - 테이블뷰관련
extension AdminUserViewController {
    
    private func configTableViewDatasource() {
        var isOffsetPublisherCalled = false
        
        tableView.rx.didEndDragging
            .withUnretained(self)
            .subscribe { viewController, _ in
                let contentOffsetY = viewController.tableView.contentOffset.y
                let contentHeight = viewController.tableView.contentSize.height
                let boundsHeight = viewController.tableView.frame.size.height
                
                if contentOffsetY > contentHeight - boundsHeight && !viewController.activityIndicator.isAnimating {
                    if !isOffsetPublisherCalled {
                        viewController.activityIndicator.startAnimating()
                        viewController.tableViewOffsetPublisher.onNext(())
                        isOffsetPublisherCalled = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            viewController.activityIndicator.stopAnimating()
                        }
                    }
                } else {
                    isOffsetPublisherCalled = false
                }
            }
            .disposed(by: disposeBag)
        
        tableView.rx.itemSelected
            .withUnretained(self)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { viewController, indexPath in
                guard let user = viewController.viewModel.userList[safe: indexPath.row] else { return }
                let detailViewController = AdminUserDetailViewController(viewModel: AdminUserDetailViewModel(selectedUser: user))
                viewController.navigationController?.pushViewController(detailViewController, animated: true)
            })
            .disposed(by: disposeBag)
        
        tableView.rx.itemDeleted
            .withUnretained(self)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] viewController, indexPath in
                guard let self else { return }
                guard let user = viewController.viewModel.userList[safe: indexPath.row] else { return }
                
                switch userListType {
                case .using:
                    print("\(userListType)")
                    unsubscribeUser(to: user)
                case .stop, .unsubscribe:
                    print("\(userListType)")
                    reusingUser(to: user, in: userListType)
                }
            })
            .disposed(by: disposeBag)
    }
    
    private func unsubscribeUser(to user: User) {
        showCustomAlert(
            alertType: .canCancel,
            titleText: "탈퇴 알림",
            messageText: "탈퇴시키시겠습니까 ?",
            confirmButtonText: "탈퇴",
            comfrimAction: { [weak self] in
                guard let self else { return }
                unsubscribePublish.onNext(user)
            })
    }
    
    private func reusingUser(to user: User, in userListType: UserListType) {
        showCustomAlert(
            alertType: .canCancel,
            titleText: "복구 알림",
            messageText: "다시 복구시키시겠습니까 ?\n해당 회원은 다시 로그인할 수 있습니다.",
            confirmButtonText: "복구",
            comfrimAction: { [weak self] in
                guard let self else { return }
                reusingPublish.onNext((user, userListType))
            })
    }
}

// MARK: - UI 관련
extension AdminUserViewController {
    
    private func addViews() {
        view.addSubview([textFieldView, searchButton, sortedMenu])
    }
    
    private func makeConstraints() {
        textFieldView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(padding)
            make.leading.equalTo(padding)
            make.height.equalTo(40)
        }
        
        searchButton.snp.makeConstraints { make in
            make.centerY.equalTo(textFieldView)
            make.leading.equalTo(textFieldView.snp.trailing).offset(padding)
            make.width.equalTo(60)
            make.height.equalTo(35)
        }
        
        sortedMenu.snp.makeConstraints { make in
            make.centerY.equalTo(textFieldView)
            make.leading.equalTo(searchButton.snp.trailing).offset(padding)
            make.trailing.equalTo(view.safeAreaLayoutGuide).offset(-padding)
            make.width.equalTo(textFieldView.snp.height)
            make.height.equalTo(textFieldView.snp.height)
        }
    }
}
