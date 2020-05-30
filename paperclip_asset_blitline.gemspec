$LOAD_PATH.push File.expand_path('lib', __dir__)

require 'paperclip_asset_blitline/version'

Gem::Specification.new do |s|
  s.name        = 'paperclip_asset_blitline'
  s.version     = PaperclipAssetBlitline::VERSION
  s.platform    = Gem::Platform::RUBY
  s.summary     = 'Upload paperclip asset to S3 directly and process with ' \
                  'blitline.'
  s.email       = 'support@usablelabs.org'
  s.homepage    = 'http://github.com/thawatchai/paperclip_asset_blitline'
  s.description = 'Upload paperclip asset to S3 directly and process with ' \
                  'blitline.'
  s.authors     = ['Thawatchai Piyawat', 'John Tjanaka']

  s.rubyforge_project = 'paperclip_asset_blitline'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n")
                                           .map{ |f| File.basename(f) }
  s.require_paths = ['lib']

  s.add_dependency('aws-sdk-s3', '~> 1')
  s.add_dependency('blitline',   '~> 2.4')
  s.add_dependency('paperclip',  '>= 4.2')
  s.add_dependency('rails',      '>= 4.2')
end
