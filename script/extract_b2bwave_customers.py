#!/usr/bin/env python3
"""
Extract the B2BWave customer export into a reviewable intermediate file.

DEVELOPMENT-ONLY, and the output is NOT committed: db/import_data/customers.json
contains names, emails, phone numbers and postal addresses for ~360 wholesale
customers. It is gitignored, and must never reach the repo or Render's build.

Because of that, the customer import is a one-time migration you run from your
own machine against the target database -- unlike the catalog import, which
ships in the repo and re-runs freely on deploy.

Usage:
    python3 script/extract_b2bwave_customers.py
"""

import datetime
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "b2bwave_source_files"
OUT_FILE = ROOT / "db" / "import_data" / "customers.json"
CUSTOMERS_GLOB = "customers_*.xlsx"

# Every exported address is either US or GB, and 32 of the 33 that name a
# country are US. Blank countries are treated as US so the address is usable;
# the raw value is preserved in `source` either way.
DEFAULT_COUNTRY = "US"

# Fields kept verbatim under `source` so nothing in the export is lost, even
# where we cannot build a valid Solidus address from it.
SOURCE_FIELDS = [
    "company_name", "email", "name", "phone", "created_at", "customer_id",
    "reference_code", "address", "address2", "city", "province", "country",
    "postal_code", "website", "company_number", "tax_id", "comments_admin",
    "latest_order_submitted_at", "parent_customer_id", "minimum_order_value",
]


def cell(value):
    if value is None:
        return None
    if isinstance(value, str):
        value = value.strip()
        return value or None
    # openpyxl hands back datetime objects for date columns (created_at,
    # latest_order_submitted_at); JSON has no datetime, so store ISO 8601.
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.isoformat()
    return value


def main():
    matches = sorted(SOURCE_DIR.glob(CUSTOMERS_GLOB))
    if not matches:
        sys.exit(f"No customer export matching {CUSTOMERS_GLOB} in {SOURCE_DIR}")
    source = matches[-1]
    print(f"source: {source.relative_to(ROOT)}")

    import openpyxl

    workbook = openpyxl.load_workbook(source, read_only=True, data_only=True)
    rows = list(workbook.active.iter_rows(values_only=True))
    workbook.close()
    header = [str(h) if h is not None else "" for h in rows[0]]

    customers, skipped = [], []
    seen_emails = set()

    for raw in rows[1:]:
        row = dict(zip(header, raw))
        email = cell(row.get("email"))
        customer_id = cell(row.get("customer_id"))

        if not email or not customer_id:
            skipped.append({"customer_id": customer_id, "reason": "missing email or customer_id"})
            continue

        email = email.lower()
        if email in seen_emails:
            skipped.append({"customer_id": customer_id, "reason": f"duplicate email {email}"})
            continue
        seen_emails.add(email)

        record = {
            "b2b_customer_id": customer_id,
            "email": email,
            "company_name": cell(row.get("company_name")),
            "contact_name": cell(row.get("name")),
            "address": None,
            "source": {field: cell(row.get(field)) for field in SOURCE_FIELDS},
        }

        # Only emit a structured address when the parts Solidus insists on are
        # present. Phone is excluded deliberately -- only 21 of 360 rows have one,
        # so the app makes it optional instead (see config/initializers/spree.rb).
        street, city, zipcode = cell(row.get("address")), cell(row.get("city")), cell(row.get("postal_code"))
        state = cell(row.get("province"))
        if street and city and zipcode and state:
            record["address"] = {
                "address1": street,
                "address2": cell(row.get("address2")),
                "city": city,
                "zipcode": str(zipcode),
                "state": str(state),
                "country_iso": (cell(row.get("country")) or DEFAULT_COUNTRY).upper(),
                "phone": cell(row.get("phone")),
                "company": cell(row.get("company_name")),
                "name": cell(row.get("name")),
            }

        customers.append(record)

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text(json.dumps(customers, indent=2, sort_keys=True) + "\n")

    with_address = sum(1 for c in customers if c["address"])
    print(f"customers written : {len(customers)}")
    print(f"  with an address : {with_address}")
    print(f"  email only      : {len(customers) - with_address}")
    print(f"skipped           : {len(skipped)}")
    for entry in skipped:
        print(f"  ! {entry}")
    print(f"\nwrote {OUT_FILE.relative_to(ROOT)} (gitignored - contains PII)")
    return 1 if skipped else 0


if __name__ == "__main__":
    sys.exit(main())
