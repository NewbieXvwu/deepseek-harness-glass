import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Native image admission is deliberately Core-owned so panel selection, drag
/// and drop, and future paste inputs all face the same pre-prompt boundary.
/// File extensions are presentation metadata only; ImageIO determines the
/// decodable UTI from the file contents before the bytes are retained.
enum NativeImageAttachmentAdmission {
    struct AcceptedImage: Equatable {
        let mediaType: String
        let data: Data
        let pixelWidth: Int
        let pixelHeight: Int
    }

    enum Rejection: Equatable {
        case limitsUnavailable
        case tooManyImages
        case fileUnreadable
        case fileTooLarge
        case messageTooLarge
        case unsupportedContentType
        case unsupportedMediaType
        case invalidImage
        case dimensionsExceeded
        case pixelsExceeded
    }

    static func admit(
        url: URL,
        limits: ImageAttachmentLimits?,
        existingImageCount: Int,
        existingImageBytes: Int
    ) -> Result<AcceptedImage, Rejection> {
        guard let limits else { return .failure(.limitsUnavailable) }
        guard existingImageCount < limits.maxImagesPerMessage else { return .failure(.tooManyImages) }
        guard let declaredSize = fileSize(at: url) else { return .failure(.fileUnreadable) }
        guard declaredSize <= limits.maxImageBytes else { return .failure(.fileTooLarge) }
        guard safeSum(existingImageBytes, declaredSize) <= limits.maxMessageImageBytes else {
            return .failure(.messageTooLarge)
        }

        // Inspect from URL first. This parses magic bytes and container metadata
        // without trusting the filename or allocating a decoded bitmap.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rawType = CGImageSourceGetType(source) as String?,
              let type = UTType(rawType),
              type.conforms(to: .image),
              let mediaType = type.preferredMIMEType
        else { return .failure(.unsupportedContentType) }
        guard limits.mediaTypes.contains(where: { $0.caseInsensitiveCompare(mediaType) == .orderedSame }) else {
            return .failure(.unsupportedMediaType)
        }
        guard let dimensions = dimensions(of: source) else { return .failure(.invalidImage) }
        guard dimensions.width <= limits.maxImageDimension, dimensions.height <= limits.maxImageDimension else {
            return .failure(.dimensionsExceeded)
        }
        guard safeProduct(dimensions.width, dimensions.height) <= limits.maxImagePixels else {
            return .failure(.pixelsExceeded)
        }

        // Recheck size after opening to close the common replace-after-stat
        // race before retaining any file contents for the Host prompt.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .failure(.fileUnreadable)
        }
        guard data.count <= limits.maxImageBytes else { return .failure(.fileTooLarge) }
        guard safeSum(existingImageBytes, data.count) <= limits.maxMessageImageBytes else {
            return .failure(.messageTooLarge)
        }
        return .success(.init(
            mediaType: mediaType,
            data: data,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height
        ))
    }

    private static func fileSize(at url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true, let size = values?.fileSize, size >= 0 else { return nil }
        return size
    }

    private static func dimensions(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0
        else { return nil }
        return (width, height)
    }

    private static func safeSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }

    private static func safeProduct(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? Int.max : result.partialValue
    }
}
