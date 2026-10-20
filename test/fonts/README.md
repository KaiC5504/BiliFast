# Stand-ins for the iPhone's system font

Tests only; nothing here ships in the app. The phone draws SF with PingFang SC for Chinese, both Apple's and licensed
only for Apple devices, so widget tests and look-alike checks of the system path load these instead
(`test/support/stand_in_fonts.dart`):

- `StandInSC-*.ttf` stand in for PingFang SC: Noto Sans SC (Adobe and Google, SIL Open Font License 1.1,
  `NotoSansSC-OFL.txt`), cut to GB2312 and the Chinese the code and tests use, instanced at three weights, given
  PingFang's line metrics, its Han glyphs lowered to PingFang's place.
- `StandInText-*.ttf` stand in for SF: Inter (The Inter Project Authors, SIL Open Font License 1.1, `Inter-OFL.txt`),
  instanced at four weights, scaled to SF's cap height and spacing, given SF's line metrics, its brackets lowered.

Both are modified versions under the OFL, renamed "BiliFast StandIn SC" and "BiliFast StandIn Text"; the sources are
Google Fonts' files at the commit `tools/make_standin_fonts.py` pins. Run that script to make them again; the numbers
in it say which phone screenshot settled each change.
