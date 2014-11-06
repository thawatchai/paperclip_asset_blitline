module PaperclipAssetBlitline
  module Hook
    module ClassMethods
      def is_storage_s3?
        ENV["S3_ACCESS_KEY_ID"].present?
      end

      def translate_content_type(content_type)
        content_type.blank? ? "application/octet-stream" : content_type.chomp
      end

      def convert_thai_filename(filename)
        cld = CLD.detect_language(filename)
        if cld[:code] == "th"
          # Rename the file if it's using Thai language.
          DateTime.now.strftime("%Y%m%d%H%M%S") + File.extname(filename)
        else
          filename
        end
      end

      def is_blitline_enabled?
        ENV["BLITLINE_APPLICATION_ID"] && self.is_storage_s3?
      end

      def blitline_asset_attributes(*args)
        (self.blitline_asset_names = args).each do |name|
          self.class_eval {
            attr_accessor "blitline_#{name}"

            # Hijack the attribute to prevent paperclip from processing automatically.
            define_method("#{name}=") do |uploaded|
              if self.class.is_blitline_enabled?
                self.send("blitline_#{name}=", uploaded)
                self.send("#{name}_file_size=", uploaded.size)
                self.send("#{name}_file_name=", self.class.convert_thai_filename(uploaded.original_filename))
                self.send("#{name}_content_type=", self.class.translate_content_type(uploaded.content_type))
              else
                self.send(name).assign(uploaded)    # This is copied from paperclip/has_attached_file.rb.
              end
            end
          }
        end
      end
    end

    module InstanceMethods
      def is_storage_s3?
        self.class.is_storage_s3?
      end

      private

      def upload_to_s3_and_process_with_blitline
        self.class.blitline_asset_names.each do |asset_name|
          begin
          is_image = self.send("#{asset_name}_content_type") =~ /(jpeg|jpg|png|gif)/i
        rescue
          raise [self.class.blitline_asset_names, asset_name, self].inspect
        end
          current_asset = self.send("blitline_#{asset_name}")
          if ! current_asset.nil? && is_image
            ::PaperclipAssetBlitline::S3Upload.new(self, current_asset, asset_name).upload!
          end
        end
      end
    end

    def self.included(klass)
      klass.extend ClassMethods
      klass.class_eval {
        cattr_accessor :blitline_asset_names
        after_save :upload_to_s3_and_process_with_blitline, if: Proc.new { |x| self.class.is_blitline_enabled? }
      }
      klass.module_eval {
        include InstanceMethods
      }
    end
  end
end