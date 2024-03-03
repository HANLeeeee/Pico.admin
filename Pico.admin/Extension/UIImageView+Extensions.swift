//
//  UIImageView+Extensions.swift
//  Pico.admin
//
//  Created by 최하늘 on 2/29/24.
//

import UIKit

extension UIImageView {
    func setImage(url: URL) {
        DispatchQueue.global().async { [weak self] in
            if let data = try? Data(contentsOf: url) {
                if let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.image = image
                    }
                }
            }
        }
    }
    
    func setImage(urlString: String) {
        let cacheKey = NSString(string: urlString)
        if let cachedImage = ImageCacheService.shared.object(forKey: cacheKey) {
            self.image = cachedImage
            return
        }
        
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, response, err in
            if let _ = err {
                DispatchQueue.main.async { [weak self] in
                    self?.image = UIImage()
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                if let data = data, let image = UIImage(data: data) {
                    ImageCacheService.shared.setObject(image, forKey: cacheKey)
                    self?.image = image
                }
            }
        }.resume()
    }
}
