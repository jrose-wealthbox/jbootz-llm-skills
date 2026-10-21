require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

wrapper = ENV.fetch('REVIEW_WRAPPER', File.expand_path('../skills/jbootz-claude-from-codex-review/scripts/review.rb', __dir__))
checks = 0
assert = ->(condition, message) { raise message unless condition; checks += 1 }
Dir.mktmpdir('claude-review-test') do |root|
  repo = File.join(root, 'project with spaces')
  bin = File.join(root, 'bin')
  FileUtils.mkdir_p([repo, bin])
  File.write(File.join(repo, 'plan.md'), 'Initial plan')
  prompt = File.join(root, 'request.md')
  File.write(prompt, 'Review this plan.')
  fake = File.join(bin, 'claude')
  File.write(fake, <<~'FAKE')
    #!/usr/bin/env ruby
    require 'json'
    if ARGV == ['--help']
      sleep 2 if ENV['FAKE_MODE'] == 'help_timeout'
      puts '--safe-mode --tools --allowedTools --disallowedTools --permission-mode --strict-mcp-config --mcp-config --model --effort --session-id --resume --output-format --append-system-prompt'
      exit
    end
    File.write(ENV.fetch('CALL_LOG'), JSON.generate({argv: ARGV, input: STDIN.read, cwd: Dir.pwd}))
    value = ->(flag) { ARGV[ARGV.index(flag) + 1] }
    id = value.call(ARGV.include?('--resume') ? '--resume' : '--session-id')
    case ENV['FAKE_MODE']
    when 'malformed' then puts 'not json'
    when 'error' then puts JSON.generate({type: 'result', subtype: 'error_during_execution', is_error: true, session_id: id, result: 'not authenticated'})
    when 'wrong_session' then puts JSON.generate({type: 'result', subtype: 'success', session_id: 'different', result: 'bad'})
    when 'timeout' then sleep 30
    else
      puts JSON.generate({type: 'result', subtype: 'success', is_error: false, session_id: id, result: 'F001: clarify the requirement'})
    end
  FAKE
  File.chmod(0755, fake)
  env = {'PATH' => "#{bin}:#{ENV.fetch('PATH')}", 'CALL_LOG' => File.join(root, 'call.json')}
  review_dir = File.join(root, 'review')
  run = lambda do |action, extra = [], mode = nil, directory = review_dir|
    Open3.capture3(env.merge('FAKE_MODE' => mode), RbConfig.ruby, wrapper, action,
      '--repo', repo, '--review-dir', directory, *extra)
  end
  first = ['--prompt-file', prompt, '--file', 'plan.md', '--rounds', '10', '--winner', 'codex']
  out, err, status = run.call('start', first)
  assert.call(status.success?, "start failed: #{err}")
  state = JSON.parse(File.read(File.join(review_dir, 'state.json')))
  call = JSON.parse(File.read(env['CALL_LOG']))
  assert.call(call['argv'].include?('--session-id'), 'start must name its session')
  assert.call(call['argv'][call['argv'].index('--model') + 1] == 'opus', 'default model')
  assert.call(call['argv'][call['argv'].index('--effort') + 1] == 'high', 'default effort')
  assert.call(call['argv'].include?('--safe-mode') && !call['argv'].include?('--bare'), 'preserve login without custom hooks')
  assert.call(call['argv'][call['argv'].index('--tools') + 1] == 'Read,Grep,Glob', 'review must not have write/shell tools')
  assert.call(call['input'].include?('Initial plan') && call['cwd'] == File.realpath(repo), 'fresh file contents and working directory')
  assert.call(File.read(File.join(review_dir, '001', 'result.md')).include?('F001'), 'durable result')
  _, _, status = run.call('start', first)
  assert.call(!status.success?, 'start must not overwrite a review')
  File.write(File.join(repo, 'plan.md'), 'Revised plan')
  _, err, status = run.call('resume', ['--prompt-file', prompt, '--model', 'custom-model', '--effort', 'medium'])
  assert.call(status.success?, "resume failed: #{err}")
  call = JSON.parse(File.read(env['CALL_LOG']))
  assert.call(call['argv'][call['argv'].index('--resume') + 1] == state['session_id'], 'resume exact session')
  assert.call(!call['argv'].include?('--continue') && call['input'].include?('Revised plan'), 'never latest session or stale input')
  assert.call(call['argv'].include?('custom-model') && call['argv'].include?('medium'), 'per-call overrides')
  _, _, status = run.call('resume', ['--prompt-file', prompt])
  call = JSON.parse(File.read(env['CALL_LOG']))
  assert.call(status.success? && call['argv'].include?('opus') && call['argv'].include?('high'), 'overrides must not persist')
  %w[malformed error wrong_session timeout].each do |mode|
    directory = File.join(root, mode)
    _, _, status = run.call('start', first + ['--timeout-seconds', '1'], mode, directory)
    assert.call(!status.success?, "#{mode} must fail")
    saved = JSON.parse(File.read(File.join(directory, 'state.json')))
    assert.call(saved['last_status'] == 'failed', "#{mode} must retain failure state")
    assert.call(File.exist?(File.join(directory, '001', 'response.json')), "#{mode} must keep raw evidence")
    _, _, status = run.call('resume', ['--prompt-file', prompt], nil, directory)
    assert.call(!status.success?, 'failed rounds require explicit acknowledgement')
    _, err, status = run.call('resume', ['--prompt-file', prompt, '--acknowledge-failed-round'], nil, directory)
    assert.call(status.success?, "explicit recovery failed: #{err}")
  end
  File.open(File.join(review_dir, '.lock'), 'w') do |lock|
    lock.flock(File::LOCK_EX)
    _, _, status = run.call('resume', ['--prompt-file', prompt])
    assert.call(!status.success?, 'concurrent round must be refused')
  end
  File.write(File.join(root, 'outside.md'), 'outside')
  _, _, status = run.call('start', ['--prompt-file', prompt, '--file', '../outside.md'], nil, File.join(root, 'outside'))
  assert.call(!status.success?, 'out-of-repo file must be refused')
  _, _, status = Open3.capture3(env, RbConfig.ruby, wrapper, 'resume', '--repo', root,
    '--review-dir', review_dir, '--prompt-file', prompt)
  assert.call(!status.success?, 'wrong repository must be refused')
  no_git = File.join(root, 'no-git-bin')
  FileUtils.mkdir_p(no_git)
  FileUtils.cp(fake, File.join(no_git, 'claude'))
  File.symlink(RbConfig.ruby, File.join(no_git, 'ruby'))
  missing_git_review = File.join(root, 'missing-git-review')
  _, _, status = Open3.capture3(env.merge('PATH' => no_git), RbConfig.ruby, wrapper, 'start',
    '--repo', repo, '--review-dir', missing_git_review, *first)
  assert.call(!status.success?, 'missing git must fail preflight')
  assert.call(!File.exist?(File.join(missing_git_review, '001')), 'missing git must not strand a round directory')
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  _, _, status = run.call('start', first + ['--timeout-seconds', '1'], 'help_timeout', File.join(root, 'slow-help'))
  elapsed_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  assert.call(!status.success? && elapsed_seconds < 2, 'CLI preflight must honor timeout')
  configured_dir = File.join(root, 'one-round')
  _, err, status = run.call('start', first + ['--rounds', '1', '--winner', 'claude'], nil, configured_dir)
  assert.call(status.success?, "configured start failed: #{err}")
  configuration = JSON.parse(File.read(File.join(configured_dir, 'state.json')))
  assert.call(configuration['rounds'] == 1 && configuration['winner'] == 'claude', 'save conversation settings')
  _, err, status = run.call('resume', ['--prompt-file', prompt], nil, configured_dir)
  assert.call(!status.success? && err.include?('limit'), 'refuse a second Claude turn when one round was selected')
  _, err, status = run.call('resume', ['--prompt-file', prompt, '--extend-rounds', '2'], nil, configured_dir)
  assert.call(status.success?, "explicit extension failed: #{err}")
  extended = JSON.parse(File.read(File.join(configured_dir, 'state.json')))
  assert.call(extended['rounds'] == 2 && extended['session_id'] == configuration['session_id'], 'extension must preserve session')
  _, _, status = run.call('resume', ['--prompt-file', prompt, '--extend-rounds', '1'], nil, configured_dir)
  assert.call(!status.success?, 'extension must increase the total')
  _, _, status = run.call('start', ['--prompt-file', prompt, '--file', 'plan.md'], nil, File.join(root, 'missing-settings'))
  assert.call(!status.success?, 'start must require user-selected rounds and winner')
  _, _, status = run.call('start', first + ['--rounds', '0'], nil, File.join(root, 'zero-rounds'))
  assert.call(!status.success?, 'round count must be positive')
  _, _, status = run.call('start', first + ['--winner', 'either'], nil, File.join(root, 'bad-winner'))
  assert.call(!status.success?, 'winner must identify Claude or Codex')
  _, _, status = run.call('resume', ['--prompt-file', prompt, '--rounds', '20'], nil, review_dir)
  assert.call(!status.success?, 'resume must not silently change conversation settings')
  unsafe_directory = File.expand_path('../unignored-review-test-output', __dir__)
  _, err, status = run.call('start', first, nil, unsafe_directory)
  assert.call(!status.success? && err.include?('gitignored'), 'review evidence must be temporary or gitignored')
  assert.call(!File.exist?(unsafe_directory), 'reject unsafe directory before creating it')
  puts "PASS: #{checks} review-wrapper assertions (fake Claude; no model calls)"
end
