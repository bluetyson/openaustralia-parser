require 'hansard_page'

module Hpricot
  module Traverse
    # Iterate over the children that aren't text nodes
    def each_child_node
      children.each do |c|
        yield c if c.respond_to?(:name)
      end
    end
  end
end

class HansardDay
  def initialize(page, logger = nil)
    @page, @logger = page, logger
  end
  
  def house
    case @page.at('chamber').inner_html
      when "SENATE" then House.senate
      when "REPS" then House.representatives
      else throw "Unexpected value for contents of <chamber> tag"
    end
  end
  
  def date
    Date.parse(@page.at('date').inner_html)
  end
  
  def permanent_url
    house_letter = house.representatives? ? "r" : "s"
    "http://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p;query=Id:chamber/hansard#{house_letter}/#{date}/0000"
  end
  
  def in_proof?
    proof = @page.at('proof').inner_html
    logger.error "Unexpected value '#{proof}' inside tag <proof>" unless proof == "1" || proof == "0"
    proof == "1"
  end

  # Strip any HTML/XML tags from the given text and remove new-line characters
  def strip_tags(text)
    text.gsub(/<\/?[^>]*>/, "").gsub("\r", '').gsub("\n", '')
  end

  # Search for the title tag and return its value, stripping out any HTML tags
  def title_tag_value(debate)
    # Doing this rather than calling inner_text to preserve html entities which for some reason get all screwed up by inner_text
    strip_tags(debate.at('title').inner_html)
  end
  
  def title(debate)
    e = case debate.name
    when 'debate'
      debate
    when 'subdebate.1'
      debate.parent
    when 'subdebate.2'
      debate.parent.parent
    else
      throw "Unexpected tag #{debate.name}"
    end    
    title = title_tag_value(e)
    cognates = e.search('cognateinfo').search('title').map{|a| strip_tags(a.inner_html)}
    ([title] + cognates).join('; ')
  end
  
  def subtitle(debate)
    case debate.name
    when 'debate'
      ""
    when 'subdebate.1'
      title_tag_value(debate)
    when 'subdebate.2'
      title_tag_value(debate.parent) + '; ' + title_tag_value(debate)
    else
      throw "Unexpected tag #{debate.name}"
    end    
  end
  
  def full_title(debate)
    if subtitle(debate) == ""
      title(debate)
    else
      title(debate) + "; " + subtitle(debate)
    end
  end
  
  def pages_from_debate(debate)
    p = []
    title = title(debate)
    subtitle = subtitle(debate)
    full_title = full_title(debate)

    question = false
    procedural = false
    debate.each_child_node do |e|
      case e.name
      when 'debateinfo', 'subdebateinfo'
        question = false
        procedural = false
      when 'speech'
        #puts "USE: #{e.name} > #{full_title}"
        p << HansardPage.new(e, title, subtitle, self, @logger)
        question = false
        procedural = false
      when 'division'
        #puts "SKIP: #{e.name} > #{full_title}"
        p << nil
        question = false
        procedural = false
      when 'question', 'answer'
        # We'll skip answer because they always come in pairs of 'question' and 'answer'
        unless question
          #puts "USE: #{e.name} > #{full_title}"
          # TODO: All 'question' and 'answer' blocks in this section should be passed to HansardPage
          p << HansardPage.new(e, title, subtitle, self, @logger)
        end
        question = true
        procedural = false
      when 'motionnospeech', 'para', 'motion', 'interjection', 'quote'
        unless procedural
          #puts "SKIP: Procedural text: #{e.name} > #{full_title}"
          p << nil
        end
        question = false
        procedural = true
      when 'subdebate.1', 'subdebate.2'
        p = p + pages_from_debate(e)
        question = false
        procedural = false
      else
        throw "Unexpected tag #{e.name}"
      end
    end
    p
  end
  
  def pages
    p = []
    # Step through the top-level debates
    # When something that was a page in old parlinfo web system is not supported we just return nil for it. This ensures that it is
    # still accounted for in the counting of the ids but we don't try to use it to generate any content
    #puts "SKIP: Official Hansard"
    p << nil
    @page.at('hansard').each_child_node do |e|
      case e.name
      when 'session.header'
      when 'chamber.xscript', 'maincomm.xscript'
        e.each_child_node do |e|
          case e.name
            when 'business.start', 'adjournment'
              p << nil
              #puts "SKIP: #{e.name}"
            when 'debate'
              p = p + pages_from_debate(e)
            else
              throw "Unexpected tag #{e.name}"
          end
        end
      when 'answers.to.questions'
        e.each_child_node do |e|
          case e.name
          when 'debate'
            pages_from_debate(e)
          else
            throw "Unexpected tag #{e.name}"
          end
        end
      else
        throw "Unexpected tag #{e.name}"
      end
    end
    p
  end  
end