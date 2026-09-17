#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs bin/gen_html under the Ruby executing this file, so running it with
# each Ruby of interest (the system 2.6, a Homebrew 3.x or 4.x) checks that
# interpreter. Needs multimarkdown on PATH, as the build does.

require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'

SCRIPT_PATH = File.expand_path('../bin/gen_html', __dir__)

class GenHtmlTest < Minitest::Test
  def setup
    skip 'multimarkdown not on PATH' unless system('command -v multimarkdown >/dev/null 2>&1')
  end

  def run_gen_html(*args, stdin: '', env: {})
    Open3.capture3(env, RbConfig.ruby, SCRIPT_PATH, *args, stdin_data: stdin)
  end

  def test_converts_markdown_on_stdout
    out, err, status = run_gen_html(stdin: "# Hello\n\nSome *text*.\n")
    assert status.success?, "gen_html failed: #{err}"
    assert_includes out, '<h1'
    assert_includes out, '<em>text</em>'
  end

  def test_output_option_writes_file_and_nothing_to_stdout
    Dir.mktmpdir do |dir|
      target = File.join(dir, 'page.html')
      out, err, status = run_gen_html('-o', target, stdin: "# Hello\n")
      assert status.success?, "gen_html failed: #{err}"
      assert_equal '', out
      assert_includes File.read(target), '<h1'
    end
  end

  def test_failed_run_leaves_existing_output_untouched
    Dir.mktmpdir do |dir|
      target = File.join(dir, 'page.html')
      File.write(target, 'previous content')
      # Without a markdown compiler gen_html must fail, and the file it was
      # asked to write must not be truncated or replaced. The system Ruby
      # needs uname from /usr/bin at start-up, so PATH keeps the base
      # directories and only drops the one that supplies multimarkdown.
      path = "#{dir}:/usr/bin:/bin"
      skip 'multimarkdown found in /usr/bin or /bin' if system({ 'PATH' => path }, 'command -v multimarkdown >/dev/null 2>&1')
      _out, err, status = run_gen_html('-o', target, stdin: "# Hello\n", env: { 'PATH' => path })
      refute status.success?, 'gen_html succeeded without a markdown compiler'
      assert_includes err, 'Unable to find a markdown compiler'
      assert_equal 'previous content', File.read(target)
    end
  end
end
