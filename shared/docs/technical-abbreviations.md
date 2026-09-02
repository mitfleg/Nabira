# Technical abbreviations

System spell checkers are the primary word signal, but they are not a reliable source for
technical abbreviations. The dedicated abbreviation layer therefore runs before typo correction.

Contract:

1. Automatic abbreviation conversion is limited to Russian-layout input whose English-layout
   image is an exact entry in the curated list.
2. Entries contain 3–12 ASCII letters and return their canonical case (`vpn` → `VPN`,
   `oauth` → `OAuth`). Two-letter tokens remain conservative because layout collisions are dense.
3. The positive abbreviation signal runs before ALL-CAPS, camel-case, and dictionary vetoes.
4. A correctly typed English abbreviation is normalized before typo suggestions, so `vpn` cannot
   become an unrelated English word.
5. User `never convert` exceptions keep their existing higher priority. Undo learning remains able
   to suppress a false positive.
6. Both platform implementations must contain exactly the canonical entries in
   `shared/testdata/technical-abbreviations.json`.

The Russian-layout images were audited against the bundled 50k Russian frequency list. `EXE`
(`учу`) and `TLS` (`еды`) are deliberately excluded because their source images are real Russian
words. Adding an entry requires repeating this collision audit and adding a cross-platform test.
