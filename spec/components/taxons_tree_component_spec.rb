require "solidus_starter_frontend_spec_helper"

RSpec.describe TaxonsTreeComponent, type: :component do
  let(:taxon_without_descendants) { create(:taxon, children: []) }

  # Every taxon here gets a product on purpose: the component hides categories
  # with nothing available to buy, so a bare taxon tree renders as empty.
  let(:taxon_with_descendants) do
    root = create(:taxon)

    children = [
      stocked_taxon(name: 'child 1', parent: root),
      stocked_taxon(name: 'child 2', parent: root)
    ]

    # child 1 grandchild
    stocked_taxon(name: 'grandchild 1', parent: children[0])

    root
  end

  def stocked_taxon(name:, parent:)
    create(:taxon, name: name, parent: parent).tap do |taxon|
      create(:product, taxons: [taxon])
    end
  end

  let(:title) { 'some_title' }
  let(:root_taxon) { taxon_with_descendants }
  let(:current_taxon) { nil }
  let(:max_level) { 1 }
  let(:current_item_classes) { 'underline' }

  let(:local_assigns) do
    {
      title: title,
      root_taxon: root_taxon,
      current_taxon: current_taxon,
      max_level: max_level,
      current_item_classes: current_item_classes
    }
  end

  context 'when rendered' do
    before do
      render_inline(described_class.new(**local_assigns))
    end

    describe 'concerning max_level and root_taxon' do
      context 'when the max level is less than 1' do
        let(:max_level) { 0 }

        it 'does not render any items' do
          expect(page.all('li')).to be_empty
        end
      end

      context 'when the max level is 1' do
        let(:max_level) { 1 }

        context 'when the root taxon has no descendants' do
          let(:root_taxon) { taxon_without_descendants }

          it 'does not render any items' do
            expect(page.all('li')).to be_empty
          end
        end

        context 'when the root taxon has descendants' do
          let(:root_taxon) { taxon_with_descendants }

          it "renders a list of the root taxon's children" do
            expect(page.all('li').map(&:text)).to match(['child 1', 'child 2'])
          end
        end
      end

      context 'when the max level is greater than 1' do
        let(:max_level) { 2 }

        context 'when the root taxon has no descendants' do
          let(:root_taxon) { taxon_without_descendants }

          it 'does not render any items' do
            expect(page.all('li')).to be_empty
          end
        end

        context 'when the root taxon has descendants' do
          let(:root_taxon) { taxon_with_descendants }

          it "renders a list of the root taxon's descendants" do
            # child 1's text includes the text of the grandchild 1.
            expect(page.all('li').map(&:text)).to match(['child 1grandchild 1', 'grandchild 1', 'child 2'])
          end
        end
      end
    end

    describe 'concerning current_taxon' do
      context 'when current_taxon is not provided' do
        let(:current_taxon) { nil }

        it 'does not mark any taxon as "current"' do
          expect(page).to have_no_css('li', class: current_item_classes)
        end
      end

      context 'when current_taxon is provided' do
        context 'when current_taxon matches a descendant' do
          let(:current_taxon) { root_taxon.children.first }

          it 'marks the current taxon as "current"' do
            expect(page.find('li', class: current_item_classes)).to have_text('child 1')
          end
        end

        context 'when current_taxon does not match any descendant' do
          let(:current_taxon) { create(:taxon) }

          it 'does not mark any taxon as "current"' do
            expect(page).to have_no_css('li', class: current_item_classes)
          end
        end
      end
    end

    describe 'concerning title' do
      let(:base_class) { 'some_base_class' }

      context 'when a title is provided' do
        let(:title) { 'some title' }

        it 'renders the title' do
          expect(page).to have_content('some title')
        end
      end

      context 'when there is no title provided' do
        let(:title) { nil }

        it 'does not render the title' do
          expect(page).to_not have_content('some title')
        end
      end
    end
  end
  describe 'categories with nothing available to buy' do
    # Discontinuing the last product in a category used to leave its nav link
    # pointing at an empty page -- which is how "Gelcaps" survived being taken
    # off sale.
    let(:root) { create(:taxon) }
    let!(:stocked) { stocked_taxon(name: 'in stock', parent: root) }
    let!(:emptied) { stocked_taxon(name: 'discontinued', parent: root) }

    before do
      emptied.products.each { |product| product.update!(discontinue_on: 1.day.ago) }
      render_inline(described_class.new(root_taxon: root, max_level: 1))
    end

    it 'are left out of the tree' do
      expect(page.all('li').map(&:text)).to eq(['in stock'])
    end
  end
end
