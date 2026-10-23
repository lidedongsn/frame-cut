import FCCore
import SwiftUI

/// 把工程中的字段包装成 Binding，修改经由 EditorStore（可撤销）。
extension EditorModel {
    func clipBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<VideoClip, T>, default fallback: T) -> Binding<T> {
        Binding(
            get: { self.project.mainClip(id: id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.store.perform { $0.updateMain(id: id) { $0[keyPath: keyPath] = value } } }
        )
    }

    func musicBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<AudioClip, T>, default fallback: T) -> Binding<T> {
        Binding(
            get: { self.project.music(id: id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.store.perform { $0.updateMusic(id: id) { $0[keyPath: keyPath] = value } } }
        )
    }

    func subtitleBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<Subtitle, T>, default fallback: T) -> Binding<T> {
        Binding(
            get: { self.project.subtitle(id: id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.store.perform { $0.updateSubtitle(id: id) { $0[keyPath: keyPath] = value } } }
        )
    }

    func textBinding<T>(_ id: UUID, _ keyPath: WritableKeyPath<TextClip, T>, default fallback: T) -> Binding<T> {
        Binding(
            get: { self.project.text(id: id)?[keyPath: keyPath] ?? fallback },
            set: { value in self.store.perform { $0.updateText(id: id) { $0[keyPath: keyPath] = value } } }
        )
    }

    func projectBinding<T>(_ keyPath: WritableKeyPath<Project, T>) -> Binding<T> {
        Binding(
            get: { self.project[keyPath: keyPath] },
            set: { value in self.store.perform { $0[keyPath: keyPath] = value } }
        )
    }

    /// 滑块拖动期间合并为一次撤销。
    func coalesce(_ editing: Bool) {
        if editing { store.beginCoalescing() } else { store.endCoalescing() }
    }

    /// Time ↔ 秒的 Binding。
    func seconds(_ binding: Binding<Time>) -> Binding<Double> {
        Binding(get: { binding.wrappedValue.seconds }, set: { binding.wrappedValue = Time(seconds: $0) })
    }
}

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }
}

func colorBinding(_ binding: Binding<RGBA>) -> Binding<Color> {
    Binding(get: { binding.wrappedValue.color }, set: { binding.wrappedValue = RGBA($0) })
}
