require 'rexml/document'

class PeopleXMLReader
  def PeopleXMLReader.read(people_filename, members_filename)
    people = People.new
    xml = REXML::Document.new(File.open(people_filename))
    xml.elements.each("publicwhip/person") do |e|
      name = Name.title_first_last(e.attributes["latestname"])
      # TODO: Should really check that the beginning of the string is correct
      person_id = e.attributes["id"].match(/[0-9]+/)[0].to_i
      person = Person.new(name, person_id)
      e.elements.each("office") do |e|
        member_id = e.attributes["id"].match(/[0-9]+/)[0].to_i
        # TODO: Currently ignore current field in XML
        person.add_house_period(:id => member_id)
      end
      people << person
    end
    
    xml = REXML::Document.new(File.open(members_filename))
    xml.elements.each("publicwhip/member") do |e|
      # TODO: Check that the names of people don't change as this currently doesn't work
      name = Name.new(:title => e.attributes["title"], :first => e.attributes["firstname"], :last => e.attributes["lastname"])
      throw "Unexpected value in house" if e.attributes["house"] != "commons"
      # TODO: Should really check that the beginning of the string is correct
      member_id = e.attributes["id"].match(/[0-9]+/)[0].to_i
      
      period = people.find_house_period_by_id(member_id)
      
      period.from_date = Date.parse(e.attributes["fromdate"])
      period.to_date = Date.parse(e.attributes["todate"])
      period.from_why = e.attributes["fromwhy"]
      period.to_why = e.attributes["towhy"]
      period.party = e.attributes["party"]
      period.division = e.attributes["constituency"]
    end
    people
  end
end