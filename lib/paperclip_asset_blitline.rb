# Include hook code here
require 'paperclip_asset_blitline/paperclip_asset_blitline'

module PaperclipAssetBlitline
  if defined?(Rails) && Rails::VERSION::MAJOR >= 3
    class Engine < Rails::Engine
    end
  end
end
