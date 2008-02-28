#!/usr/bin/env ruby

$:.unshift "#{File.dirname(__FILE__)}/lib"

require 'rubygems'
require 'mechanize'
require 'builder'

# My bits and bobs
require 'id'
require 'speech'
require 'configuration'
require 'people'

def quote(text)
  text.sub('&', '&amp;')
end

# Merges together two or more speeches by the same person that occur consecutively
class Speeches
  def initialize
    @speeches = []
  end
  
  def add_speech(speaker, time, url, speech_id, content)
    if speaker.nil? || @speeches.empty? || @speeches.last.speaker.nil? || speaker != @speeches.last.speaker
      @speeches << Speech.new(speaker, time, url, speech_id)
    end
    @speeches.last.append_to_content(content)
  end
  
  def write(x)
    @speeches.each {|s| s.output(x)}
  end
end

def lookup_speaker(speakername, people, date)
  if speakername.nil?
    speakername = "unknown"
  end
  
  # HACK alert (Oh you know what this whole thing is a big hack alert)
  if speakername =~ /^the speaker/i
    speakername = "Mr David Hawker"
  # The name might be "The Deputy Speaker (Mr Smith)". So, take account of this
  elsif speakername =~ /^the deputy speaker/i
    speakername = "Mr Ian Causley"
  elsif speakername.downcase == "the clerk"
    # TODO: Handle "The Clerk" correctly
    speakername = "unknown"
  end
  # Lookup id of member based on speakername
  if speakername.downcase == "unknown"
    nil
  else
    people.find_house_member_by_name(Name.title_first_last(speakername), date)
  end
end

def min(a, b)
  if a < b
    a
  else
    b
  end
end

def strip_tags(doc)
  str=doc.to_s
  str.gsub(/<\/?[^>]*>/, "")
end

def extract_speaker_from_talkername_tag(content, people, date)
  tag = content.search('span.talkername a').first
  if tag
    lookup_speaker(tag.inner_html, people, date)
  end
end

def extract_speaker_in_interjection(content, people, date)
  if content.search("div.speechType").inner_html == "Interjection"
    text = strip_tags(content.search("div.speechType + *").first)
    m = text.match(/([a-z].*) interjecting/i)
    if m
      name = m[1]
      lookup_speaker(name, people, date)
    else
      m = text.match(/([a-z].*)—/i)
      if m
        name = m[1]
        lookup_speaker(name, people, date)
      end
    end
  else
    throw "Not an interjection"
  end
end

def process_subspeeches(subspeeches_content, people, date, speeches, time, url, speech_id, speaker)
  # Now extract the subspeeches
	subspeeches_content.each do |e|
	  tag_class = e.attributes["class"]
	  if tag_class == "subspeech0" || tag_class == "subspeech1"
      speaker = extract_speaker_from_talkername_tag(e, people, date) || extract_speaker_in_interjection(e, people, date)
    elsif tag_class == "paraitalic"
      speaker = nil
    end
    speeches.add_speech(speaker, time, url, speech_id, e)
	end
end

def parse_hansard_day_page(page, date, agent, people, xml_filename)
  xml = File.open(xml_filename, 'w')
  x = Builder::XmlMarkup.new(:target => xml, :indent => 1)

  title = ""
  subtitle = ""

  speech_id = Id.new("uk.org.publicwhip/debate/#{date}.")

  x.instruct!
  x.publicwhip do
    # Structure of the page is such that we are only interested in some of the links
    page.links[30..-4].each do |link|
    #for link in page.links[108..108] do
      puts "Processing: #{link}"
    	# Only going to consider speeches for the time being
    	if link.to_s =~ /Speech:/
      	# Link text for speech has format:
      	# HEADING > NAME > HOUR:MINS:SECS
      	split = link.to_s.split('>').map{|a| a.strip}
      	puts "Warning: Expected split to have length 3" unless split.size == 3
      	time = split[2]
       	sub_page = agent.click(link)
       	# Extract permanent URL of this subpage. Also, quoting because there is a bug
       	# in XML Builder that for some reason is not quoting attributes properly
       	url = quote(sub_page.links.text("[Permalink]").uri.to_s)
      	# Type of page. Possible values: No, Speech, Bills
      	#type = sub_page.search('//span[@id=dlMetadata__ctl7_Label3]/*').to_s
      	#puts "Warning: Expected type Speech but was type #{type}" unless type == "Speech"
     	  newtitle = sub_page.search('div#contentstart div.hansardtitle').inner_html
     	  newsubtitle = sub_page.search('div#contentstart div.hansardsubtitle').inner_html

     	  # Only add headings if they have changed
     	  if newtitle != title
       	  x.tag!("major-heading", newtitle, :id => speech_id, :url => url)
        end
     	  if newtitle != title || newsubtitle != subtitle
       	  x.tag!("minor-heading", newsubtitle, :id => speech_id, :url => url)
        end
        title = newtitle
        subtitle = newsubtitle

        speeches = Speeches.new

        # Untangle speeches from subspeeches
        speech_content = Hpricot::Elements.new
      	content = sub_page.search('div#contentstart > div.speech0 > *')
      	tag_classes = content.map{|e| e.attributes["class"]}
      	subspeech0_index = tag_classes.index("subspeech0")
      	paraitalic_index = tag_classes.index("paraitalic")

        if subspeech0_index.nil?
          subspeech_index = paraitalic_index
        elsif paraitalic_index.nil?
          subspeech_index = subspeech0_index
        else
          subspeech_index = min(subspeech0_index, paraitalic_index)
        end

        if subspeech_index
          speech_content = content[0..subspeech_index-1]
          subspeeches_content = content[subspeech_index..-1]
        else
          speech_content = content
        end
        # Extract speaker name from link
        speaker = extract_speaker_from_talkername_tag(speech_content, people, date)
        speeches.add_speech(speaker, time, url, speech_id, speech_content)

    	  if subspeeches_content
    	    process_subspeeches(subspeeches_content, people, date, speeches, time, url, speech_id, speaker)
    	  end
  	    speeches.write(x)   
      end
    end
  end

  xml.close
end

conf = Configuration.new

# First load people back in so that we can look up member id's
people = People.read_csv("data/members.csv")

system("mkdir -p pwdata/scrapedxml/debates")

# Required to workaround long viewstates generated by .NET (whatever that means)
# See http://code.whytheluckystiff.net/hpricot/ticket/13
Hpricot.buffer_size = 262144

agent = WWW::Mechanize.new
agent.set_proxy(conf.proxy_host, conf.proxy_port)

date = Date.new(2007, 9, 20)
url = "http://parlinfoweb.aph.gov.au/piweb/browse.aspx?path=Chamber%20%3E%20House%20Hansard%20%3E%20#{date.year}%20%3E%20#{date.day}%20#{Date::MONTHNAMES[date.month]}%20#{date.year}"
page = agent.get(url)

xml_filename = "pwdata/scrapedxml/debates/debates#{date}.xml"

parse_hansard_day_page(page, date, agent, people, xml_filename)

# Temporary hack: nicely indent XML
system("tidy -quiet -indent -xml -modify -wrap 0 -utf8 #{xml_filename}")

# And load up the database
system(conf.web_root + "/twfy/scripts/xml2db.pl --debates --all --force")