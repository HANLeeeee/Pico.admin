//
//  ImageCacheService.swift
//  Pico.admin
//
//  Created by 최하늘 on 2/29/24.
//

import UIKit

final class ImageCacheService {
    static let shared = NSCache<NSString, UIImage>()
    
    private init() {
        
    }
}
