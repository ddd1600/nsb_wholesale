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

  let(:blobs) do
    {
      'aaa' => png(20),
      'bbb' => png(120),
      'ccc' => png(220)
    }
  end

  let(:manifest) do
    {
      site: 'https://example.test',
      products_seen: 2,
      distinct_images: blobs.size,
      skus: {
        'MATCHED-SKU' => { name: 'Public product', images: %w[aaa bbb] }
      },
      catalog: [
        { name: 'No SKU product', permalink: 'https://example.test/p', type: 'variable',
          sku: '', variation_skus: [], variation_labels: [ '10 Count' ], images: %w[ccc] }
      ],
      blobs: blobs.transform_values.with_index do |bytes, index|
        { file: "#{%w[aaa bbb ccc][index]}.png", bytes: bytes.bytesize, sources: [ "https://example.test/#{index}.png" ] }
      end,
      products_without_sku: []
    }
  end

  let(:overrides) { { 'OVERRIDE-SKU' => 'No SKU product' } }

  before do
    blobs.each { |key, bytes| tmp_dir.join("#{key}.png").binwrite(bytes) }
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
        .to eq([ 'aaa.png', 'bbb.png' ])
    end

    it 'links products whose public listing exposes no SKU via sku_overrides.json' do
      described_class.new.call

      expect(overridden.reload.master.images.map { |i| i.attachment.blob.filename.to_s }).to eq([ 'ccc.png' ])
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
        attachment: { io: StringIO.new(blobs['aaa']), filename: 'aaa.png', content_type: 'image/png' }
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

  describe 'ordering' do
    it 'puts images back into the manifest order' do
      # Nsb::CatalogImporter attaches the B2BWave copy of a photo and a later
      # prune removes it, which leaves the survivors in an order nobody chose.
      matched.master.images.create!(
        attachment: { io: StringIO.new(blobs['bbb']), filename: 'bbb.png', content_type: 'image/png' }
      )

      described_class.new.call

      expect(matched.reload.master.images.order(:position).map { |i| i.attachment.blob.filename.to_s })
        .to eq([ 'aaa.png', 'bbb.png' ])
    end

    it 'leaves images the manifest does not know about at the end' do
      matched.master.images.create!(
        attachment: { io: StringIO.new(png(60)), filename: 'stranger.png', content_type: 'image/png' }
      )

      described_class.new.call

      expect(matched.reload.master.images.order(:position).map { |i| i.attachment.blob.filename.to_s })
        .to eq([ 'aaa.png', 'bbb.png', 'stranger.png' ])
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
