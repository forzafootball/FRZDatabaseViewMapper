# coding: utf-8
Pod::Spec.new do |spec|
  spec.name         = 'FRZDatabaseViewMapper'
  spec.version      = '1.1.0'
  spec.platform     = :ios, '9.0'
  spec.homepage     = 'https://github.com/ForzaFootball/FRZDatabaseViewMapper'
  spec.authors      = { 'Joel Ekström' => 'joel@forzafootball.com' }
  spec.summary      = 'Handles YapDatabase view mapping boilerplate, multiple view mappings in the same view'
  spec.license      = 'MIT'
  spec.source       = { :git => 'https://github.com/forzafootball/FRZDatabaseViewMapper.git', :tag => "v#{spec.version}" }
  spec.source_files = '*.{h,m}'
  spec.frameworks   = 'Foundation', 'UIKit'
  spec.dependency     'YapDatabase', '~> 3.0'
end
