# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'
require 'vips'

RSpec.describe Nsb::LogoLightVariant do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  let(:source) { dir.join('logo.png') }
  let(:target) { dir.join('logo_light.png') }

  # Left half near-black (the wordmark), right half saturated green (the
  # pineapple), fully opaque.
  before do
    width = 40
    ink = Vips::Image.black(width / 2, 20).add([ 34, 34, 34 ]).cast('uchar')
    brand = Vips::Image.black(width / 2, 20).add([ 20, 170, 90 ]).cast('uchar')
    opaque = Vips::Image.black(width, 20).add(255).cast('uchar')
    ink.join(brand, :horizontal).bandjoin(opaque).write_to_file(source.to_s)
  end

  after { FileUtils.remove_entry(dir) }

  def pixel(path, x)
    Vips::Image.new_from_file(path.to_s).getpoint(x, 10)
  end

  it 'lightens the near-black wordmark' do
    described_class.new(source: source, target: target).call

    expect(pixel(target, 5).first(3)).to eq(described_class::INK)
  end

  it 'leaves the brand colour alone' do
    described_class.new(source: source, target: target).call

    expect(pixel(target, 30).first(3)).to eq(pixel(source, 30).first(3))
  end

  it 'keeps the alpha channel' do
    described_class.new(source: source, target: target).call

    expect(Vips::Image.new_from_file(target.to_s)).to have_attributes(bands: 4)
  end

  it 'refuses a source with no transparency' do
    flat = dir.join('flat.png')
    Vips::Image.black(10, 10).add(30).cast('uchar').write_to_file(flat.to_s)

    expect { described_class.new(source: flat, target: target).call }
      .to raise_error(/no alpha channel/)
  end
end
