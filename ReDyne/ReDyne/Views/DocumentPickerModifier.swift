import SwiftUI
import UniformTypeIdentifiers
import Combine

class SceneDelegateWrapper: ObservableObject {
    @Published var sceneDelegate: SceneDelegate?

    init(sceneDelegate: SceneDelegate) {
        self.sceneDelegate = sceneDelegate
    }
}

public struct DocumentPickerModifier: ViewModifier {
    @ObservedObject var sceneDelegateWrapper: SceneDelegateWrapper
    @State private var docController: UIDocumentPickerViewController?
    @State private var delegate: UIDocumentPickerDelegate

    @Binding var isPresented: Bool

    var callback: ([URL]) -> ()
    private let onDismiss: () -> Void
    private let types: [UTType]
    private let multiple: Bool

    init(isPresented: Binding<Bool>, types: [UTType], multiple: Bool, sceneDelegateWrapper: SceneDelegateWrapper, callback: @escaping ([URL]) -> (), onDismiss: @escaping () -> Void) {
        self.callback = callback
        self.onDismiss = onDismiss
        self.types = types
        self.multiple = multiple
        self.sceneDelegateWrapper = sceneDelegateWrapper
        self.delegate = Coordinator(callback: callback, onDismiss: onDismiss)
        self._isPresented = isPresented
    }

    public func body(content: Content) -> some View {
        content.onChange(of: isPresented) { isPresented in
            print("DocumentPickerModifier: isPresented changed to \(isPresented)")
            if isPresented, docController == nil {
                print("Creating document picker controller")
                let controller = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
                controller.allowsMultipleSelection = multiple
                controller.shouldShowFileExtensions = true
                controller.delegate = delegate
                self.docController = controller

                DispatchQueue.main.async {
                    if let rootVC = sceneDelegateWrapper.sceneDelegate?.window.rootViewController {
                        print("Presenting document picker from root VC")
                        rootVC.present(controller, animated: true)
                    } else {
                        print("No root view controller available in scene delegate")
                    }
                }
            } else if !isPresented, let docController = docController {
                print("Dismissing document picker")
                docController.dismiss(animated: true)
                self.docController = nil
            }
        }
    }

    private func shutdown() {
        isPresented = false
        docController = nil
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var callback: ([URL]) -> ()
        private let onDismiss: () -> Void

        init(callback: @escaping ([URL]) -> Void, onDismiss: @escaping () -> Void) {
            self.callback = callback
            self.onDismiss = onDismiss
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            callback(urls)
            onDismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDismiss()
        }
    }
}

extension View {
    func documentPicker(
        isPresented: Binding<Bool>,
        types: [UTType],
        multiple: Bool = false,
        sceneDelegateWrapper: SceneDelegateWrapper,
        onPick: @escaping ([URL]) -> Void,
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        self.modifier(DocumentPickerModifier(
            isPresented: isPresented,
            types: types,
            multiple: multiple,
            sceneDelegateWrapper: sceneDelegateWrapper,
            callback: onPick,
            onDismiss: onDismiss
        ))
    }
}
