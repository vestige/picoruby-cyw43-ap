MRuby::Gem::Specification.new('picoruby-cyw43-ap') do |spec|
  spec.version = '0.1.0'
  spec.license = 'MIT'
  spec.authors = ['vestige']
  spec.summary = 'DHCP-backed CYW43 access point support for PicoRuby'
  spec.require_name = 'cyw43/ap'

  spec.add_dependency 'picoruby-cyw43'
end
