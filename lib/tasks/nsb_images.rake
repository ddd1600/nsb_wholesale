# frozen_string_literal: true

namespace :nsb do
  namespace :images do
    desc "Report what nsb:images:import would do, without writing anything"
    task report: :environment do
      result = Nsb::SiteImageImporter.new(dry_run: true).call

      puts
      puts "=" * 72
      puts "DRY RUN -- nothing was written"
      puts "site images: #{result}"

      puts "\nWOULD ATTACH:"
      result.products_matched.select { |row| row[:attached].positive? }.each do |row|
        puts "  +#{row[:attached].to_s.rjust(2)}  #{row[:sku].ljust(24)} #{row[:name]}"
      end

      already = result.products_matched.reject { |row| row[:attached].positive? }
      puts "\nALREADY UP TO DATE (#{already.size}):"
      already.each { |row| puts "  #{row[:sku].ljust(24)} #{row[:name]}" }

      puts "\nNO IMAGES ON THE PUBLIC SITE (#{result.products_unmatched.size}):"
      result.products_unmatched.each { |row| puts "  #{row[:sku].ljust(24)} #{row[:name]}" }

      report_failures(result)
    end

    desc "Attach product photos scraped from newsouthbotanicals.com (safe to re-run)"
    task import: :environment do
      result = Nsb::SiteImageImporter.new.call

      puts
      puts "=" * 72
      puts "site images: #{result}"
      result.products_matched.select { |row| row[:attached].positive? }.each do |row|
        puts "  +#{row[:attached].to_s.rjust(2)}  #{row[:sku].ljust(24)} #{row[:name]}"
      end

      reordered = result.products_matched.select { |row| row[:reordered] }
      if reordered.any?
        puts "\nRE-ORDERED to match the public site's gallery (#{reordered.size}):"
        reordered.each { |row| puts "  #{row[:sku].ljust(24)} #{row[:name]}" }
      end

      report_failures(result)
    end

    desc "List visually similar images within each product, for review (deletes nothing)"
    task duplicates: :environment do
      pairs = Nsb::SimilarImageReport.new.call

      puts
      puts "=" * 72
      puts "#{pairs.size} similar pair(s). Nothing was deleted -- these need your eyes."
      puts "Distance 0 is the same picture. Anything above ~4 is often two real"
      puts "photos of near-identical white bottles, so check before removing."
      puts

      pairs.group_by { |pair| pair.product }.each do |product, product_pairs|
        puts "#{product.master.sku.to_s.ljust(24)} #{product.name}"
        product_pairs.each do |pair|
          puts "   distance #{pair.distance.to_s.rjust(2)}  image ##{pair.keep.id} " \
               "#{pair.keep.attachment.blob.filename}"
          puts "               vs image ##{pair.candidate.id} " \
               "#{pair.candidate.attachment.blob.filename}"
        end
        puts
      end
    end

    desc "Remove same-photo duplicates within a product (DRY_RUN=false to apply)"
    task prune_duplicates: :environment do
      dry_run = ENV.fetch("DRY_RUN", "true") != "false"
      removals = Nsb::DuplicateImagePruner.new(dry_run: dry_run).call

      puts
      puts "=" * 72
      puts dry_run ? "DRY RUN -- nothing was deleted. Re-run with DRY_RUN=false to apply." : "DELETED"
      puts "#{removals.size} duplicate image(s), #{(removals.sum(&:bytes_freed) / 1024.0 / 1024).round(1)} MB"
      puts

      removals.each do |removal|
        puts "#{removal.product.master.sku.to_s.ljust(22)} #{removal.product.name}"
        puts "   remove ##{removal.removed[:id]} #{removal.removed[:filename]} (#{removal.removed[:bytes] / 1024}KB)"
        puts "   keep   ##{removal.kept[:id]} #{removal.kept[:filename]} (#{removal.kept[:bytes] / 1024}KB)"
      end
    end

    def report_failures(result)
      return if result.failures.empty?

      puts "\nFAILURES:"
      result.failures.each { |row| puts "  #{row[:sku]}  #{row[:name]} -- #{row[:error]}" }
      # Non-zero exit so a broken import is not mistaken for success.
      abort "finished with #{result.failures.size} failure(s)"
    end
  end
end
