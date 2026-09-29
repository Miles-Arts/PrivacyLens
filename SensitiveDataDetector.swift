//
//  SensitiveDataDetector.swift
//  PrivaLock
//
//  Created for PrivaLock - Privacy & Data Redaction Tool.
//  Motor clasificador de datos sensibles para detección On-Device mediante NSDataDetector y Regex.
//  Copyright © 2026. Todos los derechos reservados.
//

import Foundation

/// Categoría de sensibilidad asignada a una región de texto analizada por OCR.
enum SensitiveDataCategory: String, CaseIterable, Identifiable, Sendable {
    /// Dirección de correo electrónico (ej. usuario@dominio.com).
    case email = "Correo Electrónico"
    /// Número de teléfono o móvil (ej. 3143956047).
    case phone = "Teléfono / Celular"
    /// Documento de identidad personal (Cédula de Ciudadanía, DNI, SSN, Pasaporte).
    case identityDocument = "Documento de Identidad (C.C. / DNI)"
    /// Placa o matrícula de vehículo automotor o motocicleta.
    case licensePlate = "Placa de Vehículo"
    /// Identificación tributaria, fiscal o empresarial (NIT / RUT).
    case taxID = "NIT / RUT / Impuestos"
    /// Número de tarjeta de crédito, débito o código bancario IBAN.
    case bankAccount = "Cuenta Bancaria / Tarjeta"
    /// Dirección física o urbana.
    case address = "Dirección Física"
    /// Enlace web o dirección URL.
    case url = "Enlace Web / URL"
    /// Texto general sin categoría de alto riesgo.
    case generalText = "Texto General"

    /// Identificador único para iteración en SwiftUI.
    var id: String { rawValue }

    /// Icono de sistema (SF Symbols) correspondiente a la categoría.
    var iconName: String {
        switch self {
        case .email: return "envelope.fill"
        case .phone: return "phone.fill"
        case .identityDocument: return "person.text.rectangle.fill"
        case .licensePlate: return "car.fill"
        case .taxID: return "doc.plaintext.fill"
        case .bankAccount: return "creditcard.fill"
        case .address: return "mappin.and.ellipse"
        case .url: return "link"
        case .generalText: return "doc.text"
        }
    }
}

/// Resultado retornado tras clasificar una cadena de texto detectada por OCR.
struct SensitiveAnalysisResult: Sendable {
    /// Categoría de sensibilidad detectada.
    let category: SensitiveDataCategory
    /// Texto original analizado.
    let matchedText: String
    /// Nivel de confianza estimado de la clasificación (0.0 a 1.0).
    let confidence: Double
}

/// Motor clasificador de alto rendimiento que evalúa patrones de datos sensibles
/// mediante expresiones regulares deterministas y el framework `NSDataDetector`.
final class SensitiveDataDetector: @unchecked Sendable {

    /// Instancia de `NSDataDetector` configurada para teléfonos, enlaces y direcciones físicas.
    private let dataDetector: NSDataDetector?

    /// Inicializa el detector de datos sensibles configurando los tipos de coincidencia lingüística.
    nonisolated init() {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .address]
        self.dataDetector = try? NSDataDetector(types: types.rawValue)
    }

    /// Clasifica una cadena de texto en su categoría de privacidad correspondiente.
    ///
    /// - Parameter text: Texto extraído mediante OCR.
    /// - Returns: Estructura `SensitiveAnalysisResult` con la categoría identificada y nivel de confianza.
    nonisolated func classify(text: String) -> SensitiveAnalysisResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SensitiveAnalysisResult(category: .generalText, matchedText: text, confidence: 0.0)
        }

        // 1. Detección de Placas de Vehículos (Automóviles y Motocicletas)
        if matchesLicensePlate(trimmed) {
            return SensitiveAnalysisResult(category: .licensePlate, matchedText: trimmed, confidence: 0.95)
        }

        // 2. Detección de NIT / RUT / Identificación Tributaria
        if matchesTaxID(trimmed) {
            return SensitiveAnalysisResult(category: .taxID, matchedText: trimmed, confidence: 0.92)
        }

        // 3. Detección por Expresión Regular para Documento de Identidad (C.C., DNI, Cédula, Pasaporte, SSN)
        if matchesIdentityDocument(trimmed) {
            return SensitiveAnalysisResult(category: .identityDocument, matchedText: trimmed, confidence: 0.95)
        }

        // 4. Detección por Expresión Regular para Cuentas Bancarias / Tarjetas / IBAN
        if matchesBankAccount(trimmed) {
            return SensitiveAnalysisResult(category: .bankAccount, matchedText: trimmed, confidence: 0.90)
        }

        // 5. Detección de Correo Electrónico (Regex de alta precisión)
        if matchesEmail(trimmed) {
            return SensitiveAnalysisResult(category: .email, matchedText: trimmed, confidence: 0.98)
        }

        // 6. Detección mediante NSDataDetector del sistema (Teléfonos, Direcciones, URLs)
        if let detector = dataDetector {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            let matches = detector.matches(in: trimmed, options: [], range: range)

            for match in matches {
                if match.resultType == .phoneNumber {
                    return SensitiveAnalysisResult(category: .phone, matchedText: trimmed, confidence: 0.95)
                } else if match.resultType == .link {
                    let matchStr = (trimmed as NSString).substring(with: match.range)
                    if matchStr.contains("@") {
                        return SensitiveAnalysisResult(category: .email, matchedText: trimmed, confidence: 0.98)
                    } else {
                        return SensitiveAnalysisResult(category: .url, matchedText: trimmed, confidence: 0.85)
                    }
                } else if match.resultType == .address {
                    return SensitiveAnalysisResult(category: .address, matchedText: trimmed, confidence: 0.80)
                }
            }
        }

        // 7. Evaluación contextual por palabras clave (Español e Inglés)
        let lower = trimmed.lowercased()
        if lower.contains("placa") || lower.contains("plate") || lower.contains("matricula") {
            return SensitiveAnalysisResult(category: .licensePlate, matchedText: trimmed, confidence: 0.88)
        }
        if lower.contains("nit") || lower.contains("rut") || lower.contains("tribut") {
            return SensitiveAnalysisResult(category: .taxID, matchedText: trimmed, confidence: 0.88)
        }
        if lower.contains("c.c.") || lower.contains("cc") || lower.contains("cedula") || lower.contains("dni") || lower.contains("ident") || lower.contains("pasaporte") || lower.contains("passport") {
            return SensitiveAnalysisResult(category: .identityDocument, matchedText: trimmed, confidence: 0.85)
        }
        if lower.contains("celular") || lower.contains("tel") || lower.contains("phone") || lower.contains("movil") {
            return SensitiveAnalysisResult(category: .phone, matchedText: trimmed, confidence: 0.85)
        }
        if lower.contains("email") || lower.contains("correo") || lower.contains("@") {
            return SensitiveAnalysisResult(category: .email, matchedText: trimmed, confidence: 0.90)
        }

        return SensitiveAnalysisResult(category: .generalText, matchedText: trimmed, confidence: 0.10)
    }

    // MARK: - Métodos Privados de Evaluación Regex

    /// Verifica si el texto coincide con una matrícula o placa de vehículo (ej. ABC 123 o ABC 12D).
    private nonisolated func matchesLicensePlate(_ text: String) -> Bool {
        let patterns = [
            "\\b[A-Za-z]{3}[ -]?[0-9]{3}\\b",      // Automóviles (ej. ABC-123)
            "\\b[A-Za-z]{3}[ -]?[0-9]{2}[A-Za-z]\\b" // Motocicletas (ej. ABC-12D)
        ]
        for pattern in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    /// Verifica si el texto coincide con una identificación fiscal o empresarial (NIT o RUT).
    private nonisolated func matchesTaxID(_ text: String) -> Bool {
        let patterns = [
            "(?i)(nit|rut)\\s*:?\\s*\\d{8,11}[ -]?\\d?",
            "\\b\\d{9}[ -]?\\d\\b"
        ]
        for pattern in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    /// Verifica si el texto coincide con un formato estricto de correo electrónico.
    private nonisolated func matchesEmail(_ text: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Verifica si el texto coincide con formatos de documentos de identidad (C.C., DNI, Pasaporte, SSN).
    private nonisolated func matchesIdentityDocument(_ text: String) -> Bool {
        let patterns = [
            "(?i)(c\\.?c\\.?|cedula|dni|nif|pass|ssn|pasaporte|passport)\\s*:?\\s*[A-Za-z0-9]+",
            "\\b\\d{7,10}\\b"
        ]

        for pattern in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    /// Verifica si el texto coincide con numeraciones de tarjetas de crédito o códigos IBAN.
    private nonisolated func matchesBankAccount(_ text: String) -> Bool {
        let ibanPattern = "\\b[A-Z]{2}\\d{2}[A-Z0-9]{11,30}\\b"
        let cardPattern = "\\b(?:\\d[ -]*?){13,16}\\b"
        return text.range(of: ibanPattern, options: .regularExpression) != nil ||
               text.range(of: cardPattern, options: .regularExpression) != nil
    }
}
