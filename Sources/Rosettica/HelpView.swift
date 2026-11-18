import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            HelpContent()
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 640)
    }
}

struct HelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                Text("Rosettica User Guide")
                    .font(.title.bold())

                helpSection(
                    "What is Rosettica?",
                    """
                    Rosettica recreates the classic gear drawing toy invented by Denys Fisher and \
                    first presented in 1965. Toothed cogs roll inside or around rings and other \
                    frames; a pen placed in one of the cog's holes traces intricate, flower-like \
                    curves — hypotrochoids when rolling inside a form, epitrochoids when rolling \
                    around the outside. The simulation is faithful, teeth and all.
                    """
                )

                helpSection(
                    "Quick start",
                    """
                    1. Pick a form (the fixed piece) — a ring, triangle, square, pentagon, \
                    hexagon, or oval.
                    2. Choose whether the cog rolls Inside or Outside the form.
                    3. Pick a cog size. Only cogs that physically fit the form are offered.
                    4. Set the pen hole position: near the rim gives bold loops, near the center \
                    gives gentle curves.
                    5. Adjust line width, line color, and paper (background) color.
                    6. The Preview box and the translucent curve on the canvas show exactly what \
                    you will get. Click “Draw Pattern” (⌘D) to stamp it.
                    7. Change the settings and stamp again — layering patterns in different colors \
                    is what it is all about.
                    """
                )

                helpSection(
                    "Watching a pattern come to life",
                    """
                    The “Drawing speed” control decides how a stamped pattern appears. “Instant” \
                    and “Fast” give quick results. “Slow” and especially “Learn” mimic the real \
                    toy: the toothed cog rolls along the form's teeth at constant speed while the \
                    pen in its hole draws the line — you can watch the gear ratio do its magic, \
                    tooth by tooth, lap by lap. Notice how the pen speeds up and slows down even \
                    though the cog rolls steadily — that is the mathematics of the curve at work. \
                    “Finish Drawing Now” completes the pattern immediately if a slow drawing takes \
                    too long. “Random Demo” (⇧⌘R) turns the canvas into an endless show: random \
                    patterns in vibrant colors on black, drawn one after another with the rolling \
                    cog visible, exactly like the Rosettica screensaver. Your document is not \
                    changed — click the button again to return to your own drawing.
                    """
                )

                helpSection(
                    "How the shape is determined",
                    """
                    The pattern repeats after the cog has gone around the form a number of times \
                    given by the tooth counts: a curve closes after (cog teeth ÷ greatest common \
                    divisor of both tooth counts) laps. Small common divisors give dense, \
                    many-petaled rosettes; large ones give simple flowers. The classic ring has 96 \
                    teeth inside and 105 outside — try the 105-tooth side with a 52-tooth cog for \
                    a spectacular 52-lap pattern.
                    """
                )

                helpSection(
                    "Layers, undo, and starting over",
                    """
                    Every stamped pattern becomes a layer, listed in the sidebar. Remove a single \
                    layer with its trash button, or use “Clear All”. Everything — drawing, \
                    deleting, background changes — can be undone with ⌘Z and redone with ⇧⌘Z.
                    """
                )

                helpSection(
                    "Saving, loading, exporting, printing",
                    """
                    • Save (⌘S) / Save As (⇧⌘S) store your work as a .rosettica document.
                    • Open (⌘O) loads a saved document; recent files appear in File ▸ Open Recent.
                    • File ▸ Export writes the finished pattern as a PNG image (⌘E, 2048 × 2048 \
                    pixels) or as resolution-independent vector graphics: SVG (⇧⌘E) or PDF (⌥⌘E), \
                    1200 × 1200 pt with smooth Bézier curves — ideal for large prints, plotters \
                    and further editing in vector drawing apps.
                    • Print (⌘P) prints the finished pattern, scaled to fit the page.
                    """
                )

                helpSection(
                    "Tips",
                    """
                    • The dashed outline on the canvas shows the selected form; the dashed circle \
                    is the cog with its pen hole at the start position.
                    • “Start position” rotates where the cog begins — on non-circular forms this \
                    genuinely changes the pattern, not just its orientation.
                    • “Form rotation” spins the whole form. Stamp a pattern, rotate the form \
                    (say a triangle by 60°), and stamp again for kaleidoscopic overlays.
                    • Pen hole at 100 % on a 48-tooth cog inside the 96-ring draws a perfectly \
                    straight line — a famous curiosity known as Cardan circles.
                    • Light lines (0.5–1 pt) layered many times look most like the real toy.
                    """
                )
        }
    }

    private func helpSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
