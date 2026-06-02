import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import AppKit

/// Convertit n'importe quelle image en icône AWTRIX : GIF 8×8 aplati sur fond noir.
/// Le GIF est choisi car le décodeur JPEG embarqué d'AWTRIX échoue sur les petits JPG.
enum IconConverter {

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Dessine l'image en 8×8 sur fond noir, sans lissage (rendu pixel art).
    static func render8x8(_ image: CGImage, size: Int = 8) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }

    static func encodeGIF(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.gif.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// GIF prêt pour AWTRIX : un GIF (souvent animé) est conservé tel quel, le reste est converti.
    static func awtrixGIF(from data: Data) -> Data? {
        if data.starts(with: [0x47, 0x49, 0x46]) { return data } // "GIF"
        return makeAwtrixIcon(from: data)?.gif
    }

    /// Pipeline complet : données image brutes → (GIF prêt pour AWTRIX, aperçu agrandi).
    static func makeAwtrixIcon(from data: Data) -> (gif: Data, preview: NSImage)? {
        guard let cg = decode(data),
              let small = render8x8(cg),
              let gif = encodeGIF(small) else { return nil }
        let preview = NSImage(cgImage: small, size: NSSize(width: 8, height: 8))
        return (gif, preview)
    }
}
