# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'

class ZeitwerkScannerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_scan_flat_files
    write_file("greeter.rb", "class Greeter; end")
    write_file("worker.rb", "class Worker; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)

    assert_equal 2, entries.size
    names = entries.map(&:full_path).sort
    assert_equal %w[Greeter Worker], names
    assert(entries.all? { |e| e.type == :file })
  end

  def test_scan_implicit_namespace
    FileUtils.mkdir_p(File.join(@tmpdir, "billing"))
    write_file("billing/payment.rb", "module Billing; class Payment; end; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)

    ns = entries.find { |e| e.type == :namespace }
    assert_equal "Billing", ns.full_path
    assert_nil ns.file # implicit namespace — no .rb file

    file = entries.find { |e| e.type == :file }
    assert_equal "Billing::Payment", file.full_path
    assert_equal "Billing", file.parent
  end

  def test_scan_explicit_namespace
    FileUtils.mkdir_p(File.join(@tmpdir, "billing"))
    write_file("billing.rb", "module Billing; VERSION = '1.0'; end")
    write_file("billing/payment.rb", "module Billing; class Payment; end; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)

    ns = entries.find { |e| e.type == :namespace }
    assert_equal "Billing", ns.full_path
    refute_nil ns.file # explicit namespace — has .rb file
  end

  def test_scan_deeply_nested
    FileUtils.mkdir_p(File.join(@tmpdir, "billing/processors"))
    write_file("billing/processors/stripe.rb", "module Billing; module Processors; class Stripe; end; end; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)

    paths = entries.map(&:full_path).sort
    assert_includes paths, "Billing"
    assert_includes paths, "Billing::Processors"
    assert_includes paths, "Billing::Processors::Stripe"
  end

  def test_build_file_index
    write_file("greeter.rb", "class Greeter; end")
    FileUtils.mkdir_p(File.join(@tmpdir, "billing"))
    write_file("billing/payment.rb", "module Billing; class Payment; end; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)
    index = Boxwerk::ZeitwerkScanner.build_file_index(entries)

    assert_equal File.join(@tmpdir, "greeter.rb"), index["Greeter"]
    assert_equal File.join(@tmpdir, "billing/payment.rb"), index["Billing::Payment"]
    # Implicit namespace has no file
    assert_nil index["Billing"]
  end

  def test_ignores_hidden_directories
    FileUtils.mkdir_p(File.join(@tmpdir, ".hidden"))
    write_file("greeter.rb", "class Greeter; end")
    write_file(".hidden/secret.rb", "class Secret; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)

    names = entries.map(&:full_path)
    assert_includes names, "Greeter"
    refute_includes names, "Secret"
  end

  def test_inflection_snake_case
    write_file("tax_calculator.rb", "class TaxCalculator; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)

    assert_equal "TaxCalculator", entries.first.full_path
  end

  def test_register_autoloads_in_box
    skip unless defined?(Ruby::Box)

    write_file("greeter.rb", "class Greeter; def self.hi = 'hello'; end")
    write_file("worker.rb", "class Worker; def self.work = 'working'; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)
    box = Ruby::Box.new
    Boxwerk::ZeitwerkScanner.register_autoloads(box, entries)

    assert_equal "hello", box.eval("Greeter.hi")
    assert_equal "working", box.eval("Worker.work")
  end

  def test_register_autoloads_nested_in_box
    skip unless defined?(Ruby::Box)

    FileUtils.mkdir_p(File.join(@tmpdir, "billing"))
    write_file("billing/payment.rb", "module Billing; class Payment; def self.charge = 100; end; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)
    box = Ruby::Box.new
    Boxwerk::ZeitwerkScanner.register_autoloads(box, entries)

    assert_equal 100, box.eval("Billing::Payment.charge")
  end

  def test_register_autoloads_explicit_namespace_in_box
    skip unless defined?(Ruby::Box)

    FileUtils.mkdir_p(File.join(@tmpdir, "billing"))
    write_file("billing.rb", "module Billing; VERSION = '1.0'; end")
    write_file("billing/payment.rb", "module Billing; class Payment; def self.charge = 100; end; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)
    box = Ruby::Box.new
    Boxwerk::ZeitwerkScanner.register_autoloads(box, entries)

    assert_equal "1.0", box.eval("Billing::VERSION")
    assert_equal 100, box.eval("Billing::Payment.charge")
  end

  def test_box_isolation
    skip unless defined?(Ruby::Box)

    write_file("greeter.rb", "class Greeter; def self.hi = 'hello'; end")

    entries = Boxwerk::ZeitwerkScanner.scan(@tmpdir)
    box = Ruby::Box.new
    Boxwerk::ZeitwerkScanner.register_autoloads(box, entries)

    # Constant should be in the box but not in root
    assert_equal "hello", box.eval("Greeter.hi")
    assert_raises(NameError) { Object.const_get(:Greeter) }
  end

  private

  def write_file(relative_path, content)
    path = File.join(@tmpdir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
