# Include hook code here
require 'paperclip_asset_blitline/paperclip_asset_blitline'

module PaperclipAssetBlitline
  class Engine < Rails::Engine
  end if defined?(Rails) && Rails::VERSION::MAJOR >= 3
end

