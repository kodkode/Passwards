import Foundation

/// Default sections/fields seeded into the edit form for each category.
/// Storage is always the generic sections/fields model — templates are only
/// a starting point, matching 1Password's built-in fields.
public enum CategoryTemplates {
    public static func template(for category: Category) -> [ItemSection] {
        switch category {
        case .login:
            return [ItemSection(fields: [
                ItemField(label: "username", kind: .text, purpose: .username),
                ItemField(label: "password", kind: .concealed, purpose: .password),
                ItemField(label: "one-time password", kind: .otp),
                ItemField(label: "website", kind: .url),
            ])]
        case .secureNote:
            return []
        case .creditCard:
            return [
                ItemSection(fields: [
                    ItemField(label: "cardholder name", kind: .text, purpose: .username),
                    ItemField(label: "type", kind: .text),
                    ItemField(label: "number", kind: .concealed, purpose: .password),
                    ItemField(label: "verification number", kind: .concealed),
                    ItemField(label: "expiry date", kind: .monthYear),
                    ItemField(label: "valid from", kind: .monthYear),
                ]),
                ItemSection(title: "Contact Information", fields: [
                    ItemField(label: "issuing bank", kind: .text),
                    ItemField(label: "phone (local)", kind: .phone),
                    ItemField(label: "phone (toll free)", kind: .phone),
                    ItemField(label: "phone (intl)", kind: .phone),
                    ItemField(label: "website", kind: .url),
                ]),
                ItemSection(title: "Additional Details", fields: [
                    ItemField(label: "PIN", kind: .concealed),
                    ItemField(label: "credit limit", kind: .text),
                    ItemField(label: "cash withdrawal limit", kind: .text),
                    ItemField(label: "interest rate", kind: .text),
                    ItemField(label: "issue number", kind: .text),
                ]),
            ]
        case .identity:
            return [
                ItemSection(title: "Identification", fields: [
                    ItemField(label: "first name", kind: .text, purpose: .username),
                    ItemField(label: "initial", kind: .text),
                    ItemField(label: "last name", kind: .text),
                    ItemField(label: "sex", kind: .text),
                    ItemField(label: "birth date", kind: .date),
                    ItemField(label: "occupation", kind: .text),
                    ItemField(label: "company", kind: .text),
                    ItemField(label: "department", kind: .text),
                    ItemField(label: "job title", kind: .text),
                ]),
                ItemSection(title: "Address", fields: [
                    ItemField(label: "address", kind: .address),
                    ItemField(label: "default phone", kind: .phone),
                    ItemField(label: "home", kind: .phone),
                    ItemField(label: "cell", kind: .phone),
                    ItemField(label: "business", kind: .phone),
                ]),
                ItemSection(title: "Internet Details", fields: [
                    ItemField(label: "username", kind: .text),
                    ItemField(label: "reminder question", kind: .text),
                    ItemField(label: "reminder answer", kind: .concealed),
                    ItemField(label: "email", kind: .email),
                ]),
            ]
        case .password:
            return [ItemSection(fields: [
                ItemField(label: "password", kind: .concealed, purpose: .password),
                ItemField(label: "website", kind: .url),
            ])]
        case .document:
            return [ItemSection(fields: [
                ItemField(label: "file", kind: .file),
            ])]
        case .apiCredential:
            return [ItemSection(fields: [
                ItemField(label: "username", kind: .text, purpose: .username),
                ItemField(label: "credential", kind: .concealed, purpose: .password),
                ItemField(label: "type", kind: .text),
                ItemField(label: "filename", kind: .text),
                ItemField(label: "valid from", kind: .date),
                ItemField(label: "expires", kind: .date),
                ItemField(label: "hostname", kind: .url),
            ])]
        case .bankAccount:
            return [
                ItemSection(fields: [
                    ItemField(label: "bank name", kind: .text),
                    ItemField(label: "name on account", kind: .text, purpose: .username),
                    ItemField(label: "type", kind: .text),
                    ItemField(label: "routing number", kind: .text),
                    ItemField(label: "account number", kind: .concealed, purpose: .password),
                    ItemField(label: "SWIFT", kind: .text),
                    ItemField(label: "IBAN", kind: .text),
                    ItemField(label: "PIN", kind: .concealed),
                ]),
                ItemSection(title: "Branch Information", fields: [
                    ItemField(label: "phone", kind: .phone),
                    ItemField(label: "address", kind: .address),
                ]),
            ]
        case .cryptoWallet:
            return [ItemSection(fields: [
                ItemField(label: "recovery phrase", kind: .concealed, purpose: .password),
                ItemField(label: "password", kind: .concealed),
                ItemField(label: "wallet address", kind: .text, purpose: .username),
            ])]
        case .database:
            return [ItemSection(fields: [
                ItemField(label: "type", kind: .text),
                ItemField(label: "server", kind: .text),
                ItemField(label: "port", kind: .text),
                ItemField(label: "database", kind: .text),
                ItemField(label: "username", kind: .text, purpose: .username),
                ItemField(label: "password", kind: .concealed, purpose: .password),
                ItemField(label: "SID", kind: .text),
                ItemField(label: "alias", kind: .text),
                ItemField(label: "connection options", kind: .text),
            ])]
        case .driverLicense:
            return [ItemSection(fields: [
                ItemField(label: "full name", kind: .text, purpose: .username),
                ItemField(label: "address", kind: .address),
                ItemField(label: "date of birth", kind: .date),
                ItemField(label: "sex", kind: .text),
                ItemField(label: "height", kind: .text),
                ItemField(label: "number", kind: .concealed, purpose: .password),
                ItemField(label: "license class", kind: .text),
                ItemField(label: "conditions / restrictions", kind: .text),
                ItemField(label: "state", kind: .text),
                ItemField(label: "country", kind: .text),
                ItemField(label: "expiry date", kind: .monthYear),
            ])]
        case .emailAccount:
            return [
                ItemSection(fields: [
                    ItemField(label: "type", kind: .text),
                    ItemField(label: "username", kind: .text, purpose: .username),
                    ItemField(label: "password", kind: .concealed, purpose: .password),
                    ItemField(label: "server", kind: .text),
                    ItemField(label: "port number", kind: .text),
                    ItemField(label: "security", kind: .text),
                    ItemField(label: "auth method", kind: .text),
                ]),
                ItemSection(title: "SMTP", fields: [
                    ItemField(label: "SMTP server", kind: .text),
                    ItemField(label: "port number", kind: .text),
                    ItemField(label: "username", kind: .text),
                    ItemField(label: "password", kind: .concealed),
                    ItemField(label: "security", kind: .text),
                    ItemField(label: "auth method", kind: .text),
                ]),
                ItemSection(title: "Contact Information", fields: [
                    ItemField(label: "provider", kind: .text),
                    ItemField(label: "provider's website", kind: .url),
                    ItemField(label: "phone (local)", kind: .phone),
                    ItemField(label: "phone (toll free)", kind: .phone),
                ]),
            ]
        case .medicalRecord:
            return [
                ItemSection(fields: [
                    ItemField(label: "date", kind: .date),
                    ItemField(label: "location", kind: .text),
                    ItemField(label: "healthcare professional", kind: .text),
                    ItemField(label: "patient", kind: .text, purpose: .username),
                    ItemField(label: "reason for visit", kind: .text),
                ]),
                ItemSection(title: "Medication", fields: [
                    ItemField(label: "medication", kind: .text),
                    ItemField(label: "dosage", kind: .text),
                    ItemField(label: "medication notes", kind: .text),
                ]),
            ]
        case .membership:
            return [ItemSection(fields: [
                ItemField(label: "group", kind: .text),
                ItemField(label: "website", kind: .url),
                ItemField(label: "telephone", kind: .phone),
                ItemField(label: "member name", kind: .text, purpose: .username),
                ItemField(label: "member since", kind: .monthYear),
                ItemField(label: "expiry date", kind: .monthYear),
                ItemField(label: "member ID", kind: .text),
                ItemField(label: "PIN", kind: .concealed, purpose: .password),
            ])]
        case .outdoorLicense:
            return [ItemSection(fields: [
                ItemField(label: "full name", kind: .text, purpose: .username),
                ItemField(label: "valid from", kind: .date),
                ItemField(label: "expires", kind: .date),
                ItemField(label: "approved wildlife", kind: .text),
                ItemField(label: "maximum quota", kind: .text),
                ItemField(label: "state", kind: .text),
                ItemField(label: "country", kind: .text),
            ])]
        case .passport:
            return [ItemSection(fields: [
                ItemField(label: "type", kind: .text),
                ItemField(label: "issuing country", kind: .text),
                ItemField(label: "number", kind: .concealed, purpose: .password),
                ItemField(label: "full name", kind: .text, purpose: .username),
                ItemField(label: "sex", kind: .text),
                ItemField(label: "nationality", kind: .text),
                ItemField(label: "issuing authority", kind: .text),
                ItemField(label: "date of birth", kind: .date),
                ItemField(label: "place of birth", kind: .text),
                ItemField(label: "issued on", kind: .date),
                ItemField(label: "expiry date", kind: .date),
            ])]
        case .rewardProgram:
            return [
                ItemSection(fields: [
                    ItemField(label: "company name", kind: .text),
                    ItemField(label: "member name", kind: .text, purpose: .username),
                    ItemField(label: "member ID", kind: .text),
                    ItemField(label: "PIN", kind: .concealed, purpose: .password),
                ]),
                ItemSection(title: "More Information", fields: [
                    ItemField(label: "member ID (additional)", kind: .text),
                    ItemField(label: "member since", kind: .monthYear),
                    ItemField(label: "customer service phone", kind: .phone),
                    ItemField(label: "phone for reservations", kind: .phone),
                    ItemField(label: "website", kind: .url),
                ]),
            ]
        case .server:
            return [
                ItemSection(fields: [
                    ItemField(label: "URL", kind: .url),
                    ItemField(label: "username", kind: .text, purpose: .username),
                    ItemField(label: "password", kind: .concealed, purpose: .password),
                ]),
                ItemSection(title: "Admin Console", fields: [
                    ItemField(label: "admin console URL", kind: .url),
                    ItemField(label: "admin console username", kind: .text),
                    ItemField(label: "console password", kind: .concealed),
                ]),
                ItemSection(title: "Hosting Provider", fields: [
                    ItemField(label: "name", kind: .text),
                    ItemField(label: "website", kind: .url),
                    ItemField(label: "support URL", kind: .url),
                    ItemField(label: "support phone", kind: .phone),
                ]),
            ]
        case .socialSecurityNumber:
            return [ItemSection(fields: [
                ItemField(label: "name", kind: .text, purpose: .username),
                ItemField(label: "number", kind: .concealed, purpose: .password),
            ])]
        case .softwareLicense:
            return [
                ItemSection(fields: [
                    ItemField(label: "version", kind: .text),
                    ItemField(label: "license key", kind: .concealed, purpose: .password),
                ]),
                ItemSection(title: "Customer", fields: [
                    ItemField(label: "licensed to", kind: .text, purpose: .username),
                    ItemField(label: "registered email", kind: .email),
                    ItemField(label: "company", kind: .text),
                ]),
                ItemSection(title: "Publisher", fields: [
                    ItemField(label: "download page", kind: .url),
                    ItemField(label: "publisher", kind: .text),
                    ItemField(label: "website", kind: .url),
                    ItemField(label: "retail price", kind: .text),
                    ItemField(label: "support email", kind: .email),
                ]),
                ItemSection(title: "Order", fields: [
                    ItemField(label: "purchase date", kind: .date),
                    ItemField(label: "order number", kind: .text),
                ]),
            ]
        case .sshKey:
            return [ItemSection(fields: [
                ItemField(label: "private key", kind: .sshKey, purpose: .password),
                ItemField(label: "public key", kind: .text),
                ItemField(label: "fingerprint", kind: .text),
                ItemField(label: "key type", kind: .text),
            ])]
        case .wirelessRouter:
            return [ItemSection(fields: [
                ItemField(label: "base station name", kind: .text, purpose: .username),
                ItemField(label: "base station password", kind: .concealed, purpose: .password),
                ItemField(label: "server / IP address", kind: .text),
                ItemField(label: "AirPort ID", kind: .text),
                ItemField(label: "network name", kind: .text),
                ItemField(label: "wireless security", kind: .text),
                ItemField(label: "wireless network password", kind: .concealed),
                ItemField(label: "attached storage password", kind: .concealed),
            ])]
        case .unknown:
            // A category this build doesn't recognize — no template to seed.
            return []
        }
    }
}
