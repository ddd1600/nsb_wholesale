# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'
require 'vips'

RSpec.describe Nsb::SiteImageImporter do
  # A distinct solid-colour PNG per level, so checksums differ and the pictures
  # are genuinely different.
  def png(level)
    Vips::Image.black(24, 24).add(level).cast('uchar').write_to_buffer('.png')
  end

  let(:tmp_dir) { Pathname.new(Dir.mktmpdir) }

  # Keyed by real SHA-256, exactly as the manifest is: the importer verifies
  # downloaded bytes against the key before attaching them.
  let(:images) do
    { first: png(20), second: png(120), third: png(220) }
  end

  def digest_of(key) = Digest::SHA256.hexdigest(images.fetch(key))
  def filename_of(key) = "#{digest_of(key)[0, 16]}.png"

  let(:blobs) do
    images.to_h do |key, bytes|
      [ digest_of(key),
       { file: filename_of(key), bytes: bytes.bytesize, sources: [ "https://example.test/#{key}.png" ] } ]
    end
  end

  let(:manifest) do
    {
      site: 'https://example.test',
      products_seen: 2,
      distinct_images: blobs.size,
      skus: {
        'MATCHED-SKU' => { name: 'Public product', images: [ digest_of(:first), digest_of(:second) ] }
      },
      catalog: [
        { name: 'No SKU product', permalink: 'https://example.test/p', type: 'variable',
          sku: '', variation_skus: [], variation_labels: [ '10 Count' ], images: [ digest_of(:third) ] }
      ],
      blobs: blobs,
      products_without_sku: []
    }
  end

  let(:overrides) { { 'OVERRIDE-SKU' => 'No SKU product' } }

  before do
    images.each_key { |key| tmp_dir.join(filename_of(key)).binwrite(images.fetch(key)) }
    tmp_dir.join('manifest.json').write(manifest.to_json)
    tmp_dir.join('sku_overrides.json').write(overrides.to_json)

    stub_const("#{described_class}::DATA_DIR", tmp_dir)
    stub_const("#{described_class}::MANIFEST_PATH", tmp_dir.join('manifest.json'))
    stub_const("#{described_class}::OVERRIDES_PATH", tmp_dir.join('sku_overrides.json'))
  end

  after { FileUtils.remove_entry(tmp_dir) }

  let!(:matched) { create(:product, name: 'Matched', sku: 'MATCHED-SKU') }
  let!(:overridden) { create(:product, name: 'Overridden', sku: 'OVERRIDE-SKU') }
  let!(:absent) { create(:product, name: 'Not on the public site', sku: 'MISSING-SKU') }

  describe '#call' do
    it 'attaches every manifest image for a SKU match' do
      described_class.new.call

      expect(matched.reload.master.images.count).to eq(2)
    end

    it 'keeps the manifest order, so the site featured image lands first' do
      described_class.new.call

      expect(matched.reload.master.images.map { |i| i.attachment.blob.filename.to_s })
        .to eq([ filename_of(:first), filename_of(:second) ])
    end

    it 'links products whose public listing exposes no SKU via sku_overrides.json' do
      described_class.new.call

      expect(overridden.reload.master.images.map { |i| i.attachment.blob.filename.to_s }).to eq([ filename_of(:third) ])
    end

    it 'reports products the public site has no images for' do
      result = described_class.new.call

      expect(result.products_unmatched.map { |row| row[:sku] }).to contain_exactly('MISSING-SKU')
    end

    it 'counts what it attached' do
      expect(described_class.new.call.attached).to eq(3)
    end

    it 'is safe to re-run' do
      described_class.new.call
      second = described_class.new.call

      expect(matched.reload.master.images.count).to eq(2)
      expect(second.attached).to eq(0)
      # Two on the SKU match plus one on the override.
      expect(second.skipped_identical).to eq(3)
    end

    it 'does not re-attach an image the product already has' do
      matched.master.images.create!(
        attachment: { io: StringIO.new(images[:first]), filename: filename_of(:first), content_type: 'image/png' }
      )

      described_class.new.call

      expect(matched.reload.master.images.count).to eq(2)
    end

    it 'raises a useful error when an override points nowhere' do
      tmp_dir.join('sku_overrides.json').write({ 'OVERRIDE-SKU' => 'Nonexistent' }.to_json)

      result = described_class.new.call

      expect(result.failures.first[:error]).to include('not in the manifest')
    end
  end

  describe 'when the scrape output is not on disk, as on Render' do
    # The image files are gitignored, so production has the manifest and nothing
    # else. The importer falls back to the source URLs the manifest recorded.
    before do
      images.each_key { |key| tmp_dir.join(filename_of(key)).delete }
    end

    def stub_source(status: 200, body: nil)
      response = instance_double(
        status == 200 ? Net::HTTPOK : Net::HTTPNotFound, code: status.to_s, body: body
      )
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(status == 200)
      allow(Net::HTTP).to receive(:start).and_return(response)
    end

    it 'downloads the image and attaches it' do
      stub_source(body: images[:first])

      result = described_class.new.call

      expect(result.downloaded).to be_positive
      expect(matched.reload.master.images.count).to be_positive
    end

    it 'refuses bytes that do not match the manifest checksum' do
      # The source URL having been repointed at a different picture. Attaching
      # the wrong photo silently is worse than failing.
      stub_source(body: png(199))

      result = described_class.new.call

      expect(result.attached).to eq(0)
      expect(result.failures.first[:error]).to include('no longer matches the manifest')
    end

    it 'reports a failed fetch rather than attaching nothing quietly' do
      stub_source(status: 404, body: '')

      result = described_class.new.call

      expect(result.failures.first[:error]).to include('returned 404')
    end

    it 'does not download an image the product already has' do
      # Filenames are content-derived, so this is decided before any fetch.
      matched.master.images.create!(
        attachment: { io: StringIO.new(images[:first]), filename: filename_of(:first), content_type: 'image/png' }
      )
      stub_source(body: images[:second])

      result = described_class.new.call

      expect(result.skipped_identical).to be_positive
      expect(matched.reload.master.images.map { |i| i.attachment.blob.filename.to_s })
        .to include(filename_of(:first))
    end
  end

  describe 'ordering' do
    it 'puts images back into the manifest order' do
      # Nsb::CatalogImporter attaches the B2BWave copy of a photo and a later
      # prune removes it, which leaves the survivors in an order nobody chose.
      matched.master.images.create!(
        attachment: { io: StringIO.new(images[:second]), filename: filename_of(:second), content_type: 'image/png' }
      )

      described_class.new.call

      expect(matched.reload.master.images.order(:position).map { |i| i.attachment.blob.filename.to_s })
        .to eq([ filename_of(:first), filename_of(:second) ])
    end

    it 'leaves images the manifest does not know about at the end' do
      matched.master.images.create!(
        attachment: { io: StringIO.new(png(60)), filename: 'stranger.png', content_type: 'image/png' }
      )

      described_class.new.call

      expect(matched.reload.master.images.order(:position).map { |i| i.attachment.blob.filename.to_s })
        .to eq([ filename_of(:first), filename_of(:second), 'stranger.png' ])
    end

    it 'reports nothing to reorder on a second run' do
      described_class.new.call

      expect(described_class.new.call.products_matched.map { |row| row[:reordered] }).to all(be false)
    end
  end

  describe 'dry run' do
    it 'writes nothing' do
      result = described_class.new(dry_run: true).call

      expect(result.attached).to eq(3)
      expect(matched.reload.master.images.count).to eq(0)
    end
  end
end
