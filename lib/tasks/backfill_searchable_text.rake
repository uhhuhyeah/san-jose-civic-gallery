namespace :searchable_text do
  desc "Backfill searchable_text on all Civic::Event and Civic::Matter records"
  task backfill: :environment do
    # Backfill events
    puts "Backfilling Civic::Event searchable_text..."
    event_count = 0
    Civic::Event.find_each do |event|
      event.update_searchable_text!
      event_count += 1
      print "." if event_count % 100 == 0
    end
    puts "\nBackfilled #{event_count} events."

    # Backfill matters
    puts "Backfilling Civic::Matter searchable_text..."
    matter_count = 0
    Civic::Matter.find_each do |matter|
      matter.update_searchable_text!
      matter_count += 1
      print "." if matter_count % 100 == 0
    end
    puts "\nBackfilled #{matter_count} matters."
    puts "Done."
  end
end
