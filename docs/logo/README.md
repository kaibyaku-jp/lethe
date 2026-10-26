# lethe logo

The mark is Λ, the first letter of ΛΗΘΗ (Lethe), standing in the river of
forgetting: the waves wash its feet away. The waves cut the letter through a
mask, so the mark sits on any background. The wordmark and tagline are set in
Kalam and outlined, so the SVGs need no fonts.

| file | use |
| --- | --- |
| `lethe-logo-vertical.svg` | Mark, wordmark and tagline stacked; README header |
| `lethe-logo.svg` | Mark and wordmark side by side |
| `lethe-mark.svg` | The mark alone |
| `lethe-icon.svg` | A heavier mark with two waves for 16 to 48 px: favicons, avatars |

Each file has a `-dark` variant for dark backgrounds.

## Colors

| role | light | dark |
| --- | --- | --- |
| River | `#2B6F8F` | `#5BA4C4` |
| Letter and wordmark | `#1E1E1E` | `#F2F0EA` |
| Tagline | `#5F6368` | `#A9AFB8` |

## Rebuilding

`build.py` draws the mark and outlines the text with fontTools. Download
Kalam from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/kalam)
and run:

```sh
nix shell --impure --expr 'let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem}; in pkgs.python3.withPackages (ps: [ ps.fonttools ])' \
  -c python3 -I docs/logo/build.py path/to/kalam docs/logo
```

## License

The logo is part of this repository and released under its MIT license.
Kalam is by the Indian Type Foundry under the SIL Open Font License 1.1; the
wordmark uses outlines of its glyphs.
