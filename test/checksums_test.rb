
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
  
  def test_update_and_verify
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
  
  def test_manipulated_checksums_are_noticed
    grow_tree
    write_checksums(@root_dir)
    
    edit_checksums('73feffa4b7f6bb68e44cf984c85f6e88', '00000000000000000000000000000000')
    
    d = CheckedDir.new(@root_dir)
    d.verify_checksums do |on|
      on.invalid_signature do
        @noticed = true
        throw :skip_checksum_comparison
      end
    end
    
    assert @noticed, "Manipulated checksums not noticed."
  end
  
  def test_added_file_is_noticed
    grow_tree
    write_checksums(@root_dir)
    
    file 'worzel'
    
    d = CheckedDir.new(@root_dir)
    d.verify_checksums do |on|
      flunk_all(on)
      expect(on, :valid_signature)
      expect(on, :directory_changed)
      ignore(on, :item_unchanged)
      expect(on, :item_added, @root_dir, 'worzel')
    end
    
    validate_expectations
  end

  def test_removed_file_is_noticed
    grow_tree
    write_checksums(@root_dir)
    
    rm_file 'baz'
    
    d = CheckedDir.new(@root_dir)
    d.verify_checksums do |on|
      flunk_all(on)
      expect(on, :valid_signature)
      expect(on, :directory_changed)
      expect(on, :item_removed, @root_dir, 'baz')
      ignore(on, :item_unchanged)
    end
    
    validate_expectations
  end

  def test_changed_file_is_noticed
    grow_tree
    write_checksums(@root_dir)
    
    file 'baz', 'going thru changes'
    
    d = CheckedDir.new(@root_dir)
    d.verify_checksums do |on|
      flunk_all(on)
      expect(on, :valid_signature)
      expect(on, :directory_changed)
      expect(on, :item_changed, @root_dir,
             'baz', '73feffa4b7f6bb68e44cf984c85f6e88', 'ad769fd2bc30024dc4d636a978a4f011')
      ignore(on, :item_unchanged)
    end
    
    validate_expectations
  end
  
  ### TODO tests for
  # - added, removed, changed directories
  # - added, removed, changed empty directories
  # - upward propagation of checksum updates for changed directories
  # - skips
  
  private

  def flunk_all(on)
    CALLBACKS.map(&:first).each do |callback|
      on.send(callback) do |*args|
        flunk "callback #{callback} unexpectedly called with #{args.inspect}"
      end
    end
  end

  def expect(on, callback, *expected_args)
    @called ||= {}
    @called[[callback, *expected_args]] = [false]
    on.send(callback) do |*actual_args|
      @called[[callback, *actual_args]] = true
    end
  end
  
  def ignore(on, callback)
    on.send(callback) do |*args|
    end
  end
  
  def validate_expectations
    (@called || {}).each do |callback, called|
      assert called, "callback #{callback} was not called"
    end
  end
  
  def grow_tree
    directory 'dir1' do
      file 'foo'
      directory 'nested1' do
        directory 'nested2' do
          file 'bar', 'BAR'
        end
      end
    end
    file 'baz'
    directory 'empty'
  end

  def edit_checksums(target, replacement, where = @root_dir)
    path = File.join(where, CHECKSUM_FILENAME)
    text = File.read(path)
    text.sub!(target, replacement)
    File.open(path, 'w') { |f| f.write(text) }
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
  
  def directory(name)
    path = make_path(name)
    Dir.mkdir(path)
    @dirs.unshift(path)
    yield if block_given?
  ensure
    @dirs.shift
  end
  
  def rm_file(name)
    File.delete(make_path(name))
  end
  
  def make_path(name)
    File.join(@dirs.first, name)
  end
                    
end
