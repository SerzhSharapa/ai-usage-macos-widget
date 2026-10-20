#!/usr/bin/ruby
require 'minitest/autorun'
require 'tmpdir'
require 'stringio'
require_relative '../import-dsh-credentials'

class DshImportTest < Minitest::Test
  SENTINEL = 'FIXTURE_SECRET_SENTINEL_NEVER_PRINT'.freeze

  def document
    { 'version' => 1, 'records' => {
      'llm-pi-ai/openai-codex' => { 'kind' => 'grant', 'payload' => {
        'type' => 'oauth', 'access' => SENTINEL, 'refresh' => 'REFRESH_NEVER_FORWARD',
        'accountId' => 'fixture-account', 'expires' => 1 } },
      'foreign' => { 'payload' => { 'key' => 'FOREIGN_NEVER_FORWARD' } }
    }, 'refs' => {
      'ZAI_CODING_CN_API_KEY' => SENTINEL, 'KIMI_CODING_API_KEY' => SENTINEL,
      'OPENROUTER_API_KEY' => SENTINEL, 'UNSUPPORTED' => 'FOREIGN_NEVER_FORWARD'
    } }
  end

  def test_whitelist_and_expired_codex_does_not_block_three_valid_providers
    payload, metadata = DshCredentialImport.select(document)
    assert_equal %w[glmodingplan kimi-coding openai openrouter], payload.keys.sort
    assert_equal 'fixture-account', payload['openai']['accountId']
    assert_equal true, metadata.find { |r| r['provider'] == 'codex' }['expired']
    refute_includes JSON.generate(payload), 'REFRESH_NEVER_FORWARD'
    refute_includes JSON.generate(payload), 'FOREIGN_NEVER_FORWARD'
    refute_includes JSON.generate(metadata), SENTINEL
    refute_includes JSON.generate(metadata), 'fixture-account'
  end

  def test_unknown_deepseek_skipped_but_explicit_known_ref_supported
    fixture = document
    fixture['refs']['DEEPSEEK_API_KEY'] = SENTINEL
    payload, = DshCredentialImport.select(fixture)
    assert_equal SENTINEL, payload['deepseek']['key']
  end

  def test_wrong_type_or_conflicting_account_id_rejects_codex_only
    [42, true, [], {}, ''].each do |bad|
      fixture = document
      fixture['records']['llm-pi-ai/openai-codex']['payload']['accountId'] = bad
      payload, = DshCredentialImport.select(fixture)
      refute payload.key?('openai')
      assert_equal 3, payload.size
    end
    fixture = document
    fixture['records']['llm-pi-ai/openai-codex']['payload']['account_id'] = 'other'
    refute DshCredentialImport.select(fixture).first.key?('openai')
  end

  def test_missing_account_id_allowed_and_grant_type_required
    fixture = document
    fixture['records']['llm-pi-ai/openai-codex']['payload'].delete('accountId')
    refute DshCredentialImport.select(fixture).first['openai'].key?('accountId')
    fixture['records']['llm-pi-ai/openai-codex']['payload']['type'] = 'api'
    refute DshCredentialImport.select(fixture).first.key?('openai')
  end

  def test_malformed_refs_and_source_shape_fail_closed
    fixture = document
    fixture['refs']['KIMI_CODING_API_KEY'] = { 'value' => SENTINEL }
    fixture['refs']['OPENROUTER_API_KEY'] = "#{SENTINEL}\nheader-injection"
    payload, metadata = DshCredentialImport.select(fixture)
    refute payload.key?('kimi-coding')
    refute payload.key?('openrouter')
    assert_equal false, metadata.find { |r| r['provider'] == 'kimi' }['present']
    [nil, [], {}, { 'version' => '1', 'records' => {}, 'refs' => {} }].each do |bad|
      assert_raises(DshCredentialImport::Failure) { DshCredentialImport.select(bad) }
    end
  end

  def test_inspect_stdout_and_stderr_never_contain_secrets
    Dir.mktmpdir('dsh-fixture-') do |dir|
      source = File.join(dir, 'fixture.yaml')
      File.write(source, YAML.dump(document))
      stdout, stderr, status = Open3.capture3('/usr/bin/ruby', File.expand_path('../import-dsh-credentials.rb', __dir__), '--inspect', '--source', source)
      assert status.success?
      [stdout, stderr].each do |text|
        refute_includes text, SENTINEL
        refute_includes text, 'REFRESH_NEVER_FORWARD'
        refute_includes text, 'fixture-account'
      end
      assert_equal 4, JSON.parse(stdout)['providers'].size
    end
  end

  def test_yaml_errors_aliases_objects_and_oversize_are_generic
    Dir.mktmpdir('dsh-fixture-') do |dir|
      source = File.join(dir, 'fixture.yaml')
      ["bad: [#{SENTINEL}", "x: &a #{SENTINEL}\ny: *a", "--- !ruby/object:Object {}", 'x' * (DshCredentialImport::SOURCE_LIMIT + 1)].each do |raw|
        File.write(source, raw)
        out = StringIO.new
        assert_equal 1, DshCredentialImport.main(['--inspect', '--source', source], out)
        assert_equal({ 'error' => 'import_failed' }, JSON.parse(out.string))
        refute_includes out.string, SENTINEL
      end
    end
  end

  class FakeRunner < DshCredentialImport::Runner
    attr_reader :events
    attr_accessor :deny, :bad_receive
    def initialize
      @events = []
    end
    def verify
      @events << :verify
      raise DshCredentialImport::Failure if deny
    end
    def stop; @events << :stop; end
    def reopen; @events << :reopen; true; end
    def receive(payload, replace)
      @events << (replace ? :replace : :skip_existing)
      raise DshCredentialImport::Failure if bad_receive
      [{ 'providers' => [], 'cache_write_failed' => false }, true]
    end
  end

  def test_identity_gate_before_secret_and_single_writer_reopen
    runner = FakeRunner.new
    runner.deny = true
    assert_raises(DshCredentialImport::Failure) { runner.import({ 'openai' => {} }, false) }
    assert_equal [:verify], runner.events
    runner = FakeRunner.new
    runner.import({ 'openai' => {} }, false)
    assert_equal [:verify, :stop, :verify, :skip_existing, :reopen], runner.events
    runner = FakeRunner.new
    runner.bad_receive = true
    assert_raises(DshCredentialImport::Failure) { runner.import({ 'openai' => {} }, true) }
    assert_equal :reopen, runner.events.last
  end

  def test_actual_private_pipe_and_untrusted_child_output_sanitized
    Dir.mktmpdir('dsh-receiver-fixture-') do |dir|
      receiver = File.join(dir, 'receiver')
      # Fake only. Test child verifies secret reached stdin, not argv/env.
      File.write(receiver, <<~'RUBY')
        #!/usr/bin/ruby
        require 'json'
        input = JSON.parse(STDIN.read)
        abort if ARGV.any? { |x| x.include?('FIXTURE_SECRET') } || ENV.values.any? { |x| x.include?('FIXTURE_SECRET') }
        abort unless input['glmodingplan']['key'] == 'FIXTURE_SECRET_SENTINEL_NEVER_PRINT'
        STDERR.puts(input['glmodingplan']['key'])
        puts JSON.generate('providers' => [{'provider' => 'glm-cn', 'import_status' => 'imported',
          'request_status' => 'ok', 'accountId' => input['glmodingplan']['key'],
          'error' => input['glmodingplan']['key'], 'balance' => input['glmodingplan']['key'],
          'windows' => [{'percent' => 55, 'name' => input['glmodingplan']['key']}]}], 'cache_write_failed' => false)
      RUBY
      File.chmod(0700, receiver)
      runner = DshCredentialImport::Runner.new
      runner.instance_variable_set(:@binary, receiver)
      report = nil
      stdout, stderr = capture_io { report, success = runner.receive({ 'glmodingplan' => { 'key' => SENTINEL } }, false); assert success }
      [stdout, stderr, JSON.generate(report)].each { |text| refute_includes text, SENTINEL }
      assert_equal 55, report['providers'][0]['windows'][0]['percent']
      refute report['providers'][0].key?('balance')
      refute report['providers'][0].key?('accountId')
    end
  end

  def test_no_args_and_unknown_receiver_do_not_read_source
    out = StringIO.new
    assert_equal 0, DshCredentialImport.main([], out)
    assert_includes out.string, 'Usage:'
    out = StringIO.new
    assert_equal 1, DshCredentialImport.main(['--receiver', SENTINEL], out)
    refute_includes out.string, SENTINEL
  end

  def test_raw_child_errors_and_foreign_provider_never_forwarded
    runner = DshCredentialImport::Runner.new
    assert_raises(DshCredentialImport::Failure) { runner.sanitize('error' => SENTINEL) }
    assert_raises(DshCredentialImport::Failure) do
      runner.sanitize('providers' => [{ 'provider' => SENTINEL, 'import_status' => 'imported',
        'request_status' => 'ok' }], 'cache_write_failed' => false)
    end
    safe = runner.sanitize('providers' => [], 'cache_write_failed' => true, 'raw' => SENTINEL)
    assert_equal true, safe['cache_write_failed']
    refute_includes JSON.generate(safe), SENTINEL
  end
end
