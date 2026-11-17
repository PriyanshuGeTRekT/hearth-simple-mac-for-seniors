import SwiftUI

/// A drop-in for `@State` built on `@StateObject`.
///
/// In recent SDKs `@State` is a macro whose compiler plugin ships only inside Xcode's platform folder; on a machine whose
/// active developer directory is the Command Line Tools the plugin is not found and nothing that uses `@State` compiles.
/// This wrapper behaves the same and builds with either toolchain.
final class LocalBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ v: Value) { value = v }
}

@propertyWrapper
struct Local<Value>: DynamicProperty {
    @StateObject private var box: LocalBox<Value>

    init(wrappedValue: Value) { _box = StateObject(wrappedValue: LocalBox(wrappedValue)) }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}
