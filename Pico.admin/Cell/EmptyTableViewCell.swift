//
//  EmptyTableViewCell.swift
//  Pico
//
//  Created by 최하늘 on 10/21/23.
//

import UIKit
import SnapKit

final class EmptyTableViewCell: UITableViewCell {
    
    private let chuImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "magnifier"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let emptyView = EmptyView()
    
    // MARK: - initializer
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        addViews()
        makeConstraints()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func addViews() {
        contentView.addSubview(emptyView)
    }
    
    private func makeConstraints() {
        emptyView.snp.makeConstraints { make in
            make.top.equalTo(50)
            make.centerX.equalToSuperview()
        }
    }
}
