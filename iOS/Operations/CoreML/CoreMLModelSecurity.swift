// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import Foundation
import CoreML
import CryptoKit

/// Class responsible for ensuring Core ML model security and preventing unauthorized model replacement
final class CoreMLModelSecurity {
    // MARK: - Singleton
    
    static let shared = CoreMLModelSecurity()
    
    // MARK: - Properties
    
    /// URL to the default bundled model
    private let defaultModelURL: URL? = Bundle.main.url(forResource: "BackdoorAssistant", withExtension: "mlmodel", subdirectory: "Models")
    
    /// URL to the compiled model in the application support directory
    private var compiledModelURL: URL? {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupportURL?.appendingPathComponent("BackdoorAssistant.mlmodelc")
    }
    
    /// Signature of the original model
    private var originalModelSignature: String?
    
    // MARK: - Initialization
    
    private init() {
        // Calculate the signature of the original bundled model
        if let defaultURL = defaultModelURL {
            calculateModelSignature(at: defaultURL) { [weak self] signature in
                self?.originalModelSignature = signature
                Debug.shared.log(message: "Original model signature calculated and stored", type: .debug)
            }
        }
        
        // Setup file system monitoring
        setupModelFileMonitoring()
        
        Debug.shared.log(message: "Core ML Model Security initialized", type: .info)
    }
    
    // MARK: - Security Methods
    
    /// Verify the model's authenticity
    func verifyModelAuthenticity(at url: URL, completion: @escaping (Bool) -> Void) {
        // First check if this is the original bundled model
        if url.path == defaultModelURL?.path {
            Debug.shared.log(message: "Verified original bundled model", type: .debug)
            completion(true)
            return
        }
        
        // For compiled models, verify against the original signature
        calculateModelSignature(at: url) { [weak self] signature in
            guard let self = self, let originalSignature = self.originalModelSignature else {
                Debug.shared.log(message: "Cannot verify model: No original signature available", type: .warning)
                completion(false)
                return
            }
            
            // Compare with the original model signature or an approved update signature
            let isVerified = self.isApprovedModelSignature(signature)
            
            if isVerified {
                Debug.shared.log(message: "Model verified successfully", type: .debug)
            } else {
                Debug.shared.log(message: "Model verification failed - potentially unauthorized model", type: .warning)
            }
            
            completion(isVerified)
        }
    }
    
    /// Calculate the model's cryptographic signature
    private func calculateModelSignature(at url: URL, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            do {
                // Read model file data
                let modelData = try Data(contentsOf: url)
                
                // Calculate SHA-256 hash
                let hash = SHA256.hash(data: modelData)
                
                // Convert to string representation
                let signature = hash.compactMap { String(format: "%02x", $0) }.joined()
                
                DispatchQueue.main.async {
                    completion(signature)
                }
            } catch {
                Debug.shared.log(message: "Failed to calculate model signature: \(error.localizedDescription)", type: .error)
                DispatchQueue.main.async {
                    completion("")
                }
            }
        }
    }
    
    /// Check if the given signature is from an approved model
    private func isApprovedModelSignature(_ signature: String) -> Bool {
        // If this matches the original bundled model, it's approved
        if signature == originalModelSignature {
            return true
        }
        
        // Here we would check against a list of approved update signatures
        // In a real implementation, we might fetch this from a secure server or have it embedded
        // For now, we'll only allow the original model
        
        return false
    }
    
    /// Restore the original model if unauthorized model is detected
    func restoreOriginalModel() {
        guard let defaultURL = defaultModelURL, let compiledURL = compiledModelURL else {
            Debug.shared.log(message: "Cannot restore original model: URLs not available", type: .error)
            return
        }
        
        do {
            // Remove potentially compromised model
            if FileManager.default.fileExists(atPath: compiledURL.path) {
                try FileManager.default.removeItem(at: compiledURL)
            }
            
            // Compile and install the original model
            let recompiledURL = try MLModel.compileModel(at: defaultURL)
            
            // Create directory if needed
            try FileManager.default.createDirectory(at: compiledURL.deletingLastPathComponent(), 
                                                  withIntermediateDirectories: true)
            
            // Copy the model to application support
            try FileManager.default.copyItem(at: recompiledURL, to: compiledURL)
            
            Debug.shared.log(message: "Original model restored successfully", type: .success)
        } catch {
            Debug.shared.log(message: "Failed to restore original model: \(error.localizedDescription)", type: .error)
        }
    }
    
    // MARK: - File Monitoring
    
    /// Setup monitoring for model file changes
    private func setupModelFileMonitoring() {
        // In a real implementation, we would use file system monitoring
        // For now, we'll just set up periodic checks
        
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.performIntegrityCheck()
        }
    }
    
    /// Perform periodic integrity checks
    private func performIntegrityCheck() {
        guard let compiledURL = compiledModelURL, 
              FileManager.default.fileExists(atPath: compiledURL.path) else {
            return
        }
        
        verifyModelAuthenticity(at: compiledURL) { [weak self] isAuthentic in
            if !isAuthentic {
                Debug.shared.log(message: "Integrity check failed - restoring original model", type: .warning)
                self?.restoreOriginalModel()
            }
        }
    }
    
    /// Prevent model uploads/replacement in app sandbox
    func preventModelUpload() -> Bool {
        // In a real implementation, we would use file protection APIs
        // and entitlement restrictions to prevent uploads
        
        // For now, we'll simply verify and restore if needed
        performIntegrityCheck()
        
        return true
    }
}
