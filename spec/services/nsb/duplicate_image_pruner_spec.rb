# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'
require 'vips'

RSpec.describe Nsb::DuplicateImagePruner do
  # A left-to-right brightness ramp. Every pixel is darker than its neighbour,
  # so the difference hash is all zeros -- and stays all zeros at any size, which
  # is exactly the "same photo, different resolution" case being tested.
  def ramp(size, reverse: false)
    gradient = Vips::Image.xyz(size, size)[0].multiply(240.0 / size)
    gradient = gradient.linear(-1, 240) if reverse
    gradient.cast('uchar').write_to_buffer('.jpg')
  end

  def attach(product, filename, bytes)
    product.master.images.create!(
      attachment: { io: StringIO.new(bytes), filename: filename, content_type: 'image/jpeg' }
    )
  end

  let(:product) { create(:product, name: 'Tincture', sku: 'SKU-1') }

  describe 'a legacy copy of a site photo' do
    let!(:legacy) { attach(product, '245.jpg', ramp(64)) }
    let!(:from_site) { attach(product, 'abc123def456.jpg', ramp(256)) }

    it 'is listed for removal' do
      removals = described_class.new.call

      expect(removals.map { |r| r.removed[:filename] }).to eq([ '245.jpg' ])
    end

    it 'keeps the site original' do
      expect(described_class.new.call.first.kept[:filename]).to eq('abc123def456.jpg')
    end

    it 'deletes nothing on a dry run' do
      described_class.new(dry_run: true).call

      expect(product.reload.master.images.count).to eq(2)
    end

    it 'deletes the legacy image when applied' do
      described_class.new(dry_run: false).call

      expect(product.reload.master.images.map { |i| i.attachment.blob.filename.to_s })
        .to eq([ 'abc123def456.jpg' ])
    end
  end

  describe 'two site images that merely look alike' do
    # The real case this guards: a bottle's "Suggested Use" and "Supplement
    # Facts" panels hash identically but are two deliberate photographs.
    let!(:first) { attach(product, 'aaa111.jpg', ramp(128)) }
    let!(:second) { attach(product, 'bbb222.jpg', ramp(256)) }

    it 'are left alone, because neither came from the legacy import' do
      expect(described_class.new(dry_run: false).call).to be_empty
      expect(product.reload.master.images.count).to eq(2)
    end
  end

  describe 'a legacy image with no counterpart' do
    let!(:legacy) { attach(product, '245.jpg', ramp(64)) }
    let!(:different) { attach(product, 'abc123def456.jpg', ramp(64, reverse: true)) }

    it 'is kept' do
      expect(described_class.new(dry_run: false).call).to be_empty
      expect(product.reload.master.images.count).to eq(2)
    end
  end
end
