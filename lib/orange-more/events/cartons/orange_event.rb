class OrangeEvent < Orange::Carton
  id
  admin do
    title :name
    text :location
    fulltext :description
  end
  orange do
    time :starts
    time :ends
  end
  def starts_time
    self.starts.strftime("%I:%M %p")
  end
  def starts_date
    self.starts.strftime("%m/%d/%Y")
  end
  def ends_time
    self.ends.strftime("%I:%M %p")
  end
  def ends_date
    self.ends.strftime("%m/%d/%Y")
  end
  def date_attr(attribute, datestr = false)
    time_attr(attribute, false, datestr)
  end
  
  def time_attr(attribute, timestr = false, datestr = false)
    date = datestr || attribute_get(attribute).strftime("%m/%d/%Y")
    time = timestr || attribute_get(attribute).strftime("%I:%M %p")
    attribute_set(attribute, Time.parse(date + " " + time))
  end
  
  def starts_time=(time)
    time_attr(:starts, time)
  end
  def starts_date=(date)
    date_attr(:starts, date)
  end
  def ends_time=(time)
    time_attr(:ends, time)
  end
  def ends_date=(date)
    date_attr(:ends, date)
  end
  
  belongs_to :calendar, "OrangeCalendar", :child_key => [:orange_calendar_id]
end