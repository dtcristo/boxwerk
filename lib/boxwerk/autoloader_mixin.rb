# frozen_string_literal: true

module Boxwerk
  # Shared autoload configuration API included by both
  # {GlobalContext::Autoloader} and {PackageContext::Autoloader}.
  #
  # Provides the four public methods available in boot scripts:
  # {#push_dir}, {#collapse}, {#ignore}, and {#setup}.
  module AutoloaderMixin
    # Adds +dir+ to autoload paths and immediately registers lazy autoloads.
    # Constants in the directory are accessible via autoload from this point on.
    # @param dir [String] Absolute or relative path to an autoload root.
    # @return [self]
    def push_dir(dir)
      @push_dirs << dir
      setup
      self
    end

    # Collapses +dir+, mapping its files to the parent namespace rather than
    # introducing an intermediate namespace for the directory itself.
    # @param dir [String] Absolute or relative path to a directory to collapse.
    # @return [self]
    def collapse(dir)
      @collapse_dirs << dir
      setup
      self
    end

    # Ignores +dir+ from autoloading entirely.
    # @param dir [String] Absolute or relative path to a directory to ignore.
    # @return [self]
    def ignore(dir)
      @ignore_dirs << dir
      self
    end

    # Registers lazy autoloads for all dirs added since the last +setup+ call.
    # Called automatically by {#push_dir} and {#collapse}; only call explicitly
    # if you need to trigger registration outside of those methods.
    # @return [self]
    def setup
      new_push = @push_dirs[@setup_index[:push]..]
      new_collapse = @collapse_dirs[@setup_index[:collapse]..]
      @setup_index[:push] = @push_dirs.length
      @setup_index[:collapse] = @collapse_dirs.length
      do_setup(new_push, new_collapse) unless new_push.empty? && new_collapse.empty?
      self
    end

    private

    # Initialises the shared dir state. Call from subclass +initialize+.
    def init_dirs
      @push_dirs = []
      @collapse_dirs = []
      @ignore_dirs = []
      @setup_index = { push: 0, collapse: 0 }
    end

    # Template method: subclasses implement this to perform actual registration.
    def do_setup(_new_push, _new_collapse)
    end
  end
end
