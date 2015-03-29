require "blitline"

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
      path = @asset.path(:original).sub(/^\//, "")
      if ENV["BLITLINE_DEBUG"]
        Rails.logger.error "**************************************************************"
        Rails.logger.error "Uploading original to: #{path}"
        Rails.logger.error @uploaded_file.inspect
        Rails.logger.error "**************************************************************"
      end
      s3.buckets[ENV["S3_BUCKET"]].objects[path].write(@uploaded_file)
      s3.buckets[ENV["S3_BUCKET"]].objects[path].acl = :public_read
      if ENV["BLITLINE_DEBUG"]
        Rails.logger.error "**************************************************************"
        Rails.logger.error "Upload result:"
        Rails.logger.error s3.buckets[ENV["S3_BUCKET"]].objects[path].inspect
        Rails.logger.error "**************************************************************"
      end
      process_with_blitline!
    end

    def reprocess!
      process_with_blitline!
    end

    private

    def translate_geometry_modifier(modifier, gif = false)
      # NOTE: Add this later, we only need this for now.
      case modifier
      when "#"
        gif ? "resize_gif" : "resize_to_fill"
      else
        gif ? "resize_gif_to_fit" : "resize_to_fit"
      end
    end

    def extended_crop_functions(style, geometry)
      [{
        "name" => "crop",
        "params" => {
          "x"      => 0,
          "y"      => 0,
          "width"  => geometry.width,
          "height" => geometry.height
        },
        "save" => {
          "image_identifier" => style.to_s
        }
      }]
    end

    def style_hash_for(style, gif = false)
      geometry = Paperclip::Geometry.parse(@asset.styles[style].geometry)
      style_hash = {}
      style_hash["name"] = translate_geometry_modifier(geometry.modifier, gif)
      style_hash["params"] = {}
      if geometry.modifier == ">" && ! gif &&
         (@asset.styles[style].geometry =~ /^(\d*)x(\d+)\>$/ ||
          @asset.styles[style].geometry =~ /^(\d+)\>x?(\d*)$/)
        # NOTE: This is different from paperclip/imagemagick.
        # =>    e.g.: 940x300> will resize to the width first, then crop the height
        # =>                   if it's more than 300px.
        # =>          940>x300 will resize to the height first, then crop the width
        # =>                   if it's more than 940px.
        # =>    This doesn't work for .gif.
        if @asset.styles[style].geometry =~ /^(\d*)x(\d+)\>$/
          # Resize to width, then crop the height.
          style_hash["params"]["width"] = geometry.width
        elsif @asset.styles[style].geometry =~ /^(\d+)\>x?(\d*)$/
          # Resize to height, then crop the width.
          style_hash["params"]["height"] = geometry.height
        end
        style_hash["functions"] = extended_crop_functions(style, geometry)
      else
        style_hash["save"] = { "image_identifier" => style.to_s }
        # {
          # "bucket" => ENV["S3_BUCKET"],
          # "key"    => @asset.path(style)
        # }
        style_hash["params"]["width"]  = geometry.width  if geometry.width  > 0
        style_hash["params"]["height"] = geometry.height if geometry.height > 0
      end
      style_hash
    end

    def functions_for_blitline
      @asset.styles.keys.inject([]) do |result, style|
        result << style_hash_for(style, false)
      end
    end

    def job_for_blitline
      {
        "application_id" => ENV["BLITLINE_APPLICATION_ID"],
        "src" => "http://s3.amazonaws.com/#{ENV["S3_BUCKET"]}/#{@asset.path(:original).sub(/^\//, "")}",
        "functions" => functions_for_blitline
      }
    end

    def gif_job_for_blitline(style)
      {
        "application_id" => ENV["BLITLINE_APPLICATION_ID"],
        "src" => "http://s3.amazonaws.com/#{ENV["S3_BUCKET"]}/#{@asset.path(:original).sub(/^\//, "")}",
        "src_type" => "gif",
        "src_data" => style_hash_for(style, true)
      }
    end

    def add_job_and_process_result!(job)
      blitline_service = Blitline.new
      blitline_service.add_job_via_hash(job)

      if ENV["BLITLINE_DEBUG"]
        Rails.logger.error "**************************************************************"
        Rails.logger.error job.inspect
        Rails.logger.error "**************************************************************"
      end
      response = blitline_service.post_job_and_wait_for_poll
      response = JSON.parse(response) if response.is_a?(String) # Is JSON string?
      if ENV["BLITLINE_DEBUG"]
        Rails.logger.error "**************************************************************"
        Rails.logger.error response.inspect
        Rails.logger.error "**************************************************************"
      end

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
      begin
        images.each do |image_hash|
          size = image_hash["image_identifier"]
          file_content = open(image_hash["s3_url"]) { |f| f.read }
          path = @asset.path(size).sub(/^\//, "")
          s3.buckets[ENV["S3_BUCKET"]].objects[path].write(file_content)
          s3.buckets[ENV["S3_BUCKET"]].objects[path].acl = :public_read
        end
      rescue NoMethodError => e
        Rails.logger.error "**************************************************************"
        Rails.logger.error response.inspect
        Rails.logger.error "**************************************************************"
        raise
      end
    end

    def process_with_blitline!
      jobs = if @asset.path(:original) =~ /\.gif$/
        @asset.styles.keys.inject([]) do |result, key|
          result << gif_job_for_blitline(key)
        end
      else
        [job_for_blitline]
      end
      jobs.each { |job| add_job_and_process_result!(job) }
    end
  end
end