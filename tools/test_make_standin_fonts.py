import pathlib
import sys
import unittest

from fontTools.ttLib import TTFont

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_standin_fonts as standin  # noqa: E402


def load(name: str) -> TTFont:
    return TTFont(standin.OUT / name)


class CommittedFontsTest(unittest.TestCase):
    """The fonts in test/fonts are what the script's numbers make: change a number and they must be made again."""

    def test_chinese_lines_are_pingfangs(self):
        for style, (weight, _) in standin.SC_WEIGHTS.items():
            font = load(f"StandInSC-{style}.ttf")
            em = font["head"].unitsPerEm
            self.assertEqual(font["hhea"].ascent, round(standin.SC_ASCENT * em), style)
            self.assertEqual(font["hhea"].descent, -round(standin.SC_DESCENT * em), style)
            self.assertEqual(font["OS/2"].sTypoAscender, font["hhea"].ascent, style)
            self.assertEqual(font["OS/2"].usWeightClass, weight, style)
            self.assertEqual(font["name"].getDebugName(1), "BiliFast StandIn SC")

    def test_latin_is_scaled_to_sf(self):
        for style, (weight, _) in standin.LATIN_WEIGHTS.items():
            font = load(f"StandInText-{style}.ttf")
            em = font["head"].unitsPerEm
            self.assertEqual(em, round(2048 / standin.LATIN_SCALE), style)
            self.assertEqual(font["hhea"].ascent, round(standin.LATIN_ASCENT * em), style)
            self.assertEqual(font["hhea"].descent, -round(standin.LATIN_DESCENT * em), style)
            self.assertEqual(font["OS/2"].usWeightClass, weight, style)
            self.assertEqual(font["name"].getDebugName(1), "BiliFast StandIn Text")

    def test_every_han_glyph_is_one_em(self):
        font = load("StandInSC-Regular.ttf")
        cmap, hmtx = font.getBestCmap(), font["hmtx"]
        advances = {hmtx[cmap[ord(c)]][0] for c in "设置版本账号清除日志"}
        self.assertEqual(advances, {font["head"].unitsPerEm})

    def test_the_repos_chinese_is_in_the_font(self):
        missing = sorted(c for c in standin.repo_han() if ord(c) not in load("StandInSC-Regular.ttf").getBestCmap())
        self.assertEqual(missing, [], "run uv run tools/make_standin_fonts.py; the test font draws these as boxes")

    def test_licences_sit_beside_the_fonts(self):
        for name in ("NotoSansSC-OFL.txt", "Inter-OFL.txt"):
            self.assertIn("SIL Open Font License", (standin.OUT / name).read_text(encoding="utf-8"))


class SourcesTest(unittest.TestCase):
    def test_gb2312_holds_its_6763_han(self):
        self.assertEqual(sum(1 for c in standin.gb2312() if standin.HAN.match(c)), 6763)


if __name__ == "__main__":
    unittest.main()
