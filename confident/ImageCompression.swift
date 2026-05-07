import UIKit

/// Resize + JPEG-encode helpers used before attaching an image to a chat
/// message. Vision models accept images in any reasonable size, but sending
/// the original camera resolution wastes Multipeer bandwidth and inflates
/// the prompt with no quality gain. 1024px on the longest edge at ~70%
/// quality is a well-known sweet spot for vision-LLM prompts.
enum ImageCompression {

    /// Default longest-edge bound for attached images.
    static let defaultMaxDimension: CGFloat = 1024
    static let defaultQuality: CGFloat = 0.7

    /// Returns the compressed JPEG data, or nil if rendering fails.
    static func compress(_ image: UIImage,
                         maxDimension: CGFloat = defaultMaxDimension,
                         quality: CGFloat = defaultQuality) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1.0
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // we already chose pixel dimensions
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}
