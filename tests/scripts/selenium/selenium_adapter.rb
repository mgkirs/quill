class SeleniumAdapter

  attr_accessor :doc_length, :cursor_pos

  def initialize(driver, editor)
    @cursor_pos = 0
    @driver = driver
    @editor = editor
    @doc_length = 1 # Initial val of 1 due to Scribe's "phantom" newline
  end

  # Assumes delta will contain only one document modifying op
  def apply_delta(delta)
    index = 0
    delta['ops'].each do |op|
      if op['value']
        insert_at index, op['value']
        break
      elsif op['start'] > index
        delete_length = op['start'] - index
        delete_at(index, delete_length)
        break
      elsif !op['attributes'].empty?
        length = op['end'] - op['start']
        format_at(index, length, op['attributes'])
        break
      else
        index += op['end'] - op['start']
      end
    end
  end

  # private

  def insert_at(index, text)
    puts "Inserting #{text} at #{index}"
    move_cursor(index)
    type_text(text)
    # Remove any prexisting formatting that Scribe applied
    move_cursor(index)
    runs = text.split "\n"
    runs.each do |run|
      if run.length > 0
        highlight run.length
        remove_active_formatting
      end
      remove_highlighting
      move_cursor(index + run.length + 1) # +1 to account for \n
      index += run.length + 1
    end
    remove_highlighting
  end

  def delete_at(index, length)
    puts "Deleting #{length} at #{index}"
    move_cursor(index)
    delete(length)
  end

  def format_at(index, length, attributes)
    puts "Formatting #{length} starting at #{index} with #{attributes}"
    move_cursor(index)
    highlight(length)
    attributes.each do |attr, val|
      format(attr, val)
    end
    remove_highlighting
  end

  def remove_highlighting
    # Kludge. The only xplatform way that I've found to guarantee removing
    # highlighted text in a content editable is to command the cursor to move to
    # the 0th position. We need to first focus the editor, or chromedriver will
    # (incorrectly) extend the highlighting to the beginning of the doc.
    focus
    move_cursor 0
  end

  def remove_active_formatting
    @driver.switch_to.default_content
    active_formats = @driver.execute_script("return window.Fuzzer.getActiveFormats()")
    @driver.switch_to.frame(@driver.find_element(:tag_name, "iframe"))
    active_formats.each do |format|
      click_button_from_toolbar(format)
    end
    select_from_dropdown('size', 'normal')
    select_from_dropdown('family', 'san-serif')
    select_from_dropdown('color', 'black')
    select_from_dropdown('background', 'white')
  end

  def jump_to_start
    os = SeleniumAdapter.os()
    if os == :windows or os == :linux
      key = :home
    elsif os == :macosx
      key = :arrow_up
    end
    @driver.action.key_down(@@cmd_modifier).send_keys(key).key_up(@@cmd_modifier).perform
  end

  def move_cursor(dest_index)
    if dest_index < 0 or dest_index > doc_length
      raise IndexError, "Invalid dest_index #{dest_index} for doc_length #{doc_length}"
    end
    distance = (@cursor_pos - dest_index).abs
    if dest_index == 0
      jump_to_start()
    elsif @cursor_pos > dest_index
      distance.times do @editor.send_keys(:arrow_left) end
    else
      distance.times do @editor.send_keys(:arrow_right) end
    end
    @cursor_pos = dest_index
  end

  def highlight(length)
    keys = (0...length).to_a.map! { :arrow_right }
    @cursor_pos += length
    @driver.action.key_down(:shift).send_keys(keys).key_up(:shift).perform
  end

  def delete(length)
    highlight(length)
    @editor.send_keys(:delete)
    @doc_length -= length
    @cursor_pos -= length
  end

  def split_text(text)
    keys = []
    cur = ""
    text.each_char { |c|
      if c == "\n"
        keys << cur if cur.length > 0
        cur = ""
        keys << :enter
      elsif c == " "
        keys << cur if cur.length > 0
        cur = ""
        keys << :space
      else
        cur << c
      end
    }
    keys << cur if cur.length > 0
    return keys
  end

  def type_text(text)
    keys = split_text(text)
    if @cursor_pos == 0 && @doc_length == 0 && @driver.browser == :firefox
      # Hack to workaround inexplicable firefox behavior in which it appends a
      # newline if you append to the end of the empty document.
      @editor.send_keys(keys)
      @editor.send_keys([:arrow_down, :delete])
    else
      @editor.send_keys keys
    end
    len = keys.reduce(0) do |len, elem|
      if elem.is_a?(String) then len + elem.length else len + 1 end
    end
    @cursor_pos += len
    @doc_length += len
  end

  def click_button_from_toolbar(button_class)
    @driver.switch_to.default_content
    button = @driver.execute_script("return $('#editor-toolbar > .#{button_class}')[0]")
    button.click()
    @driver.switch_to.frame(@driver.find_element(:tag_name, "iframe"))
  end

  def select_from_dropdown(dropdown_class, value)
    @driver.switch_to.default_content
    dropdown = @driver.execute_script("return $('#editor-toolbar > .#{dropdown_class}')[0]")
    Selenium::WebDriver::Support::Select.new(dropdown).select_by(:value, value)
    @driver.switch_to.frame(@driver.find_element(:tag_name, "iframe"))
  end

  def format(format, value)
    case format
    when /bold|italic|underline/
      if Random.rand() < 0.5
        @driver.action.key_down(@@cmd_modifier).send_keys(format[0]).key_up(@@cmd_modifier).perform
      else
        click_button_from_toolbar(format)
      end
    when /link|strike/
      click_button_from_toolbar(format)
    when /family|size|background|color/
      select_from_dropdown(format, value)
    else
      raise "Unknown formatting op: #{format}"
    end
    self.focus # Need to reset focus to the editor after clicking toolbar
  end

  def focus
    @editor.send_keys ""
  end

  def self.os
    host_os = RbConfig::CONFIG['host_os']
    case host_os
    when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
      return :windows
    when /darwin|mac os/
      return :macosx
    when /linux/
      return :linux
    when /solaris|bsd/
      return :unix
    else
      raise Error::WebDriverError, "unknown os: #{host_os.inspect}"
    end
  end

  def self.os_to_modifier
    case self.os()
    when :windows
      return :control
    when :linux
      return :control
    when :macosx
      return :command
    end
  end
  @@cmd_modifier = SeleniumAdapter.os_to_modifier()
end