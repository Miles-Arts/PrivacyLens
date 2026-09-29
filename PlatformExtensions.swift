//
//  PlatformExtensions.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Extensiones unificadas multiplataforma (macOS y iOS) para CGImage, PlatformImage y Hápticos.
//  Copyright © 2026. Todos los derechos reservados.
//

import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

/// Administrador centralizado de retroalimentación háptica sutil para iOS.
@MainActor
final class HapticManager {
    /// Genera una vibración táctil de impacto (ligera, media o fuerte).
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Genera una respuesta táctil de confirmación (éxito, advertencia o error).
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    /// Genera una respuesta táctil ligera al cambiar de selección o activar un interruptor.
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

/// Implementación no-op para macOS (compatible sin errores de compilación).
@MainActor
final class HapticManager {
    static func impact(_ style: Any? = nil) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
    static func notification(_ type: Any? = nil) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
    static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
}
#endif

extension PlatformImage {
    /// Obtiene la representación `CGImage` nativa de la imagen sin importar la plataforma ni el hilo de ejecución.
    nonisolated var cgImageRepresentation: CGImage? {
        #if canImport(UIKit)
        return self.cgImage
        #elseif canImport(AppKit)
        var rect = CGRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    /// Genera una nueva instancia de `PlatformImage` (`NSImage` en macOS / `UIImage` en iOS) desde un `CGImage`.
    nonisolated static func create(from cgImage: CGImage) -> PlatformImage {
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }
}
