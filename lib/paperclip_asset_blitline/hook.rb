module PaperclipAssetBlitline
  module Hook
    module ClassMethods
      def storage_s3?
        ENV['S3_ACCESS_KEY_ID'].present?
      end

      def translate_content_type(content_type)
        content_type.blank? ? 'application/octet-stream' : content_type.chomp
      end

      def convert_filename(filename)
        # Rename the file.
        DateTime.now.strftime('%Y%m%d%H%M%S') + File.extname(filename)
      end

      def blitline_enabled?
        ENV['BLITLINE_APPLICATION_ID'] && self.storage_s3?
      end

      def blitline_asset_attributes(*args)
        self.blitline_asset_names, self.blitline_settings =
          args.partition { |a| !a.is_a?(Hash) }
        self.blitline_asset_names.each do |name|
          self.class_eval {
            attr_accessor "blitline_#{name}"

            # Hijack the attribute to prevent paperclip from processing
            # automatically.
            alias_method "orig_#{name}=", "#{name}="
            define_method("#{name}=") do |uploaded|
              if self.class.blitline_enabled? && uploaded &&
                 uploaded.respond_to?(:content_type) &&
                 uploaded.content_type =~ /(jpeg|jpg|png|gif)/i
                self.send("blitline_#{name}=", uploaded)
                self.send("#{name}_file_size=", uploaded.size)
                self.send("#{name}_file_name=",
                          self.class
                              .convert_filename(uploaded.original_filename))
                self.send("#{name}_content_type=",
                          self.class
                              .translate_content_type(uploaded.content_type))
              else
                uploaded.original_filename =
                  uploaded.original_filename.to_s.force_encoding('UTF-8')
                # Use paperclip's original assignment.
                self.send("orig_#{name}=", uploaded)
                # This is copied from paperclip/has_attached_file.rb.
                # self.send(name).assign(uploaded)
              end
            end
          }
        end
        self.blitline_settings = self.blitline_settings
                                     .inject({}) do |result, hash|
          result.merge(hash)
        end
      end
    end

    module InstanceMethods
      def storage_s3?
        self.class.storage_s3?
      end

      private

      def upload_to_s3_and_process_with_blitline
        self.class.blitline_asset_names.each do |asset_name|
          is_image =
            self.send("#{asset_name}_content_type") =~ /(jpeg|jpg|png|gif)/i
          current_asset = self.send("blitline_#{asset_name}")

          next unless !current_asset.nil? && is_image

          ::PaperclipAssetBlitline::S3Upload.new(
            self, current_asset, asset_name, self.class.blitline_settings
          ).upload!
        end
      end
    end

    def self.included(klass)
      klass.extend ClassMethods
      klass.class_eval {
        cattr_accessor :blitline_asset_names, :blitline_settings
        after_save :upload_to_s3_and_process_with_blitline,
                   if: proc { |x| x.class.blitline_enabled? }
      }
      klass.module_eval {
        include InstanceMethods
      }
    end
  end
end
