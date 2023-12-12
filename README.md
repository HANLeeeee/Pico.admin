# PICO ver.관리자


<img src = "https://github.com/HANLeeeee/Pico.admin/assets/74815957/51b4373a-406b-42b5-854f-674f312a6f95" width=200>


<br/><br/>

## 📌 프로젝트 소개
> 2023.10.05 ~ 2023.10.20 (2주간) <br/>
- [Pico](https://github.com/HANLeeeee/Pico) 의 회원 및 신고를 관리하는 APP

<br/><br/>

## 📌 기능 소개
- 회원 목록 및 신고 목록을을 확인할 수 있다.
- 사용중 / 탈퇴된 회원을 구분하여 확인할 수 있다.
- 가입일, 이름, 나이 순으로 정렬할 수 있다.
- 이름을 입력하여 검색할 수 있다.
- 회원의 디테일 정보를 확인하고 신고/차단/좋아요/결제 기록을 확인할 수 있다.
- 관리자가 직접 회원을 탈퇴할 수 있다.


<br/><br/>


##  📌 구현 내용
<details>
<summary><h3>CodeBase로 오토레이아웃 구현</h3></summary>
  
- Snapkit 라이브러리 사용하여 오토레이아웃을 구현하였습니다.
- 잊을 수 있는 translatesAutoresizingMaskIntoConstraints 및 isActive 를 생략하면서 간결한 코드를 작성할 수 있었습니다.

```swift
textFieldView.snp.makeConstraints { make in
    make.top.equalTo(view.safeAreaLayoutGuide).offset(padding)
    make.leading.equalTo(padding)
    make.height.equalTo(40)
}
```
<br/>

- remakeConstraints 나 updateConstraints 를 사용하여 쉽게 제약조건을 수정할 수 있었습니다.
```swift
sectionView.snp.remakeConstraints { make in
    make.top.equalTo(moreButton.snp.bottom).offset(20)
    make.leading.trailing.equalTo(0)
    make.height.equalTo(10)
    make.bottom.equalTo(-10)
}
```

<br/>

</details>

<details>
<summary><h3>RxCocoa와 RxSwift 사용하여 MVVM 적용</h3></summary>
  
- ViewModelType 프로토콜을 생성했습니다.
- Input: viewDidLoad, TextField 입력, Button 클릭 등의 이벤트를 정의했습니다.
- Output: TableView reload, Label 텍스트 업데이트 등 UI 업데이트를 정의했습니다.
- Input은 뷰로 들어오는 데이터를 캡슐화하고 Output은 뷰에 보내는 데이터를 캡슐화했습니다.
```swift
protocol ViewModelType {
    associatedtype Input
    associatedtype Output
    
    func transform(input: Input) -> Output
}
```
<b>ViewController</b>
- ViewModel에서 ViewModelType 프로토콜을 채택하여 Input, Output 구조를 사용했습니다.
- merge를 사용하여 여러개의 옵저버블을 하나로 합쳐 하나의 옵저버블을 방출하였습니다.
- combineLatest을 사용하여 userListType, sortedType과 merged의 최신 상태를 결합하여 방출하였습니다.
```swift
final class AdminUserViewModel: ViewModelType {
    
    struct Input {
        let viewDidLoad: Observable<Void>
        // ...(중략)
    }
    
    struct Output {
        let resultToViewDidLoad: Observable<[User]>
        // ...(중략)
    }
    
    func transform(input: Input) -> Output {
        let merged = Observable.merge(input.viewDidLoad, input.viewWillAppear)
        
        let responseViewDidLoad = Observable.combineLatest(input.userListType, input.sortedType, merged)
            .withUnretained(self)
            .flatMap { (viewModel, value) -> Observable<([User], DocumentSnapshot?)> in
                let (userListType, sortedType, _) = value
                return FirestoreService.shared.loadDocumentRx(collectionId: userListType.collectionId, dataType: User.self, orderBy: sortedType.orderBy, itemsPerPage: viewModel.itemsPerPage, lastDocumentSnapshot: nil)
            }
            .withUnretained(self)
            .map { viewModel, usersAndSnapshot in
                let (users, snapShot) = usersAndSnapshot
                viewModel.userList.removeAll()
                viewModel.lastDocumentSnapshot = snapShot
                viewModel.userList = users
                return viewModel.userList
            }
        // ...(중략)

        return Output(
            resultToViewDidLoad: responseViewDidLoad,
            // ...(중략)
        )
    }
}
```
<b>ViewModel</b>
- bind를 통해 ViewController와 ViewModel 사이의 상호작용을 설정했습니다.
- ViewController에서 dispose를 하여 하나의 데이터 스트림으로 연결했습니다.
```swift
private func bind() {
    let input = AdminUserViewModel.Input(
        viewDidLoad: viewDidLoadPublisher.asObservable(),
        // ...(중략)

    )
    let output = viewModel.transform(input: input)

    // ...(중략)

    output.needToReload
        .withUnretained(self)
        .subscribe(onNext: { viewController, _ in
            viewController.tableView.reloadData()
        })
        .disposed(by: disposeBag)
}
```



</details>

<details>
<summary><h3>페이징처리를 통한 무한스크롤</h3></summary>
  
- orderBy 튜플을 통해 0번째 요소 기준으로 내림차순/오름차순을 결정하고 페이지당 itemsPerPage 수로 가져올 항목을 제한하여 쿼리를 설정했습니다.
- DocumentSnapshot을 통해 쿼리에 이전 페이지의 마지막 문서 후부터 시작하도록 설정하여 페이지별로 데이터를 가져오게 했습니다.
- DispatchQueue.global().async를 사용하여 메소드를 호출하여 데이터를 가져오는 작업을 비동기 처리했습니다.
```swift
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
            // ...(중략)
                
                lastDocumentSnapshot = documents.last
                
                for document in documents {
                    if let data = try? document.data(as: User.self) {
                        userList.append(data)
                    }
                }
                emitter.onNext(userList)
            }
        }
        return Disposables.create()
    }
}
```

</details>


<details>
<summary><h3>컬럭션뷰셀에 따른 테이블뷰 섹션 리로드 구현</h3></summary>

- 테이블뷰셀에 컬렉션뷰를 구현하여 카테고리를 구현했습니다.
- 처음 컬렉션뷰셀이 클릭되었을 때 해당 이벤트를 통해 `onNext` 를 이용해 스트림을 전송하였습니다.
- 하지만 테이블뷰셀안에 있는 컬렉션뷰셀은 테이블뷰의 셀이 `dequeue` 될 때마다 매번 `subscribe`가 호출되어 새로운 스트림이 매번 중첩되는 것이 문제였습니다.
- 이를 해결하기 위해서 `PublishSubject`를 ViewController에서 생성 후 컬렉션뷰에 주입하고 이벤트는 ViewController에서 처리할 수 있게 했습니다.
- 이러한 구조를 통해 컬렉션뷰의 클릭 이벤트를 중첩없이 처리하고, 테이블뷰의 `dequeue`  시 `subscribe` 를 방지하여 코드의 일관성을 유지하였습니다.
  
```swift
case .recordHeader:
    let cell = tableView.dequeueReusableCell(forIndexPath: indexPath, cellType: RecordHeaderTableViewCell.self)
    cell.config(publisher: cellRecordTypePublish)
    cell.selectionStyle = .none
    return cell

case .record:
    let cell = tableView.dequeueReusableCell(forIndexPath: indexPath, cellType: AdminUserTableViewCell.self)    
    switch currentRecordType {
    case .report: // ...(중략)
    case .block: // ...(중략)
    case .like: // ...(중략)
    case .payment: // ...(중략)
    }
    return cell
```

```swift
func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    selectedCellIndex = indexPath.row
    collectionView.reloadData()
    
    guard let recordType = RecordType.allCases[safe: selectedCellIndex] else { return }
    collectionViewPublish?.onNext(recordType)
}
```


</details>


<br/><br/>

## 📌 개발 도구 및 기술 스택
<img src="https://img.shields.io/badge/swift-F05138?style=for-the-badge&logo=swift&logoColor=white"><img src="https://img.shields.io/badge/xcode-147EFB?style=for-the-badge&logo=xcode&logoColor=white"><img src="https://img.shields.io/badge/figma-F24E1E?style=for-the-badge&logo=figma&logoColor=white"><img src="https://img.shields.io/badge/github-181717?style=for-the-badge&logo=github&logoColor=white"><img src="https://img.shields.io/badge/Notion-000000?style=for-the-badge&logo=notion&logoColor=black"><img src="https://img.shields.io/badge/UIKit-2396F3?style=for-the-badge&logo=UIKit&logoColor=white"><img src="https://img.shields.io/badge/firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=white">
#### 개발환경
- Swift 5.9, Xcode 15.0.1, iOS 15.0 이상
#### 협업도구
- Figma, Github, Team Notion
#### 기술스택
- UIkit
- SwiftLint, RxSwift, SnapKit, Kingfisher
- FiresStore, Firebase Storage
- DarkMode

<br/><br/>
