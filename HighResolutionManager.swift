//
//  HighResolutionManager.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Paso 8: Auditoría de Rendimiento, Manejo de Documentos de Alta Resolución (48MP+) y PDFs.
//  Copyright © 2026. Todos los derechos reservados.
//

import Foundation
import CoreGraphics
import ImageIO
import PDFKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Administrador de alto rendimiento para el procesamiento de imágenes de ultra alta resolución (48MP+),
/// escaneos pesados y renderizado de documentos PDF con control de memoria (RAM).
final class HighResolutionManager: @unchecked Sendable {

    static let shared = HighResolutionManager()

    private init() {}

    // MARK: - Downsampling Eficiente con ImageIO

    /// Genera una imagen optimizada para visualización sin saturar la memoria RAM.
    /// Utiliza `CGImageSource` con `kCGImageSourceShouldCache: false` según las recomendaciones de Apple HIG.
    ///
    /// - Parameters:
    ///   - url: URL local del archivo de imagen.
    ///   - maxPixelDimension: Dimensión máxima (ancho o alto) para la miniatura/visualización (por defecto 2560px para pantallas Retina).
    /// - Returns: La imagen procesada o `nil` si falla.
    func loadOptimizedImage(from url: URL, maxPixelDimension: CGFloat = 2560) -> PlatformImage? {
        if url.pathExtension.lowercased() == "pdf" {
            return renderFirstPageOfPDF(at: url, targetWidth: maxPixelDimension)
        }

        return autoreleasepool {
            let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
                return nil
            }
            return createThumbnail(from: imageSource, maxPixelDimension: maxPixelDimension)
        }
    }

    /// Downsampling directo desde datos en memoria (`Data`).
    func downsample(imageData: Data, maxPixelDimension: CGFloat = 2560) -> PlatformImage? {
        return autoreleasepool {
            let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, options as CFDictionary) else {
                return nil
            }
            return createThumbnail(from: imageSource, maxPixelDimension: maxPixelDimension)
        }
    }

    /// Genera una miniatura aplanada en memoria a partir de una fuente de imagen `CGImageSource`.
    private func createThumbnail(from source: CGImageSource, maxPixelDimension: CGFloat) -> PlatformImage? {
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]

        guard let downsampledCG = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return PlatformImage.create(from: downsampledCG)
    }

    // MARK: - Procesamiento y Renderizado de Documentos PDF

    /// Renderiza la primera página de un documento PDF con resolución nítida para reconocimiento OCR.
    ///
    /// - Parameters:
    ///   - url: URL del archivo PDF en el sistema de archivos.
    ///   - targetWidth: Ancho objetivo para el renderizado vectorial a raster.
    /// - Returns: `PlatformImage` correspondiente a la página rasterizada.
    func renderFirstPageOfPDF(at url: URL, targetWidth: CGFloat = 2048) -> PlatformImage? {
        guard let pdfDocument = PDFDocument(url: url),
              let firstPage = pdfDocument.page(at: 0) else {
            return nil
        }

        let pageBounds = firstPage.bounds(for: .mediaBox)
        let scale = targetWidth / pageBounds.width
        let targetSize = CGSize(width: targetWidth, height: pageBounds.height * scale)

        #if canImport(AppKit)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }

        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(CGRect(origin: .zero, size: targetSize))

        context.scaleBy(x: scale, y: scale)
        firstPage.draw(with: .mediaBox, to: context)
        image.unlockFocus()
        return image

        #elseif canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            ctx.cgContext.translateBy(x: 0.0, y: targetSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            firstPage.draw(with: .mediaBox, to: ctx.cgContext)
        }
        #endif
    }

    // MARK: - Auditoría de Memoria RAM (En Vivo)

    /// Obtiene la memoria residente consumida actualmente por el proceso de PrivaLock en Megabytes (MB).
    /// Basado en llamadas del kernel Mach de Apple (`task_info`).
    func currentResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        } else {
            return 0.0
        }
    }
}
