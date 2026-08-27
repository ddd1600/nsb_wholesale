# frozen_string_literal: true

require "solidus_starter_frontend_spec_helper"

# The point of this importer is placement, not attachment. A 2018 lab test
# sitting above a 2025 one is a wrong answer presented confidently, so the
# ordering assertions here are the ones that matter.
RSpec.describe Nsb::LabTestImporter do
  subject(:importer) { described_class.new(data_dir: data_dir, logger: Logger.new(IO::NULL)) }

  # A real 1x1 JPEG. Small enough to attach in a spec, valid enough that Active
  # Storage's content-type detection and analysis both succeed.
  ONE_PIXEL_JPEG = Base64.decode64(<<~B64)
    /9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a
    HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAA
    AQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIh
    MUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpT
    VFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5
    usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iii
    gD//2Q==
  B64

  let(:data_dir) { Rails.root.join("tmp", "lab_tests_spec") }
  let(:product) { create(:product, b2b_product_id: 500) }

  let(:manifest) do
    {
      "certificates" => [
        { "coa" => "test coa", "files" => %w[new-coa-1.jpg new-coa-2.jpg], "b2b_product_ids" => [ 500 ] }
      ],
      "superseded_lab_test_files" => [ "old-lab-test.png" ]
    }
  end

  before do
    FileUtils.mkdir_p(data_dir)
    %w[new-coa-1.jpg new-coa-2.jpg].each { |name| File.binwrite(data_dir.join(name), ONE_PIXEL_JPEG) }
    File.write(data_dir.join("manifest.json"), JSON.pretty_generate(manifest))
    product
  end

  after { FileUtils.rm_rf(data_dir) }

  # Named so the ordering assertions read as the gallery a customer sees.
  def attach_existing(*filenames)
    filenames.each do |filename|
      product.master.images.create!(
        attachment: { io: StringIO.new(ONE_PIXEL_JPEG), filename: filename, content_type: "image/jpeg" }
      )
    end
  end

  def gallery
    product.master.images.reload.sort_by(&:position).map { |image| image.attachment.blob.filename.to_s }
  end

  it "attaches both pages of the certificate" do
    result = importer.call

    expect(result.attached).to eq(2)
    expect(gallery).to include("new-coa-1.jpg", "new-coa-2.jpg")
  end

  describe "placement" do
    it "puts the new certificate directly above the lab test it supersedes" do
      attach_existing("photo.jpg", "old-lab-test.png", "packaging.jpg")

      importer.call

      expect(gallery).to eq(%w[photo.jpg new-coa-1.jpg new-coa-2.jpg old-lab-test.png packaging.jpg])
    end

    # Product photography sells the product; a COA is a reference. It should not
    # displace the first image in the gallery.
    it "leaves the product photography above it" do
      attach_existing("photo.jpg", "old-lab-test.png")

      importer.call

      expect(gallery.first).to eq("photo.jpg")
    end

    it "appends the certificate last when the product has no older lab test" do
      attach_existing("photo.jpg", "packaging.jpg")

      importer.call

      expect(gallery).to eq(%w[photo.jpg packaging.jpg new-coa-1.jpg new-coa-2.jpg])
    end

    it "keeps the old lab test rather than deleting it" do
      attach_existing("old-lab-test.png")

      importer.call

      expect(gallery).to include("old-lab-test.png")
    end
  end

  describe "running twice" do
    it "repositions rather than attaching a second copy" do
      attach_existing("photo.jpg", "old-lab-test.png")

      importer.call
      second = importer.call

      expect(second.attached).to eq(0)
      expect(second.skipped_present).to eq(2)
      expect(gallery).to eq(%w[photo.jpg new-coa-1.jpg new-coa-2.jpg old-lab-test.png])
    end
  end

  describe "when the product is missing" do
    let(:manifest) do
      {
        "certificates" => [
          { "coa" => "orphan", "files" => [ "new-coa-1.jpg" ], "b2b_product_ids" => [ 999 ] },
          { "coa" => "test coa", "files" => [ "new-coa-2.jpg" ], "b2b_product_ids" => [ 500 ] }
        ],
        "superseded_lab_test_files" => []
      }
    end

    # The rake task exits non-zero on any failure, so this must be reported
    # rather than swallowed -- but one missing product must not cost the rest.
    it "records the failure and still attaches the others" do
      result = importer.call

      expect(result.failures.size).to eq(1)
      expect(result.failures.first[:b2b_product_id]).to eq(999)
      expect(gallery).to eq(%w[new-coa-2.jpg])
    end
  end

  describe "when a certificate file is missing from disk" do
    it "fails loudly rather than attaching a partial certificate" do
      FileUtils.rm(data_dir.join("new-coa-2.jpg"))

      result = importer.call

      expect(result.failures.size).to eq(1)
      expect(result.failures.first[:error]).to match(/missing/)
    end
  end
end
