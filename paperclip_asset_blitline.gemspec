# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

require "paperclip_asset_blitline/version"

Gem::Specification.new do |s|
  s.name        = "paperclip_asset_blitline"
  s.version     = PaperclipAssetBlitline::VERSION
  s.platform    = Gem::Platform::RUBY  
  s.summary     = "Upload paperclip asset to S3 directly and process with blitline."
  s.email       = "support@usablelabs.org"
  s.homepage    = "http://github.com/thawatchai/paperclip_asset_blitline"
  s.description = "Upload paperclip asset to S3 directly and process with blitline."
  s.authors     = ['Thawatchai Piyawat', 'John Tjanaka']

  s.rubyforge_project = "paperclip_asset_blitline"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency("rails",     ">= 3.0")
  s.add_dependency("paperclip", ">= 4.1.1")
  s.add_dependency("aws-sdk",   ">= 1.52.0")
  s.add_dependency("cld",       ">= 0.7.0")
end
