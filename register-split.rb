#!/usr/bin/env ruby
#
# This splits and combines several large pdfs containing the Register of Members' Interests into one pdf per Senator/Member
#
# Requirement: pdftk (http://www.accesspdf.com/pdftk/)
#
# On Mac OS X 10.5 the latest Macports version kept segfaulting. Installing the pre-compiled
# version from http://www.pdfhacks.com/pdftk/OSX-10.3/pdftk1.12_OSX10.3.dmg.gz worked.

$:.unshift "#{File.dirname(__FILE__)}/lib"

require 'csv'
require 'name'
require 'people'

# Full path to pdftk executable
pdftk = "/usr/local/bin/pdftk"

people = PeopleCSVReader.read_members

pdf_filename = "data/register_of_interests/senate/2008_sep_vol_1.pdf"
split_filename = "data/register_of_interests/senate/2008_sep_vol_1.split"
result_dir = "data/register_of_interests"

PageRange = Struct.new(:filename, :start, :end)

def read_in_ranges(p, pdf_filename, split_filename, date, house, people)
  # Read in one split file
  data = CSV.readlines(split_filename)
  # Throw away first line (comment)
  data.shift

  data.each_index do |i|
    start_page, last_name, first_name = data[i]
    start_page = start_page.to_i
    if i + 1 < data.size
      end_page = data[i+1][0].to_i - 1
    else
      end_page = 'end'
    end
    # Ignore page ranges marked as blank
    if last_name.downcase != "** blank page **"
      name = Name.last_title_first(last_name + " " + first_name)
      member = people.find_member_by_name_current_on_date(name, date, house)
      throw "Couldn't find #{name.full_name}" if member.nil?
      p[member.person] ||= []
      p[member.person] << PageRange.new(pdf_filename, start_page, end_page)
    end
  end
end

# Hash from person to array of page ranges
p = {}

read_in_ranges(p, pdf_filename, split_filename, Date.new(2008, 9, 1), House.senate, people)

# Now step through all the people and create the pdfs
p.each do |person, ranges|
  command = "#{pdftk} #{ranges.first.filename} cat #{ranges.first.start}-#{ranges.first.end} output #{result_dir}/roi_#{person.id_count}.pdf"
  puts "Splitting and combining pdfs for #{person.name.full_name}..."
  system(command)  
end