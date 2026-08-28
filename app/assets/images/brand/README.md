# Brand assets

Masters live outside the repo, in the operator's
`~/New South Botanicals/_____________logos` (vector `.ai`/`.pdf`/`.svg`, print
resolution PNGs, gold and monochrome variants, a full favicon set). Only what
the storefront renders is copied here; go back to that folder for anything else
rather than re-cutting artwork from these files.

`nsb_logo_horizontal.png` (610x200, transparent)
: Pineapple left, wordmark right. The header lockup. Taken from
  newsouthbotanicals.com's own upload rather than the brand folder, because the
  brand folder's horizontal versions are a different arrangement -- pineapples
  on both sides, or the pineapple on the right in gold or white. At the 44px the
  header renders it, 610px is about four times oversampled.

`nsb_logo_horizontal_light.png` (610x200, transparent)
: The same lockup with the wordmark recoloured to sand (#F5F3F0) for the dark
  theme. GENERATED, not a designer file -- the brand folder has no white version
  of this particular arrangement. `nsb:brand:light_variant` rebuilds it; it
  swaps pixels that are both dark and unsaturated, which catches the near-black
  text and leaves the pineapple's greens alone. Replace it with a real asset if
  one is ever drawn.

`nsb_logo_mark.png` (651x831, transparent)
: The pineapple alone, no wordmark, copied from
  `newsouth logo without text.png`. Not yet used anywhere. It suits a narrow
  mobile header, an email signature, or anywhere the full lockup would be
  squeezed. The higher-resolution `NSB colored high res pineapple only.png` in
  the brand folder was passed over: it carries a stray TM and sits off-centre on
  its canvas.

Favicons are in `public/`, from the brand folder's prepared set: the pineapple
without its palmetto leaves, which is the version that survives being 16px.
They replaced Solidus's starter favicon, which was Solidus's own logo.

The `logo_*.svg` files one directory up are the Solidus starter frontend's
placeholders. Nothing references them.
