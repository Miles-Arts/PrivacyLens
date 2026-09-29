//
//  PrivacyDetector.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Motor de Visión Artificial On-Device para detección de rostros, textos OCR y códigos de barras.
//  Copyright © 2026. Todos los derechos reservados.
//

import Foundation
import Vision
import CoreGraphics

/// Tipos de elementos de privacidad detectables por Vision o añadidos manualmente.
enum PrivacyRegionType: String, CaseIterable, Identifiable, Sendable {
    /// Rostro humano detectado automáticamente.
    case face = "Rostro"
    /// Bloque de texto identificado mediante OCR.
    case text = "Texto (OCR)"
    /// Código QR o código de barras detectado.
    case barcode = "Código QR / Barras"
    /// Recuadro dibujado manualmente por el usuario.
    case manual = "Manual"

    /// Identificador único para iteración en SwiftUI.
    var id: String { rawValue }

    /// Icono de sistema (SF Symbols) asociado al tipo de región.
    var iconName: String {
        switch self {
        case .face: return "person.crop.artframe"
        case .text: return "text.viewfinder"
        case .barcode: return "qrcode.viewfinder"
        case .manual: return "hand.draw.fill"
        }
    }
}

/// Representa una región detectada o dibujada manualmente en la imagen con su caja delimitadora (Bounding Box) normalizada (0.0 a 1.0).
struct DetectedPrivacyRegion: Identifiable, Equatable, Sendable {
    /// Identificador único universal de la región.
    let id: UUID
    /// Tipo de elemento detectado (Rostro, Texto, Código, Manual).
    let type: PrivacyRegionType
    /// Categoría de sensibilidad específica (Email, Teléfono, C.C., Banco, etc.).
    let category: SensitiveDataCategory
    /// Coordenadas normalizadas estilo SwiftUI (Origen en la esquina superior izquierda, valores de 0.0 a 1.0).
    var boundingBox: CGRect
    /// Texto descriptivo o contenido detectado.
    let label: String?
    /// Indica si la protección de esta región está activa.
    var isEnabled: Bool
    /// Estilo de redacción personalizado opcional para este recuadro individual.
    var customStyle: RedactionStyle?

    /// Inicializa una región de privacidad.
    init(
        id: UUID = UUID(),
        type: PrivacyRegionType,
        category: SensitiveDataCategory = .generalText,
        boundingBox: CGRect,
        label: String? = nil,
        isEnabled: Bool = true,
        customStyle: RedactionStyle? = nil
    ) {
        self.id = id
        self.type = type
        self.category = category
        self.boundingBox = boundingBox
        self.label = label
        self.isEnabled = isEnabled
        self.customStyle = customStyle
    }
}

/// Actor concurrente encargado de ejecutar las solicitudes del framework Vision de forma asíncrona.
actor PrivacyDetector {

    /// Instancia interna del clasificador de datos sensibles.
    private let sensitiveDetector = SensitiveDataDetector()

    /// Procesa una imagen y devuelve todas las regiones de privacidad detectadas según las características activadas.
    /// - Parameters:
    ///   - platformImage: Imagen en formato nativo de la plataforma (`UIImage` en iOS / `NSImage` en macOS).
    ///   - detectFaces: Si es `true`, ejecuta la detección automática de rostros.
    ///   - detectText: Si es `true`, ejecuta el OCR y clasificación de texto sensible.
    ///   - detectBarcodes: Si es `true`, ejecuta la detección de códigos QR y de barras.
    /// - Returns: Arreglo de regiones `[DetectedPrivacyRegion]`.
    func detectPrivacyRegions(
        in platformImage: PlatformImage,
        detectFaces: Bool = true,
        detectText: Bool = true,
        detectBarcodes: Bool = true
    ) async throws -> [DetectedPrivacyRegion] {
        guard let cgImage = platformImage.cgImageRepresentation else {
            throw NSError(
                domain: "PrivacyDetector",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo extraer la matriz de imagen (CGImage)."]
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            var detectedRegions: [DetectedPrivacyRegion] = []
            var requests: [VNRequest] = []

            // 1. Solicitud condicional para detección de Rostros
            if detectFaces {
                let faceRequest = VNDetectFaceRectanglesRequest { request, error in
                    if let results = request.results as? [VNFaceObservation] {
                        for face in results {
                            let convertedBox = self.convertVisionRect(face.boundingBox, expandPercent: 0.05)
                            detectedRegions.append(
                                DetectedPrivacyRegion(
                                    type: .face,
                                    category: .generalText,
                                    boundingBox: convertedBox,
                                    label: "Rostro"
                                )
                            )
                        }
                    }
                }
                requests.append(faceRequest)
            }

            // 2. Solicitud condicional para OCR y Clasificación de Texto Sensible
            if detectText {
                let textRequest = VNRecognizeTextRequest { request, error in
                    if let results = request.results as? [VNRecognizedTextObservation] {
                        for textObs in results {
                            guard let topCandidate = textObs.topCandidates(1).first else { continue }
                            let rawText = topCandidate.string
                            // Margen de seguridad del 2.5% para cubrir caracteres altos y descendentes (g, j, p, q, tildes)
                            let convertedBox = self.convertVisionRect(textObs.boundingBox, expandPercent: 0.025)

                            let analysis = self.sensitiveDetector.classify(text: rawText)

                            let displayLabel: String
                            if analysis.category != .generalText {
                                displayLabel = "\(analysis.category.rawValue)"
                            } else {
                                displayLabel = rawText
                            }

                            detectedRegions.append(
                                DetectedPrivacyRegion(
                                    type: .text,
                                    category: analysis.category,
                                    boundingBox: convertedBox,
                                    label: displayLabel
                                )
                            )
                        }
                    }
                }
                textRequest.recognitionLevel = .accurate
                textRequest.usesLanguageCorrection = true
                // Idiomas optimizados para Hispanoamérica y documentos en inglés
                textRequest.recognitionLanguages = ["es-CO", "es-ES", "en-US"]
                requests.append(textRequest)
            }

            // 3. Solicitud condicional para detección de Códigos QR y Barras
            if detectBarcodes {
                let barcodeRequest = VNDetectBarcodesRequest { request, error in
                    if let results = request.results as? [VNBarcodeObservation] {
                        for barcode in results {
                            let convertedBox = self.convertVisionRect(barcode.boundingBox, expandPercent: 0.02)
                            let payload = barcode.payloadStringValue ?? "Código QR/Barras"
                            detectedRegions.append(
                                DetectedPrivacyRegion(
                                    type: .barcode,
                                    category: .url,
                                    boundingBox: convertedBox,
                                    label: "Código: \(payload)"
                                )
                            )
                        }
                    }
                }
                requests.append(barcodeRequest)
            }

            guard !requests.isEmpty else {
                continuation.resume(returning: [])
                return
            }

            do {
                try handler.perform(requests)
                continuation.resume(returning: detectedRegions)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Métodos Privados de Conversión

    /// Convierte las coordenadas del framework Vision (Origen abajo-izquierda) a las coordenadas de SwiftUI (Origen arriba-izquierda)
    /// aplicando un margen de seguridad porcentual para garantizar cobertura total de bordes.
    private nonisolated func convertVisionRect(_ visionRect: CGRect, expandPercent: CGFloat = 0.0) -> CGRect {
        var rect = CGRect(
            x: visionRect.origin.x,
            y: 1.0 - visionRect.origin.y - visionRect.size.height,
            width: visionRect.size.width,
            height: visionRect.size.height
        )

        if expandPercent > 0 {
            let dx = rect.width * expandPercent
            let dy = rect.height * (expandPercent * 1.5)
            rect = rect.insetBy(dx: -dx, dy: -dy)

            // Clamp estricto dentro de [0.0, 1.0]
            rect.origin.x = max(0.0, rect.origin.x)
            rect.origin.y = max(0.0, rect.origin.y)
            rect.size.width = min(1.0 - rect.origin.x, rect.size.width)
            rect.size.height = min(1.0 - rect.origin.y, rect.size.height)
        }

        return rect
    }
}
