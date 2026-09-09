//
//  TileImageProcessor.swift
//  MVK++ Phone App
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

/// Reproduces the web app's CSS tile filters in Core Image.
///
/// One shared instance for the whole app. The old code built a `CIContext`
/// per tile overlay — and a fresh overlay is created on every base-map
/// switch — so each switch leaked a Metal command queue and a texture cache.
enum TileImageProcessor {

    /// CSS filters operate on gamma-encoded sRGB values. Core Image
    /// linearises by default, which makes an inverted tile come out grey
    /// instead of dark — pinning the working colour space to sRGB is what
    /// makes the ported "Sötét" and "Halvány" layers match the web pixel for
    /// pixel.
    private static let context: CIContext = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        return CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
            .workingColorSpace: space as Any,
            .outputColorSpace: space as Any,
        ])
    }()

    private static let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Base-map tiles are opaque, so they re-encode as JPEG: roughly four
    /// times faster than PNG and half the bytes on disk. Encoding cost is the
    /// whole reason zooming used to stutter — a screenful of tiles is forty
    /// PNG encodes in the same second.
    private static let jpegQuality: CGFloat = 0.86

    /// Applies `filter` and returns re-encoded bytes, or `nil` if the tile
    /// could not be decoded (a 404 body, a truncated download).
    ///
    /// CSS filter order is significant — invert, then hue, then the colour
    /// controls — so the chain below mirrors the declaration exactly.
    static func apply(_ filter: TileFilter, to data: Data) -> Data? {
        guard var image = CIImage(data: data) else { return nil }

        if filter.invert {
            let step = CIFilter.colorInvert()
            step.inputImage = image
            guard let output = step.outputImage else { return nil }
            image = output
        }

        if filter.hueRotate != 0 {
            let step = CIFilter.hueAdjust()
            step.inputImage = image
            step.angle = Float(filter.hueRotate * .pi / 180)
            guard let output = step.outputImage else { return nil }
            image = output
        }

        if filter.brightness != 1 {
            // CSS brightness multiplies the channels; Core Image's own
            // `brightness` is additive, so a colour matrix does the job.
            let step = CIFilter.colorMatrix()
            step.inputImage = image
            let k = CGFloat(filter.brightness)
            step.rVector = CIVector(x: k, y: 0, z: 0, w: 0)
            step.gVector = CIVector(x: 0, y: k, z: 0, w: 0)
            step.bVector = CIVector(x: 0, y: 0, z: k, w: 0)
            step.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            guard let output = step.outputImage else { return nil }
            image = output
        }

        // `saturate` and `grayscale` are two ends of the same control: CSS
        // grayscale(g) equals a saturation of 1 − g.
        let saturation = filter.grayscale > 0 ? (1 - filter.grayscale) : filter.saturate
        if saturation != 1 || filter.contrast != 1 {
            let step = CIFilter.colorControls()
            step.inputImage = image
            step.saturation = Float(saturation)
            step.contrast = Float(filter.contrast)
            step.brightness = 0
            guard let output = step.outputImage else { return nil }
            image = output
        }

        return context.jpegRepresentation(
            of: image.cropped(to: image.extent),
            colorSpace: outputColorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: jpegQuality]
        )
    }

    /// Crops one quadrant (or sixteenth, or …) out of an ancestor tile and
    /// blows it up to full tile size.
    ///
    /// Used only when a tile cannot be fetched at all. A blurry map beats a
    /// white hole, which is what the rider saw before — "néha eltűnik" was
    /// this exact case.
    static func upscale(_ data: Data, ancestor: TileCoordinate, target: TileCoordinate) -> Data? {
        guard target.z > ancestor.z, let image = UIImage(data: data)?.cgImage else { return nil }

        let steps = target.z - ancestor.z
        let divisor = 1 << steps
        let side = CGFloat(image.width) / CGFloat(divisor)
        guard side >= 1 else { return nil }

        let offsetX = CGFloat(target.x - ancestor.x * divisor) * side
        let offsetY = CGFloat(target.y - ancestor.y * divisor) * side
        guard let quadrant = image.cropping(to: CGRect(x: offsetX, y: offsetY, width: side, height: side)) else {
            return nil
        }

        let size = CGSize(width: image.width, height: image.height)
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat.preferred()
            format.scale = 1
            format.opaque = true
            return format
        }())

        return renderer.image { _ in
            UIImage(cgImage: quadrant).draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: jpegQuality)
    }
}
