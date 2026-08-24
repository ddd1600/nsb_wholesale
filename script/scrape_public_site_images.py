#!/usr/bin/env python3
"""Pull product images from the public newsouthbotanicals.com storefront.

Writes image files plus a manifest to db/import_data/scraped_images/ for review.
It does NOT touch the database -- run lib/tasks/nsb_images.rake afterwards to
import what the manifest describes.

Two sources, because neither alone is complete:

  * The public WooCommerce Store API (/wp-json/wc/store/products) gives every
    product with its full gallery, but variable products carry no SKU there and
    their variations expose no images.
  * Each product page embeds a `data-product_variations` JSON blob that does
    carry per-variation SKU and image -- and those SKUs are the ones that match
    the wholesale catalog.

Images are deduplicated by SHA-256, so a file shared by several products (very
common here -- variations usually reuse the parent shot) is stored once.

Usage:  python3 script/scrape_public_site_images.py
"""
import hashlib
import html
import json
import pathlib
import re
import sys
import time
import urllib.request

SITE = "https://newsouthbotanicals.com"
API = f"{SITE}/wp-json/wc/store/products?per_page=100&page=1"
# The site sits behind a WAF that 403s anything not shaped like a browser --
# a descriptive bot UA is rejected outright.
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
DELAY = 0.4  # be polite to the operator's own production site

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "db" / "import_data" / "scraped_images"
MANIFEST = OUT_DIR / "manifest.json"

VARIATIONS_RE = re.compile(r'data-product_variations="([^"]+)"')


def get(url, binary=False):
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read()
    time.sleep(DELAY)
    return body if binary else body.decode("utf-8", "replace")


def variation_rows(permalink):
    """[(sku, image_url)] from a product page's variation form, if it has one."""
    try:
        page = get(permalink)
    except Exception as error:  # noqa: BLE001 - reported, not swallowed
        print(f"  ! could not fetch {permalink}: {error}", file=sys.stderr)
        return []

    match = VARIATIONS_RE.search(page)
    if not match:
        return []

    try:
        variations = json.loads(html.unescape(match.group(1)))
    except json.JSONDecodeError as error:
        print(f"  ! unreadable variation blob on {permalink}: {error}", file=sys.stderr)
        return []

    rows = []
    for variation in variations:
        sku = (variation.get("sku") or "").strip()
        image = variation.get("image") or {}
        src = image.get("full_src") or image.get("src") or ""
        if sku:
            rows.append((sku, src))
    return rows


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    products = json.loads(get(API))
    print(f"{len(products)} products from the Store API")

    # sha256 -> {"file": name, "bytes": n, "sources": [url, ...]}
    blobs = {}
    # sku -> {"name": .., "images": [sha256, ...]}
    by_sku = {}
    # Every public product, whether or not it exposed a SKU. The importer needs
    # these to fall back to name matching -- the Delta-8 gummies (our two best
    # sellers) are a variable product whose variations carry no SKU at all.
    catalog = []
    unmatched_galleries = []

    def download(url):
        """Fetch a URL once, return its sha256, or None on failure."""
        for digest, blob in blobs.items():
            if url in blob["sources"]:
                return digest
        try:
            body = get(url, binary=True)
        except Exception as error:  # noqa: BLE001
            print(f"  ! could not fetch image {url}: {error}", file=sys.stderr)
            return None

        digest = hashlib.sha256(body).hexdigest()
        if digest in blobs:
            # Same bytes at a different URL -- record the alias, store once.
            blobs[digest]["sources"].append(url)
            return digest

        suffix = pathlib.Path(url.split("?")[0]).suffix.lower() or ".jpg"
        name = f"{digest[:16]}{suffix}"
        (OUT_DIR / name).write_bytes(body)
        blobs[digest] = {"file": name, "bytes": len(body), "sources": [url]}
        return digest

    def record(sku, product_name, digest):
        if digest is None:
            return
        entry = by_sku.setdefault(sku, {"name": product_name, "images": []})
        if digest not in entry["images"]:  # dedupe within a product
            entry["images"].append(digest)

    for product in products:
        name = product["name"]
        parent_sku = (product.get("sku") or "").strip()
        gallery = [image["src"] for image in product.get("images", []) if image.get("src")]
        print(f"- {name[:60]} ({product['type']}, {len(gallery)} gallery images)")

        gallery_digests = [download(url) for url in gallery]

        variations = variation_rows(product["permalink"]) if product["type"] == "variable" else []

        if parent_sku:
            for digest in gallery_digests:
                record(parent_sku, name, digest)

        for sku, src in variations:
            # The variation's own shot goes first, then the shared gallery.
            if src:
                record(sku, name, download(src))
            for digest in gallery_digests:
                record(sku, name, digest)

        variation_labels = [
            " ".join(attribute["value"] for attribute in variation["attributes"])
            for variation in product.get("variations", [])
        ]
        catalog.append({
            "name": name,
            "permalink": product["permalink"],
            "type": product["type"],
            "sku": parent_sku,
            "variation_skus": sorted({sku for sku, _src in variations}),
            "variation_labels": variation_labels,
            "images": [digest for digest in gallery_digests if digest],
        })

        if not parent_sku and not any(sku for sku, _src in variations):
            unmatched_galleries.append({"name": name, "permalink": product["permalink"]})

    manifest = {
        "site": SITE,
        "products_seen": len(products),
        "distinct_images": len(blobs),
        "skus": by_sku,
        "catalog": catalog,
        "blobs": blobs,
        "products_without_sku": unmatched_galleries,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")

    print()
    print(f"distinct images stored : {len(blobs)}")
    print(f"SKUs with images       : {len(by_sku)}")
    print(f"products with no SKU   : {len(unmatched_galleries)} (importer falls back to name matching)")
    for row in unmatched_galleries:
        print(f"  - {row['name']}")
    print(f"wrote {MANIFEST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
