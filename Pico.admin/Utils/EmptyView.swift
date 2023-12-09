//
//  EmptyView.swift
//  Pico.admin
//
//  Created by 최하늘 on 12/10/23.
//

import UIKit
import SnapKit

final class EmptyView: UIView {
    
    private let chuImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "magnifier"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let infomationLabel: UILabel = {
        let label = UILabel()
        label.text = "기록이 없습니다."
        label.textAlignment = .center
        return label
    }()
    
    // MARK: - initializer
    override init(frame: CGRect) {
        super.init(frame: frame)
        configBackgroundColor()
        addViews()
        makeConstraints()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func addViews() {
        addSubview([chuImageView, infomationLabel])
    }
    
    private func makeConstraints() {
        chuImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.equalTo(60)
            make.height.equalTo(120)
        }

        infomationLabel.snp.makeConstraints { make in
            make.top.equalTo(chuImageView.snp.bottom)
            make.centerX.equalToSuperview()
        }
    }
}
