// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import SwiftUI

// The controls a window's regions hold, from the design system's Windows
// section: the segmented filter and the dot it carries, the popup button,
// the switch, the banner, and the row that reports a condition. Every
// number here is a `Win` token, so no view picks one.

/// One pill. `dot` is the worst state of the cards behind that segment,
/// and nil when they are all well: a row of green dots on a filter says
/// nothing and costs the eye the same.
struct AppSegmentItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var count: Int?
    var dot: Color?

    var id: Value {
        value
    }
}

/// The segmented filter. A filter can hide a card that needs the reader,
/// so a pill says so before it is pressed.
struct AppSegmented<Value: Hashable>: View {
    let items: [AppSegmentItem<Value>]
    @Binding var selection: Value
    /// The pills share the row's width equally: a two-way choice that is
    /// the whole of a sheet row, rather than a filter over a list.
    var fill = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { pill($0) }
        }
        .padding(2)
        .background(WindowSurface.segmentTrack, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
    }

    private func pill(_ item: AppSegmentItem<Value>) -> some View {
        let selected = selection == item.value
        return Button {
            selection = item.value
        } label: {
            HStack(spacing: Win.s3) {
                if let dot = item.dot {
                    StateDot(tint: dot)
                }
                Text(item.title).font(Win.button12)
                if let count = item.count {
                    Text("\(count)").font(Win.button12).foregroundStyle(selected ? .secondary : .tertiary)
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, Win.s5)
            .padding(.vertical, Win.s2)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(
                selected ? WindowSurface.segmentOn : .clear,
                in: RoundedRectangle(cornerRadius: Win.segment, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A row's setting when it is one of a short list of values. Its label is
/// the current value and never the setting's name: the name is the row's
/// first line, and a control repeating it says the value nowhere.
struct AppPopup<Value: Hashable>: View {
    let options: [AppSegmentItem<Value>]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option.title) { selection = option.value }
            }
        } label: {
            HStack(spacing: Win.s4) {
                Text(title).font(Win.button12).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold)).opacity(0.55)
            }
        }
        .menuStyle(.button)
        .buttonStyle(AppPopupStyle())
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var title: String {
        options.first { $0.value == selection }?.title ?? ""
    }
}

/// The popup's own shape: the search field's tokens, at a button's height.
struct AppPopupStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, Win.s4)
            .frame(height: Win.button)
            .background(WindowSurface.field, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Win.control, style: .continuous)
                    .strokeBorder(WindowSurface.controlLine, lineWidth: 1)
            )
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// The search field: the field's fill and line, a glyph, and a placeholder
/// that names what it filters.
struct AppSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: Win.s3) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(Win.button12)
        }
        .appField()
    }
}

/// A one-line text field on the search field's tokens, for the one value a
/// sheet asks you to type (a program's name).
struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 132

    var body: some View {
        TextField(placeholder, text: $text).textFieldStyle(.plain).font(Win.button12)
            .appField()
            .frame(width: width)
    }
}

extension View {
    /// The field's shape: fill, 1pt line, control radius, button height.
    func appField() -> some View {
        padding(.horizontal, Win.s4)
            .frame(height: Win.button)
            .background(WindowSurface.field, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Win.control, style: .continuous)
                    .strokeBorder(WindowSurface.controlLine, lineWidth: 1)
            )
    }
}

/// A setting that applies the moment it is flipped. macOS draws it, so it
/// is the one control with no tokens of its own.
struct AppSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// What just happened, in the window rather than in a modal over it. It
/// clears on the next action, and carries on its right the one thing the
/// sentence leaves open: an undo, or jit's own words.
struct WindowBanner<Actions: View>: View {
    let tint: Color
    let text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: Win.s3) {
            StateDot(tint: tint)
            Text(text).font(Win.sub)
            Spacer(minLength: Win.s5)
            HStack(spacing: Win.s3) { actions() }
        }
        .padding(.horizontal, Win.s6)
        .padding(.vertical, Win.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.13))
        .overlay(alignment: .bottom) { Rectangle().fill(WindowSurface.separator).frame(height: 1) }
    }
}

extension WindowBanner where Actions == EmptyView {
    /// A banner whose sentence is the whole of it.
    init(tint: Color, text: String) {
        self.init(tint: tint, text: text) { EmptyView() }
    }
}

/// A condition inside the card it belongs to: the mark, the word, one
/// fact that may wrap, jit's own words where they are the diagnosis, and
/// the single button that changes it.
struct AppNoteRow<Actions: View>: View {
    enum Mark {
        case dot(Color)
        case failed
        case busy
    }

    let mark: Mark
    let name: String
    var fact: String?
    var verbatim: String?
    var last = false
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Win.s5) {
                glyph.padding(.top, 2)
                VStack(alignment: .leading, spacing: Win.s1) {
                    Text(name).font(Win.rowName)
                    if let fact {
                        Text(fact).font(Win.rowFact).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let verbatim {
                        Text(verbatim).font(Win.command).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Win.s5).padding(.vertical, Win.s4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WindowSurface.verbatim, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
                            .padding(.top, Win.s3)
                    }
                }
                Spacer(minLength: Win.s5)
                HStack(spacing: Win.s3) { actions() }
            }
            .padding(.vertical, Win.s4)
            .padding(.horizontal, Win.s3)
            if !last {
                Rectangle().fill(WindowSurface.rowLine).frame(height: 1)
            }
        }
    }

    @ViewBuilder private var glyph: some View {
        switch mark {
        case let .dot(tint):
            StateDot(tint: tint).padding(.top, 4)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14)).foregroundStyle(Color(StatusMark.red))
        case .busy:
            ProgressView().controlSize(.small)
        }
    }
}

/// One line of a window's header, under the headline: a thing to do, in
/// the numbers a card below shows, ending in the card's verb as a link.
/// The header addition Findings introduced (jit-app #44), shared so every
/// window says its to-do the same way.
struct HeaderTodo: Identifiable {
    var id: String
    var text: String
    /// The verb, as a link at the end of the line; nil when the line asks
    /// nothing.
    var verb: String?
    var tint: Color
    var action: () -> Void = {}

    /// The line as one sentence: text, the app's separator, the verb.
    var sentence: String {
        verb.map { text + " · " + $0 } ?? text
    }
}

/// One Text per line with the verb linked inside it, so a narrow window
/// wraps the sentence as prose and never strands the verb. A dot in the
/// line's colour, always beside a word.
struct HeaderTodoLines: View {
    let todos: [HeaderTodo]

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s2) {
            ForEach(todos) { todo in
                HStack(alignment: .firstTextBaseline, spacing: Win.s4) {
                    Circle().fill(todo.tint).frame(width: 8, height: 8)
                    Text(Self.sentence(todo)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let todo = todos.first(where: { Self.url($0) == url }) {
                todo.action()
            }
            return .handled
        })
    }

    /// The sentence with its verb as a link, in the colour the app's plain
    /// buttons use.
    static func sentence(_ todo: HeaderTodo) -> AttributedString {
        var sentence = AttributedString(todo.sentence)
        if let verb = todo.verb, let range = sentence.range(of: verb, options: .backwards), let url = url(todo) {
            sentence[range].link = url
            sentence[range].foregroundColor = Color(StatusMark.accent)
        }
        return sentence
    }

    /// An address for the line's action, matched back in `openURL`; never
    /// opened anywhere else.
    static func url(_ todo: HeaderTodo) -> URL? {
        URL(string: "jitpass-todo://" + (todo.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))
    }
}
