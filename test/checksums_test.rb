
require 'rubygems'
#require 'ruby-debug'

require 'test/unit'
require 'contest'
require 'fileutils'
require 'set'
require 'tmpdir'

load File.join(File.dirname(__FILE__), '../checksums')


class ChecksumsTest < Test::Unit::TestCase
  include Checksums

  setup do
    @tree = grow_tree
    @root_dir = @tree.root
  end
  
  teardown do
    validate_expectations
    @tree.cut_down
  end
  
  
  context "directories" do

    test "are listed in bottom up order" do
      dirs = strip_root(BottomUpDirectories.new(@root_dir))
      assert_equal @tree.directory_count, dirs.size
      
      dirs.each_with_index do |higher, i|
        dirs[0, i].each do |lower|
          assert_no_match %r{^#{lower}}, higher,
              "Higher directory #{higher} listed before lower directory #{lower}"
        end
      end
    end
    
    test "can exclude top-level directory by path" do
      dirs = strip_root(BottomUpDirectories.new(@root_dir, :exclude => 'dir1'))
      assert_equal_elements [ '/empty', '' ], dirs
    end

    test "can exclude mid-level directory by path" do
      dirs = strip_root(BottomUpDirectories.new(@root_dir, :exclude => 'dir1/nested1'))
      assert_equal_elements [ '/empty', '/dir1', '' ], dirs
    end

    test "can exclude directories by glob pattern" do
      @tree.directory '.ignored'
      @tree.directory 'dir1/nested1/.ignored'
      dirs = strip_root(BottomUpDirectories.new(@root_dir, :exclude => '**/.ignored'))
      assert_equal_elements [ '/empty', '/dir1', '/dir1/nested1', '/dir1/nested1/nested2', '' ], dirs
    end
  end
  
  
  context "in a checked directory" do
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
        f = @tree.file 'added_file'
        antedate(f)
        @checked = CheckedDir.new(@root_dir)
      end

      test "update is necessary" do
        assert @checked.needs_update?
      end

      test "the added file is noticed" do
        @checked.verify_checksums do |on|
          flunk_all(on)
          ignore(on, :valid_signature, :item_unchanged)
          expect(on, :directory_changed, @root_dir)
          expect(on, :item_added, @root_dir, 'added_file')
        end
      end

      test "added_items" do
        changes = @checked.verify_checksums
        assert_equal ['added_file'], changes.added_items
      end
    end

    context "with a removed file" do
      setup do
        @tree.rm_file 'baz'
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

      test "removed_items" do
        changes = @checked.verify_checksums
        assert_equal ['baz'], changes.removed_items
      end
    end

    context "with a changed file" do
      setup do
        @tree.file 'baz', 'going thru changes'
        @checked = CheckedDir.new(@root_dir)
        @expected_hash  = '73feffa4b7f6bb68e44cf984c85f6e88'
        @actual_hash    = 'ad769fd2bc30024dc4d636a978a4f011'
      end
      
      test "the changed file is noticed" do
        @checked.verify_checksums do |on|
          flunk_all(on)
          ignore(on, :valid_signature, :item_unchanged)
          expect(on, :directory_changed, @root_dir)
          expect(on, :item_changed, @root_dir,
                'baz', @expected_hash, @actual_hash)
        end
      end

      test "changed_items" do
        changes = @checked.verify_checksums
        assert_equal [{ :item           => 'baz',
                        :expected_hash  => @expected_hash,
                        :actual_hash    => @actual_hash }],
            changes.changed_items
      end
    end
    
    context "with an added empty sub-directory" do
      setup do
        @tree.directory "newdir"
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

    context "with a removed empty sub-directory" do
      setup do
        @tree.rm_directory "empty"
        @checked = CheckedDir.new(@root_dir)
      end
      
      test "the removed directory is noticed" do
        @checked.verify_checksums do |on|
          flunk_all(on)
          ignore(on, :valid_signature, :item_unchanged)
          expect(on, :directory_changed)
          expect(on, :item_removed, @root_dir, 'empty')
        end
      end
    end
  
    context "with recursively checked directories" do
      setup do
        write_checksums(@root_dir, 'dir1', 'nested1', 'nested2')
        write_checksums(@root_dir, 'dir1', 'nested1')
        write_checksums(@root_dir, 'dir1')
        antedate(@root_dir, 'dir1', 'nested1', 'nested2', 'bar')
      end

      test "updates propagate upwards" do
        sleep 1
        assert needs_update?(@root_dir, 'dir1', 'nested1', 'nested2')
        write_checksums(@root_dir, 'dir1', 'nested1', 'nested2')
        assert needs_update?(@root_dir, 'dir1', 'nested1')
        write_checksums(@root_dir, 'dir1', 'nested1')
        assert needs_update?(@root_dir, 'dir1')
        write_checksums(@root_dir, 'dir1')
        assert needs_update?(@root_dir)
      end
      
      context "after update" do
        setup do
          write_checksums(@root_dir)
        end

        test "checksum for sub-directory is not empty" do
          # The exact checksum of the checksum file depends on
          # the key used for signing it.
          # TODO consider using the unsigned checksums
          assert_not_equal '', @checked.saved_checksums['dir1']
        end
      end
    end

    context "skipping" do
      setup do
        @checked = CheckedDir.new(@root_dir)
      end
      
      test "checksum comparison can be skipped" do
        @checked.verify_checksums do |on|
          flunk_all(on)
          on.valid_signature do
            throw :skip_checksum_comparison
          end
        end
      end

      test "item comparison can be skipped" do
        @tree.file 'added_file'
        @checked.verify_checksums do |on|
          flunk_all(on)
          ignore(on, :valid_signature)
          on.directory_changed do
            throw :skip_item_comparison
          end
        end
      end
    end


  end
  
  
  context "in an unchecked directory" do

    context "with an added file" do
      setup do
        @tree.file 'added_file'
        @checked = CheckedDir.new(@root_dir)
      end

      test "the added file is noticed" do
        @checked.verify_checksums do |on|
          flunk_all(on)
          ignore(on, :valid_signature, :item_unchanged)
          expect(on, :directory_changed, @root_dir)
          expect(on, :item_added, @root_dir, 'added_file')
        end
      end
    end

  end

  
  private

  def grow_tree
    F.new do
      directory 'dir1' do
        file 'foo'
        directory 'nested1' do
          directory 'nested2' do
            file 'bar', 'BAR'
          end
        end
        symlink 'fool', 'foo'
        symlink 'dead'
      end
      file 'baz'
      directory 'empty'
    end
  end

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
  
  def strip_root(dirs)
    dirs.map { |d|
      d.sub(/^#{@root_dir}/, '')
    }
  end

  def read_checksums(*where)
    where = [@root_dir] if where.empty?
    path = File.join(File.join(*where), CHECKSUM_FILENAME)
    [ path, File.read(path) ]
  end

  def edit_checksums(target, replacement, *where)
    path, text = read_checksums(*where)
    text.sub!(target, replacement)
    File.open(path, 'w') { |f| f.write(text) }
  end
  
  def write_checksums(*where)
    dir_path = File.join(*where)
    d = CheckedDir.new(dir_path)
    d.write_checksum_file
    assert File.file?(File.join(dir_path, CHECKSUM_FILENAME)), 'Checksum file not written'
  end

  def needs_update?(*where)
    dir_path = File.join(*where)
    CheckedDir.new(dir_path).needs_update?
  end

  def antedate(*path)
    t = Time.now + 1
    File.utime(t, t, File.join(*path))
  end
  
  def assert_equal_elements(expected, actual, message = nil)
    e_set = Set.new(expected)
    a_set = Set.new(actual)
    assert_equal(e_set, a_set, message)
  end
end


class F
  attr_reader :root
  
  def initialize(&block)
    @root = Dir.mktmpdir
    @dir_stack = [@root]
    instance_eval(&block) if block_given?
  end
    
  def cut_down
    FileUtils.rm_rf(@root)
  end

  def file(name, contents = name)
    make_path(name).tap do |path|
      File.open(path, 'w') do |f|
        f.write(contents)
      end
    end
  end

  def symlink(name, target = nil)
    target ||= 'does-not-exist'
    make_path(name).tap do |path|
      File.symlink(target, path)
    end
  end

  def directory(name)
    @directory_count ||= 0
    make_path(name).tap do |path|
      Dir.mkdir(path)
      @directory_count += 1
      @dir_stack.unshift(path)
      yield if block_given?
    end
  ensure
    @dir_stack.shift
  end

  def rm_file(name)
    File.delete(make_path(name))
  end

  def rm_directory(name)
    # invalidates @directory_count
    FileUtils.rm_rf(make_path(name))
  end

  def directory_count
    (@directory_count || 0) + 1 # add 1 for root dir
  end

  private

  def make_path(name)
    File.join(@dir_stack.first, name)
  end
end
