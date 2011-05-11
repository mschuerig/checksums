
require 'rubygems'
require 'ruby-debug'

require 'test/unit'
require 'fileutils'
require 'tmpdir'

require 'checksums'


class ChecksumsTest < Test::Unit::TestCase
  include Checksums

  def setup
    @root_dir = Dir.mktmpdir
    @dirs = [@root_dir]
    puts @root_dir
  end
  
  def teardown
    FileUtils.rm_rf(@root_dir)
  end
  
  def test_update_verify
    grow_tree
    write_checksums(@root_dir)
    
    d = CheckedDir.new(@root_dir)
    d.verify_checksums do |on|
      flunk_all(on)
      expect(on, :valid_signature)
      expect(on, :directory_unchanged)
    end
    
    validate_expectations
  end
  
  private

  def flunk_all(on)
    CALLBACKS.map(&:first).each do |callback|
      on.send(callback) do |*args|
        flunk "callback #{callback} unexpectedly called with #{args.inspect}"
      end
    end
  end

  def expect(on, callback)
    @called ||= {}
    @called[callback] = false
    on.send(callback) do |*args|
      @called[callback] = true
    end
  end
  
  def validate_expectations
    (@called || {}).each do |callback, called|
      assert called, "callback #{callback} was not called"
    end
  end
  
  def grow_tree
    dir 'dir1' do
      file 'foo'
      dir 'nested1' do
        dir 'nested2' do
          file 'bar', 'BAR'
        end
      end
    end
    file 'baz'
    dir 'empty'
  end

  def write_checksums(where)
    d = CheckedDir.new(where)
    d.write_checksum_file
    assert File.file?(File.join(where, CHECKSUM_FILENAME)), 'Checksum file not written'
  end
  
  def file(name, contents = name)
    File.open(make_path(name), 'w') do |f|
      f.write(contents)
    end
  end
  
  def dir(name)
    path = make_path(name)
    Dir.mkdir(path)
    @dirs.unshift(path)
    yield if block_given?
  ensure
    @dirs.shift
  end
  
  def make_path(name)
    File.join(@dirs.first, name)
  end
                    
end
