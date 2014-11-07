module PaperclipAssetBlitline
  class S3Upload
    attr_accessor :media_file, :uploaded_file, :asset_name, :asset

    def initialize(media_file, uploaded_file, asset_name = :asset)
      @media_file    = media_file
      @uploaded_file = uploaded_file
      @asset_name    = asset_name
      @asset         = @media_file.send(@asset_name)
    end

    def upload!
      s3 = AWS::S3.new
      s3.buckets[ENV["S3_BUCKET"]].objects[@asset.path(:original)].write(@uploaded_file)
      s3.buckets[ENV["S3_BUCKET"]].objects[@asset.path(:original)].acl = :public_read
      process_with_blitline!
    end

    private

    def translate_geometry_modifier(modifier)
      # NOTE: Add this later, we only need this for now.
      case modifier
      when "#"
        "resize_to_fill"
      else
        "resize_to_fit"
      end
    end

    def translate_gif_geometry_modifier(modifier)
      # NOTE: Add this later, we only need this for now.
      case modifier
      when "#"
        "resize_gif"
      else
        "resize_gif_to_fit"
      end
    end

    def asset_styles_for_blitline
      @asset.styles.keys.inject([]) do |result, style|
        geometry = Paperclip::Geometry.parse(@asset.styles[style].geometry)
        style_hash = {
          "save"   => { "image_identifier" => style.to_s } #,
          # "bucket" => ENV["S3_BUCKET"],
          # "key"    => @asset.path(style)
        }
        style_hash["params"] = {}
        style_hash["params"]["width"]  = geometry.width  if geometry.width  > 0
        style_hash["params"]["height"] = geometry.height if geometry.height > 0
        style_hash["name"] = @asset.path(style) =~ /\.gif$/ ?
                               translate_gif_geometry_modifier(geometry.modifier) :
                                 translate_geometry_modifier(geometry.modifier)
        result << style_hash
      end
    end

    def process_with_blitline!
      blitline_service = Blitline.new
      url = "http://s3.amazonaws.com/#{ENV["S3_BUCKET"]}/#{@asset.path(:original)}"
      blitline_service.add_job_via_hash({
        "application_id" => ENV["BLITLINE_APPLICATION_ID"],
        "src" => url,
        "functions" => asset_styles_for_blitline
      })
      # Rails.logger.error "**************************************************************"
      # Rails.logger.error asset_styles_for_blitline.inspect
      # Rails.logger.error "**************************************************************"
      response = blitline_service.post_job_and_wait_for_poll
      # Rails.logger.error "**************************************************************"
      # Rails.logger.error response.inspect
      # Rails.logger.error "**************************************************************"

      # { "original_meta"=>{"width"=>262, "height"=>192},
      #   "images"=>[
      #     {"image_identifier"=>"large", "s3_url"=>"http://s3.amazonaws.com/blitline/2014110219/4633/9BI2668ztwAtaEhrp-BwHFQ.jpg", "meta"=>{"width"=>640, "height"=>469}},
      #     {"image_identifier"=>"default", "s3_url"=>"http://s3.amazonaws.com/blitline/2014110219/4633/8UwifuPh5MVd-NowPU85W5g.jpg", "meta"=>{"width"=>480, "height"=>352}},
      #     {"image_identifier"=>"medium", "s3_url"=>"http://s3.amazonaws.com/blitline/2014110219/4633/6RR3cVYtEgvF3AqJMPblv5g.jpg", "meta"=>{"width"=>320, "height"=>235}},
      #     {"image_identifier"=>"small", "s3_url"=>"http://s3.amazonaws.com/blitline/2014110219/4633/5u-ice8GToCll8vWQ6VER0Q.jpg", "meta"=>{"width"=>160, "height"=>117}},
      #     {"image_identifier"=>"tiny", "s3_url"=>"http://s3.amazonaws.com/blitline/2014110219/4633/4-qr0DDTUu89iWoh7ocrtpw.jpg", "meta"=>{"width"=>80, "height"=>59}}
      #   ],
      #   "job_id"=>"6Io_LP13xwL29UmKYjBs4wA"
      # }
    
      # Copy each images in the response back to s3.
      s3 = AWS::S3.new
      images = response["images"]
      images.each do |image_hash|
        size = image_hash["image_identifier"]
        file_content = open(image_hash["s3_url"]) { |f| f.read }
        s3.buckets[ENV["S3_BUCKET"]].objects[@asset.path(size)].write(file_content)
        s3.buckets[ENV["S3_BUCKET"]].objects[@asset.path(size)].acl = :public_read
      end    
    end
  end
end