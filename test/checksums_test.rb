
require 'rubygems'
require 'ruby-debug' ### REMOVE

require 'test/unit'
require 'contest'
require 'fileutils'
require 'tmpdir'

require 'checksums'


class ChecksumsTest < Test::Unit::TestCase
  include Checksums

  setup do
    @root_dir = grow_tree
  end
  
  teardown do
    validate_expectations
    cut_down_tree
  end
  
  context "in a checksummed directory" do
    setup do
      write_checksums(@root_dir)
      @checked = CheckedDir.new(@root_dir)
    end
    
    test "update is not necessary" do
      assert !@checked.needs_update?
    end
    
    test "checksums verify" do
      @checked.verify_checksums do |on|
        flunk_all(on)
        expect(on, :valid_signature)
        expect(on, :directory_unchanged)
      end
    end
    
    test "manipulated checksums are noticed" do
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
    
    context "with an added file" do
      setup do
        file 'worzel'
        @checked = CheckedDir.new(@root_dir)
        backdate @checked.checksum_file
      end

      test "update is necessary" do
        assert @checked.needs_update?
      end

      test "the added file is noticed" do
        @checked.verify_checksums do |on|
          flunk_all(on)
          ignore(on, :valid_signature, :item_unchanged)
          expect(on, :directory_changed, @root_dir)
          expect(on, :item_added, @root_dir, 'worzel')
        end
      end
    end

    context "with a removed file" do
      setup do
        rm_file 'baz'
        @checked = CheckedDir.new(@root_dir)
      end
      
      test "the removed file is noticed" do
        @checked.verify_checksums do |on|
          flunk_all(on)
          ignore(on, :valid_signature, :item_unchanged)
          expect(on, :directory_changed, @root_dir)
          expect(on, :item_removed, @root_dir, 'baz')
        end
      end
    end

    context "with a changed file" do
      setup do
        file 'baz', 'going thru changes'
        @checked = CheckedDir.new(@root_dir)
      end
      
      test "the changed file is noticed" do
        @checked.verify_checksums do |on|
          flunk_all(on)
          ignore(on, :valid_signature, :item_unchanged)
          expect(on, :directory_changed, @root_dir)
          expect(on, :item_changed, @root_dir,
                'baz', '73feffa4b7f6bb68e44cf984c85f6e88', 'ad769fd2bc30024dc4d636a978a4f011')
        end
      end
    end
    
    context "with an added empty sub-directory" do
      setup do
        directory "newdir"
        @checked = CheckedDir.new(@root_dir)
      end
      
      test "the added directory is noticed" do
        @checked.verify_checksums do |on|
          flunk_all(on)
          ignore(on, :valid_signature, :item_unchanged)
          expect(on, :directory_changed)
          expect(on, :item_added, @root_dir, 'newdir')
        end
      end
    end
  end
  
  ### TODO tests for
  # - added, removed, changed directories
  # - added, removed, changed empty directories
  # - upward propagation of checksum updates for changed directories
  # - skips
  #
  
  
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
    @called[[callback, *expected_args]] = false
    on.send(callback) do |*actual_args|
      if expected_args.empty?
        @called[[callback]] = true
      else
        @called[[callback, *actual_args]] = true
      end
    end
  end
  
  def ignore(on, *callbacks)
    callbacks.each do |callback|
      on.send(callback) do |*args|
      end
    end
  end
  
  def validate_expectations
    (@called || {}).each do |callback, called|
      assert called, "callback #{callback.inspect} was not called"
    end
  end
  
  def grow_tree
    @root_dir = Dir.mktmpdir
    @dirs = [@root_dir]
     @root_dir ### REMOVE
    
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
    
    @root_dir
  end

  def cut_down_tree
    FileUtils.rm_rf(@root_dir)
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
    make_path(name).tap do |path|
      File.open(path, 'w') do |f|
        f.write(contents)
      end
    end
  end
  
  def directory(name)
    make_path(name).tap do |path|
      Dir.mkdir(path)
      @dirs.unshift(path)
      yield if block_given?
    end
  ensure
    @dirs.shift
  end
  
  def rm_file(name)
    File.delete(make_path(name))
  end

  def backdate(*paths)
    File.utime(0, 0, *paths)
  end
#   def touch(*paths)
#     offset = paths.last.is_a?(Fixnum) ? paths.pop : 0
#     now = Time.now
#     paths.each do |path|
#       t = (offset == 0) ? now : (File.mtime(path) + offset)
#       File.utime(t, t, path)
#     end
#   end
  
  def make_path(name)
    File.join(@dirs.first, name)
  end
                    
end
