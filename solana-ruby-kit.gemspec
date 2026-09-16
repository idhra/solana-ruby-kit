# frozen_string_literal: true

require_relative 'lib/solana/ruby/kit/version'

Gem::Specification.new do |spec|
  spec.name                  = 'solana-ruby-kit'
  spec.version               = Solana::Ruby::Kit::VERSION
  spec.authors               = ['Paul Zupan, Idhra Inc.']
  spec.summary               = 'Ruby port of the Anza TypeScript SDK (@anza-xyz/kit)'
  spec.homepage              = 'https://github.com/idhra/solana-ruby-kit'
  spec.license               = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'
  spec.require_paths         = ['lib']

  # `homepage_uri` is omitted deliberately: `spec.homepage` already supplies it, and
  # repeating the same URI under a second key makes rubygems.org drop the duplicate.
  spec.metadata = {
    'source_code_uri'   => "#{spec.homepage}/tree/main",
    'documentation_uri' => "#{spec.homepage}/wiki",
    'bug_tracker_uri'   => "#{spec.homepage}/issues"
  }

  spec.files = Dir['lib/**/*.rb', 'lib/**/*.tt'] + ['LICENSE', 'README.md', 'solana-ruby-kit.gemspec']
  spec.extra_rdoc_files = ['LICENSE', 'README.md']

  # `rpc_types/sol.rb` requires bigdecimal, which stopped being a default gem
  # in Ruby 3.4. Without this the gem does not load at all on 3.4+; it went
  # unnoticed because webmock -> crack pulls bigdecimal into development.
  # Bounded rather than `~> 3.1` because 4.x is current and the only API used
  # here is the Kernel#BigDecimal conversion, unchanged across both majors.
  spec.add_dependency 'bigdecimal', '>= 3.1', '< 5'
  spec.add_dependency 'openssl', '~> 3.3'
  # Sorbet does not follow semver — the patch component is a build number, and the
  # runtime must track the compiler's series — so these are bounded at the minor level.
  spec.add_dependency 'sorbet-runtime', '~> 0.6'
  spec.add_dependency 'rbnacl', '~> 7.1'
  spec.add_dependency 'websocket-client-simple', '~> 0.9'

  spec.add_development_dependency 'sorbet', '~> 0.6'
  spec.add_development_dependency 'drb', '~> 2.2'
  spec.add_development_dependency 'sexp_processor', '~> 4.17'
  spec.add_development_dependency 'parser', '~> 3.3'
  spec.add_development_dependency 'tapioca', '~> 0.16'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'webmock', '~> 3.26'
end
