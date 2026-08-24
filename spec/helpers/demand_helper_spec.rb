# frozen_string_literal: true

require 'solidus_starter_frontend_spec_helper'

RSpec.describe DemandHelper, type: :helper do
  describe '#demand_share' do
    it 'rounds a large share to whole percent' do
      expect(helper.demand_share(0.503)).to eq('50%')
    end

    it 'keeps a decimal place below one percent, where most of the tail lives' do
      expect(helper.demand_share(0.008)).to eq('0.8%')
    end

    it 'says "<0.1%" rather than "0.0%" for a share that is small but real' do
      # One unit of 8,723 is 0.01%, which would otherwise read as "none sold".
      expect(helper.demand_share(0.0001)).to eq('<0.1%')
    end

    it 'still shows a true zero as zero' do
      expect(helper.demand_share(0.0)).to eq('0%')
    end
  end
end
