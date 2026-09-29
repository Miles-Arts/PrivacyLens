//
//  RedactionEngine.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Motor gráfico para el aplanado destructivo de píxeles y la eliminación de metadatos EXIF / GPS.
//  Copyright © 2026. Todos los derechos reservados.
//

import Foundation
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers

/// Estilo visual de redacción aplicado sobre las regiones sensibles.
enum RedactionStyle: String, CaseIterable, Identifiable, Sendable {
    /// Ocultamiento con rectángulo negro sólido puro (#000000) que destruye los píxeles originales.
    case blackBar = "Barra Negra (Clásica)"
    /// Ocultamiento con filtro de desenfoque gaussiano de alta intensidad irreversible.
    case blur = "Desenfoque Blur"
    /// Ocultamiento mediante pixelado destructivo de tipo mosaico de alta escala.
    case pixelate = "Pixelado (Mosaico)"

    /// Identificador único para iteración en vistas SwiftUI.
    var id: String { rawValue }

    /// Nombre del icono SF Symbols representativo del estilo.
    var iconName: String {
        switch self {
        case .blackBar: return "square.fill"
        case .blur: return "drop.fill"
        case .pixelate: return "checkerboard.rectangle"
        }
    }
}

/// Motor gráfico especializado en el aplanado físico de píxeles (destructive flattening)
/// y en la exportación higienizada sin metadatos de geolocalización o autoría.
///
/// ### Garantía de No Recuperación Forense:
/// Las regiones protegidas son sobrescritas en el contexto de mapa de bits (`CGContext`)
/// reemplazando los valores numéricos de los canales RGB originales. Esto imposibilita
/// la reversión de los datos mediante ajustes de contraste, brillo o histogramas.
final class RedactionEngine: @unchecked Sendable {

    /// Contexto de CoreImage reutilizable para transformaciones de filtros gráficos eficientes.
    private let ciContext = CIContext()

    /// Genera una nueva imagen aplanada sobrescribiendo físicamente las regiones marcadas.
    ///
    /// - Parameters:
    ///   - platformImage: Imagen de origen cargada en memoria.
    ///   - regions: Colección de regiones detectadas o agregadas manualmente.
    ///   - defaultStyle: Estilo gráfico predeterminado para regiones sin estilo específico.
    ///   - isDestructiveFlatten: Si es `true`, reemplaza irreversiblemente los bytes de los píxeles.
    /// - Returns: Nueva instancia de `PlatformImage` protegida o `nil` en caso de falla de asignación de memoria.
    nonisolated func redactImage(
        _ platformImage: PlatformImage,
        regions: [DetectedPrivacyRegion],
        style defaultStyle: RedactionStyle,
        isDestructiveFlatten: Bool = true
    ) -> PlatformImage? {
        guard let cgImage = platformImage.cgImageRepresentation else { return nil }

        guard isDestructiveFlatten else {
            // Si el aplanado destructivo está desactivado, retorna la imagen original
            return platformImage
        }

        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4 * width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)

        // 1. Dibuja la imagen original sobre el lienzo gráfico
        context.draw(cgImage, in: fullRect)

        // 2. Pre-genera la versión desenfocada completa si alguna región utiliza el estilo Blur
        var blurredCIImage: CIImage?
        let hasBlurRegions = regions.contains(where: { $0.isEnabled && ($0.customStyle ?? defaultStyle) == .blur })
        if hasBlurRegions {
            let ciImage = CIImage(cgImage: cgImage)
            if let filter = CIFilter(name: "CIGaussianBlur") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(25.0, forKey: kCIInputRadiusKey)
                if let output = filter.outputImage {
                    blurredCIImage = output.cropped(to: ciImage.extent)
                }
            }
        }

        // 3. Pre-genera la versión pixelada completa si alguna región utiliza el estilo Pixelado
        var pixelatedCIImage: CIImage?
        let hasPixelateRegions = regions.contains(where: { $0.isEnabled && ($0.customStyle ?? defaultStyle) == .pixelate })
        if hasPixelateRegions {
            let ciImage = CIImage(cgImage: cgImage)
            if let filter = CIFilter(name: "CIPixellate") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                let pixelScale = max(16.0, CGFloat(width) / 50.0)
                filter.setValue(pixelScale, forKey: kCIInputScaleKey)
                if let output = filter.outputImage {
                    pixelatedCIImage = output.cropped(to: ciImage.extent)
                }
            }
        }

        // 4. Aplica la redacción zona por zona sobre los píxeles reales de la imagen
        for region in regions where region.isEnabled {
            let effectiveStyle = region.customStyle ?? defaultStyle

            let rectInPixels = CGRect(
                x: region.boundingBox.origin.x * CGFloat(width),
                y: (1.0 - region.boundingBox.origin.y - region.boundingBox.size.height) * CGFloat(height),
                width: region.boundingBox.size.width * CGFloat(width),
                height: region.boundingBox.size.height * CGFloat(height)
            )

            switch effectiveStyle {
            case .blackBar:
                // Sobrescribe píxeles con negro puro (#000000) de forma destructiva
                context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
                context.fill(rectInPixels)

            case .blur:
                if let blurredCIImage,
                   let croppedCG = ciContext.createCGImage(blurredCIImage, from: rectInPixels) {
                    context.draw(croppedCG, in: rectInPixels)
                } else {
                    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
                    context.fill(rectInPixels)
                }

            case .pixelate:
                if let pixelatedCIImage,
                   let croppedCG = ciContext.createCGImage(pixelatedCIImage, from: rectInPixels) {
                    context.draw(croppedCG, in: rectInPixels)
                } else {
                    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1.0))
                    context.fill(rectInPixels)
                }
            }
        }

        // 5. Genera el bitmap final aplanado
        guard let finalCGImage = context.makeImage() else { return nil }
        return PlatformImage.create(from: finalCGImage)
    }

    /// Exporta los datos binarios de la imagen redactada despojándola de metadatos EXIF / GPS.
    ///
    /// - Parameters:
    ///   - platformImage: Imagen a exportar.
    ///   - format: Formato de archivo objetivo (`.jpeg` o `.png`).
    ///   - stripEXIF: Si es `true`, excluye completamente las coordenadas de geolocalización y marcas EXIF.
    /// - Returns: Búfer de datos binarios `Data` listo para guardar o compartir de forma privada.
    nonisolated func exportCleanImageData(
        _ platformImage: PlatformImage,
        format: UTType = .jpeg,
        stripEXIF: Bool = true
    ) -> Data? {
        guard let cgImage = platformImage.cgImageRepresentation else { return nil }

        let mutableData = NSMutableData()
        let typeIdentifier = format.identifier as CFString

        guard let destination = CGImageDestinationCreateWithData(mutableData, typeIdentifier, 1, nil) else {
            return nil
        }

        // Si stripEXIF es true, no pasamos el diccionario de propiedades de origen,
        // garantizando que las cabeceras EXIF, GPS, IPTC y TIFF queden vacías.
        CGImageDestinationAddImage(destination, cgImage, nil)

        if CGImageDestinationFinalize(destination) {
            return mutableData as Data
        }
        return nil
    }
}
