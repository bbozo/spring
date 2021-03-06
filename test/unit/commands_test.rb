require "helper"
require "spring/commands"

class CommandsTest < ActiveSupport::TestCase
  test "test command needs a test name" do
    begin
      real_stderr = $stderr
      $stderr = StringIO.new('')

      command = Spring::Commands::Test.new
      command.call([])

      assert_equal "you need to specify what test to run: spring test TEST_NAME\n", $stderr.string
    ensure
      $stderr = real_stderr
    end
  end

  test 'children of Command have inheritable accessor named "preload"' do
    command1, command2 = 2.times.map { Class.new(Spring::Commands::Command) }

    command1.preloads << "foo"
    assert_equal ["foo"], command1.preloads
    assert_equal [], command2.preloads

    command2.preloads << "bar"
    assert_equal ["foo"], command1.preloads
    assert_equal ["bar"], command2.preloads

    command1.preloads = ["omg"]
    assert_equal ["omg"], command1.preloads
    assert_equal ["bar"], command2.preloads

    command3 = Class.new(command1)
    command3.preloads << "foo"
    assert_equal ["omg", "foo"], command3.preloads
    assert_equal ["omg"], command1.preloads
  end

  test "prints error message when preloaded file does not exist" do
    begin
      original_stderr = $stderr
      $stderr = StringIO.new('')
      my_command_class = Class.new(Spring::Commands::Command)
      my_command_class.preloads = %w(i_do_not_exist)

      my_command_class.new.setup
      assert_match /The #<Class:0x[0-9a-f]+> command tried to preload i_do_not_exist but could not find it./, $stderr.string
    ensure
      $stderr = original_stderr
    end
  end
end
