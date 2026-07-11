import AuthenticationServices
import SwiftUI
import PasswardsCore
import PasswardsOrchestration

class CredentialProviderViewController: ASCredentialProviderViewController {
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let domains = serviceIdentifiers.map { $0.identifier }
        
        let hostingController = UIHostingController(
            rootView: AutoFillView(
                domains: domains,
                onSelect: { [weak self] username, password in
                    let credential = ASPasswordCredential(user: username, password: password)
                    self?.extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
                },
                onCancel: { [weak self] in
                    self?.extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue))
                }
            )
        )
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        hostingController.didMove(toParent: self)
    }
}
