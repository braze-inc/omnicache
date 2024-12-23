# frozen_string_literal: true

require_relative "lib/omnicache/version"

Gem::Specification.new do |spec|
  spec.name = "omnicache"
  spec.version = OmniCache::VERSION
  spec.authors = ["Evan Goldenberg"]
  spec.email = ["evan.goldenberg@braze.com"]

  spec.summary = "An in-memory caching library for Ruby"
  spec.homepage = "https://github.com/braze-inc/omnicache"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.require_paths = ["lib"]
end
