require "blitline"

module PaperclipAssetBlitline
  class S3Upload
    attr_accessor :media_file, :uploaded_file, :asset_name, :asset

    def initialize(media_file, uploaded_file, asset_name = :asset, options = {})
      @media_file    = media_file
      @uploaded_file = uploaded_file
      @asset_name    = asset_name
      @options       = options
      @asset         = @media_file.send(@asset_name)
    end

    def upload!
      s3 = Aws::S3::Client.new
      path = @asset.path(:original).sub(/^\//, "")
      if ENV["BLITLINE_DEBUG"]
        Rails.logger.error "**************************************************************"
        Rails.logger.error "Uploading original to: #{path}"
        Rails.logger.error @uploaded_file.inspect
        Rails.logger.error "**************************************************************"
      end

      bucket = Aws::S3::Resource.new.bucket(ENV["S3_BUCKET"])
      bucket.put_object(
        key:            path,
        body:           @uploaded_file,
        content_length: @asset.size,
        acl:            "public-read"
      )
      # s3.buckets[ENV["S3_BUCKET"]].objects[path].write(@uploaded_file)
      # s3.buckets[ENV["S3_BUCKET"]].objects[path].acl = :public_read
      if ENV["BLITLINE_DEBUG"]
        Rails.logger.error "**************************************************************"
        Rails.logger.error "Upload result:"
        Rails.logger.error bucket.object(path).inspect
        Rails.logger.error "**************************************************************"
      end
      process_with_blitline!
    end

    def reprocess!
      process_with_blitline!
    end

    private

    def translate_geometry_modifier(modifier, animated_gif = false)
      # NOTE: Add this later, we only need this for now.
      case modifier
      when "#"
        animated_gif ? "resize_gif" : "resize_to_fill"
      else
        animated_gif ? "resize_gif_to_fit" : "resize_to_fit"
      end
    end

    def extended_crop_functions(style, geometry)
      [
        {
          "name" => "crop",
          "params" => {
            "x"      => 0,
            "y"      => 0,
            "width"  => geometry.width,
            "height" => geometry.height
          }
        }.merge(watermark_function(style, geometry))
      ]
    end

    def watermark_function(style, geometry)
      options = {
        "save" => {
          "image_identifier" => style.to_s
        }
      }

      unless @options[:watermark].blank?
        text = @options[:watermark].respond_to?(:call) ?
                 @options[:watermark].call(@media_file) : @options[:watermark]

        if text.blank?
          options
        else
          {
            "functions" => [
              {
                "name" => "watermark",
                "params" => {
                  "text"       => text,
                  "gravity"    => "SouthGravity",
                  "point_size" => (geometry.width / 20).to_s,
                  "opacity"    => "0.2"
                }
              }.merge(options)
            ] 
          }
        end
      else
        options
      end
    end

    def style_hash_for(style, animated_gif = false)
      geometry = Paperclip::Geometry.parse(@asset.styles[style].geometry)
      style_hash = {}
      style_hash["name"] = translate_geometry_modifier(geometry.modifier, animated_gif)
      style_hash["params"] = {}
      if geometry.modifier == ">" && ! animated_gif &&
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
        # {
          # "bucket" => ENV["S3_BUCKET"],
          # "key"    => @asset.path(style)
        # }
        style_hash["params"]["width"]  = geometry.width  if geometry.width  > 0
        style_hash["params"]["height"] = geometry.height if geometry.height > 0

        if animated_gif
          style_hash["save"] = { "image_identifier" => style.to_s }
        else
          style_hash.merge!(watermark_function(style, geometry))
        end
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

    def add_job(job)
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
      response
    end

    def add_job_and_process_result!(job)
      response = add_job(job)

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
      s3 = Aws::S3::Client.new
      images = response["images"]
      begin
        images.each do |image_hash|
          if ! image_hash["error"].blank?
            @media_file.errors[@asset_name] << image_hash["error"]
          elsif ! image_hash["failed_image_identifiers"].blank?
            @media_file.errors[@asset_name] << ("Failed image identifiers:" + image_hash["failed_image_identifiers"].join(", "))
          else
            size = image_hash["image_identifier"]
            file_content = open(image_hash["s3_url"]) { |f| f.read }
            path = @asset.path(size).sub(/^\//, "")

            bucket = Aws::S3::Resource.new.bucket(ENV["S3_BUCKET"])
            bucket.put_object(
              key:            path,
              body:           file_content,
              content_length: file_content.length,
              acl:            "public-read"
            )

            # s3.buckets[ENV["S3_BUCKET"]].objects[path].write(file_content)
            # s3.buckets[ENV["S3_BUCKET"]].objects[path].acl = :public_read
          end
        end
      rescue NoMethodError, TypeError, OpenURI::HTTPError => e
        Rails.logger.error "**************************************************************"
        Rails.logger.error response.inspect
        Rails.logger.error response.class.inspect
        Rails.logger.error response["images"].inspect
        Rails.logger.error "**************************************************************"
        raise
      end
    end

    def process_with_blitline!
      jobs = if @asset.path(:original) =~ /\.gif$/ && is_animated_gif?
        @asset.styles.keys.inject([]) do |result, key|
          result << gif_job_for_blitline(key)
        end
      else
        [job_for_blitline]
      end
      jobs.each { |job| add_job_and_process_result!(job) }
    end

    def is_animated_gif?
      job = {
        "application_id" => ENV["BLITLINE_APPLICATION_ID"],
        "src" => "http://s3.amazonaws.com/#{ENV["S3_BUCKET"]}/#{@asset.path(:original).sub(/^\//, "")}",
        "get_exif" => "true",
        "v" => "1.21",
        "functions" => [
          {
            "name" => "resize_to_fit",
            "params" => {
              "width" => "100"
            },
            "save" => {
              "image_identifier" => "MY_CLIENT_ID"
            }    
          }
        ]
      }

      response = add_job(job)

      # Expected output:
      # {
      #     "original_meta": {
      #         "width": 350,
      #         "height": 350,
      #         "original_exif": {
      #             "FileSize": "6.9 kB",
      #             "FileModifyDate": "2017-05-09 10:33:49 +0000",
      #             "FileAccessDate": "2017-05-09 10:33:49 +0000",
      #             "FileInodeChangeDate": "2017-05-09 10:33:49 +0000",
      #             "FileType": "GIF",
      #             "FileTypeExtension": "gif",
      #             "MIMEType": "image/gif",
      #             "GIFVersion": "89a",
      #             "ImageWidth": 350,
      #             "ImageHeight": 350,
      #             "HasColorMap": "Yes",
      #             "ColorResolutionDepth": 4,
      #             "BitsPerPixel": 4,
      #             "BackgroundColor": 15,
      #             "AnimationIterations": "Infinite",
      #             "FrameCount": 5,
      #             "Duration": "5.00 s",
      #             "ImageSize": "350x350",
      #             "Megapixels": 0.122
      #         },
      #         "density_info": {
      #             "density_x": 72,
      #             "density_y": 72,
      #             "units": "PixelsPerInch"
      #         },
      #         "filesize": 7051
      #     },
      #     "images": [
      #         {
      #             "image_identifier": "MY_CLIENT_ID",
      #             "s3_url": "http://blitline.s3.amazonaws.com/2017050910/4633/this_file_will_be_autodeleted_in_24hrs_4YC5msZzvAx9cM3Wez2UNJQ.jpg",
      #             "meta": {
      #                 "width": 100,
      #                 "height": 100
      #             }
      #         }
      #     ],
      #     "job_id": "9rDkX8nGd8WyDLlar7iSJwA"
      # }

      !response.blank? && !response["original_meta"].blank? &&
        !response["original_meta"]["original_exif"].blank? &&
        !response["original_meta"]["original_exif"]["FrameCount"].blank? &&
        response["original_meta"]["original_exif"]["FrameCount"].to_i > 0
    end
  end
end