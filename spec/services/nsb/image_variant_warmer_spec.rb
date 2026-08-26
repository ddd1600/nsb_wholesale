# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'
require 'vips'

RSpec.describe Nsb::ImageVariantWarmer do
  def photo
    Vips::Image.gaussnoise(900, 900, mean: 128, sigma: 40, seed: 3)
                .cast('uchar').write_to_buffer('.jpg', Q: 82)
  end

  let!(:product) { create(:product) }

  let!(:image) do
    product.master.images.create!(
      attachment: { io: StringIO.new(photo), filename: 'front.jpg', content_type: 'image/jpeg' }
    )
  end

  def transforms_while
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('transform.active_storage') { count += 1 }
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it 'generates a variant for every style it is asked for' do
    result = described_class.new(styles: %i[mini small]).call

    expect(result.generated).to eq(2)
    expect(result.failures).to be_empty
  end

  it 'warms the variants the storefront actually asks for' do
    # The property that matters. A variant is found by a digest of its
    # transformation hash, so a warmer that built that hash slightly differently
    # would report success and leave the page just as slow.
    described_class.new(styles: %i[small]).call

    later = transforms_while { image.reload.attachment.variant(:small) }

    expect(later).to eq(0)
  end

  it 'leaves a style it was not asked to warm cold' do
    described_class.new(styles: %i[small]).call

    later = transforms_while { image.reload.attachment.variant(:mini) }

    expect(later).to eq(1)
  end

  it 'is safe to re-run' do
    described_class.new(styles: %i[mini small]).call

    second = described_class.new(styles: %i[mini small]).call

    expect(second.generated).to eq(0)
    expect(second.existing).to eq(2)
  end

  it 'records a failure without aborting the rest' do
    broken = product.master.images.create!(
      attachment: { io: StringIO.new(photo), filename: 'broken.jpg', content_type: 'image/jpeg' }
    )
    broken.attachment.blob.update!(key: 'gone-from-storage')

    result = described_class.new(styles: %i[small]).call

    expect(result.failures.map { |row| row[:image_id] }).to eq([ broken.id ])
    expect(result.generated).to eq(1)
  end
end
