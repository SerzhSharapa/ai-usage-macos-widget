#!/usr/bin/ruby
# Owner-triggered, read-only DSH import. Credentials go only through a private
# child stdin pipe into our verified app. Ruby/Psych shipped with macOS 2.6.
require 'json'
require 'yaml'
require 'open3'
require 'optparse'

module DshCredentialImport
  SOURCE_LIMIT = 2 * 1024 * 1024
  PIPE_LIMIT = 65_536
  PROVIDERS = %w[codex glm-cn kimi openrouter deepseek].freeze
  REFS = {
    'ZAI_CODING_CN_API_KEY' => ['glmodingplan', 'glm-cn'],
    'KIMI_CODING_API_KEY' => ['kimi-coding', 'kimi'],
    'OPENROUTER_API_KEY' => ['openrouter', 'openrouter'],
    'DEEPSEEK_API_KEY' => ['deepseek', 'deepseek']
  }.freeze
  class Failure < StandardError; end

  def self.string?(value)
    value.is_a?(String) && !value.strip.empty? && !value.match?(/[\r\n\x00]/)
  end

  def self.select(document, now = Time.now.to_i)
    raise Failure unless document.is_a?(Hash) && document['version'].is_a?(Integer) &&
      document['records'].is_a?(Hash) && document['refs'].is_a?(Hash)
    payload = {}
    metadata = []
    record = document['records']['llm-pi-ai/openai-codex']
    if record
      grant = record.is_a?(Hash) ? record['payload'] : nil
      valid = record.is_a?(Hash) && record['kind'] == 'grant' && grant.is_a?(Hash) &&
        grant['type'] == 'oauth' && string?(grant['access'])
      # Reject wrong-typed/conflicting IDs; never silently convert them to nil.
      ids = []
      if valid
        %w[accountId chatgpt_account_id account_id].each do |name|
          next unless grant.key?(name) && !grant[name].nil?
          valid = false unless string?(grant[name])
          ids << grant[name]
        end
        valid = false if ids.uniq.length > 1
      end
      if valid
        item = { 'type' => 'oauth', 'access' => grant['access'] }
        item['accountId'] = ids.first unless ids.empty?
        payload['openai'] = item
      end
      expires = grant.is_a?(Hash) ? grant['expires'] : nil
      # DSH grants use epoch milliseconds; tolerate seconds for fixtures/versions.
      expires = expires / 1000.0 if expires.is_a?(Integer) && expires > 1_000_000_000_000
      metadata << { 'provider' => 'codex', 'kind' => 'oauth', 'present' => !!valid,
                    'expired' => expires.is_a?(Numeric) ? expires <= now : nil }
    end
    REFS.each do |name, (target, provider)|
      next unless document['refs'].key?(name)
      key = document['refs'][name]
      present = string?(key)
      payload[target] = { 'type' => 'api', 'key' => key } if present
      metadata << { 'provider' => provider, 'kind' => 'api', 'present' => present }
    end
    raise Failure if JSON.generate(payload).bytesize > PIPE_LIMIT
    [payload, metadata]
  end

  # Codex CLI auth.json: fresh OAuth grant after `codex login`. Only
  # tokens.access_token + tokens.account_id are read; refresh_token and the
  # root OPENAI_API_KEY are never copied. Wrong-typed present ID is a hard
  # failure (WR-06), never a silent nil.
  def self.codex_cli_entry(path)
    File.open(path, 'rb') do |file|
      raise Failure unless file.stat.file? && file.stat.uid == Process.uid
      raw = file.read(SOURCE_LIMIT + 1)
      raise Failure if raw.bytesize > SOURCE_LIMIT
      document = JSON.parse(raw)
      tokens = document['tokens']
      raise Failure unless tokens.is_a?(Hash) && string?(tokens['access_token'])
      entry = { 'type' => 'oauth', 'access' => tokens['access_token'] }
      unless tokens['account_id'].nil?
        raise Failure unless string?(tokens['account_id'])
        entry['accountId'] = tokens['account_id']
      end
      entry
    end
  rescue Failure
    raise
  rescue StandardError
    # JSON exception text may echo source bytes; fail fixed, never raw.
    raise Failure, 'codex_auth_invalid', []
  end

  def self.load_source(path)
    File.open(path, 'rb') do |file|
      raise Failure unless file.stat.file? && file.stat.uid == Process.uid
      raw = file.read(SOURCE_LIMIT + 1)
      raise Failure if raw.bytesize > SOURCE_LIMIT
      # Positional arguments work with system Ruby 2.6 / Psych 3.
      select(YAML.safe_load(raw, [], [], false))
    end
  rescue StandardError
    # Psych exception messages may contain an entire secret-bearing source line.
    raise Failure, 'source_invalid', []
  end

  class Runner
    def initialize
      @scripts = File.expand_path(__dir__)
      @app = File.join(Dir.home, 'Applications', 'AI Usage Widget.app')
      @binary = File.join(@app, 'Contents', 'MacOS', 'AI Usage Widget')
      @environment = { 'HOME' => Dir.home, 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin' }
    end

    def command_ok(*args)
      system(@environment, *args, :out => File::NULL, :err => File::NULL, :unsetenv_others => true)
    end

    def verify
      # No arbitrary receiver path or env-controlled verifier/identity overrides.
      raise Failure unless File.realpath(@binary) == File.join(File.realpath(@app), 'Contents/MacOS/AI Usage Widget')
      raise Failure unless command_ok('/bin/bash', File.join(@scripts, 'verify-install.sh'), '--app-path', @app)
      version, status = Open3.capture2(@environment, '/usr/bin/plutil', '-extract', 'CFBundleVersion',
        'raw', '-o', '-', File.join(@app, 'Contents/Info.plist'), :err => File::NULL, :unsetenv_others => true)
      # v6 consumes no stdin flag; v7+ is the reviewed import protocol.
      raise Failure unless status.success? && version.strip.to_i >= 7
    end

    def stop
      raise Failure unless command_ok('/bin/bash', File.join(@scripts, 'stop-installed.sh'))
    end

    def reopen
      command_ok('/usr/bin/open', @app)
    end

    def receive(payload, replace)
      args = [@binary, '--import-credentials-stdin']
      args << '--replace-existing' if replace
      output = ''.b
      overflow = false
      status = nil
      # stderr goes directly to /dev/null, not a tool log or a diagnostic report.
      Open3.popen2(@environment, *args, :err => File::NULL, :unsetenv_others => true) do |input, stdout, wait|
        input.binmode
        input.write(JSON.generate(payload))
        input.close
        loop do
          chunk = stdout.read(4096)
          break unless chunk
          if output.bytesize + chunk.bytesize <= PIPE_LIMIT
            output << chunk
          else
            overflow = true # keep draining without retaining arbitrary output
          end
        end
        status = wait.value
      end
      raise Failure if overflow
      [sanitize(JSON.parse(output)), status.success?]
    rescue StandardError
      raise Failure, 'receiver_failed', []
    end

    def sanitize(report)
      raise Failure unless report.is_a?(Hash) && report['providers'].is_a?(Array) &&
        [true, false].include?(report['cache_write_failed'])
      rows = report['providers'].map do |row|
        raise Failure unless row.is_a?(Hash) && PROVIDERS.include?(row['provider']) &&
          %w[imported skipped_existing keychain_failed].include?(row['import_status']) &&
          %w[ok failed not_requested].include?(row['request_status'])
        safe = row.select { |k, _| %w[provider import_status request_status].include?(k) }
        safe['needs_reauth'] = row['needs_reauth'] == true
        %w[balance fetched_at].each do |key|
          number = row[key]
          safe[key] = number if number.is_a?(Numeric) && number.finite?
        end
        safe['error'] = 'usage_request_failed' if row.key?('error')
        safe['windows'] = (row['windows'].is_a?(Array) ? row['windows'].first(32) : []).map do |window|
          next {} unless window.is_a?(Hash)
          window.select { |key, value| %w[percent resets_at].include?(key) && value.is_a?(Numeric) && value.finite? }
        end
        safe
      end
      { 'providers' => rows, 'cache_write_failed' => report['cache_write_failed'] }
    end

    def import(payload, replace)
      raise Failure if payload.empty?
      verify # verify BEFORE stopping own GUI or sending any credential
      stop
      begin
        verify # recheck after stop, before spawning receiver
        report, success = receive(payload, replace)
      ensure
        reopened = reopen # even invalid child report/import failure must restore GUI
      end
      report['reopened'] = !!reopened
      [report, success && reopened]
    end
  end

  def self.main(argv, out = $stdout)
    options = { :source => File.join(Dir.home, '.dsh', '.credentials.yaml') }
    parser = OptionParser.new do |o|
      o.banner = 'Usage: /usr/bin/ruby scripts/import-dsh-credentials.rb --inspect | --import [--replace-existing] [--source PATH] [--codex-auth PATH]'
      o.on('--inspect') { options[:inspect] = true }
      o.on('--import') { options[:import] = true }
      o.on('--replace-existing') { options[:replace] = true }
      o.on('--source PATH') { |p| options[:source] = p }
      o.on('--codex-auth PATH') { |p| options[:codex_auth] = p }
    end
    return out.puts(parser.to_s) || 0 if argv.empty?
    parser.parse!(argv)
    raise Failure unless argv.empty? && (!!options[:inspect] ^ !!options[:import]) &&
      (!options[:replace] || options[:import])
    payload, metadata = load_source(options[:source])
    if options[:codex_auth]
      # Fresh CLI grant wins over the (possibly expired) DSH copy; the DSH
      # store itself is never written.
      payload['openai'] = codex_cli_entry(options[:codex_auth])
      metadata.each do |row|
        row['source'] = 'codex-cli' if row['provider'] == 'codex'
      end
    end
    if options[:inspect]
      out.puts(JSON.generate('providers' => metadata))
      return 0
    end
    report, success = Runner.new.import(payload, !!options[:replace])
    report['source'] = metadata
    out.puts(JSON.generate(report))
    success ? 0 : 1
  rescue StandardError
    out.puts(JSON.generate('error' => 'import_failed'))
    1
  end
end

exit(DshCredentialImport.main(ARGV)) if $PROGRAM_NAME == __FILE__
