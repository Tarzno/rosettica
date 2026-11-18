import SwiftUI

/// The license Rosettica is published under. Must stay identical to the
/// LICENSE file in the repository root — Scripts/build-app.sh compares the two
/// (via `--license`) and refuses to build a bundle if they differ.
enum License {
    static let text = """
        MIT License

        Copyright (c) 2026 Hanno Teeling

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """

    /// The text as paragraphs, with the file's hard line breaks removed so
    /// each paragraph wraps to whatever width the window has.
    static var paragraphs: [String] {
        text.components(separatedBy: "\n\n").map {
            $0.replacingOccurrences(of: "\n", with: " ")
        }
    }
}

/// Rosettica ▸ License: shows the license text.
struct LicenseView: View {
    var body: some View {
        ScrollView {
            LicenseContent()
                .padding(24)
        }
        .frame(minWidth: 420, idealWidth: 560, minHeight: 300, idealHeight: 470)
    }
}

/// The license paragraphs (separate from the scroll view so they can be
/// rendered off screen for verification, like `HelpContent`).
struct LicenseContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(License.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                // The first paragraph is the license's name.
                Text(paragraph)
                    .font(index == 0 ? .system(size: 15, weight: .bold) : .system(size: 13))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
