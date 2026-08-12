# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

RSpec.describe Nsb::CatalogImporter do
  # 1x1 PNG. Small enough to keep the suite fast, real enough that Active
  # Storage and Solidus's image validations treat it as a genuine image.
  ONE_PIXEL_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

  let(:data_dir) { Pathname(Dir.mktmpdir) }

  def write_catalog(records)
    (data_dir / "product_images").mkpath
    (data_dir / "products.json").write(JSON.generate(records))
  end

  def write_image(filename)
    path = data_dir / "product_images" / filename
    path.dirname.mkpath
    path.binwrite(ONE_PIXEL_PNG)
    { "file" => filename, "sha256" => Digest::SHA256.hexdigest(ONE_PIXEL_PNG), "bytes" => ONE_PIXEL_PNG.bytesize }
  end

  def record(overrides = {})
    {
      "b2b_product_id" => 241,
      "sku" => "2302",
      "name" => "Supreme Formula Tincture",
      "description" => "<p>A tincture.</p>",
      "category_path" => "Tinctures/Supreme Formula",
      "price" => 48.0,
      "active" => true,
      "image" => nil
    }.merge(overrides)
  end

  after { FileUtils.remove_entry(data_dir) }

  subject(:importer) { described_class.new(data_dir: data_dir) }

  it "creates a product keyed on b2b_product_id" do
    write_catalog([record])

    result = importer.call

    expect(result.created).to eq(1)
    expect(result.failures).to be_empty
    product = Spree::Product.find_by(b2b_product_id: 241)
    expect(product.name).to eq("Supreme Formula Tincture")
    expect(product.master.sku).to eq("2302")
    expect(product.price).to eq(48.0)
  end

  it "builds the nested taxon tree from category_path" do
    write_catalog([record])

    importer.call

    taxon = Spree::Product.find_by(b2b_product_id: 241).taxons.first
    expect(taxon.name).to eq("Supreme Formula")
    expect(taxon.parent.name).to eq("Tinctures")
    expect(taxon.parent.parent.name).to eq("Categories")
  end

  it "updates in place rather than duplicating when re-run" do
    write_catalog([record])
    importer.call

    write_catalog([record("name" => "Renamed Tincture", "price" => 52.0)])
    result = described_class.new(data_dir: data_dir).call

    expect(result.created).to eq(0)
    expect(result.updated).to eq(1)
    expect(Spree::Product.where(b2b_product_id: 241).count).to eq(1)
    product = Spree::Product.find_by(b2b_product_id: 241)
    expect(product.name).to eq("Renamed Tincture")
    expect(product.price).to eq(52.0)
  end

  it "keeps a SKU that B2BWave left as the placeholder '-'" do
    write_catalog([record("sku" => "-")])

    importer.call

    expect(Spree::Product.find_by(b2b_product_id: 241).master.sku).to eq("-")
  end

  it "imports a priceless marketing item at zero rather than skipping it" do
    write_catalog([record("price" => nil, "name" => "Trifold Brochure")])

    result = importer.call

    expect(result.failures).to be_empty
    expect(Spree::Product.find_by(b2b_product_id: 241).price).to eq(0)
  end

  describe "images" do
    it "attaches the image with a clean filename" do
      write_catalog([record("image" => write_image("241.png"))])

      result = importer.call

      expect(result.images_attached).to eq(1)
      image = Spree::Product.find_by(b2b_product_id: 241).master.images.first
      expect(image.attachment).to be_attached
      # Guards the bug where passing a bare IO stored the absolute local path.
      expect(image.attachment.blob.filename.to_s).to eq("241.png")
    end

    it "does not re-upload an unchanged image on re-run" do
      write_catalog([record("image" => write_image("241.png"))])
      importer.call

      result = described_class.new(data_dir: data_dir).call

      expect(result.images_attached).to eq(0)
      expect(result.images_skipped).to eq(1)
      expect(ActiveStorage::Blob.count).to eq(1)
    end

    it "reports a failure instead of importing a product whose image is missing" do
      write_catalog([record("image" => { "file" => "gone.png", "bytes" => 10, "sha256" => "x" })])

      result = importer.call

      expect(result.failures.size).to eq(1)
      expect(result.failures.first[:error]).to match(/image file missing/)
      # The per-record transaction must leave nothing behind.
      expect(Spree::Product.where(b2b_product_id: 241)).to be_empty
    end
  end

  it "isolates a failing record so the rest of the catalog still imports" do
    write_catalog([
      record,
      record("b2b_product_id" => 242, "sku" => "2301", "name" => "", "category_path" => "Tinctures")
    ])

    result = importer.call

    expect(result.created).to eq(1)
    expect(result.failures.size).to eq(1)
    expect(Spree::Product.find_by(b2b_product_id: 241)).to be_present
  end
end
