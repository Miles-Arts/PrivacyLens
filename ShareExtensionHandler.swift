//
//  ShareExtensionHandler.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Paso 7: Extensión de Compartir del Sistema (macOS y iOS).
//  Copyright © 2026. Todos los derechos reservados.
//

import Foundation
import CoreGraphics
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Controlador de la Extensión de Compartir (Share Extension) para procesar
/// imágenes directamente desde el menú contextual del sistema (Finder, Safari, Fotos).
final class ShareExtensionHandler {

    /// Instancia compartida del detector de privacidad local
    private let detector = PrivacyDetector()

    /// Instancia compartida del motor de redacción física
    private let engine = RedactionEngine()

    init() {}

    /// Extrae de forma asíncrona los datos de imagen desde los proveedores de ítems (`NSItemProvider`)
    /// recibidos a través del contexto de la extensión del sistema con soporte para downsampling.
    ///
    /// - Parameter itemProviders: Arreglo de proveedores de contenido compartidos por el sistema.
    /// - Returns: La imagen procesable como `PlatformImage`.
    @MainActor
    func extractImage(from itemProviders: [NSItemProvider]) async throws -> PlatformImage {
        for provider in itemProviders {
            // Comprueba si el proveedor contiene una imagen directa
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    _ = provider.loadDataRepresentation(for: .image) { data, error in
                        if let data = data {
                            continuation.resume(returning: data)
                        } else if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "PrivaLock.ShareExtension",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "No se pudieron extraer datos de la imagen."]
                            ))
                        }
                    }
                }

                if let image = HighResolutionManager.shared.downsample(imageData: data) ?? PlatformImage(data: data) {
                    return image
                }
            }
        }

        throw NSError(
            domain: "PrivaLock.ShareExtension",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "No se encontró ningún archivo de imagen compatible en los elementos compartidos."]
        )
    }

    /// Ejecuta el pipeline completo de protección rápida automática para extensiones:
    /// detecta rostros, textos sensibles y códigos QR, redacta destructivamente y elimina metadatos EXIF.
    ///
    /// - Parameters:
    ///   - image: La imagen original a redactar.
    ///   - style: Estilo de redacción a aplicar (por defecto barra negra).
    /// - Returns: La imagen redactada lista para compartir de forma segura.
    func fastAutoProtect(
        image: PlatformImage,
        style: RedactionStyle = .blackBar
    ) async throws -> (redactedImage: PlatformImage, detectedCount: Int) {
        // 1. Detección automática On-Device con Vision AI
        let regions = try await detector.detectPrivacyRegions(
            in: image,
            detectFaces: true,
            detectText: true,
            detectBarcodes: true
        )

        // 2. Redacción destructiva física a prueba de recuperación
        guard let cleanImage = engine.redactImage(
            image,
            regions: regions,
            style: style,
            isDestructiveFlatten: true
        ) else {
            throw NSError(
                domain: "PrivaLock.ShareExtension",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo generar la imagen aplanada."]
            )
        }

        return (cleanImage, regions.count)
    }
}
