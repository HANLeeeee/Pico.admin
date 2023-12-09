//
//  UIImage+Extensions.swift
//  Pico
//
//  Created by 최하늘 on 10/9/23.
//

import UIKit

extension UIImage {
    /// 이미지 비율에 맞춰서 가로 세로 높이 구하기
    func getRatio(height: CGFloat = 0, width: CGFloat = 0) -> CGFloat {
        let widthRatio = CGFloat(self.size.width / self.size.height)
        let heightRatio = CGFloat(self.size.height / self.size.width)
        
        if height != 0 {
            return height / heightRatio
        }
        if width != 0 {
            return width / widthRatio
        }
        return 0
    }
}
