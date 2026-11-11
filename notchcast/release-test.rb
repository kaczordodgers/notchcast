#!/usr/bin/env ruby
require 'yaml'
require 'open3'
require 'tmpdir'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
ACTION = YAML.load_file(File.join(__dir__, 'actions/release/action.yml'))


def assert(value, message)
  raise message unless value
end

ACTION.fetch('runs').fetch('steps').each do |step|
  assert(step['shell'] == 'bash -e {0}', "#{step['name']} must preserve the workflow's implicit bash shell")
  output, status = Open3.capture2e('bash', '-n', stdin_data: step.fetch('run'))
  assert(status.success?, "#{step['name']} shell syntax failed: #{output}")
end

%w[snapshot sync].each do |name|
  job = name == 'snapshot' ? 'snapshot' : 'release'
  workflow = YAML.load_file(File.join(ROOT, ".github/workflows/#{name}.yml"))
  callers = workflow.fetch('jobs').fetch(job).fetch('steps').select { |step| step['uses'] == './tools/notchcast/actions/release' }
  assert(callers.size == 1, "#{name} must use the shared release action once")
  if name == 'snapshot'
    assert(callers.first['if'] == "steps.checks.outputs.green == 'true'", 'snapshot release must remain gated on lint and tests')
  end
  puts "PASS #{name} calls the shared release action once"
end

launch = ACTION.fetch('runs').fetch('steps').find { |step| step['name'] == 'Launch and stay alive' }
assert(launch && launch['run'].include?("sleep 30\n") && launch['run'].include?('kill -0 "$PID"'), 'release must check liveness after 30 seconds')

Dir.mktmpdir('release-launch-') do |directory|
  FileUtils.mkdir_p(File.join(directory, 'tools/notchcast'))
  File.write(File.join(directory, 'tools/notchcast/config.env'), "APP_NAME=Fixture\n")
  FileUtils.mkdir_p(File.join(directory, 'bin'))
  File.write(File.join(directory, 'bin/ditto'), "#!/bin/bash\ncp -R \"$1\" \"$2\"\n")
  # Wait until the fixture app has run, not a fixed 0.2 s: on a loaded runner a crashing
  # fixture could still be starting when the liveness check ran.
  File.write(File.join(directory, 'bin/sleep'), "#!/bin/bash\n[ \"$1\" = 30 ] || exit 9\n" \
    "for _ in $(seq 300); do [ -e \"$RUNNER_TEMP/ran\" ] && break; /bin/sleep 0.1; done\n/bin/sleep 0.5\n")
  FileUtils.chmod(0755, Dir.glob(File.join(directory, 'bin/*')))
  app = File.join(directory, 'DerivedData/Build/Products/Release/Fixture.app/Contents/MacOS')
  FileUtils.mkdir_p(app)
  executable = File.join(app, 'Fixture')
  script = File.join(directory, 'launch.sh')
  File.write(script, launch.fetch('run'))
  env = {'RUNNER_TEMP' => directory, 'PATH' => "#{directory}/bin:#{ENV.fetch('PATH')}"}
  [['exec /bin/sleep 120', true], ['exit 1', false]].each do |body, expected|
    File.write(executable, "#!/bin/bash\ntouch \"$RUNNER_TEMP/ran\"\n#{body}\n")
    FileUtils.chmod(0755, executable)
    FileUtils.rm_rf(File.join(directory, 'launch'))
    FileUtils.rm_f(File.join(directory, 'ran'))
    output, status = Open3.capture2e(env, 'bash', '-e', script, chdir: directory)
    assert(status.success? == expected, "launch result does not match process liveness: #{output}")
    puts "PASS launch check #{expected ? 'accepts a live process' : 'rejects a crashed process'}"
  end
end
puts 'release action: PASS'
