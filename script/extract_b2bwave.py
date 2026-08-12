#!/usr/bin/env python3
"""
Extract the B2BWave catalog export into a reviewable intermediate form.

This is a DEVELOPMENT-ONLY step. It never runs on production. It reads the
spreadsheet exports in b2bwave_source_files/ and writes:

    db/import_data/products.json          - catalog, reviewable as plain text
    db/import_data/shipping_methods.json  - rows B2BWave modelled as products
    db/import_data/product_images/<sku>.<ext>

The committed output is what the Rails importer consumes, so production never
needs Python, an xlsx gem, or network access to B2BWave's CDN. That matters:
we are migrating off B2BWave, and its Cloudinary account may not outlive the
migration.

Idempotent: images already downloaded are skipped unless --force is passed.

Usage:
    python3 script/extract_b2bwave.py [--force]
"""

import argparse
import hashlib
import json
import mimetypes
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "b2bwave_source_files"
OUT_DIR = ROOT / "db" / "import_data"
IMAGE_DIR = OUT_DIR / "product_images"

PRICE_LIST_GLOB = "All-Categories-Wholesale_Price_List_*.xlsx"

# B2BWave has no first-class shipping methods, so the previous operator modelled
# carriers as orderable products. They must NOT become Solidus products --
# Solidus has real shipping methods. Keyed by category_path.
SHIPPING_CATEGORY = "Shipping"

# Extensions we trust from the CDN response.
EXT_BY_TYPE = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}


def newest_source():
    matches = sorted(SOURCE_DIR.glob(PRICE_LIST_GLOB))
    if not matches:
        sys.exit(f"No price list matching {PRICE_LIST_GLOB} in {SOURCE_DIR}")
    return matches[-1]


def cell(value):
    """Normalise a spreadsheet cell to a clean value or None."""
    if value is None:
        return None
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return value


def read_rows(path):
    import openpyxl

    workbook = openpyxl.load_workbook(path, read_only=True, data_only=True)
    rows = list(workbook.active.iter_rows(values_only=True))
    workbook.close()
    header = [str(h) if h is not None else "" for h in rows[0]]
    return [dict(zip(header, row)) for row in rows[1:]]


def download(url, dest, force):
    """Fetch url to dest. Returns (status, sha256, bytes). Skips existing files."""
    if dest.exists() and not force:
        data = dest.read_bytes()
        return "skipped", hashlib.sha256(data).hexdigest(), len(data)

    request = urllib.request.Request(url, headers={"User-Agent": "nsb-wholesale-migration"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
        content_type = response.headers.get("Content-Type", "").split(";")[0].strip()

    if not content_type.startswith("image/"):
        raise ValueError(f"expected an image, got {content_type!r}")

    extension = EXT_BY_TYPE.get(content_type) or mimetypes.guess_extension(content_type) or ".jpg"
    dest = dest.with_suffix(extension)
    dest.write_bytes(data)
    return "downloaded", hashlib.sha256(data).hexdigest(), len(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="re-download images that already exist")
    args = parser.parse_args()

    source = newest_source()
    print(f"source: {source.relative_to(ROOT)}")
    rows = read_rows(source)
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)

    products, shipping, failures = [], [], []

    for row in rows:
        sku = cell(row.get("product_sku"))
        name = cell(row.get("product_name"))
        if not sku or not name:
            failures.append({"sku": sku, "name": name, "error": "missing sku or name"})
            continue

        category = cell(row.get("category_path")) or ""
        record = {
            "sku": str(sku),
            "name": name,
            "description": cell(row.get("product_desc")),
            "category_path": category,
            "price": cell(row.get("Wholesale Price List")),
            "msrp": cell(row.get("price_msrp")),
            "taxable": cell(row.get("product_tax")) == "Taxable",
            "active": bool(cell(row.get("product_active"))),
            "b2b_product_id": cell(row.get("b2b_product_id")),
            "source_url": cell(row.get("current_product_url")),
        }

        if category.split("/")[0] == SHIPPING_CATEGORY:
            shipping.append(record)
            continue

        # Prefer the live Cloudinary asset; the CloudFront copy is the fallback.
        image_url = cell(row.get("current_image_url")) or cell(row.get("last_imported_image_url"))
        record["image"] = None

        if image_url:
            try:
                # Filenames key on b2b_product_id, not sku: at least one live
                # product ships with the placeholder sku "-", and two contain
                # spaces. b2b_product_id is populated and unique for every row.
                basename = str(record["b2b_product_id"])
                status, digest, size = download(image_url, IMAGE_DIR / basename, args.force)
                stored = next(IMAGE_DIR.glob(f"{basename}.*"))
                record["image"] = {
                    "file": stored.name,
                    "sha256": digest,
                    "bytes": size,
                    "source_url": image_url,
                }
                print(f"  {status:11} {sku:16} {stored.name} ({size:,}b)")
            except Exception as error:  # noqa: BLE001 - report, never silently continue
                failures.append({"sku": str(sku), "url": image_url, "error": str(error)})
                print(f"  FAILED      {sku:16} {error}")
        else:
            print(f"  no-image    {sku:16} {name[:45]}")

        products.append(record)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "products.json").write_text(json.dumps(products, indent=2, sort_keys=True) + "\n")
    (OUT_DIR / "shipping_methods.json").write_text(json.dumps(shipping, indent=2, sort_keys=True) + "\n")

    with_image = sum(1 for p in products if p["image"])
    print("\n" + "=" * 60)
    print(f"products written    : {len(products)}  ({with_image} with an image)")
    print(f"shipping rows split : {len(shipping)}  -> shipping_methods.json (NOT products)")
    print(f"failures            : {len(failures)}")
    for failure in failures:
        print(f"  ! {failure}")

    # A non-zero exit on failure keeps this honest in a script or CI context.
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
