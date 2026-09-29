//
//  AppLanguage.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Sistema de localización bilingüe (Español / Inglés) en tiempo real.
//  Copyright © 2026. Todos los derechos reservados.
//

import SwiftUI

/// Idiomas disponibles en PrivaLock.
enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spanish: return "🇪🇸 Español"
        case .english: return "🇺🇸 English"
        }
    }
}

/// Claves de texto traducibles para toda la aplicación.
struct AppStrings {
    let language: AppLanguage

    init(lang: String) {
        self.language = AppLanguage(rawValue: lang) ?? .spanish
    }

    // MARK: - Banner de Privacidad
    var privacyBannerTitle: String {
        language == .spanish ? "Privacidad 100% On-Device" : "100% On-Device Privacy"
    }
    var privacyBannerSubtitle: String {
        language == .spanish
            ? "Tus fotos y documentos nunca salen de tu dispositivo."
            : "Your photos and documents never leave your device."
    }

    // MARK: - Barra de Archivo
    var fileNameLabel: String {
        language == .spanish ? "Nombre:" : "Name:"
    }
    var fileNamePlaceholder: String {
        language == .spanish ? "Nombre del archivo" : "File name"
    }

    // MARK: - Modos de Vista
    var viewModeDetections: String {
        language == .spanish ? "Detecciones AI" : "AI Detections"
    }
    var viewModeRedacted: String {
        language == .spanish ? "Vista Protegida" : "Protected View"
    }

    // MARK: - Dibujo Manual & Estilos
    var drawBoxButton: String {
        language == .spanish ? "+ Dibujar Recuadro" : "+ Draw Box"
    }
    var cancelDrawingButton: String {
        language == .spanish ? "Cancelar Dibujo" : "Cancel Drawing"
    }
    var globalStyleLabel: String {
        language == .spanish ? "Estilo Global:" : "Global Style:"
    }
    var undoButton: String {
        language == .spanish ? "Deshacer" : "Undo"
    }
    var redoButton: String {
        language == .spanish ? "Rehacer" : "Redo"
    }

    // MARK: - Zoom y Centrado
    var zoomInHelp: String {
        language == .spanish ? "Aumentar tamaño (Zoom +)" : "Zoom in (+)"
    }
    var zoomOutHelp: String {
        language == .spanish ? "Reducir tamaño (Zoom -)" : "Zoom out (-)"
    }
    var centerButton: String {
        language == .spanish ? "Centrar" : "Center"
    }
    var centerHelp: String {
        language == .spanish
            ? "Centrar imagen y restablecer zoom al 100%"
            : "Center image and reset zoom to 100%"
    }

    // MARK: - Acciones, Guardado, Compartir e Impresión
    var saveProtectedButton: String {
        language == .spanish ? "Guardar Imagen Protegida" : "Save Protected Image"
    }
    var shareButton: String {
        language == .spanish ? "Compartir" : "Share"
    }
    var shareHelp: String {
        language == .spanish
            ? "Compartir con WhatsApp, Mail, AirDrop, Mensajes u otras aplicaciones"
            : "Share via WhatsApp, Mail, AirDrop, Messages or other apps"
    }
    var printButton: String {
        language == .spanish ? "Imprimir" : "Print"
    }
    var printHelp: String {
        language == .spanish
            ? "Imprimir imagen protegida o guardar como documento PDF"
            : "Print protected image or save as PDF document"
    }
    var copyClipboardButton: String {
        language == .spanish ? "Copiar al Portapapeles" : "Copy to Clipboard"
    }
    var changePhotoButton: String {
        language == .spanish ? "Cambiar Foto" : "Change Photo"
    }
    var copySuccess: String {
        language == .spanish
            ? "¡Imagen protegida copiada al portapapeles exitosamente!"
            : "Protected image successfully copied to clipboard!"
    }
    var copyError: String {
        language == .spanish
            ? "No se pudo copiar la imagen al portapapeles."
            : "Could not copy image to clipboard."
    }

    // MARK: - Tarjeta de Bienvenida
    var welcomeTitle: String {
        language == .spanish
            ? "Protege tus fotos antes de compartir"
            : "Protect your photos before sharing"
    }
    var welcomeSubtitle: String {
        language == .spanish
            ? "Selecciona una foto o documento para ocultar rostros, direcciones, placas y datos sensibles automáticamente."
            : "Select a photo or document to automatically hide faces, addresses, plates and sensitive data."
    }
    var importPhotoButton: String {
        language == .spanish ? "Importar Foto" : "Import Photo"
    }
    var importDocumentButton: String {
        language == .spanish ? "Documento" : "Document"
    }
    var loadingMediaText: String {
        language == .spanish ? "Cargando archivo..." : "Loading file..."
    }

    // MARK: - Resumen de Detección
    var visionSummaryTitle: String {
        language == .spanish ? "Detección Automática (Vision AI)" : "Automatic Detection (Vision AI)"
    }
    func protectedCountText(enabled: Int, total: Int) -> String {
        language == .spanish
            ? "\(enabled) protegidos de \(total)"
            : "\(enabled) protected of \(total)"
    }
    var badgeFaces: String { language == .spanish ? "Rostros" : "Faces" }
    var badgeEmails: String { "Emails" }
    var badgePhones: String { language == .spanish ? "Teléfonos" : "Phones" }
    var badgeID: String { language == .spanish ? "C.C. / DNI" : "ID Card / DNI" }
    var badgePlates: String { language == .spanish ? "Placas" : "Plates" }
    var badgeTaxID: String { language == .spanish ? "NIT / RUT" : "Tax ID" }
    var badgeQR: String { language == .spanish ? "Códigos QR" : "QR Codes" }
    var badgeManual: String { language == .spanish ? "Manuales" : "Manual" }

    // MARK: - Estado de Análisis
    var analyzingText: String {
        language == .spanish
            ? "Actualizando protección con Vision AI..."
            : "Updating protection with Vision AI..."
    }

    // MARK: - Características de Protección
    var securityFeaturesTitle: String {
        language == .spanish ? "Características de Protección" : "Protection Features"
    }
    var securityFeaturesSubtitle: String {
        language == .spanish ? "Toca cada fila para activar/desactivar" : "Tap each row to toggle on/off"
    }

    var featFacesTitle: String {
        language == .spanish ? "Detección de Rostros" : "Face Detection"
    }
    var featFacesDesc: String {
        language == .spanish ? "Oculta rostros automáticamente en fotos." : "Automatically hides faces in photos."
    }

    var featTextTitle: String {
        language == .spanish ? "Reconocimiento OCR & Datos" : "OCR & Sensitive Data"
    }
    var featTextDesc: String {
        language == .spanish ? "Identifica teléfonos, emails, direcciones y documentos." : "Identifies phones, emails, addresses and IDs."
    }

    var featBarcodesTitle: String {
        language == .spanish ? "Códigos QR y Barras" : "QR Codes & Barcodes"
    }
    var featBarcodesDesc: String {
        language == .spanish ? "Encuentra y cubre automáticamente códigos en facturas y pases." : "Finds and covers codes on bills and tickets."
    }

    var featEXIFTitle: String {
        language == .spanish ? "Limpieza Metadatos EXIF" : "Strip EXIF Metadata"
    }
    var featEXIFDesc: String {
        language == .spanish ? "Elimina las coordenadas GPS exactas al exportar." : "Removes exact GPS coordinates when exporting."
    }

    var featFlattenTitle: String {
        language == .spanish ? "Aplanado Destructivo" : "Destructive Flattening"
    }
    var featFlattenDesc: String {
        language == .spanish ? "Sobrescribe píxeles a prueba de Photoshop." : "Overwrites pixels to prevent Photoshop recovery."
    }

    // MARK: - Ajustes (Settings)
    var settingsTitle: String {
        language == .spanish ? "Ajustes de PrivaLock" : "PrivaLock Settings"
    }
    var settingsDone: String {
        language == .spanish ? "Listo" : "Done"
    }
    var settingsLanguageSection: String {
        language == .spanish ? "Idioma de la App" : "App Language"
    }
    var settingsTypographySection: String {
        language == .spanish ? "Tamaño de Letra" : "Font Size"
    }
    var settingsResetFont: String {
        language == .spanish ? "Restablecer a 14 pt (Por Defecto)" : "Reset to 14 pt (Default)"
    }
    var settingsPreviewLabel: String {
        language == .spanish ? "Vista Previa:" : "Live Preview:"
    }
    var settingsPreviewSample: String {
        language == .spanish
            ? "PrivaLock protege tus documentos, cédulas y rostros con inteligencia artificial local."
            : "PrivaLock protects your documents, ID cards, and faces with on-device artificial intelligence."
    }

    // MARK: - Modo Privado y Auditoría de Seguridad
    var privateModeTitle: String {
        language == .spanish ? "Modo Privado (Cero Rastros)" : "Private Mode (Zero Traces)"
    }
    var privateModeSubtitle: String {
        language == .spanish
            ? "En Modo Privado, PrivaLock no almacena registros, peso, horas ni archivos."
            : "In Private Mode, PrivaLock does not store logs, file sizes, timestamps, or files."
    }
    var normalModeBadge: String {
        language == .spanish ? "Modo Normal" : "Normal Mode"
    }
    var privateModeBadge: String {
        language == .spanish ? "Modo Privado" : "Private Mode"
    }
    var auditHistoryTitle: String {
        language == .spanish ? "Historial de Operaciones" : "Operation History"
    }
    var auditHistoryEmpty: String {
        language == .spanish ? "No hay registros guardados." : "No saved records."
    }
    var clearHistoryButton: String {
        language == .spanish ? "Borrar Historial" : "Clear History"
    }
    var auditSecurityBlindage: String {
        language == .spanish ? "Blindaje de Seguridad & Anti-Tracking" : "Security Shield & Anti-Tracking"
    }
    var auditSQLInjectionProtected: String {
        language == .spanish ? "Inmune a inyecciones SQL: Arquitectura 100% nativa sin motores SQL ni consultas dinámicas." : "Immune to SQL Injection: 100% native architecture with zero SQL engines or queries."
    }
    var auditNoTrackingInfo: String {
        language == .spanish ? "Cero telemetría: tus datos nunca viajan por la red ni se comparten con terceros." : "Zero telemetry: your data never travels across the network or reaches third parties."
    }

    // MARK: - Navegación PDF
    func pdfPageIndicator(current: Int, total: Int) -> String {
        language == .spanish ? "Página \(current) de \(total)" : "Page \(current) of \(total)"
    }
}
