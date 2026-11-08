#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
ACTION = YAML.load_file(File.join(__dir__, 'actions/release/action.yml'))


def assert(value, message)
  raise message unless value
end


def release_steps(workflow, job)
  steps = workflow.fetch('jobs').fetch(job).fetch('steps')
  first = steps.index { |step| step['name'] == 'Import the signing identity' }
  last = steps.index { |step| step['name'] == 'Package zip and dmg' }
  steps[first..last]
end


def rendered(caller)
  inputs = ACTION.fetch('inputs').transform_values { |input| input['default'] }
  inputs.merge!(caller.fetch('with'))
  ACTION.fetch('runs').fetch('steps').map do |original|
    step = JSON.parse(JSON.generate(original))
    next if step['name'] == 'Check app identity' && inputs['identity-first'] == 'true'
    step.delete('shell')
    step.delete('if')
    step['if'] = caller['if'] if caller['if']
    step.fetch('env', {}).transform_values! do |value|
      value.gsub(/\$\{\{ inputs\.([\w-]+) \}\}/) { inputs.fetch(Regexp.last_match(1)) }
    end
    step.fetch('env', {}).delete('IDENTITY_FIRST')
    identity = 'if [ "$IDENTITY_FIRST" = true ]; then ./tools/notchcast/check-identity.sh app "$APP"; fi'
    step['run'] = step['run'].lines.map do |line|
      if line.strip == identity
        "./tools/notchcast/check-identity.sh app \"$APP\"\n" if inputs['identity-first'] == 'true'
      else
        line
      end
    end.compact.join
    step
  end.compact
end

ACTION.fetch('runs').fetch('steps').each do |step|
  assert(step['shell'] == 'bash -e {0}', "#{step['name']} must preserve the workflow's implicit bash shell")
  output, status = Open3.capture2e('bash', '-n', stdin_data: step.fetch('run'))
  assert(status.success?, "#{step['name']} shell syntax failed: #{output}")
end

snapshot_launch = nil
%w[snapshot sync].each do |name|
  job = name == 'snapshot' ? 'snapshot' : 'release'
  workflow = YAML.load_file(File.join(ROOT, ".github/workflows/#{name}.yml"))
  callers = workflow.fetch('jobs').fetch(job).fetch('steps').select { |step| step['uses'] == './tools/notchcast/actions/release' }
  assert(callers.size == 1, "#{name} must use the shared release action once")
  caller = callers.first
  if name == 'snapshot'
    assert(caller['if'] == "steps.checks.outputs.green == 'true'", 'snapshot release must remain gated on lint and tests')
  else
    assert(caller.dig('with', 'identity-first') == 'true', 'mirror identity verification order changed')
  end
  after = rendered(caller)
  launch = after.find { |step| step['name'] == 'Launch and stay alive' }
  assert(launch && launch['run'].include?("sleep 30\n") && launch['run'].include?('kill -0 "$PID"'), 'release must check liveness after 30 seconds')
  snapshot_launch = launch['run'] if name == 'snapshot'
  assert(launch['run'] == snapshot_launch, 'both releases must run the same launch check')
  next if ARGV.empty?
  source, status = Open3.capture2('git', 'show', "#{ARGV.first}:.github/workflows/#{name}.yml", chdir: ROOT)
  assert(status.success?, 'cannot load the release baseline')
  before = release_steps(YAML.safe_load(source), job)
  comparable = name == 'sync' ? after.reject { |step| step['name'] == 'Launch and stay alive' } : after
  Dir.mktmpdir('release-equivalence-') do |directory|
    old_path = File.join(directory, 'before.json')
    new_path = File.join(directory, 'after.json')
    File.write(old_path, JSON.pretty_generate(before.map { |step| step.sort.to_h }))
    File.write(new_path, JSON.pretty_generate(after.map { |step| step.sort.to_h }))
    diff, status = Open3.capture2('diff', '-u', old_path, new_path)
    assert(before == comparable, "#{name} release behavior changed:\n#{diff}")
    assert(status.exitstatus <= 1, 'could not diff rendered release steps')
    puts diff unless diff.empty?
  end
  puts "PASS #{name} rendered release steps match #{ARGV.first}#{name == 'sync' ? ' except the added launch check' : ''}"
end

Dir.mktmpdir('release-launch-') do |directory|
  FileUtils.mkdir_p(File.join(directory, 'tools/notchcast'))
  File.write(File.join(directory, 'tools/notchcast/config.env'), "APP_NAME=Fixture\n")
  FileUtils.mkdir_p(File.join(directory, 'bin'))
  File.write(File.join(directory, 'bin/ditto'), "#!/bin/bash\ncp -R \"$1\" \"$2\"\n")
  File.write(File.join(directory, 'bin/sleep'), "#!/bin/bash\n[ \"$1\" = 30 ] || exit 9\n/bin/sleep 0.2\n")
  FileUtils.chmod(0755, Dir.glob(File.join(directory, 'bin/*')))
  app = File.join(directory, 'DerivedData/Build/Products/Release/Fixture.app/Contents/MacOS')
  FileUtils.mkdir_p(app)
  executable = File.join(app, 'Fixture')
  script = File.join(directory, 'launch.sh')
  File.write(script, snapshot_launch)
  env = {'RUNNER_TEMP' => directory, 'PATH' => "#{directory}/bin:#{ENV.fetch('PATH')}"}
  [['exec /bin/sleep 120', true], ['exit 1', false]].each do |body, expected|
    File.write(executable, "#!/bin/bash\n#{body}\n")
    FileUtils.chmod(0755, executable)
    FileUtils.rm_rf(File.join(directory, 'launch'))
    output, status = Open3.capture2e(env, 'bash', '-e', script, chdir: directory)
    assert(status.success? == expected, "launch result does not match process liveness: #{output}")
    puts "PASS launch check #{expected ? 'accepts a live process' : 'rejects a crashed process'}"
  end
end
puts 'release action: PASS'
