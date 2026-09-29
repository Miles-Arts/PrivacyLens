//
//  ExportManager.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Gestor integral de exportación segura, despojo de metadatos, compartir e imprimir.
//  Copyright © 2026. Todos los derechos reservados.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
import Photos
#elseif canImport(AppKit)
import AppKit
#endif

/// Gestor de alta seguridad encargado de la exportación de archivos protegidos a disco (macOS)
/// y a la Fototeca (iOS), garantizando despojo de metadatos EXIF/GPS, desinfección de nombres de archivo
/// y prevención de fuga de información en el portapapeles.
@MainActor
final class ExportManager {

    /// Motor interno de redacción y renderizado destructivo.
    private static let engine = RedactionEngine()

    // MARK: - Sanitización y Blindaje de Nombres de Archivo

    /// Sanitiza rigurosamente los nombres de archivo ingresados por el usuario para prevenir
    /// ataques de Path Traversal (`../`), inyección de caracteres de control o corrupción del sistema de archivos.
    ///
    /// - Parameter rawName: Cadena sin procesar proveniente de la interfaz de usuario.
    /// - Returns: Nombre de archivo desinfectado que garantiza contención dentro del sandbox.
    static func sanitizeFileName(_ rawName: String) -> String {
        var clean = rawName
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Limita a caracteres alfanuméricos seguros, espacios, guiones y puntos
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        clean = clean.components(separatedBy: allowed.inverted).joined()

        if clean.isEmpty {
            clean = "PrivaLock_Protegida"
        }

        if !clean.lowercased().hasSuffix(".jpg") && !clean.lowercased().hasSuffix(".jpeg") {
            clean += ".jpg"
        }
        return clean
    }

    // MARK: - Guardado de Imágenes Protegidas

    /// Guarda la imagen redactada en el destino correspondiente según la plataforma activa.
    ///
    /// - Parameters:
    ///   - platformImage: Imagen en formato nativo con la redacción física aplicada.
    ///   - defaultFileName: Nombre sugerido para el archivo.
    ///   - stripEXIF: Indica si se deben despojar las coordenadas GPS y metadatos EXIF.
    /// - Returns: Mensaje descriptivo con el resultado de la operación.
    /// - Throws: Errores generados durante la codificación o la persistencia.
    static func saveRedactedImage(
        _ platformImage: PlatformImage,
        defaultFileName: String = "PrivaLock_Protegida.jpg",
        stripEXIF: Bool = true
    ) async throws -> String {
        guard let cleanData = engine.exportCleanImageData(platformImage, format: .jpeg, stripEXIF: stripEXIF) else {
            throw NSError(
                domain: "ExportManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo generar la imagen para exportar."]
            )
        }

        let safeName = sanitizeFileName(defaultFileName)

        #if canImport(AppKit)
        return try await saveOnMacOS(data: cleanData, defaultFileName: safeName)
        #elseif canImport(UIKit)
        return try await saveOnIOS(data: cleanData)
        #endif
    }

    // MARK: - Compartir e Imprimir

    /// Comparte la imagen protegida mediante el selector nativo del sistema operativo (WhatsApp, Mail, AirDrop, etc.).
    ///
    /// - Parameters:
    ///   - platformImage: Imagen protegida a compartir.
    ///   - fileName: Nombre de archivo asignado a la exportación temporal limpia.
    static func shareImage(_ platformImage: PlatformImage, fileName: String) {
        guard let cleanData = engine.exportCleanImageData(platformImage, format: .jpeg, stripEXIF: true) else { return }

        // Purgamos previamente archivos temporales anteriores para garantizar cero rastros
        cleanupTemporaryFiles()

        let safeName = sanitizeFileName(fileName)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        try? cleanData.write(to: tempURL)

        #if canImport(AppKit)
        let picker = NSSharingServicePicker(items: [tempURL, platformImage])
        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView {
            let centerRect = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
            picker.show(relativeTo: centerRect, of: contentView, preferredEdge: .minY)
        }
        #elseif canImport(UIKit)
        let activityVC = UIActivityViewController(activityItems: [tempURL, platformImage], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #endif
    }

    /// Envía la imagen protegida al diálogo de impresión del sistema (o exportación a PDF nativo).
    ///
    /// - Parameter platformImage: Imagen a imprimir.
    static func printImage(_ platformImage: PlatformImage) {
        #if canImport(AppKit)
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: platformImage.size))
        imageView.image = platformImage
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let printOperation = NSPrintOperation(view: imageView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.run()
        #elseif canImport(UIKit)
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "PrivaLock Document"
        printController.printInfo = printInfo
        printController.printingItem = platformImage
        printController.present(animated: true, completionHandler: nil)
        #endif
    }

    // MARK: - Portapapeles con Protección de Privacidad

    /// Copia la imagen protegida al portapapeles con blindaje anti-fuga (localOnly y expiración de 120s en iOS).
    ///
    /// - Parameter platformImage: Imagen a copiar.
    /// - Returns: `true` si la operación concluyó exitosamente.
    static func copyToClipboard(_ platformImage: PlatformImage) -> Bool {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([platformImage])
        #elseif canImport(UIKit)
        if let data = platformImage.jpegData(compressionQuality: 0.95) {
            // Protección de portapapeles:
            // 1. .localOnly: Impide la transmisión automática a otros dispositivos vía iCloud Universal Clipboard.
            // 2. .expirationDate: Purga automáticamente el buffer del portapapeles tras 120 segundos.
            UIPasteboard.general.setItems(
                [[UTType.jpeg.identifier: data]],
                options: [
                    .localOnly: true,
                    .expirationDate: Date().addingTimeInterval(120)
                ]
            )
            return true
        } else {
            UIPasteboard.general.image = platformImage
            return true
        }
        #endif
    }

    // MARK: - Purga Forense de Archivos Temporales

    /// Elimina de forma segura cualquier residuo o archivo temporal de exportación en disco para garantizar cero rastro forense.
    static func cleanupTemporaryFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in contents where file.lastPathComponent.hasPrefix("PrivaLock") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Implementaciones Específicas de Plataforma

    #if canImport(AppKit)
    /// Abre el panel nativo de guardado `NSSavePanel` en macOS.
    private static func saveOnMacOS(data: Data, defaultFileName: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.jpeg, .png]
            savePanel.nameFieldStringValue = defaultFileName
            savePanel.title = "Guardar Imagen Protegida por PrivaLock"
            savePanel.prompt = "Guardar"

            savePanel.begin { response in
                if response == .OK, let targetURL = savePanel.url {
                    do {
                        try data.write(to: targetURL)
                        continuation.resume(returning: "Imagen guardada exitosamente en \(targetURL.lastPathComponent)")
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "ExportManager",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Guardado cancelado por el usuario."]
                    ))
                }
            }
        }
    }
    #endif

    #if canImport(UIKit)
    /// Guarda la imagen en la Fototeca de iOS mediante `PHPhotoLibrary` con manejo seguro de errores y permisos `.addOnly`.
    private static func saveOnIOS(data: Data) async throws -> String {
        guard let uiImage = UIImage(data: data) else {
            throw NSError(
                domain: "ExportManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo preparar la imagen para guardar en la Fototeca."]
            )
        }

        // 1. Verificación y solicitud explícita de autorización para añadir a la Fototeca (.addOnly)
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if currentStatus == .notDetermined {
            let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                throw NSError(
                    domain: "ExportManager",
                    code: 3301,
                    userInfo: [NSLocalizedDescriptionKey: "Permiso denegado. Ve a Ajustes > PrivaLock y activa 'Añadir solo fotos'."]
                )
            }
        } else if currentStatus != .authorized && currentStatus != .limited {
            throw NSError(
                domain: "ExportManager",
                code: 3301,
                userInfo: [NSLocalizedDescriptionKey: "Permiso denegado. Ve a Ajustes > PrivaLock y activa 'Añadir solo fotos'."]
            )
        }

        // 2. Guardado seguro usando PHAssetChangeRequest directamente desde UIImage (inmune a error 3311)
        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: "Imagen guardada exitosamente en la Fototeca.")
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "ExportManager",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Error al guardar en la Fototeca."]
                    ))
                }
            }
        }
    }
    #endif
}
