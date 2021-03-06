# Fantasdic
# Copyright (C) 2006 - 2007 Mathieu Blondel
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require 'libglade2'
begin
    require 'gnome2'
rescue LoadError
    require 'gtk2'
    Fantasdic.missing_dependency('Ruby/GNOME2', 'Better integration in GNOME')
end

module Fantasdic
module UI

    HAVE_GNOME2 = Object.const_defined? "Gnome"
    HAVE_STATUS_ICON = Gtk.const_defined? "StatusIcon"
    HAVE_PRINT = Gtk.const_defined? "PrintOperation"

    def self.main
        options = CommandLineOptions.instance

        if HAVE_GNOME2
            pgm = Gnome::Program.new('fantasdic', VERSION)
            pgm.app_datadir = Config::MAIN_DATA_DIR
        else
            Gtk.init
        end

        # Start Fantasdic normally
        # Or ask the first process to pop up the window if it exists
        instance = IPC::Instance.find(IPC::Instance::REMOTE)

        if ARGV.length == 2
            params = {:dictionary => ARGV[0], :strategy => options[:match],
                      :word => ARGV[1]}
        else
            params = {}
        end

        if instance
            IPC::Instance.send(instance, IPC::Instance::REMOTE, params)
        else
            MainApp.new(params)
            Gtk.main
        end
    end


end
end

require 'fantasdic/ui/glade_base'
require 'fantasdic/ui/utils'
require 'fantasdic/ui/alert_dialog'
require 'fantasdic/ui/about_dialog'
require 'fantasdic/ui/preferences_dialog'
require 'fantasdic/ui/add_dictionary_dialog'
require 'fantasdic/ui/combobox_entry'
require 'fantasdic/ui/matches_listview.rb'
require 'fantasdic/ui/result_text_view'
require 'fantasdic/ui/print' if Fantasdic::UI::HAVE_PRINT
require 'fantasdic/ui/ipc'
require 'fantasdic/ui/browser'
require 'fantasdic/ui/main_app'