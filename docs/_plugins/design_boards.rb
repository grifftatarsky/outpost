# frozen_string_literal: true

require "fileutils"

# Copies the design boards' underscore-named assets into the built site.
#
# Jekyll skips every path beginning with an underscore, and the board export names both a folder
# and the files inside it that way (`_ds/…/_ds_bundle.js`). Without this the boards publish
# unstyled and nothing says so.
#
# This used to also inject the responsive stylesheet into the boards at build time, because the
# folder was a drop zone a re-export would replace. The design pass is closed and nothing will be
# re-exported (2026-08-18), so the boards are ordinary checked-in files now: the `<link>` is baked
# into each board's own `<head>`, and edits to the boards are edits like any other.
module DesignBoards
  BOARDS_DIR = "design/boards"

  def self.mirror_underscored(site)
    source = File.join(site.source, BOARDS_DIR)
    Dir.glob(File.join(source, "_*")).each do |path|
      FileUtils.mkdir_p(File.join(site.dest, BOARDS_DIR))
      FileUtils.cp_r(path, File.join(site.dest, BOARDS_DIR), remove_destination: true)
    end
  end
end

Jekyll::Hooks.register :site, :post_write do |site|
  DesignBoards.mirror_underscored(site)
end
