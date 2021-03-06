require 'minitest/autorun'
require 'flexmock/test_unit'
require 'minitest/spec'

# simplecov must be loaded FIRST. Only the files required after it gets loaded
# will be profiled !!!
if ENV['TEST_ENABLE_COVERAGE'] == '1'
    begin
        require 'simplecov'
    rescue LoadError
        require 'orogen'
        OroGen.warn "coverage is disabled because the 'simplecov' gem cannot be loaded"
    rescue Exception => e
        require 'orogen'
        OroGen.warn "coverage is disabled: #{e.message}"
    end
end

require 'orogen'

if ENV['TEST_ENABLE_PRY'] != '0'
    begin
        require 'pry'
        if ENV['TEST_DEBUG'] == '1'
            require 'pry-rescue/minitest'
        end
    rescue Exception
        OroGen.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

module OroGen
    module SelfTest
        TEST_DIR = File.expand_path(File.join('..', '..', '..', 'test'), __FILE__)
        TEST_DATA_DIR = File.join( TEST_DIR, 'data' )
        WC_ROOT  = File.join(TEST_DIR, 'wc')

        # Overload of {test_dir} for use in specs, as test_* is somewhat hidden
        # by minitest
        def path_to_test
            TEST_DIR
        end

        # @return [String] the full path to oroGen's test/data folder, where
        #   fixtures are stored
        def path_to_data
            TEST_DATA_DIR
        end

        # @return [String] the full path to oroGen's test/wc folder, where
        #   code is being generated by the tests
        def path_to_wc_root
            WC_ROOT
        end

        def create_dummy_project
            loader = OroGen::Loaders::Files.new
            OroGen::Loaders::RTT.setup_loader(loader)
            OroGen::Spec::Project.new(loader)
        end

        if defined? FlexMock
            include FlexMock::ArgumentTypes
            include FlexMock::MockContainer
        end

        def setup
            # Setup code for all the tests
        end

        def teardown
            # Teardown code for all the tests
        end
    end
end

# Workaround a problem with flexmock and minitest not being compatible with each
# other (currently). See github.com/jimweirich/flexmock/issues/15.
if defined?(FlexMock) && !FlexMock::TestUnitFrameworkAdapter.method_defined?(:assertions)
    class FlexMock::TestUnitFrameworkAdapter
        attr_accessor :assertions
    end
    FlexMock.framework_adapter.assertions = 0
end

module Minitest
    class Test
        include OroGen::SelfTest
    end
end

