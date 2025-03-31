// Proprietary Software License Version 1.0
//
// Copyright (C) 2025 BDG
//
// Backdoor App Signer is proprietary software. You may not use, modify, or distribute it except as expressly permitted under the terms of the Proprietary Software License.

import UIKit

/// A view that displays the current AI processing mode (On-Device, Hybrid, or Cloud)
class ChatStatusView: UIView {
    // MARK: - UI Components
    
    private let iconImageView = UIImageView()
    private let statusLabel = UILabel()
    private let downloadButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    
    // MARK: - Properties
    
    /// Current AI processing mode
    private var currentMode: CustomAIService.ProcessingMode = .cloud {
        didSet {
            updateUI()
        }
    }
    
    /// Flag to indicate if ML models are being downloaded
    private var isDownloading = false {
        didSet {
            updateDownloadState()
        }
    }
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupObservers()
        
        // Set initial mode
        currentMode = CustomAIService.shared.currentMode
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupObservers()
        
        // Set initial mode
        currentMode = CustomAIService.shared.currentMode
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        // Configure container view
        backgroundColor = .systemBackground.withAlphaComponent(0.7)
        layer.cornerRadius = 12
        layer.masksToBounds = true
        
        // Add shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 3
        
        // Setup icon image view
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .systemBlue
        addSubview(iconImageView)
        
        // Setup status label
        statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .left
        addSubview(statusLabel)
        
        // Setup download button
        downloadButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
        downloadButton.tintColor = .systemBlue
        downloadButton.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
        addSubview(downloadButton)
        
        // Setup activity indicator
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .systemBlue
        addSubview(activityIndicator)
        
        // Apply auto layout
        setupConstraints()
        
        // Update UI with current mode
        updateUI()
    }
    
    private func setupConstraints() {
        // Enable auto layout
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // Icon constraints
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 20),
            iconImageView.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Status label constraints
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: downloadButton.leadingAnchor, constant: -8)
        ])
        
        // Download button constraints
        NSLayoutConstraint.activate([
            downloadButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            downloadButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            downloadButton.widthAnchor.constraint(equalToConstant: 30),
            downloadButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // Activity indicator constraints
        NSLayoutConstraint.activate([
            activityIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        // Observe AI processing mode changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(aiProcessingModeChanged(_:)),
            name: NSNotification.Name("AIProcessingModeChanged"),
            object: nil
        )
        
        // Observe ML model download status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelDownloadStarted(_:)),
            name: NSNotification.Name("MLModelDownloadStarted"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelDownloadFinished(_:)),
            name: NSNotification.Name("MLModelDownloadFinished"),
            object: nil
        )
    }
    
    @objc private func aiProcessingModeChanged(_ notification: Notification) {
        if let mode = notification.userInfo?["mode"] as? CustomAIService.ProcessingMode {
            DispatchQueue.main.async {
                self.currentMode = mode
            }
        } else {
            // If mode not provided, get it from the service
            DispatchQueue.main.async {
                self.currentMode = CustomAIService.shared.currentMode
            }
        }
    }
    
    @objc private func modelDownloadStarted(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isDownloading = true
        }
    }
    
    @objc private func modelDownloadFinished(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isDownloading = false
            
            // Update current mode
            self.currentMode = CustomAIService.shared.currentMode
            
            // Provide feedback based on success
            if let success = notification.userInfo?["success"] as? Bool, success {
                self.showSuccessAnimation()
            }
        }
    }
    
    // MARK: - UI Updates
    
    private func updateUI() {
        // Update icon
        iconImageView.image = UIImage(systemName: currentMode.iconName)
        
        // Update status label
        statusLabel.text = currentMode.displayName
        
        // Show download button only for cloud mode
        downloadButton.isHidden = currentMode == .onDevice || isDownloading
    }
    
    private func updateDownloadState() {
        if isDownloading {
            downloadButton.isHidden = true
            activityIndicator.startAnimating()
        } else {
            downloadButton.isHidden = currentMode == .onDevice
            activityIndicator.stopAnimating()
        }
    }
    
    private func showSuccessAnimation() {
        // Create a temporary success checkmark
        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.tintColor = .systemGreen
        checkmark.alpha = 0
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkmark)
        
        NSLayoutConstraint.activate([
            checkmark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            checkmark.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 20),
            checkmark.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Animate the checkmark
        UIView.animate(withDuration: 0.3, animations: {
            checkmark.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 1.0, options: [], animations: {
                checkmark.alpha = 0
            }, completion: { _ in
                checkmark.removeFromSuperview()
            })
        })
    }
    
    // MARK: - Actions
    
    @objc private func downloadButtonTapped() {
        // Start downloading ML models
        isDownloading = true
        
        // Use haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Download all models
        CoreMLAIIntegration.shared.downloadAllModels()
    }
    
    // MARK: - Layout
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: 200, height: 36)
    }
}
