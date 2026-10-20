import io
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import screen_diff  # noqa: E402

FONT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "fonts" / "MiSans-Regular.ttf"
WIDTH, HEIGHT = 1320, 900
LINE = "奥丁也是有打法也是得练的不会用"


def font(pt: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT), round(pt * 3))


def draw_text(draw: ImageDraw.ImageDraw, x_pt: float, centre_pt: float, text: str, *, pt: float = 15,
              tracking: float = 0, fill=(24, 25, 28)) -> None:
    face = font(pt)
    x = x_pt * 3
    for char in text:
        draw.text((x, centre_pt * 3), char, font=face, fill=fill, anchor="lm")
        x += face.getlength(char) + tracking * 3


def screen(*, lines: list[tuple[float, float]], top: float = 0, box: tuple[float, float] | None = None,
           size: float = 15, tracking: float = 0, fill=(24, 25, 28)) -> Image.Image:
    """A white screen with a line of text at each (x, centre) pt, all moved down `top` pt, and a grey box."""
    image = Image.new("RGB", (WIDTH, HEIGHT), "white")
    draw = ImageDraw.Draw(image)
    if box is not None:
        draw.rounded_rectangle((54 * 3, (box[0] + top) * 3, 428 * 3, (box[1] + top) * 3), radius=24,
                               fill=(246, 247, 248))
    for x, centre in lines:
        draw_text(draw, x, centre + top, LINE, pt=size, tracking=tracking, fill=fill)
    return image


class ScreenDiffTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = pathlib.Path(self.folder.name)

    def measure(self, ours: Image.Image, official: Image.Image, **options):
        a, b = self.root / "ours.png", self.root / "official.png"
        ours.save(a)
        official.save(b)
        return screen_diff.run(a, b, **options)

    def matched(self, rows):
        return [row for row in rows if row.ours is not None and row.official is not None]

    def test_the_same_screen_has_nothing_marked(self):
        shot = screen(lines=[(56, 50), (56, 74), (66, 120)], box=(100, 140))
        text, rows, shift = self.measure(shot, shot)
        self.assertEqual(shift, 0)
        self.assertEqual(len(self.matched(rows)), 3)
        self.assertTrue(all(not row.marks for row in rows), text)
        self.assertIn("0 of 3 elements flagged", text)

    def test_a_shot_cropped_lower_lines_up_without_marks(self):
        ours = screen(lines=[(56, 50), (56, 74), (56, 98)])
        official = screen(lines=[(56, 50), (56, 74), (56, 98)], top=10).crop((0, 0, WIDTH, HEIGHT - 60))
        text, rows, shift = self.measure(ours, official)
        self.assertAlmostEqual(shift / 3, 10, places=0)
        self.assertTrue(all(not row.marks for row in rows), text)

    def test_two_whole_screens_are_lined_up_by_the_status_bar(self):
        ours = screen(lines=[(56, 50), (56, 74), (56, 98)])
        official = screen(lines=[(56, 50), (56, 74), (56, 98)], top=4)
        text, rows, shift = self.measure(ours, official)
        self.assertEqual(shift, 0)
        self.assertAlmostEqual(self.matched(rows)[0].dy, 4, delta=0.4, msg=text)

    def test_one_line_lower_shows_as_a_step_there_and_nowhere_else(self):
        ours = screen(lines=[(56, 50), (56, 74), (56, 98), (56, 122)])
        official = screen(lines=[(56, 50), (56, 74), (56, 101), (56, 125)])
        text, rows, _ = self.measure(ours, official)
        steps = [row.step for row in self.matched(rows)]
        self.assertAlmostEqual(steps[2], 3, delta=0.4, msg=text)
        self.assertLess(abs(steps[3]), 0.4, text)
        self.assertIn("step +3", "  ".join(self.matched(rows)[2].marks))

    def test_tracked_text_reads_wider_at_the_same_size_and_centre(self):
        ours = screen(lines=[(56, 50)], tracking=0.25)
        official = screen(lines=[(56, 50)])
        text, rows, _ = self.measure(ours, official)
        row = self.matched(rows)[0]
        self.assertTrue(any(mark.startswith("width +") for mark in row.marks), text)
        self.assertAlmostEqual(row.glyph, 1, delta=0.03)
        self.assertLess(abs(row.dy), 0.4)

    def test_a_bigger_font_reads_as_size(self):
        text, rows, _ = self.measure(screen(lines=[(56, 50)], size=16), screen(lines=[(56, 50)], size=15))
        row = self.matched(rows)[0]
        self.assertTrue(any(mark.startswith("size +") for mark in row.marks), text)

    def test_lighter_glyphs_read_as_less_ink(self):
        ours = screen(lines=[(56, 50)], fill=(120, 120, 124))
        text, rows, _ = self.measure(ours, screen(lines=[(56, 50)]))
        self.assertLess(self.matched(rows)[0].ink, 0.85, text)

    def test_white_text_on_the_dark_player_is_measured_too(self):
        def dark(top: float) -> Image.Image:
            image = Image.new("RGB", (WIDTH, HEIGHT), (12, 12, 14))
            draw_text(ImageDraw.Draw(image), 56, 50 + top, LINE, fill=(255, 255, 255))
            return image

        text, rows, _ = self.measure(dark(0), dark(2))
        row = self.matched(rows)[0]
        self.assertAlmostEqual(row.dy, 2, delta=0.4, msg=text)
        self.assertAlmostEqual(row.glyph, 1, delta=0.03)

    def test_a_grey_box_is_found_through_its_text_and_its_edges_compared(self):
        ours = screen(lines=[(66, 120), (66, 143)], box=(100, 170))
        official = screen(lines=[(66, 120), (66, 143)], box=(100, 160))
        text, _, _ = self.measure(ours, official)
        box = [line for line in text.splitlines() if line.strip().startswith("box")]
        self.assertEqual(len(box), 1, text)
        self.assertTrue(box[0].strip().startswith("box 100.00-170"), text)
        self.assertIn("bottom -10.00", box[0])
        self.assertNotIn("top", box[0].split(" vs ")[1])

    def test_a_line_missing_from_one_shot_is_listed(self):
        text, rows, _ = self.measure(screen(lines=[(56, 50), (56, 74), (56, 98)]), screen(lines=[(56, 50), (56, 98)]))
        self.assertEqual(sum(1 for row in rows if row.official is None), 1, text)
        self.assertIn("only in ours", text)

    def test_the_command_line_prints_utf8_and_writes_the_overlay_where_asked(self):
        shot = screen(lines=[(56, 50)])
        a, b = self.root / "a.png", self.root / "b.png"
        shot.save(a)
        shot.save(b)
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(screen_diff.main([str(a), str(b), "--overlay", str(self.root / "overlay")]), 0)
        self.assertIn("official = ours +0.00 pt", out.getvalue())
        self.assertTrue((self.root / "overlay" / "a__b.png").is_file())


if __name__ == "__main__":
    unittest.main()
