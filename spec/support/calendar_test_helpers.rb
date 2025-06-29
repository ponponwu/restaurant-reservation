# frozen_string_literal: true

module CalendarTestHelpers
  # Navigate to July 2025 by clicking the next month button
  # Assumes the calendar is already loaded and visible
  def navigate_to_july_calendar
    find('.flatpickr-next-month').click
    # Wait for calendar to update by checking for visible day elements
    expect(page).to have_css('.flatpickr-day', visible: true, wait: 5)
  end

  # Find a calendar day element by day number within the current month
  # @param day_number [Integer] The day number to find (1-31)
  # @return [Capybara::Node::Element, nil] The day element or nil if not found
  def find_calendar_day(day_number)
    within('.flatpickr-calendar') do
      day_elements = all('.flatpickr-day').select { |el| el.text.strip == day_number.to_s }
      day_elements.first if day_elements.any?
    end
  end

  # Expect a calendar day to be disabled
  # @param day_number [Integer] The day number to check (1-31)
  def expect_day_disabled(day_number)
    day_element = find_calendar_day(day_number)
    if day_element
      expect(day_element[:class]).to include('flatpickr-disabled'),
                                     "Expected day #{day_number} to be disabled, but it was enabled"
    else
      raise "Could not find day #{day_number} in calendar"
    end
  end

  # Expect a calendar day to be enabled (not disabled)
  # @param day_number [Integer] The day number to check (1-31)
  def expect_day_enabled(day_number)
    day_element = find_calendar_day(day_number)
    if day_element
      expect(day_element[:class]).not_to include('flatpickr-disabled'),
                                         "Expected day #{day_number} to be enabled, but it was disabled"
    else
      raise "Could not find day #{day_number} in calendar"
    end
  end

  # Click on a calendar day if it's enabled
  # @param day_number [Integer] The day number to click (1-31)
  # @param force [Boolean] Whether to force click even if disabled (default: false)
  def click_calendar_day(day_number, force: false)
    day_element = find_calendar_day(day_number)
    if day_element
      if force || !day_element[:class].include?('flatpickr-disabled')
        day_element.click
      else
        raise "Cannot click day #{day_number} because it is disabled. Use force: true to override."
      end
    else
      raise "Could not find day #{day_number} in calendar"
    end
  end

  # Wait for Flatpickr calendar to be loaded and visible
  def wait_for_flatpickr_calendar_to_load
    expect(page).to have_css('.flatpickr-calendar', visible: true, wait: 10)
    expect(page).to have_css('.flatpickr-day', visible: true, wait: 10)
    expect(page).to have_css('.flatpickr-current-month', visible: true, wait: 10)
  end

  # Navigate to a specific month/year by clicking next/previous buttons
  # Note: This is a simple implementation that only handles forward navigation
  # @param target_month [Integer] Target month (1-12)
  # @param target_year [Integer] Target year
  # @param max_clicks [Integer] Maximum number of clicks to prevent infinite loops (default: 24)
  def navigate_to_month(target_month, target_year, max_clicks: 24)
    wait_for_flatpickr_calendar_to_load
    
    clicks = 0
    while clicks < max_clicks
      # Get current month/year from calendar
      current_month_element = find('.flatpickr-current-month .cur-month', visible: true, wait: 5)
      current_year_element = find('.flatpickr-current-month .cur-year', visible: true, wait: 5)

      current_month_text = current_month_element.text
      current_year = current_year_element.value.to_i
      
      current_month = Date::MONTHNAMES.index(current_month_text)
      
      break if current_month == target_month && current_year == target_year
      
      if target_year > current_year || (target_year == current_year && target_month > current_month)
        find('.flatpickr-next-month', wait: 5).click
      else
        find('.flatpickr-prev-month', wait: 5).click
      end
      
      # Wait for navigation to complete by checking calendar state
      expect(page).to have_css('.flatpickr-current-month', visible: true, wait: 2)
      clicks += 1
    end
    
    raise "Could not navigate to #{target_month}/#{target_year} after #{max_clicks} attempts" if clicks >= max_clicks
  end

  # Find a day by date across any month (more robust than day number)
  # @param date [Date] The specific date to find
  # @return [Capybara::Node::Element, nil] The day element or nil if not found
  def find_calendar_date(date)
    # First navigate to the correct month
    navigate_to_month(date.month, date.year)
    
    # Then find the day element by aria-label or other attributes
    within('.flatpickr-calendar') do
      # Try to find by aria-label first (most reliable)
      day_element = first(".flatpickr-day[aria-label*='#{date.strftime('%B %-d, %Y')}']", wait: 5)
      return day_element if day_element
      
      # Fallback to finding by day number and checking if it's in the correct month
      day_elements = all('.flatpickr-day', wait: 5).select do |el| 
        el.text.strip == date.day.to_s && !el[:class].include?('prevMonthDay') && !el[:class].include?('nextMonthDay')
      end
      day_elements.first if day_elements.any?
    end
  end

  # Expect a specific date to be disabled
  # @param date [Date] The date to check
  def expect_date_disabled(date)
    wait_for_flatpickr_calendar_to_load # Ensure calendar is loaded
    day_element = find_calendar_date(date)
    if day_element
      expect(day_element[:class]).to include('flatpickr-disabled'),
                                     "Expected #{date} to be disabled, but it was enabled"
    else
      raise "Could not find #{date} in calendar"
    end
  end

  # Expect a specific date to be enabled
  # @param date [Date] The date to check
  def expect_date_enabled(date)
    wait_for_flatpickr_calendar_to_load # Ensure calendar is loaded
    day_element = find_calendar_date(date)
    if day_element
      expect(day_element[:class]).not_to include('flatpickr-disabled'),
                                         "Expected #{date} to be enabled, but it was disabled"
    else
      raise "Could not find #{date} in calendar"
    end
  end

  # Click on a specific date
  # @param date [Date] The date to click
  # @param force [Boolean] Whether to force click even if disabled (default: false)
  def click_calendar_date(date, force: false)
    wait_for_flatpickr_calendar_to_load # Ensure calendar is loaded
    day_element = find_calendar_date(date)
    if day_element
      if force || !day_element[:class].include?('flatpickr-disabled')
        day_element.click
      else
        raise "Cannot click #{date} because it is disabled. Use force: true to override."
      end
    else
      raise "Could not find #{date} in calendar"
    end
  end

  # Helper method for the common pattern in existing tests - navigate to July and find/check days
  # This maintains compatibility with the existing test patterns
  def setup_july_calendar
    wait_for_flatpickr_calendar_to_load
    navigate_to_july_calendar
  end

  # Alias for backward compatibility with existing tests
  def wait_for_calendar
    wait_for_flatpickr_calendar_to_load
  end
end

# Include the helper in system tests
RSpec.configure do |config|
  config.include CalendarTestHelpers, type: :system
end