import Foundation
import UIKit

@MainActor
enum InspectionPhotoDataNormalizer {
    private static let maximumDimension: CGFloat = 2_048
    private static let compressionQuality: CGFloat = 0.8

    static func normalizedData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else {
            return nil
        }

        return normalizedData(from: image)
    }

    static func normalizedData(from image: UIImage) -> Data? {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else {
            return nil
        }

        let scale = min(1, maximumDimension / longestSide)
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return renderedImage.jpegData(compressionQuality: compressionQuality)
    }
}
