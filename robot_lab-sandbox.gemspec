# frozen_string_literal: true

require_relative "lib/robot_lab/sandbox/version"

Gem::Specification.new do |spec|
  spec.name = "robot_lab-sandbox"
  spec.version = RobotLab::Sandbox::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dvanhoozer@gmail.com"]

  spec.summary = "OS-level confinement for RobotLab skill scripts."
  spec.description = "Deny-by-default, capability-scoped execution for AgentSkills scripts. On macOS, wraps " \
                     "scripts in a generated sandbox-exec (Seatbelt) profile derived from the skill's " \
                     "declared capabilities intersected with a configured ceiling; robot_lab core runs " \
                     "unconfined until this gem is required."
  spec.homepage = "https://github.com/MadBomber/robot_lab-sandbox"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "robot_lab", ">= 0.1"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
