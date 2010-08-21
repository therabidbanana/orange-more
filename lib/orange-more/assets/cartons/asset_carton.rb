class OrangeAsset < Orange::Carton
  id
  admin do
    title :name, :length => 255
    text :caption, :length => 255
  end
  orange do
    string :path, :length => 255
    string :mime_type
    string :secondary_path, :length => 255, :required => false
    string :secondary_mime_type
  end
  property :s3_bucket, String, :length => 64, :required => false
  
  def file_path
    if(s3_bucket)
      "http://s3.amazonaws.com/#{s3_bucket}/#{path}"
    else
      File.join('', 'assets', 'uploaded', path)
    end
  end
  
  def to_s
    <<-DOC
    {"id": #{self.id}, "html": "#{self.to_asset_tag}"}
    DOC
  end
  
  def pdf?
    mime_type =~ /^application\/pdf/
  end
  def image?
    mime_type =~ /^image/
  end
  def file?
    !(pdf? || image?)
  end
  
  def to_asset_tag(alt = "")
    alt = alt.blank? ? caption : alt
    alt = alt.blank? ? name : alt
    case mime_type
    when /^image/
      "<img src='#{file_path}' border='0' alt='#{alt}' />"
    when /^application\/pdf/
      "<span class='pdf_link'><a href='#{file_path}'>#{alt}</a></span>"
    else
      "<span class='file_link'><a href='#{file_path}'>#{alt}</a></span>"
    end
  end
end
