# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'
require 'vips'

RSpec.describe Nsb::SitePhotoPreparer do
  # Noise, not a flat colour: PNG squeezes a solid block to almost nothing, so a
  # flat fixture would "prove" that JPEG makes files bigger. Real product photos
  # compress like this one does.
  def image(width, height, seed = 1)
    Vips::Image.gaussnoise(width, height, mean: 128, sigma: 40, seed: seed)
                .cast('uchar').write_to_buffer('.png')
  end

  let(:source_dir) { Pathname.new(Dir.mktmpdir) }
  let(:output_dir) { Pathname.new(Dir.mktmpdir) }

  let(:huge) { image(3000, 3000, 1) }
  let(:small) { image(400, 400, 2) }

  let(:blobs) do
    {
      Digest::SHA256.hexdigest(huge) => { file: 'huge.png', bytes: huge.bytesize, sources: [ 'https://example.test/h' ] },
      Digest::SHA256.hexdigest(small) => { file: 'small.png', bytes: small.bytesize, sources: [ 'https://example.test/s' ] }
    }
  end

  before do
    source_dir.join('huge.png').binwrite(huge)
    source_dir.join('small.png').binwrite(small)
    source_dir.join('manifest.json').write({ blobs: blobs }.to_json)

    stub_const("#{described_class}::SOURCE_DIR", source_dir)
    stub_const("#{described_class}::OUTPUT_DIR", output_dir)
    stub_const("#{described_class}::INDEX_PATH", output_dir.join('index.json'))
  end

  after do
    FileUtils.remove_entry(source_dir)
    FileUtils.remove_entry(output_dir)
  end

  it 'caps the longest edge' do
    described_class.new.call

    written = output_dir.glob('*.jpg').map { |path| Vips::Image.new_from_file(path.to_s) }
    expect(written.map { |image| [ image.width, image.height ].max }.max)
      .to eq(described_class::MAX_EDGE)
  end

  it 'leaves an already-small image alone rather than upscaling it' do
    described_class.new.call

    sizes = output_dir.glob('*.jpg').map { |path| Vips::Image.new_from_file(path.to_s).width }
    expect(sizes).to include(400)
  end

  it 'makes the set dramatically smaller' do
    # The real set goes from 87MB to 14MB; the point is that a print-resolution
    # original does not survive as one.
    result = described_class.new.call

    expect(result.output_bytes).to be < result.source_bytes
    expect(result.written).to eq(2)
  end

  it 'writes an index the importer can verify bytes against' do
    described_class.new.call

    index = JSON.parse(output_dir.join('index.json').read)
    expect(index.keys).to match_array(blobs.keys)
    index.each_value do |entry|
      bytes = output_dir.join(entry.fetch('file')).binread
      expect(Digest::SHA256.hexdigest(bytes)).to eq(entry.fetch('sha256'))
    end
  end

  it 'is idempotent' do
    described_class.new.call

    expect(described_class.new.call.written).to eq(0)
  end

  it 'says so when there is no scrape output to work from' do
    source_dir.join('manifest.json').delete

    expect { described_class.new.call }.to raise_error(/no scrape output/)
  end
end
