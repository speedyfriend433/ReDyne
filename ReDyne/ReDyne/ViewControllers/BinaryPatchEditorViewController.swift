import UIKit

class BinaryPatchEditorViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate {
    
    // MARK: - Properties
    
    private let patchSet: BinaryPatchSet
    private let binaryPath: String
    private var patch: BinaryPatch?
    private let isNewPatch: Bool
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    private let nameField = UITextField()
    private let descriptionTextView = UITextView()
    private let virtualAddressField = UITextField()
    private let fileOffsetField = UITextField()
    private let originalBytesField = UITextField()
    private let patchedBytesField = UITextField()
    private let severitySegment = UISegmentedControl(items: ["Info", "Low", "Med", "High", "Critical"])
    private let notesTextView = UITextView()
    
    // MARK: - Initialization
    
    init(patchSet: BinaryPatchSet, binaryPath: String, patch: BinaryPatch?) {
        self.patchSet = patchSet
        self.binaryPath = binaryPath
        self.patch = patch
        self.isNewPatch = patch == nil
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = isNewPatch ? "New Patch" : "Edit Patch"
        view.backgroundColor = UIColor.systemGroupedBackground
        
        setupNavigationBar()
        setupScrollView()
        setupFields()
        setupKeyboardToolbars()
        
        if let patch = patch {
            populateFields(with: patch)
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupKeyboardToolbars() {
        let toolbar = createKeyboardToolbar()
        
        nameField.inputAccessoryView = toolbar
        virtualAddressField.inputAccessoryView = toolbar
        fileOffsetField.inputAccessoryView = toolbar
        originalBytesField.inputAccessoryView = toolbar
        patchedBytesField.inputAccessoryView = toolbar
        descriptionTextView.inputAccessoryView = toolbar
        notesTextView.inputAccessoryView = toolbar
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardFrame.height, right: 0)
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    // MARK: - Setup
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(savePatch))
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func setupFields() {
        var lastView: UIView?
        let spacing: CGFloat = 16
        let sectionSpacing: CGFloat = 32
        let basicInfoHeader = createSectionHeader(text: "Basic Information")
        contentView.addSubview(basicInfoHeader)
        NSLayoutConstraint.activate([
            basicInfoHeader.topAnchor.constraint(equalTo: contentView.topAnchor, constant: spacing),
            basicInfoHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            basicInfoHeader.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = basicInfoHeader
        
        let nameCard = createCardView()
        contentView.addSubview(nameCard)
        NSLayoutConstraint.activate([
            nameCard.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 12),
            nameCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            nameCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        
        let nameLabel = createLabel(text: "Name")
        nameCard.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: nameCard.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: nameCard.leadingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: nameCard.trailingAnchor, constant: -12)
        ])
        
        nameField.placeholder = "e.g., Fix crash"
        nameField.borderStyle = .none
        nameField.font = .systemFont(ofSize: 16)
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameCard.addSubview(nameField)
        NSLayoutConstraint.activate([
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            nameField.leadingAnchor.constraint(equalTo: nameCard.leadingAnchor, constant: 12),
            nameField.trailingAnchor.constraint(equalTo: nameCard.trailingAnchor, constant: -12),
            nameField.bottomAnchor.constraint(equalTo: nameCard.bottomAnchor, constant: -12),
            nameField.heightAnchor.constraint(equalToConstant: 44)
        ])
        lastView = nameCard
        
        let descLabel = createLabel(text: "Description (Optional)")
        contentView.addSubview(descLabel)
        NSLayoutConstraint.activate([
            descLabel.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
            descLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            descLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = descLabel
        
        descriptionTextView.font = .systemFont(ofSize: 16)
        descriptionTextView.layer.borderColor = UIColor.separator.cgColor
        descriptionTextView.layer.borderWidth = 0.5
        descriptionTextView.layer.cornerRadius = 8
        descriptionTextView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descriptionTextView)
        NSLayoutConstraint.activate([
            descriptionTextView.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 8),
            descriptionTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            descriptionTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing),
            descriptionTextView.heightAnchor.constraint(equalToConstant: 80)
        ])
        lastView = descriptionTextView
        
        let vaddrLabel = createLabel(text: "Virtual Address (hex)")
        contentView.addSubview(vaddrLabel)
        NSLayoutConstraint.activate([
            vaddrLabel.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
            vaddrLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            vaddrLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = vaddrLabel
        
        virtualAddressField.placeholder = "0x100001000"
        virtualAddressField.borderStyle = .roundedRect
        virtualAddressField.keyboardType = .asciiCapable
        virtualAddressField.autocapitalizationType = .allCharacters
        virtualAddressField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(virtualAddressField)
        NSLayoutConstraint.activate([
            virtualAddressField.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 8),
            virtualAddressField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            virtualAddressField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = virtualAddressField
        
        let foffsetLabel = createLabel(text: "File Offset (hex)")
        contentView.addSubview(foffsetLabel)
        NSLayoutConstraint.activate([
            foffsetLabel.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
            foffsetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            foffsetLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = foffsetLabel
        
        fileOffsetField.placeholder = "0x4000"
        fileOffsetField.borderStyle = .roundedRect
        fileOffsetField.keyboardType = .asciiCapable
        fileOffsetField.autocapitalizationType = .allCharacters
        fileOffsetField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(fileOffsetField)
        NSLayoutConstraint.activate([
            fileOffsetField.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 8),
            fileOffsetField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            fileOffsetField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = fileOffsetField
        
        let origLabel = createLabel(text: "Original Bytes (hex, space-separated)")
        contentView.addSubview(origLabel)
        NSLayoutConstraint.activate([
            origLabel.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
            origLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            origLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = origLabel
        
        originalBytesField.placeholder = "1F 20 03 D5"
        originalBytesField.borderStyle = .roundedRect
        originalBytesField.keyboardType = .asciiCapable
        originalBytesField.autocapitalizationType = .allCharacters
        originalBytesField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(originalBytesField)
        NSLayoutConstraint.activate([
            originalBytesField.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 8),
            originalBytesField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            originalBytesField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = originalBytesField
        
        let patchLabel = createLabel(text: "Patched Bytes (hex, space-separated)")
        contentView.addSubview(patchLabel)
        NSLayoutConstraint.activate([
            patchLabel.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
            patchLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            patchLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = patchLabel
        
        patchedBytesField.placeholder = "1F 20 03 D5"
        patchedBytesField.borderStyle = .roundedRect
        patchedBytesField.keyboardType = .asciiCapable
        patchedBytesField.autocapitalizationType = .allCharacters
        patchedBytesField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(patchedBytesField)
        NSLayoutConstraint.activate([
            patchedBytesField.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 8),
            patchedBytesField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            patchedBytesField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = patchedBytesField
        
        let sevLabel = createLabel(text: "Severity")
        contentView.addSubview(sevLabel)
        NSLayoutConstraint.activate([
            sevLabel.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
            sevLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            sevLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = sevLabel
        
        severitySegment.selectedSegmentIndex = 2
        severitySegment.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(severitySegment)
        NSLayoutConstraint.activate([
            severitySegment.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 8),
            severitySegment.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            severitySegment.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = severitySegment
        
        let notesLabel = createLabel(text: "Notes (Optional)")
        contentView.addSubview(notesLabel)
        NSLayoutConstraint.activate([
            notesLabel.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: spacing),
            notesLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            notesLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing)
        ])
        lastView = notesLabel
        
        notesTextView.font = .systemFont(ofSize: 16)
        notesTextView.layer.borderColor = UIColor.separator.cgColor
        notesTextView.layer.borderWidth = 0.5
        notesTextView.layer.cornerRadius = 8
        notesTextView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(notesTextView)
        NSLayoutConstraint.activate([
            notesTextView.topAnchor.constraint(equalTo: lastView!.bottomAnchor, constant: 8),
            notesTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spacing),
            notesTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spacing),
            notesTextView.heightAnchor.constraint(equalToConstant: 80),
            notesTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacing)
        ])
    }
    
    private func createLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func createSectionHeader(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func createCardView() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 12
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.05
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 4
        return card
    }
    
    private func createKeyboardToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissKeyboard))
        
        toolbar.items = [flexSpace, doneButton]
        return toolbar
    }
    
    private func populateFields(with patch: BinaryPatch) {
        nameField.text = patch.name
        descriptionTextView.text = patch.description
        virtualAddressField.text = "0x\(String(format: "%llX", patch.virtualAddress))"
        fileOffsetField.text = "0x\(String(format: "%llX", patch.fileOffset))"
        originalBytesField.text = patch.originalBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        patchedBytesField.text = patch.patchedBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        notesTextView.text = patch.notes
        
        switch patch.severity {
        case .info: severitySegment.selectedSegmentIndex = 0
        case .low: severitySegment.selectedSegmentIndex = 1
        case .medium: severitySegment.selectedSegmentIndex = 2
        case .high: severitySegment.selectedSegmentIndex = 3
        case .critical: severitySegment.selectedSegmentIndex = 4
        }
    }
    
    // MARK: - Actions
    
    @objc private func savePatch() {
        guard let name = nameField.text, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("Please enter a patch name")
            return
        }
        
        guard let vaddrText = virtualAddressField.text, let vaddr = parseHex(vaddrText) else {
            showError("Invalid virtual address")
            return
        }
        
        guard let foffsetText = fileOffsetField.text, let foffset = parseHex(foffsetText) else {
            showError("Invalid file offset")
            return
        }
        
        guard let originalBytes = parseBytes(originalBytesField.text ?? "") else {
            showError("Invalid original bytes")
            return
        }
        
        guard let patchedBytes = parseBytes(patchedBytesField.text ?? "") else {
            showError("Invalid patched bytes")
            return
        }
        
        guard originalBytes.count == patchedBytes.count else {
            showError("Original and patched bytes must have the same length")
            return
        }
        
        let severity: BinaryPatch.Severity
        switch severitySegment.selectedSegmentIndex {
        case 0: severity = .info
        case 1: severity = .low
        case 2: severity = .medium
        case 3: severity = .high
        case 4: severity = .critical
        default: severity = .medium
        }
        
        let checksum = try? MachOUtilities.checksumForBinary(at: binaryPath) ?? ""
        
        let newPatch = BinaryPatch(
            id: patch?.id ?? UUID(),
            name: name,
            description: descriptionTextView.text,
            severity: severity,
            status: .draft,
            enabled: true,
            virtualAddress: vaddr,
            fileOffset: foffset,
            originalBytes: Data(originalBytes),
            patchedBytes: Data(patchedBytes),
            createdAt: patch?.createdAt ?? Date(),
            updatedAt: Date(),
            checksum: checksum ?? "",
            notes: notesTextView.text,
            expectedUUID: patchSet.targetUUID,
            expectedArchitecture: patchSet.targetArchitecture
        )
        
        do {
            if isNewPatch {
                try BinaryPatchService.shared.addPatch(newPatch, to: patchSet.id)
            } else {
                try BinaryPatchService.shared.updatePatch(newPatch, in: patchSet.id)
            }
            navigationController?.popViewController(animated: true)
        } catch {
            ErrorHandler.showError(error, in: self)
        }
    }
    
    @objc private func cancel() {
        navigationController?.popViewController(animated: true)
    }
    
    // MARK: - Helpers
    
    private func parseHex(_ string: String) -> UInt64? {
        var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("0x") || cleaned.hasPrefix("0X") {
            cleaned = String(cleaned.dropFirst(2))
        }
        return UInt64(cleaned, radix: 16)
    }
    
    private func parseBytes(_ string: String) -> [UInt8]? {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        var bytes: [UInt8] = []
        for component in components {
            guard let byte = UInt8(component, radix: 16) else { return nil }
            bytes.append(byte)
        }
        
        return bytes.isEmpty ? nil : bytes
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate

extension BinaryPatchEditorViewController {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
